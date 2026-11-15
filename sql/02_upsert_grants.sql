/* Milestone 4: upsert dbo.Grants_Staging into dbo.Grants.

   Run by load_grants.py after it fills the staging table, inside the same
   transaction. You can also run it by hand in VS Code (USE ReporterGrants first).

   - New appl_id            -> INSERT
   - Existing, data changed  -> UPDATE (and stamp updated_at)
   - Existing, no change     -> left alone (updated_at keeps its old value)
   - In Grants but not in staging -> left alone (no automatic deletes)

   Returns one row: staged_rows, inserted_rows, updated_rows.
*/

SET NOCOUNT ON;  -- no "(n rows affected)" messages, so the final SELECT is the only result

DECLARE @actions TABLE (action_taken NVARCHAR(10));  -- one row per INSERT/UPDATE the MERGE does

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
    COUNT(CASE WHEN action_taken = N'UPDATE' THEN 1 END) AS updated_rows
FROM @actions;
