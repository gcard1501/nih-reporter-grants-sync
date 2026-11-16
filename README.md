# NIH RePORTER grants sync

Pull public grant data from an API, load it into SQL Server, reconcile it against a second source and log every change. Built with Python and T-SQL, using public NIH data and a fake internal tracker.

## The problem

Organizations often keep the same records in more than one system. A research office tracks its grants in an internal spreadsheet, while the funder publishes the official numbers. Over time the two drift apart: someone mistypes an award amount, an end date gets extended at the source but not in the tracker, or a new grant never gets added.

Checking this by hand doesn't scale and isn't repeatable. This project automates it:

1. **Pull** the official data from the source system's API.
2. **Load** it into a database, so re-runs update rows instead of duplicating them.
3. **Reconcile** it against the internal tracker and flag every mismatch.
4. **Log changes** so there's an audit trail of what changed at the source, and when.

The source is the [NIH RePORTER API](https://api.reporter.nih.gov/), which is free and public and needs no key. The "internal tracker" is fake: a CSV built from the same public data with deliberate errors planted in it. No private or real contract data is used.

## How it works

```
NIH RePORTER API
      │  pull_grants.py        (POST v2/projects/search, 500 per page)
      ▼
data/*.csv
      │  load_grants.py        (stage, log changes, MERGE, one transaction)
      ▼
dbo.Grants ◄──────────── dbo.ChangeLog   (old value → new value, per field)
      │
      │  sql/04_reconcile.sql  (FULL OUTER JOIN + field-by-field compare)
      ▼
mismatch report ◄──────── dbo.Tracker_Grants
                                ▲  load_tracker.py
                          fake_tracker/internal_grants_tracker.csv
```

### 1. Pull ([pull_grants.py](pull_grants.py))

Asks the `v2/projects/search` endpoint for one university's grants for fiscal years 2022–2025 (the search is set in `CRITERIA` at the top of the script). The API returns at most 500 records per request, so the script pages through the results with `offset` and `limit`, sorting by `appl_id` so records don't shift between pages and pausing one second between requests. It keeps 14 fields and writes them to `data/`. At the end it checks that the row count matches the API's `meta.total` and that no `appl_id` appears twice.

### 2. Load ([load_grants.py](load_grants.py), [sql/02_upsert_grants.sql](sql/02_upsert_grants.sql))

- **Key choice:** each row is keyed on `appl_id`, not `project_num`. Project numbers repeat for multi-component grants (in our data, 5 project numbers cover 29 rows), so they can't identify a row.
- **Staging:** the CSV is cleaned (blanks → `NULL`, text → numbers and dates) and copied into `dbo.Grants_Staging`.
- **Upsert:** a `MERGE` inserts new `appl_id`s and updates only rows where at least one value actually changed. The comparison uses `EXISTS (... EXCEPT ...)`, which treats two `NULL`s as equal, so blank fields don't cause false updates.
- **No automatic deletes:** a grant missing from one pull is left alone rather than deleted.
- **One transaction:** staging, change logging and the `MERGE` all commit together or roll back together.

Running it twice in a row gives `Inserted: 0, Updated: 0` the second time.

### 3. Reconcile ([sql/04_reconcile.sql](sql/04_reconcile.sql))

The fake tracker covers the FY2023 R21 grants. [make_tracker.py](make_tracker.py) exported a clean copy once, then errors were planted by hand, and the edited file is committed. [load_tracker.py](load_tracker.py) replaces the contents of `dbo.Tracker_Grants` with the CSV each time it runs.

The reconciliation query returns one row per problem, and no rows means the two sources agree:

| Issue | Meaning |
| --- | --- |
| `MISSING_FROM_TRACKER` | Grant is in RePORTER but not in the tracker |
| `NOT_IN_REPORTER_SCOPE` | Tracker row has no matching RePORTER grant (typo, wrong year, made up) |
| `VALUE_MISMATCH` | Same grant, but PI name, award amount, start date or end date differs |
| `DUPLICATE_IN_TRACKER` | Same project number appears more than once in the tracker |

A `FULL OUTER JOIN` finds grants on only one side. `CROSS APPLY (VALUES ...)` turns each grant's four compared fields into four rows, so a single `IS DISTINCT FROM` check (`NULL`-safe, SQL Server 2022+) catches every field difference.

### 4. Log changes ([sql/05_create_changelog.sql](sql/05_create_changelog.sql))

Before the `MERGE` overwrites anything, the upsert writes one row to `dbo.ChangeLog` for every field whose value changed, with the old value, the new value and a UTC timestamp. New grants aren't logged, because they're new rows rather than changes. Changing one value at the source and re-running produces exactly one ChangeLog row.

## How to run it from a fresh clone

These steps are for an Apple Silicon Mac with Homebrew.

### Prerequisites

- [Homebrew](https://brew.sh/)
- Python 3.10 or later (built and tested on 3.13)
- [Docker Desktop](https://www.docker.com/products/docker-desktop/)
- VS Code with the [MSSQL extension](https://marketplace.visualstudio.com/items?itemName=ms-mssql.mssql), to run the `.sql` files

### 1. Clone and install OpenSSL 3

```bash
git clone <this-repo-url>
cd REPORTER-API
brew install openssl@3
```

**Why OpenSSL 3:** Microsoft's SQL Server driver (bundled inside `mssql-python`) needs OpenSSL to encrypt the connection, and it doesn't support OpenSSL 4, which is now Homebrew's default. [run.sh](run.sh) points the driver at OpenSSL 3 for the one command it runs and changes nothing else on your Mac. **Run every Python script through `./run.sh`.** Without it, you'll see `OpenSSL library could not be loaded`. For the full explanation, see [docs/setup-notes.md](docs/setup-notes.md#macos-openssl-note).

### 2. Start SQL Server 2022 in Docker

Choose a strong password (SQL Server rejects weak ones) and start the container:

```bash
docker run -d --name sql_server_container \
  -e "ACCEPT_EULA=Y" \
  -e "MSSQL_SA_PASSWORD=<your-strong-password>" \
  -p 1433:1433 \
  mcr.microsoft.com/mssql/server:2022-latest
```

On Apple Silicon this image runs under emulation. If the container exits right away, turn on **Use Rosetta for x86_64/amd64 emulation** in Docker Desktop settings.

### 3. Create the Python environment

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

### 4. Create your `.env`

```bash
cp .env.example .env
```

Open `.env` and set `DB_PASSWORD` to the password from step 2. `.env` is listed in `.gitignore`, so it is never committed.

### 5. Test the connection

```bash
./run.sh python test_connection.py
```

You should see `Connected as: sa | database: master` followed by the SQL Server version.

### 6. Create the database and tables

In VS Code, connect the MSSQL extension to `localhost,1433` with login `sa`. Then open each file below and run it (**Cmd+Shift+E**), in this order:

1. `sql/01_create_tables.sql`: the database, `dbo.Grants` and `dbo.Grants_Staging`
2. `sql/03_create_tracker_table.sql`: `dbo.Tracker_Grants`
3. `sql/05_create_changelog.sql`: `dbo.ChangeLog`

All three must exist before the first load, because the upsert writes to `dbo.ChangeLog` on every run. Each script is safe to re-run. (`sql/02` is run by `load_grants.py`, and `sql/04` is the reconciliation in step 9.)

### 7. Pull and load the grants

```bash
./run.sh python pull_grants.py
./run.sh python load_grants.py
```

The pull ends with three checks, and the first two should be `True`. The first load inserts every row. Run `load_grants.py` again and it should report `Inserted: 0` and `Updated: 0`.

### 8. Load the fake tracker

```bash
./run.sh python load_tracker.py
```

The tracker CSV with its planted errors is already in the repo, so you don't need `make_tracker.py`. It refuses to overwrite an existing tracker anyway.

### 9. Run the reconciliation

Open `sql/04_reconcile.sql` in VS Code and run it. With the committed tracker, it returns:

| project_num | issue | field | reporter_value | tracker_value |
| --- | --- | --- | --- | --- |
| 1R21AA030632-01A1 | VALUE_MISMATCH | award_amount | 214267.00 | 214.00 |
| 1R21AG077426-01A1 | VALUE_MISMATCH | project_end_date | 2025-04-30 | 2035-04-30 |
| 5R21DK125917-03 | DUPLICATE_IN_TRACKER | | | 2 rows |
| 5R21DK125917-03 | VALUE_MISMATCH | contact_pi_name | JAJA, CHEEDY | , CHEEDY |
| 5R21HG011929-04 | MISSING_FROM_TRACKER | | | |

RePORTER is live data. If NIH revises one of these grants after this README was written, you may see an extra row or a different value.

### 10. See the ChangeLog work

1. Open `data/usf_grants_fy2022_2025.csv` and change one `award_amount`.
2. Run `./run.sh python load_grants.py`. It reports `Updated: 1` and `Changed fields logged to dbo.ChangeLog: 1`.
3. Check the log:

   ```sql
   SELECT * FROM ReporterGrants.dbo.ChangeLog ORDER BY changed_at DESC;
   ```

4. To restore the real value, re-run `pull_grants.py` and `load_grants.py`. That logs a second row, from your edited value back to the real one.

## What would change in production

This project runs on a laptop against a local Docker container. Connecting real business systems would also need the following.

- **Authentication and secrets:** real systems need credentials stored securely, never in the code. A `.env` file is fine locally. In production, credentials belong in a secrets manager or key vault and are rotated regularly.
- **A limited-permission login instead of `sa`:** `sa` can do anything on the server. The loader should use a dedicated SQL login with only the permissions it needs: read and write on the grants, tracker and ChangeLog tables, plus `ALTER` on the two tables it empties with `TRUNCATE` (SQL Server requires that), and nothing else. We use `sa` only because this is a local container.
- **A real server certificate:** locally the connection uses `Encrypt=yes;TrustServerCertificate=yes`. Traffic is encrypted, but the client accepts the container's self-signed certificate without checking who it belongs to. In production, install a certificate issued by a trusted authority on the server and set `TrustServerCertificate=no`, so the client confirms it's talking to the real server.
- **Governance:** IT approval, data loss prevention (DLP) policies and a named owner who is responsible for the integration.
- **Monitoring:** alerts when a run fails, plus a documented manual fallback if the integration goes down.
- **Human review before updating a system of record:** this project only *flags* mismatches and never writes back to the tracker. That should stay true until a person has reviewed the changes.
- **Connector options:** some systems have no built-in connector for low-code tools like Power Automate. The choice is then between a third-party connector and the system's own API, and that decision belongs to IT and depends on budget.

## How this pattern applies to other business systems

The steps here are the same ones used to connect most business systems, for example a finance or HR platform feeding another tool:

| This project | General pattern | Example: HR platform → payroll |
| --- | --- | --- |
| RePORTER API | Source system's API | HR platform's employee API |
| `appl_id` as the key | A stable ID that never repeats | Employee ID, not name or email |
| Paging with `offset`/`limit` | Respect API limits; get every record | Same, plus rate limits and auth tokens |
| Staging + `MERGE` | Re-runnable load, no duplicates | Daily sync that's safe to retry |
| Fake tracker + reconcile query | Compare against the other system | Flag pay-rate or status mismatches |
| `dbo.ChangeLog` | Audit trail of every change | Who changed, what, from, to, when |

Lessons from this project that carry over:

- **Check that your key is really unique.** The obvious ID (`project_num`) turned out to repeat. Confirm uniqueness against the real data before you build on it.
- **Make every run safe to repeat.** If a run fails halfway through, you should be able to run it again without cleaning anything up. That's what one transaction plus an upsert gives you.
- **Compare `NULL`s on purpose.** A plain `<>` silently skips rows where one side is blank, which is exactly where data problems tend to hide.
- **Flag, don't fix.** Deleting or overwriting automatically is risky. Report the difference and let a person decide.

## Next versions

These are out of scope for version 1:

- **Scheduling:** run the pull and load automatically, for example nightly.
- **A user interface** for viewing mismatches and the ChangeLog.
- **AI features**, for example summarizing what changed since the last run.
- **Power Automate** (or another low-code tool) to trigger runs or send alerts.
- **Run the reconciliation automatically** after each load.
- **Save reconciliation results to a table**, so mismatches have a history the same way changes do.
- **Show `tracker_row_id` in the reconciliation output**, so a mismatch on a duplicated tracker row says *which* row is wrong.
- **A shared `db.py` helper** for the connection string and the CSV `clean()` function, which are currently copied into three scripts.
- **Retire `run.sh`** once Microsoft's driver supports OpenSSL 4. To check, run `python test_connection.py` without it after upgrading `mssql-python`.

## Project files

| Path | Purpose |
| --- | --- |
| `pull_grants.py` | Pull grants from the API to `data/` |
| `load_grants.py` | Stage, log changes and upsert into `dbo.Grants` |
| `make_tracker.py` | One-time export of the clean tracker (already done) |
| `load_tracker.py` | Load the fake tracker into `dbo.Tracker_Grants` |
| `test_connection.py` | Check that Python can log in to SQL Server |
| `run.sh` | Run a command with OpenSSL 3 visible to the driver |
| `sql/01`–`05` | Tables, upsert, tracker table, reconciliation, ChangeLog |
| `fake_tracker/` | The fake internal tracker with planted errors |
| `docs/project-plan.md` | Milestones and the "done" checklist |
| `docs/setup-notes.md` | Why `run.sh` exists |
| `.env.example` | Template for your local `.env` (no secrets) |
