"""Milestone 4, step 2: check that Python can log in to SQL Server.

Reads the connection settings from .env, connects with Microsoft's
mssql-python driver and prints the server version. The password is
never printed.
"""

import os  # reads environment variables

import mssql_python               # Microsoft's SQL Server driver for Python
from dotenv import load_dotenv    # loads .env into environment variables

# --- 1. Load settings from .env ---------------------------------------------

load_dotenv()                                  # copy each KEY=value in .env into os.environ

server = os.environ["DB_SERVER"]               # e.g. localhost,1433
user = os.environ["DB_USER"]                   # e.g. sa
password = os.environ["DB_PASSWORD"]           # KeyError here means .env is missing a line

# --- 2. Build the connection string -----------------------------------------

conn_str = (
    f"Server={server};"                        # host,port of the container
    "Database=master;"                         # built-in database; ReporterGrants comes in step 3
    f"UID={user};"                             # SQL login name
    "PWD={" + password.replace("}", "}}") + "};"   # braces let the password contain ; or =
    "Encrypt=yes;"                             # encrypt traffic between Python and SQL Server
    "TrustServerCertificate=yes;"              # accept the container's self-signed certificate (local only)
)

# --- 3. Connect and ask for the version -------------------------------------

conn = mssql_python.connect(conn_str)          # opens the connection (log in)
cursor = conn.cursor()                         # a cursor sends queries and reads results
cursor.execute("SELECT @@VERSION, SUSER_SNAME(), DB_NAME();")
version, login, database = cursor.fetchone()   # one row, three columns

print("Connected as:", login, "| database:", database)
print(version.splitlines()[0])                 # first line of @@VERSION is enough

conn.close()                                   # always release the connection
