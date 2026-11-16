"""Milestone 5: load the fake internal grants tracker into SQL Server.

Reads fake_tracker/internal_grants_tracker.csv and replaces every row in
dbo.Tracker_Grants with it (TRUNCATE + INSERT in one transaction). The
tracker is a snapshot, so a full replace is all we need, no MERGE.

Run from the project folder:  ./run.sh python load_tracker.py
"""

import csv                       # reads the CSV file
import os                        # reads environment variables
from datetime import date        # Python's date type, matches SQL DATE
from decimal import Decimal      # exact decimal numbers, matches SQL DECIMAL

import mssql_python              # Microsoft's SQL Server driver for Python
from dotenv import load_dotenv   # loads .env into environment variables

# --- 1. Settings ----------------------------------------------------------

CSV_PATH = "fake_tracker/internal_grants_tracker.csv"   # written by make_tracker.py, then hand-edited

COLUMNS = [                      # CSV columns, in the same order as the INSERT
    "project_num",
    "contact_pi_name",
    "award_amount",
    "project_start_date",
    "project_end_date",
]

MONEY_COLUMNS = {"award_amount"}
DATE_COLUMNS = {"project_start_date", "project_end_date"}

# --- 2. Read and clean the CSV --------------------------------------------

def clean(column, value):
    """Turn one CSV text value into the Python type its SQL column expects.
    Same rules as load_grants.py."""
    value = value.strip()                      # drop stray spaces
    if value == "":
        return None                            # blank cell -> NULL in SQL Server
    if column in MONEY_COLUMNS:
        return Decimal(value)                  # "214267.00" -> Decimal("214267.00")
    if column in DATE_COLUMNS:
        return date.fromisoformat(value[:10])  # "2025-04-30" -> date(2025, 4, 30)
    return value                               # everything else stays text

rows = []
with open(CSV_PATH, encoding="utf-8", newline="") as f:
    for record in csv.DictReader(f):
        rows.append(tuple(clean(col, record[col]) for col in COLUMNS))

print(f"Read {len(rows)} rows from {CSV_PATH}")

# --- 3. Connect -----------------------------------------------------------

load_dotenv()

conn_str = (
    f"Server={os.environ['DB_SERVER']};"
    f"Database={os.environ['DB_NAME']};"
    f"UID={os.environ['DB_USER']};"
    "PWD={" + os.environ["DB_PASSWORD"].replace("}", "}}") + "};"
    "Encrypt=yes;"
    "TrustServerCertificate=yes;"              # local Docker container only
)

insert_sql = (
    f"INSERT INTO dbo.Tracker_Grants ({', '.join(COLUMNS)}) "
    f"VALUES ({', '.join('?' for _ in COLUMNS)});"
)

# --- 4. Replace the tracker rows in one transaction -----------------------

conn = mssql_python.connect(conn_str)          # autocommit is off
try:
    cursor = conn.cursor()
    cursor.execute("TRUNCATE TABLE dbo.Tracker_Grants;")  # remove the old snapshot
    cursor.executemany(insert_sql, rows)       # insert the new one
    cursor.execute("SELECT COUNT(*) FROM dbo.Tracker_Grants;")
    loaded = cursor.fetchone()[0]
    conn.commit()                              # save both steps together
except Exception:
    conn.rollback()                            # any error: keep the old snapshot
    raise
finally:
    conn.close()

# --- 5. Report ------------------------------------------------------------

print(f"Loaded {loaded} rows into dbo.Tracker_Grants")
