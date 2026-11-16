/* Milestone 6: ChangeLog table, an audit trail of changed values.

   sql/02_upsert_grants.sql adds one row here for every field whose value
   changed on a re-run of load_grants.py (before the MERGE overwrites it).
   New grants (inserts) are not logged: they are new rows, not changes.

   Safe to re-run: the table is created only if it doesn't exist yet.
   Run in VS Code: open this file, connect, then Execute Query (Cmd+Shift+E).
*/

USE ReporterGrants;
GO

IF OBJECT_ID(N'dbo.ChangeLog', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.ChangeLog (
        change_id   INT IDENTITY(1,1) NOT NULL,   -- surrogate key, just numbers the rows
        appl_id     INT            NOT NULL,      -- which grant changed (key of dbo.Grants)
        field_name  VARCHAR(50)    NOT NULL,      -- which column changed, e.g. award_amount
        -- Stored as text because the fields have different types (money, dates, text).
        -- 400 fits the longest field, project_title. NULL = the value was blank.
        old_value   NVARCHAR(400)  NULL,
        new_value   NVARCHAR(400)  NULL,
        changed_at  DATETIME2(0)   NOT NULL CONSTRAINT DF_ChangeLog_changed_at DEFAULT SYSUTCDATETIME(),  -- UTC, like dbo.Grants
        CONSTRAINT PK_ChangeLog PRIMARY KEY CLUSTERED (change_id)
    );

    -- Speeds up "show me the history of one grant".
    CREATE NONCLUSTERED INDEX IX_ChangeLog_appl_id ON dbo.ChangeLog (appl_id, changed_at);
END;
GO

-- Check: list the new table's columns.
SELECT c.column_id, c.name AS column_name, TYPE_NAME(c.user_type_id) AS data_type, c.is_nullable
FROM sys.columns AS c
WHERE c.object_id = OBJECT_ID(N'dbo.ChangeLog')
ORDER BY c.column_id;
