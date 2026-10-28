USE F1Analytics;
GO

/* ============================================================
   F1 Analytics - DW load logging
   Logs executions of dimension/fact loading procedures.
   Existing SSIS logging (etl.PackageRun / etl.TaskRun) remains unchanged.
   ============================================================ */

IF SCHEMA_ID(N'etl') IS NULL
    EXEC(N'CREATE SCHEMA etl');
GO

/* ============================================================
   1. Run header
   ============================================================ */
IF OBJECT_ID(N'etl.DwLoadRun', N'U') IS NULL
BEGIN
    CREATE TABLE etl.DwLoadRun
    (
        DwLoadRunKey       BIGINT IDENTITY(1,1) NOT NULL
            CONSTRAINT PK_DwLoadRun PRIMARY KEY,
        LoadName           NVARCHAR(200) NOT NULL,
        ExecutionSource    NVARCHAR(50)  NOT NULL,
        StartedAt          DATETIME2(3)  NOT NULL,
        FinishedAt         DATETIME2(3)  NULL,
        DurationSeconds    DECIMAL(18,3) NULL,
        Status             NVARCHAR(20)  NOT NULL,
        TriggeredBy        NVARCHAR(128) NULL,
        HostName           NVARCHAR(128) NULL,
        ErrorNumber        INT NULL,
        ErrorMessage       NVARCHAR(4000) NULL,

        CONSTRAINT CK_DwLoadRun_Status
            CHECK (Status IN (N'RUNNING', N'SUCCEEDED', N'FAILED'))
    );
END;
GO

/* ============================================================
   2. Individual procedure execution log
   ============================================================ */
IF OBJECT_ID(N'etl.DwLoadStepRun', N'U') IS NULL
BEGIN
    CREATE TABLE etl.DwLoadStepRun
    (
        DwLoadStepRunKey   BIGINT IDENTITY(1,1) NOT NULL
            CONSTRAINT PK_DwLoadStepRun PRIMARY KEY,
        DwLoadRunKey       BIGINT NOT NULL,
        StepOrder          INT NOT NULL,
        StepName           NVARCHAR(200) NOT NULL,
        StepType           NVARCHAR(30) NOT NULL,
        ProcedureName      NVARCHAR(261) NOT NULL,
        StartedAt          DATETIME2(3) NOT NULL,
        FinishedAt         DATETIME2(3) NULL,
        DurationSeconds    DECIMAL(18,3) NULL,
        Status             NVARCHAR(20) NOT NULL,
        RowsAffected       BIGINT NULL,
        ErrorNumber        INT NULL,
        ErrorMessage       NVARCHAR(4000) NULL,

        CONSTRAINT FK_DwLoadStepRun_DwLoadRun
            FOREIGN KEY (DwLoadRunKey)
            REFERENCES etl.DwLoadRun(DwLoadRunKey),

        CONSTRAINT CK_DwLoadStepRun_Status
            CHECK (Status IN (N'RUNNING', N'SUCCEEDED', N'FAILED')),

        CONSTRAINT CK_DwLoadStepRun_StepType
            CHECK (StepType IN (N'DIMENSION', N'FACT'))
    );

    CREATE INDEX IX_DwLoadStepRun_Run_Order
        ON etl.DwLoadStepRun(DwLoadRunKey, StepOrder, DwLoadStepRunKey);
END;
GO

/* ============================================================
   3. Start a DW load run
   ============================================================ */
CREATE OR ALTER PROCEDURE etl.usp_StartDwLoadRun
    @LoadName        NVARCHAR(200),
    @ExecutionSource NVARCHAR(50) = N'MANUAL',
    @DwLoadRunKey    BIGINT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO etl.DwLoadRun
    (
        LoadName,
        ExecutionSource,
        StartedAt,
        Status,
        TriggeredBy,
        HostName
    )
    VALUES
    (
        @LoadName,
        @ExecutionSource,
        SYSDATETIME(),
        N'RUNNING',
        SUSER_SNAME(),
        HOST_NAME()
    );

    SET @DwLoadRunKey = CONVERT(BIGINT, SCOPE_IDENTITY());
END;
GO

/* ============================================================
   4. Finish a DW load run
   ============================================================ */
CREATE OR ALTER PROCEDURE etl.usp_EndDwLoadRun
    @DwLoadRunKey BIGINT,
    @Status       NVARCHAR(20),
    @ErrorNumber  INT = NULL,
    @ErrorMessage NVARCHAR(4000) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @Status NOT IN (N'SUCCEEDED', N'FAILED')
        THROW 50001, N'Invalid final DW load status. Expected SUCCEEDED or FAILED.', 1;

    DECLARE @FinishedAt DATETIME2(3) = SYSDATETIME();

    UPDATE etl.DwLoadRun
    SET
        FinishedAt       = @FinishedAt,
        DurationSeconds  = CONVERT(DECIMAL(18,3),
                                   DATEDIFF_BIG(MILLISECOND, StartedAt, @FinishedAt) / 1000.0),
        Status            = @Status,
        ErrorNumber       = @ErrorNumber,
        ErrorMessage      = @ErrorMessage
    WHERE DwLoadRunKey = @DwLoadRunKey;

    IF @@ROWCOUNT = 0
        THROW 50002, N'DW load run not found.', 1;
END;
GO

/* ============================================================
   5. Generic logged procedure executor
   Only two-part procedure names are accepted: schema.procedure
   ============================================================ */
CREATE OR ALTER PROCEDURE etl.usp_ExecuteLoggedDwProcedure
    @DwLoadRunKey  BIGINT,
    @StepOrder     INT,
    @StepName      NVARCHAR(200),
    @StepType      NVARCHAR(30),
    @ProcedureName NVARCHAR(261)
AS
BEGIN
    SET NOCOUNT ON;

    IF @StepType NOT IN (N'DIMENSION', N'FACT')
        THROW 50003, N'Invalid step type. Expected DIMENSION or FACT.', 1;

    IF NOT EXISTS
    (
        SELECT 1
        FROM etl.DwLoadRun
        WHERE DwLoadRunKey = @DwLoadRunKey
          AND Status = N'RUNNING'
    )
        THROW 50004, N'DW load run does not exist or is not RUNNING.', 1;

    DECLARE
        @DwLoadStepRunKey BIGINT,
        @StartedAt        DATETIME2(3) = SYSDATETIME(),
        @FinishedAt       DATETIME2(3),
        @SchemaName       SYSNAME,
        @ProcName         SYSNAME,
        @Sql              NVARCHAR(MAX),
        @ValidationError  NVARCHAR(2048);

    INSERT INTO etl.DwLoadStepRun
    (
        DwLoadRunKey,
        StepOrder,
        StepName,
        StepType,
        ProcedureName,
        StartedAt,
        Status
    )
    VALUES
    (
        @DwLoadRunKey,
        @StepOrder,
        @StepName,
        @StepType,
        @ProcedureName,
        @StartedAt,
        N'RUNNING'
    );

    SET @DwLoadStepRunKey = CONVERT(BIGINT, SCOPE_IDENTITY());

    BEGIN TRY
        SET @SchemaName = PARSENAME(@ProcedureName, 2);
        SET @ProcName   = PARSENAME(@ProcedureName, 1);

        IF @SchemaName IS NULL
           OR @ProcName IS NULL
           OR PARSENAME(@ProcedureName, 3) IS NOT NULL
           OR PARSENAME(@ProcedureName, 4) IS NOT NULL
        BEGIN
            SET @ValidationError = N'ProcedureName must use two-part format: schema.procedure.';
            THROW 50005, @ValidationError, 1;
        END;

        IF OBJECT_ID(@SchemaName + N'.' + @ProcName, N'P') IS NULL
        BEGIN
            SET @ValidationError = N'Procedure not found: ' + @ProcedureName;
            THROW 50006, @ValidationError, 1;
        END;

        SET @Sql = N'EXEC ' + QUOTENAME(@SchemaName) + N'.' + QUOTENAME(@ProcName) + N';';

        EXEC sys.sp_executesql @Sql;

        SET @FinishedAt = SYSDATETIME();

        UPDATE etl.DwLoadStepRun
        SET
            FinishedAt      = @FinishedAt,
            DurationSeconds = CONVERT(DECIMAL(18,3),
                                      DATEDIFF_BIG(MILLISECOND, StartedAt, @FinishedAt) / 1000.0),
            Status           = N'SUCCEEDED'
        WHERE DwLoadStepRunKey = @DwLoadStepRunKey;
    END TRY
    BEGIN CATCH
        DECLARE
            @CaughtErrorNumber  INT = ERROR_NUMBER(),
            @CaughtErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();

        SET @FinishedAt = SYSDATETIME();

        -- Jeżeli wywołana procedura pozostawiła aktywną lub
        -- niezatwierdzalną transakcję, najpierw ją wycofujemy.
        -- Inaczej próba zapisania statusu FAILED kończy się 3930
        -- i maskuje pierwotny błąd ETL.
        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;

        UPDATE etl.DwLoadStepRun
        SET
            FinishedAt      = @FinishedAt,
            DurationSeconds = CONVERT(DECIMAL(18,3),
                                      DATEDIFF_BIG(MILLISECOND, StartedAt, @FinishedAt) / 1000.0),
            Status           = N'FAILED',
            ErrorNumber      = @CaughtErrorNumber,
            ErrorMessage     = @CaughtErrorMessage
        WHERE DwLoadStepRunKey = @DwLoadStepRunKey;

        THROW;
    END CATCH;
END;
GO

/* ============================================================
   6. Dimension wrapper with per-procedure logging
   ============================================================ */
CREATE OR ALTER PROCEDURE dw.usp_LoadAllDimensions
    @DwLoadRunKey BIGINT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE
        @OwnRun       BIT = 0,
        @ErrorNumber  INT,
        @ErrorMessage NVARCHAR(4000);

    IF @DwLoadRunKey IS NULL
    BEGIN
        SET @OwnRun = 1;

        EXEC etl.usp_StartDwLoadRun
            @LoadName        = N'F1Analytics Dimensions Load',
            @ExecutionSource = N'MANUAL',
            @DwLoadRunKey    = @DwLoadRunKey OUTPUT;
    END;

    BEGIN TRY
        EXEC etl.usp_ExecuteLoggedDwProcedure @DwLoadRunKey, 110, N'Load DimSeason',              N'DIMENSION', N'dw.usp_LoadDimSeason';
        EXEC etl.usp_ExecuteLoggedDwProcedure @DwLoadRunKey, 120, N'Load DimCountry',             N'DIMENSION', N'dw.usp_LoadDimCountry';
        EXEC etl.usp_ExecuteLoggedDwProcedure @DwLoadRunKey, 130, N'Load DimCircuit',             N'DIMENSION', N'dw.usp_LoadDimCircuit';
        EXEC etl.usp_ExecuteLoggedDwProcedure @DwLoadRunKey, 140, N'Load DimRaceWeekend',         N'DIMENSION', N'dw.usp_LoadDimRaceWeekend';
        EXEC etl.usp_ExecuteLoggedDwProcedure @DwLoadRunKey, 150, N'Load DimSessionType',         N'DIMENSION', N'dw.usp_LoadDimSessionType';
        EXEC etl.usp_ExecuteLoggedDwProcedure @DwLoadRunKey, 160, N'Load DimSession',             N'DIMENSION', N'dw.usp_LoadDimSession';
        EXEC etl.usp_ExecuteLoggedDwProcedure @DwLoadRunKey, 170, N'Load DimDriver',              N'DIMENSION', N'dw.usp_LoadDimDriver';
        EXEC etl.usp_ExecuteLoggedDwProcedure @DwLoadRunKey, 180, N'Load DimTeam',                N'DIMENSION', N'dw.usp_LoadDimTeam';
        EXEC etl.usp_ExecuteLoggedDwProcedure @DwLoadRunKey, 190, N'Load DimTeamColour',          N'DIMENSION', N'dw.usp_LoadDimTeamColour';
        EXEC etl.usp_ExecuteLoggedDwProcedure @DwLoadRunKey, 200, N'Load DimFlag',                N'DIMENSION', N'dw.usp_LoadDimFlag';
        EXEC etl.usp_ExecuteLoggedDwProcedure @DwLoadRunKey, 210, N'Load DimRaceControlCategory', N'DIMENSION', N'dw.usp_LoadDimRaceControlCategory';

        IF @OwnRun = 1
        BEGIN
            EXEC etl.usp_EndDwLoadRun
                @DwLoadRunKey = @DwLoadRunKey,
                @Status       = N'SUCCEEDED';
        END;
    END TRY
    BEGIN CATCH
        SET @ErrorNumber  = ERROR_NUMBER();
        SET @ErrorMessage = ERROR_MESSAGE();

        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;

        IF @OwnRun = 1
           AND EXISTS (
                SELECT 1
                FROM etl.DwLoadRun
                WHERE DwLoadRunKey = @DwLoadRunKey
           )
        BEGIN
            EXEC etl.usp_EndDwLoadRun
                @DwLoadRunKey = @DwLoadRunKey,
                @Status       = N'FAILED',
                @ErrorNumber  = @ErrorNumber,
                @ErrorMessage = @ErrorMessage;
        END;

        THROW;
    END CATCH;
END;
GO

/* ============================================================
   7. Fact wrapper with per-procedure logging
   ============================================================ */
CREATE OR ALTER PROCEDURE dw.usp_LoadAllFacts
    @DwLoadRunKey BIGINT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE
        @OwnRun       BIT = 0,
        @ErrorNumber  INT,
        @ErrorMessage NVARCHAR(4000);

    IF @DwLoadRunKey IS NULL
    BEGIN
        SET @OwnRun = 1;

        EXEC etl.usp_StartDwLoadRun
            @LoadName        = N'F1Analytics Facts Load',
            @ExecutionSource = N'MANUAL',
            @DwLoadRunKey    = @DwLoadRunKey OUTPUT;
    END;

    BEGIN TRY
        EXEC etl.usp_ExecuteLoggedDwProcedure @DwLoadRunKey, 310, N'Load FactSessionResult', N'FACT', N'dw.usp_LoadFactSessionResult';
        EXEC etl.usp_ExecuteLoggedDwProcedure @DwLoadRunKey, 320, N'Load FactLap',           N'FACT', N'dw.usp_LoadFactLap';
        EXEC etl.usp_ExecuteLoggedDwProcedure @DwLoadRunKey, 330, N'Load FactStint',         N'FACT', N'dw.usp_LoadFactStint';
        EXEC etl.usp_ExecuteLoggedDwProcedure @DwLoadRunKey, 340, N'Load FactPitStop',       N'FACT', N'dw.usp_LoadFactPitStop';
        EXEC etl.usp_ExecuteLoggedDwProcedure @DwLoadRunKey, 350, N'Load FactWeather',       N'FACT', N'dw.usp_LoadFactWeather';
        EXEC etl.usp_ExecuteLoggedDwProcedure @DwLoadRunKey, 360, N'Load FactRaceControl',   N'FACT', N'dw.usp_LoadFactRaceControl';
        EXEC etl.usp_ExecuteLoggedDwProcedure @DwLoadRunKey, 370, N'Load FactAttendance',    N'FACT', N'dw.usp_LoadFactAttendance';

        IF @OwnRun = 1
        BEGIN
            EXEC etl.usp_EndDwLoadRun
                @DwLoadRunKey = @DwLoadRunKey,
                @Status       = N'SUCCEEDED';
        END;
    END TRY
    BEGIN CATCH
        SET @ErrorNumber  = ERROR_NUMBER();
        SET @ErrorMessage = ERROR_MESSAGE();

        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;

        IF @OwnRun = 1
           AND EXISTS (
                SELECT 1
                FROM etl.DwLoadRun
                WHERE DwLoadRunKey = @DwLoadRunKey
           )
        BEGIN
            EXEC etl.usp_EndDwLoadRun
                @DwLoadRunKey = @DwLoadRunKey,
                @Status       = N'FAILED',
                @ErrorNumber  = @ErrorNumber,
                @ErrorMessage = @ErrorMessage;
        END;

        THROW;
    END CATCH;
END;
GO

/* ============================================================
   8. One entry point for the full DW load
   This is what SQL Server Agent will call later.
   ============================================================ */
CREATE OR ALTER PROCEDURE etl.usp_RunDwLoad
    @ExecutionSource NVARCHAR(50) = N'MANUAL'
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE
        @DwLoadRunKey BIGINT,
        @ErrorNumber  INT,
        @ErrorMessage NVARCHAR(4000);

    EXEC etl.usp_StartDwLoadRun
        @LoadName        = N'F1Analytics DW Load',
        @ExecutionSource = @ExecutionSource,
        @DwLoadRunKey    = @DwLoadRunKey OUTPUT;

    BEGIN TRY
        EXEC dw.usp_LoadAllDimensions @DwLoadRunKey = @DwLoadRunKey;
        EXEC dw.usp_LoadAllFacts      @DwLoadRunKey = @DwLoadRunKey;

        EXEC etl.usp_EndDwLoadRun
            @DwLoadRunKey = @DwLoadRunKey,
            @Status       = N'SUCCEEDED';
    END TRY
    BEGIN CATCH
        SET @ErrorNumber  = ERROR_NUMBER();
        SET @ErrorMessage = ERROR_MESSAGE();

        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;

        -- Jeżeli rollback objął także rekord runa (np. przy
        -- zewnętrznej/implicit transaction), nie generujemy
        -- wtórnego 50002. Najważniejsze jest zachowanie
        -- pierwotnego błędu ETL.
        IF EXISTS (
            SELECT 1
            FROM etl.DwLoadRun
            WHERE DwLoadRunKey = @DwLoadRunKey
        )
        BEGIN
            EXEC etl.usp_EndDwLoadRun
                @DwLoadRunKey = @DwLoadRunKey,
                @Status       = N'FAILED',
                @ErrorNumber  = @ErrorNumber,
                @ErrorMessage = @ErrorMessage;
        END;

        THROW;
    END CATCH;
END;
GO

/* ============================================================
   9. Useful monitoring view
   ============================================================ */
CREATE OR ALTER VIEW etl.vw_DwLoadHistory
AS
SELECT
    r.DwLoadRunKey,
    r.LoadName,
    r.ExecutionSource,
    r.Status AS RunStatus,
    r.StartedAt AS RunStartedAt,
    r.FinishedAt AS RunFinishedAt,
    r.DurationSeconds AS RunDurationSeconds,
    r.TriggeredBy,
    r.HostName,
    r.ErrorNumber AS RunErrorNumber,
    r.ErrorMessage AS RunErrorMessage,
    s.DwLoadStepRunKey,
    s.StepOrder,
    s.StepName,
    s.StepType,
    s.ProcedureName,
    s.Status AS StepStatus,
    s.StartedAt AS StepStartedAt,
    s.FinishedAt AS StepFinishedAt,
    s.DurationSeconds AS StepDurationSeconds,
    s.RowsAffected,
    s.ErrorNumber AS StepErrorNumber,
    s.ErrorMessage AS StepErrorMessage
FROM etl.DwLoadRun AS r
LEFT JOIN etl.DwLoadStepRun AS s
    ON s.DwLoadRunKey = r.DwLoadRunKey;
GO

/* ============================================================
   Manual test:

   EXEC etl.usp_RunDwLoad @ExecutionSource = N'MANUAL';

   SELECT TOP (20) *
   FROM etl.DwLoadRun
   ORDER BY DwLoadRunKey DESC;

   SELECT *
   FROM etl.vw_DwLoadHistory
   WHERE DwLoadRunKey = (SELECT MAX(DwLoadRunKey) FROM etl.DwLoadRun)
   ORDER BY StepOrder, DwLoadStepRunKey;
   ============================================================ */
