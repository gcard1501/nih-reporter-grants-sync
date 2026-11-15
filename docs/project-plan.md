# Project plan: NIH RePORTER grants sync

## Goal

Practice a common integration pattern on real public data: **pull from an API → load into a database → reconcile against another source → log changes.** The same pattern applies when connecting business systems such as a finance or HR platform to other tools.

## Data source

- NIH RePORTER API v2, free and public, no key needed.
- Endpoint: `POST https://api.reporter.nih.gov/v2/projects/search`
- Docs: <https://api.reporter.nih.gov/>. Check the docs for paging limits and field names before building.

## What we're building

1. **Pull.** A Python script calls the projects/search endpoint for a fixed set of grants (e.g., one organization or one disease area for one fiscal year), pages through all results, and saves them to a CSV.
2. **Load.** Load the results into a SQL Server table. Use the application ID (`appl_id`) as the key so re-runs update rows instead of creating duplicates. (The plan originally said project number, but project numbers repeat for multi-component grants: in our data, 5 project numbers cover 29 rows, so they can't be the key.)
3. **Reconcile.** Create a fake "internal grants tracker" (CSV or Excel) for the same grants with a few deliberate errors: a wrong award amount, a wrong end date and a missing project. A T-SQL query flags every mismatch.
4. **Log changes.** A ChangeLog table records the field, old value, new value and timestamp whenever a re-run finds a difference.
5. **Write it up.** A README covering the problem, how it works, how to run it, what would change in production and how the pattern applies to other systems.

**Out of scope for version 1:** scheduling, a user interface, AI features and Power Automate. List these under "Next versions" in the README instead of building them.

## Milestones

| # | Milestone | Skills practiced |
| --- | --- | --- |
| 1 | Repo created, first commit, `.gitignore` in place | Git basics |
| 2 | One API call returns results; I can explain the request and response | REST, JSON |
| 3 | Paging works and all results are saved to a CSV | Loops, API limits |
| 4 | Data loaded into SQL Server; re-runs don't duplicate rows | Python to SQL, keys, upserts |
| 5 | Fake tracker built; the reconciliation query flags all planted errors | T-SQL joins, data validation |
| 6 | ChangeLog table populated on re-run | Audit trails |
| 7 | README written | Documentation |

## Done means

- [ ] Public GitHub repo with working code and no secrets.
- [ ] The script runs end to end from a fresh clone, following the README.
- [ ] The reconciliation query catches every deliberate error in the fake tracker.
- [ ] A re-run with one changed value produces exactly one ChangeLog row.
- [ ] The README covers everything in step 5.

## Production notes (for the README)

- **Authentication:** real business systems need credentials stored securely, not in the code.
- **Governance:** IT approval, data loss prevention (DLP) policies and a named owner for the integration.
- **Monitoring:** alerts when a run fails, plus a manual fallback if the integration goes down.
- **Human review** before anything updates a system of record.
- **Connector options:** some systems have no built-in connector for low-code tools like Power Automate. The options are then a third-party connector or the system's own API, which is a decision for IT and budget.
