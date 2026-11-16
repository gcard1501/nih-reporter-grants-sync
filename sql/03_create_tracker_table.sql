/* Milestone 5: table for the fake "internal grants tracker".

   The tracker is a hand-maintained list of grants (fake, built from public
   RePORTER data with deliberate errors). load_tracker.py replaces its rows
   on every run; sql/04_reconcile.sql compares it to dbo.Grants.

   Safe to re-run: the table is created only if it doesn't exist yet.
   Run in VS Code: open this file, connect, then Execute Query (Cmd+Shift+E).
*/

USE ReporterGrants;
GO

IF OBJECT_ID(N'dbo.Tracker_Grants', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Tracker_Grants (
        -- Surrogate key: just numbers the rows. project_num is NOT the key on
        -- purpose, so a duplicate row in the tracker still loads and the
        -- reconciliation query can flag it.
        tracker_row_id     INT IDENTITY(1,1) NOT NULL,
        project_num        VARCHAR(25)    NOT NULL,  -- join key to dbo.Grants
        contact_pi_name    NVARCHAR(100)  NULL,
        award_amount       DECIMAL(14,2)  NULL,
        project_start_date DATE           NULL,
        project_end_date   DATE           NULL,
        loaded_at          DATETIME2(0)   NOT NULL CONSTRAINT DF_Tracker_Grants_loaded_at DEFAULT SYSUTCDATETIME(),
        CONSTRAINT PK_Tracker_Grants PRIMARY KEY CLUSTERED (tracker_row_id)
    );

    -- Not unique on purpose (see above); speeds up the join on project_num.
    CREATE NONCLUSTERED INDEX IX_Tracker_Grants_project_num ON dbo.Tracker_Grants (project_num);
END;
GO

-- Check: list the new table's columns.
SELECT c.column_id, c.name AS column_name, TYPE_NAME(c.user_type_id) AS data_type, c.is_nullable
FROM sys.columns AS c
WHERE c.object_id = OBJECT_ID(N'dbo.Tracker_Grants')
ORDER BY c.column_id;
