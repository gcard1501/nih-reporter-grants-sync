/* Milestone 4: upsert dbo.Grants_Staging into dbo.Grants.

   Run by load_grants.py after it fills the staging table, inside the same
   transaction. You can also run it by hand in VS Code (USE ReporterGrants first).

   - New appl_id            -> INSERT
   - Existing, data changed  -> UPDATE (and stamp updated_at)
   - Existing, no change     -> left alone (updated_at keeps its old value)
   - In Grants but not in staging -> left alone (no automatic deletes)

   Milestone 6: before the MERGE, every changed field is written to
   dbo.ChangeLog (one row per field, with old and new value).

   Returns one row: staged_rows, inserted_rows, updated_rows, changelog_rows.
*/

SET NOCOUNT ON;  -- no "(n rows affected)" messages, so the final SELECT is the only result

DECLARE @actions TABLE (action_taken NVARCHAR(10));  -- one row per INSERT/UPDATE the MERGE does
DECLARE @changelog_rows INT;

-- 1. Log changed fields (milestone 6) ------------------------------------------
--    Must run BEFORE the MERGE: afterwards dbo.Grants already holds the new values.
--    The inner JOIN keeps only appl_ids that already exist, so new grants aren't logged.
--    CROSS APPLY (VALUES ...) unpivots: one wide row becomes 13 rows of
--    (field_name, old_value, new_value). Values become text so they fit one column;
--    style 23 writes dates as yyyy-mm-dd.
INSERT INTO dbo.ChangeLog (appl_id, field_name, old_value, new_value)
SELECT t.appl_id, v.field_name, v.old_value, v.new_value
FROM dbo.Grants AS t
JOIN dbo.Grants_Staging AS s
    ON s.appl_id = t.appl_id
CROSS APPLY (VALUES
    ('project_num',        CONVERT(NVARCHAR(400), t.project_num),            CONVERT(NVARCHAR(400), s.project_num)),
    ('core_project_num',   CONVERT(NVARCHAR(400), t.core_project_num),       CONVERT(NVARCHAR(400), s.core_project_num)),
    ('fiscal_year',        CONVERT(NVARCHAR(400), t.fiscal_year),            CONVERT(NVARCHAR(400), s.fiscal_year)),
    ('activity_code',      CONVERT(NVARCHAR(400), t.activity_code),          CONVERT(NVARCHAR(400), s.activity_code)),
    ('project_title',      t.project_title,                                  s.project_title),
    ('contact_pi_name',    t.contact_pi_name,                                s.contact_pi_name),
    ('award_amount',       CONVERT(NVARCHAR(400), t.award_amount),           CONVERT(NVARCHAR(400), s.award_amount)),
    ('direct_cost_amt',    CONVERT(NVARCHAR(400), t.direct_cost_amt),        CONVERT(NVARCHAR(400), s.direct_cost_amt)),
    ('indirect_cost_amt',  CONVERT(NVARCHAR(400), t.indirect_cost_amt),      CONVERT(NVARCHAR(400), s.indirect_cost_amt)),
    ('project_start_date', CONVERT(NVARCHAR(10), t.project_start_date, 23),  CONVERT(NVARCHAR(10), s.project_start_date, 23)),
    ('project_end_date',   CONVERT(NVARCHAR(10), t.project_end_date, 23),    CONVERT(NVARCHAR(10), s.project_end_date, 23)),
    ('budget_start',       CONVERT(NVARCHAR(10), t.budget_start, 23),        CONVERT(NVARCHAR(10), s.budget_start, 23)),
    ('budget_end',         CONVERT(NVARCHAR(10), t.budget_end, 23),          CONVERT(NVARCHAR(10), s.budget_end, 23))
) AS v (field_name, old_value, new_value)
-- "Old differs from new", NULL-safe: same EXCEPT trick as the MERGE below,
-- so a field that is blank on both sides doesn't count as a change.
WHERE EXISTS (SELECT v.old_value EXCEPT SELECT v.new_value);

SET @changelog_rows = @@ROWCOUNT;  -- rows the INSERT just added (read it right away)

-- 2. Upsert ---------------------------------------------------------------------

MERGE dbo.Grants WITH (HOLDLOCK) AS t   -- HOLDLOCK: stop two loads inserting the same key at once
USING dbo.Grants_Staging AS s
    ON t.appl_id = s.appl_id

-- Row exists and at least one column differs. EXCEPT treats NULL = NULL as equal.
WHEN MATCHED AND EXISTS (
        SELECT s.project_num, s.core_project_num, s.fiscal_year, s.activity_code,
               s.project_title, s.contact_pi_name,
               s.award_amount, s.direct_cost_amt, s.indirect_cost_amt,
               s.project_start_date, s.project_end_date, s.budget_start, s.budget_end
        EXCEPT
        SELECT t.project_num, t.core_project_num, t.fiscal_year, t.activity_code,
               t.project_title, t.contact_pi_name,
               t.award_amount, t.direct_cost_amt, t.indirect_cost_amt,
               t.project_start_date, t.project_end_date, t.budget_start, t.budget_end
    )
    THEN UPDATE SET
        t.project_num        = s.project_num,
        t.core_project_num   = s.core_project_num,
        t.fiscal_year        = s.fiscal_year,
        t.activity_code      = s.activity_code,
        t.project_title      = s.project_title,
        t.contact_pi_name    = s.contact_pi_name,
        t.award_amount       = s.award_amount,
        t.direct_cost_amt    = s.direct_cost_amt,
        t.indirect_cost_amt  = s.indirect_cost_amt,
        t.project_start_date = s.project_start_date,
        t.project_end_date   = s.project_end_date,
        t.budget_start       = s.budget_start,
        t.budget_end         = s.budget_end,
        t.updated_at         = SYSUTCDATETIME()

-- New appl_id: insert it. inserted_at and updated_at fill from their defaults.
WHEN NOT MATCHED BY TARGET
    THEN INSERT (appl_id, project_num, core_project_num, fiscal_year, activity_code,
                 project_title, contact_pi_name,
                 award_amount, direct_cost_amt, indirect_cost_amt,
                 project_start_date, project_end_date, budget_start, budget_end)
         VALUES (s.appl_id, s.project_num, s.core_project_num, s.fiscal_year, s.activity_code,
                 s.project_title, s.contact_pi_name,
                 s.award_amount, s.direct_cost_amt, s.indirect_cost_amt,
                 s.project_start_date, s.project_end_date, s.budget_start, s.budget_end)

-- No WHEN NOT MATCHED BY SOURCE ... DELETE on purpose: a grant missing from
-- one pull is not deleted automatically.

OUTPUT $action INTO @actions (action_taken);  -- $action is 'INSERT' or 'UPDATE'

SELECT
    (SELECT COUNT(*) FROM dbo.Grants_Staging)          AS staged_rows,
    COUNT(CASE WHEN action_taken = N'INSERT' THEN 1 END) AS inserted_rows,
    COUNT(CASE WHEN action_taken = N'UPDATE' THEN 1 END) AS updated_rows,
    @changelog_rows                                      AS changelog_rows
FROM @actions;
