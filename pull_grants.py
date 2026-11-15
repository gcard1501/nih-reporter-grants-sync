"""Milestone 3: page through all NIH RePORTER results and save them to a CSV.

Pulls every University of South Florida project for fiscal years 2022-2025
from the v2 projects/search endpoint, 500 records per request, waiting
1 second between requests, and writes the fields we need to data/.
"""

import csv   # writes the CSV file
import os    # creates the data/ folder
import time  # pauses between requests

import requests  # sends the HTTP requests

# --- 1. Settings ----------------------------------------------------------

URL = "https://api.reporter.nih.gov/v2/projects/search"  # the search endpoint

HEADERS = {
    "Content-Type": "application/json",  # the body we send is JSON
    "Accept": "application/json",        # we want JSON back
}

CRITERIA = {                                    # what to search for
    "org_names": ["UNIVERSITY OF SOUTH FLORIDA"],
    "fiscal_years": [2022, 2023, 2024, 2025],
}

PAGE_SIZE = 500      # records per request (the API's maximum)
PAUSE_SECONDS = 1    # wait between requests, to be polite to the API

FIELDS = [               # the only fields we keep, in CSV column order
    "appl_id",           # unique ID for each record
    "project_num",       # e.g. 5R01EY031684-06; changes each year
    "core_project_num",  # e.g. R01EY031684; same across years
    "fiscal_year",
    "activity_code",     # grant type, e.g. R01
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

OUTPUT_PATH = "data/usf_grants_fy2022_2025.csv"  # where the CSV goes

# --- 2. Page through all results ------------------------------------------

all_rows = []          # every record we keep, across all pages
offset = 0             # how many records to skip; 0 means start at the first one

while True:                                        # repeat until a "break" stops us
    payload = {                                    # the request body for this page
        "criteria": CRITERIA,                      # same search every time
        "offset": offset,                          # where this page starts
        "limit": PAGE_SIZE,                        # how many records this page can hold
        "sort_field": "appl_id",                   # fixed order so records don't move between pages
        "sort_order": "asc",                       # smallest appl_id first
    }
    response = requests.post(URL, headers=HEADERS, json=payload, timeout=30)  # send the request
    response.raise_for_status()                    # stop with an error on 4xx/5xx
    data = response.json()                         # turn the JSON text into a Python dict
    total = data["meta"]["total"]                  # how many records match the search in all
    page = data["results"]                         # the records on this page (a list)

    for project in page:                           # go through each record on this page
        all_rows.append({f: project[f] for f in FIELDS})  # keep only our fields

    print(f"offset {offset}: got {len(page)}, have {len(all_rows)} of {total}")  # show progress
    offset += len(page)                            # move the start point past what we just got

    if len(page) == 0 or offset >= total:          # nothing came back, or we have everything
        break                                      # leave the loop
    print("Waiting 1 second")
    time.sleep(PAUSE_SECONDS)                      # wait before asking for the next page

# --- 3. Save to CSV -------------------------------------------------------

os.makedirs("data", exist_ok=True)                 # create data/ if it isn't there yet

with open(OUTPUT_PATH, "w", encoding="utf-8", newline="") as f:  # open the file for writing
    writer = csv.DictWriter(f, fieldnames=FIELDS)  # maps each dict's keys to columns
    writer.writeheader()                           # first line: the column names
    writer.writerows(all_rows)                     # one line per record; None becomes an empty cell

print(f"\nWrote {len(all_rows)} rows to {OUTPUT_PATH}")  # confirm where it went

# --- 4. Checks ------------------------------------------------------------

unique_appl_ids = {row["appl_id"] for row in all_rows}         # a set drops duplicates
unique_project_nums = {row["project_num"] for row in all_rows}

print("Rows match meta.total:", len(all_rows) == total)                   # got everything?
print("No duplicate appl_id:", len(unique_appl_ids) == len(all_rows))     # paging was clean?
print("Unique project_num values:", len(unique_project_nums))             # for the milestone 4 key choice
