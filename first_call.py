"""Milestone 2: make one call to the NIH RePORTER v2 projects/search endpoint.

Asks for University of South Florida projects in fiscal year 2025, limited
to 10 results, then prints the total match count and the fields of one project.
"""

import json

import requests

# --- 1. The request -------------------------------------------------------

URL = "https://api.reporter.nih.gov/v2/projects/search"

HEADERS = {
    "Content-Type": "application/json",  # the body we send is JSON
    "Accept": "application/json",        # we want JSON back
}

PAYLOAD = {
    "criteria": {
        "org_names": ["UNIVERSITY OF SOUTH FLORIDA"],
        "fiscal_years": [2022, 2023, 2024, 2025],
    },
    "offset": 0,   # start at the first matching record
    "limit": 10,   # return at most 10 records in this response
}

# json=PAYLOAD turns the Python dict into a JSON string for the request body.
# timeout stops the script from hanging forever if the API doesn't answer.
response = requests.post(URL, headers=HEADERS, json=PAYLOAD, timeout=30)

# Stop with a clear error if the API returned 4xx or 5xx.
response.raise_for_status()

# --- 2. The response ------------------------------------------------------

data = response.json()  # turn the JSON text into a Python dict

print("HTTP status:", response.status_code)
print("Top-level keys:", list(data.keys()))
print("Total matching records (meta.total):", data["meta"]["total"])
print("Records in this response:", len(data["results"]))

print("\n--- Fields for the first project ---")
first_project = data["results"][0]
for field_name, value in first_project.items():
    text = json.dumps(value)  # show nested lists and dicts as JSON text
    if len(text) > 100:
        text = text[:100] + "..."  # shorten long values such as abstracts
    print(f"{field_name}: {text}")
