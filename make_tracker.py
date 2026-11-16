"""Milestone 5: write a clean copy of the fake "internal grants tracker".

Exports the FY2023 R21 grants from dbo.Grants to
fake_tracker/internal_grants_tracker.csv. You then hand-edit that file to
plant deliberate errors for the reconciliation query to find.

Run once, from the project folder:  ./run.sh python make_tracker.py
It refuses to overwrite an existing tracker, so your edits are safe.
"""

import csv                       # writes the CSV file
import os                        # file checks and environment variables
import sys                       # exits early with a message

import mssql_python              # Microsoft's SQL Server driver for Python
from dotenv import load_dotenv   # loads .env into environment variables

# --- 1. Settings ----------------------------------------------------------

TRACKER_PATH = "fake_tracker/internal_grants_tracker.csv"

COLUMNS = [                      # tracker columns, in CSV order
    "project_num",
    "contact_pi_name",
    "award_amount",
    "project_start_date",
    "project_end_date",
]

# The tracker's scope. sql/04_reconcile.sql uses the same filter.
SELECT_SQL = (
    f"SELECT {', '.join(COLUMNS)} FROM dbo.Grants "
    "WHERE fiscal_year = 2023 AND activity_code = 'R21' "
    "ORDER BY project_num;"
)

# --- 2. Don't overwrite planted errors ------------------------------------

if os.path.exists(TRACKER_PATH):
    sys.exit(f"{TRACKER_PATH} already exists; not overwriting it. "
             "Delete it first if you really want a fresh clean copy.")

# --- 3. Read the in-scope grants ------------------------------------------

load_dotenv()

conn_str = (
    f"Server={os.environ['DB_SERVER']};"
    f"Database={os.environ['DB_NAME']};"
    f"UID={os.environ['DB_USER']};"
    "PWD={" + os.environ["DB_PASSWORD"].replace("}", "}}") + "};"
    "Encrypt=yes;"
    "TrustServerCertificate=yes;"              # local Docker container only
)

conn = mssql_python.connect(conn_str)
try:
    cursor = conn.cursor()
    cursor.execute(SELECT_SQL)
    rows = cursor.fetchall()
finally:
    conn.close()

# --- 4. Write the CSV -----------------------------------------------------

os.makedirs(os.path.dirname(TRACKER_PATH), exist_ok=True)
with open(TRACKER_PATH, "w", encoding="utf-8", newline="") as f:
    writer = csv.writer(f)
    writer.writerow(COLUMNS)                   # header row
    for row in rows:
        # None -> blank cell; dates print as YYYY-MM-DD; Decimals as 416667.00
        writer.writerow("" if v is None else v for v in row)

print(f"Wrote {len(rows)} grants to {TRACKER_PATH}")
