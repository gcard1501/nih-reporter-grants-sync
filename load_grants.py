"""Milestone 4: load the grants CSV into SQL Server without creating duplicates.

Reads data/usf_grants_fy2022_2025.csv, copies it into dbo.Grants_Staging,
then runs sql/02_upsert_grants.sql (a MERGE) to insert new appl_ids and
update changed rows in dbo.Grants. Everything runs in one transaction.
Milestone 6: the same file first logs each changed field to dbo.ChangeLog.

Run from the project folder:  ./run.sh python load_grants.py
"""

import csv                       # reads the CSV file
import os                        # reads environment variables
from datetime import date        # Python's date type, matches SQL DATE
from decimal import Decimal      # exact decimal numbers, matches SQL DECIMAL

import mssql_python              # Microsoft's SQL Server driver for Python
from dotenv import load_dotenv   # loads .env into environment variables

# --- 1. Settings ----------------------------------------------------------

CSV_PATH = "data/usf_grants_fy2022_2025.csv"   # written by pull_grants.py
UPSERT_SQL_PATH = "sql/02_upsert_grants.sql"   # the MERGE statement

COLUMNS = [                  # CSV columns, in the same order as the staging table
    "appl_id",
    "project_num",
    "core_project_num",
    "fiscal_year",
    "activity_code",
    "project_title",
    "contact_pi_name",
    "award_amount",
    "direct_cost_amt",
    "indirect_cost_amt",
    "project_start_date",
    "project_end_date",
    "budget_start",
    "budget_end",
]

INT_COLUMNS = {"appl_id", "fiscal_year"}
MONEY_COLUMNS = {"award_amount", "direct_cost_amt", "indirect_cost_amt"}
DATE_COLUMNS = {"project_start_date", "project_end_date", "budget_start", "budget_end"}

# --- 2. Read and clean the CSV --------------------------------------------

def clean(column, value):
    """Turn one CSV text value into the Python type its SQL column expects."""
    value = value.strip()                      # drop stray spaces, e.g. "HELLER, RICHARD "
    if value == "":
        return None                            # blank cell -> NULL in SQL Server
    if column in INT_COLUMNS:
        return int(value)                      # "10152592" -> 10152592
    if column in MONEY_COLUMNS:
        return Decimal(value)                  # "416667" -> Decimal("416667"), no rounding errors
    if column in DATE_COLUMNS:
        return date.fromisoformat(value[:10])  # "2024-05-31T00:00:00" -> date(2024, 5, 31)
    return value                               # everything else stays text

rows = []                                      # one tuple per CSV row, in COLUMNS order
with open(CSV_PATH, encoding="utf-8", newline="") as f:
    for record in csv.DictReader(f):           # each record is a dict: column name -> text
        rows.append(tuple(clean(col, record[col]) for col in COLUMNS))

print(f"Read {len(rows)} rows from {CSV_PATH}")

# --- 3. Connect -----------------------------------------------------------

load_dotenv()                                  # copy each KEY=value in .env into os.environ

conn_str = (
    f"Server={os.environ['DB_SERVER']};"
    f"Database={os.environ['DB_NAME']};"
    f"UID={os.environ['DB_USER']};"
    "PWD={" + os.environ["DB_PASSWORD"].replace("}", "}}") + "};"
    "Encrypt=yes;"                             # encrypt traffic
    "TrustServerCertificate=yes;"              # accept the container's self-signed certificate (local only)
)

with open(UPSERT_SQL_PATH, encoding="utf-8") as f:
    upsert_sql = f.read()                      # the MERGE, kept in its own .sql file

insert_sql = (                                 # one ? per column; the driver fills them in safely
    f"INSERT INTO dbo.Grants_Staging ({', '.join(COLUMNS)}) "
    f"VALUES ({', '.join('?' for _ in COLUMNS)});"
)

# --- 4. Stage and upsert in one transaction --------------------------------

conn = mssql_python.connect(conn_str)          # autocommit is off: nothing is saved until commit()
try:
    cursor = conn.cursor()
    cursor.execute("TRUNCATE TABLE dbo.Grants_Staging;")  # empty last run's staging rows
    cursor.executemany(insert_sql, rows)       # copy every CSV row into staging
    cursor.execute(upsert_sql)                 # MERGE staging into dbo.Grants
    staged, inserted, updated, logged = cursor.fetchone()  # the counts row the MERGE file returns
    conn.commit()                              # save everything at once
except Exception:
    conn.rollback()                            # any error: undo all of it, including the TRUNCATE
    raise                                      # then show the error
finally:
    conn.close()                               # always release the connection

# --- 5. Report ------------------------------------------------------------

print(f"Staged:    {staged}")
print(f"Inserted:  {inserted}")
print(f"Updated:   {updated}")
print(f"Unchanged: {staged - inserted - updated}")
print(f"Changed fields logged to dbo.ChangeLog: {logged}")
