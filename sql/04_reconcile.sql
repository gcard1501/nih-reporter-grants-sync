/* Milestone 5: reconcile the internal grants tracker against RePORTER.

   Returns one row per problem. No rows = tracker and RePORTER agree.

   Scope: FY2023 R21 grants (same filter as make_tracker.py).
   Join key: project_num (unique within this scope).

   Issues flagged:
     MISSING_FROM_TRACKER   in-scope RePORTER grant with no tracker row
     NOT_IN_REPORTER_SCOPE  tracker row with no in-scope RePORTER grant
                            (typo, wrong year/type or made-up grant)
     VALUE_MISMATCH         same grant, a compared field differs
     DUPLICATE_IN_TRACKER   project_num appears more than once in the tracker

   Note: a typo'd project_num in the tracker shows up twice, as MISSING (the
   real number) and NOT_IN_REPORTER_SCOPE (the typo). That's expected.

   Run in VS Code: open this file, connect, then Execute Query (Cmd+Shift+E).
*/

USE ReporterGrants;
GO

WITH reporter AS (               -- the grants the tracker is supposed to cover
    SELECT project_num, contact_pi_name, award_amount, project_start_date, project_end_date
    FROM dbo.Grants
    WHERE fiscal_year = 2023
      AND activity_code = 'R21'
),
tracker AS (
    SELECT project_num, contact_pi_name, award_amount, project_start_date, project_end_date
    FROM dbo.Tracker_Grants
)

-- 1. Grants on only one side. FULL OUTER JOIN keeps unmatched rows from both
--    sides; the side with no match comes back as NULLs.
SELECT
    COALESCE(r.project_num, t.project_num) AS project_num,
    CASE WHEN t.project_num IS NULL THEN 'MISSING_FROM_TRACKER'
         ELSE 'NOT_IN_REPORTER_SCOPE' END  AS issue,
    CAST(NULL AS VARCHAR(30))              AS field,
    CAST(NULL AS NVARCHAR(400))            AS reporter_value,
    CAST(NULL AS NVARCHAR(400))            AS tracker_value
FROM reporter AS r
FULL OUTER JOIN tracker AS t
    ON t.project_num = r.project_num
WHERE r.project_num IS NULL
   OR t.project_num IS NULL

UNION ALL

-- 2. Field-by-field differences on matched grants. CROSS APPLY (VALUES ...)
--    turns each grant's 4 fields into 4 rows (field, reporter, tracker), so a
--    single WHERE checks them all. Values are cast to text for display;
--    dates use style 23 (YYYY-MM-DD).
SELECT
    r.project_num,
    'VALUE_MISMATCH',
    v.field,
    v.reporter_value,
    v.tracker_value
FROM reporter AS r
JOIN tracker  AS t
    ON t.project_num = r.project_num
CROSS APPLY (VALUES
    ('contact_pi_name',    CAST(r.contact_pi_name AS NVARCHAR(400)),       CAST(t.contact_pi_name AS NVARCHAR(400))),
    ('award_amount',       CAST(r.award_amount AS NVARCHAR(400)),          CAST(t.award_amount AS NVARCHAR(400))),
    ('project_start_date', CONVERT(NVARCHAR(400), r.project_start_date, 23), CONVERT(NVARCHAR(400), t.project_start_date, 23)),
    ('project_end_date',   CONVERT(NVARCHAR(400), r.project_end_date, 23),   CONVERT(NVARCHAR(400), t.project_end_date, 23))
) AS v (field, reporter_value, tracker_value)
-- IS DISTINCT FROM (SQL Server 2022+) is a NULL-safe "<>":
-- NULL vs. a value = different; NULL vs. NULL = same.
WHERE v.reporter_value IS DISTINCT FROM v.tracker_value

UNION ALL

-- 3. Duplicate rows in the tracker.
SELECT
    project_num,
    'DUPLICATE_IN_TRACKER',
    NULL,
    NULL,
    CONCAT(COUNT(*), N' rows')
FROM tracker
GROUP BY project_num
HAVING COUNT(*) > 1

ORDER BY project_num, issue, field;
