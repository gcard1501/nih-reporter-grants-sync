/* Milestone 4: create the ReporterGrants database and its tables.

   Safe to re-run: every object is created only if it doesn't exist yet.
   Note: re-running will NOT change a table that already exists. To change
   a column later, write an ALTER TABLE (or drop and recreate in dev).

   Run in VS Code: open this file, connect to the container (localhost,1433,
   login sa), then Execute Query (Cmd+Shift+E).
*/

-- 1. Database ---------------------------------------------------------------
IF DB_ID(N'ReporterGrants') IS NULL
    CREATE DATABASE ReporterGrants;
GO

USE ReporterGrants;
GO

-- 2. Main table: one row per RePORTER application (appl_id) -------------------
--    appl_id is the key because project_num repeats for multi-component
--    grants (e.g. U19 subprojects share one project_num in the same year).
IF OBJECT_ID(N'dbo.Grants', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Grants (
        appl_id            INT            NOT NULL,
        project_num        VARCHAR(25)    NOT NULL,  -- e.g. 5R01EB023878-05 (changes each year)
        core_project_num   VARCHAR(15)    NOT NULL,  -- e.g. R01EB023878 (same across years)
        fiscal_year        SMALLINT       NOT NULL,
        activity_code      VARCHAR(5)     NULL,      -- grant type, e.g. R01
        project_title      NVARCHAR(400)  NULL,      -- NVARCHAR: titles can contain non-ASCII characters
        contact_pi_name    NVARCHAR(100)  NULL,
        award_amount       DECIMAL(14,2)  NULL,
        direct_cost_amt    DECIMAL(14,2)  NULL,      -- blank for a few records in the API
        indirect_cost_amt  DECIMAL(14,2)  NULL,
        project_start_date DATE           NULL,
        project_end_date   DATE           NULL,
        budget_start       DATE           NULL,
        budget_end         DATE           NULL,
        inserted_at        DATETIME2(0)   NOT NULL CONSTRAINT DF_Grants_inserted_at DEFAULT SYSUTCDATETIME(),
        updated_at         DATETIME2(0)   NOT NULL CONSTRAINT DF_Grants_updated_at  DEFAULT SYSUTCDATETIME(),
        CONSTRAINT PK_Grants PRIMARY KEY CLUSTERED (appl_id)
    );

    -- Not unique on purpose; milestone 5 will join on these.
    CREATE NONCLUSTERED INDEX IX_Grants_project_num      ON dbo.Grants (project_num);
    CREATE NONCLUSTERED INDEX IX_Grants_core_project_num ON dbo.Grants (core_project_num);
END;
GO

-- 3. Staging table: a scratch copy of the CSV, emptied at the start of each load.
--    Same data columns and types, but no key and no audit columns.
IF OBJECT_ID(N'dbo.Grants_Staging', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Grants_Staging (
        appl_id            INT            NULL,
        project_num        VARCHAR(25)    NULL,
        core_project_num   VARCHAR(15)    NULL,
        fiscal_year        SMALLINT       NULL,
        activity_code      VARCHAR(5)     NULL,
        project_title      NVARCHAR(400)  NULL,
        contact_pi_name    NVARCHAR(100)  NULL,
        award_amount       DECIMAL(14,2)  NULL,
        direct_cost_amt    DECIMAL(14,2)  NULL,
        indirect_cost_amt  DECIMAL(14,2)  NULL,
        project_start_date DATE           NULL,
        project_end_date   DATE           NULL,
        budget_start       DATE           NULL,
        budget_end         DATE           NULL
    );
END;
GO

-- 4. Check ---------------------------------------------------------------------
SELECT t.name AS table_name, COUNT(c.column_id) AS column_count
FROM sys.tables AS t
JOIN sys.columns AS c ON c.object_id = t.object_id
GROUP BY t.name
ORDER BY t.name;
