USE F1Analytics;
GO

/*
    F1 Analytics - ETL framework

    Schemat etl przechowuje:
    - konfigurację ładowania plików CSV do warstwy stg,
    - log całych uruchomień procesu ETL,
    - log poszczególnych kroków / plików / procedur.

    Wersja uproszczona:
    - zostawiamy tylko constrainty potrzebne dla integralności danych,
    - rezygnujemy z nadmiarowych CHECK i UNIQUE,
    - daty logów zapisujemy w UTC.
*/


-- =========================================================
-- Schemat ETL
-- =========================================================
IF SCHEMA_ID('etl') IS NULL
    EXEC('CREATE SCHEMA etl');
GO


-- =========================================================
-- etl.LoadConfig
-- 1 rekord = 1 typ datasetu ładowany do jednej tabeli stg
-- =========================================================
IF OBJECT_ID('etl.LoadConfig', 'U') IS NULL
BEGIN
    CREATE TABLE etl.LoadConfig (
        LoadConfigKey          INT IDENTITY(1,1) PRIMARY KEY,
        DatasetName            NVARCHAR(100) NOT NULL UNIQUE,
        SourceFolder           NVARCHAR(500) NOT NULL,
        FilePattern            NVARCHAR(255) NOT NULL,
        TargetSchema           SYSNAME NOT NULL,
        TargetTable            SYSNAME NOT NULL,
        LoadOrder              SMALLINT NOT NULL,
        TruncateBeforeLoad     BIT NOT NULL DEFAULT (1),
        HasHeader              BIT NOT NULL DEFAULT (1),
        Delimiter              NCHAR(1) NOT NULL DEFAULT (N','),
        IsActive               BIT NOT NULL DEFAULT (1)
    );
END;
GO


-- =========================================================
-- etl.PackageRun
-- 1 rekord = 1 pełne uruchomienie pakietu / procesu ETL
-- =========================================================
IF OBJECT_ID('etl.PackageRun', 'U') IS NULL
BEGIN
    CREATE TABLE etl.PackageRun (
        PackageRunKey      BIGINT IDENTITY(1,1) PRIMARY KEY,
        RunGuid            UNIQUEIDENTIFIER NOT NULL DEFAULT (NEWID()),
        PackageName        NVARCHAR(200) NOT NULL,
        Status             VARCHAR(20) NOT NULL DEFAULT ('RUNNING'),
        StartedAtUtc       DATETIME2(3) NOT NULL DEFAULT (SYSUTCDATETIME()),
        FinishedAtUtc      DATETIME2(3) NULL,

        DurationSeconds AS (
            CASE
                WHEN FinishedAtUtc IS NULL THEN NULL
                ELSE CONVERT(
                    DECIMAL(18,3),
                    DATEDIFF_BIG(
                        MILLISECOND,
                        StartedAtUtc,
                        FinishedAtUtc
                    )
                ) / 1000
            END
        ),

        HostName           NVARCHAR(128) NULL DEFAULT (HOST_NAME()),
        LoginName          NVARCHAR(128) NULL DEFAULT (ORIGINAL_LOGIN()),
        ErrorMessage       NVARCHAR(4000) NULL,

        UNIQUE (RunGuid),

        CHECK (
            Status IN (
                'RUNNING',
                'SUCCEEDED',
                'FAILED',
                'SKIPPED'
            )
        )
    );
END;
GO


-- =========================================================
-- etl.TaskRun
-- 1 rekord = 1 krok należący do konkretnego PackageRun
--
-- TaskType:
-- CSV_LOAD  - ładowanie CSV do stg
-- SQL_PROC  - wykonanie procedury SQL
-- OTHER     - pozostały krok
-- =========================================================
IF OBJECT_ID('etl.TaskRun', 'U') IS NULL
BEGIN
    CREATE TABLE etl.TaskRun (
        TaskRunKey         BIGINT IDENTITY(1,1) PRIMARY KEY,
        PackageRunKey      BIGINT NOT NULL,
        LoadConfigKey      INT NULL,
        TaskName           NVARCHAR(200) NOT NULL,
        TaskType           VARCHAR(20) NOT NULL,
        Status             VARCHAR(20) NOT NULL DEFAULT ('RUNNING'),

        SourceName         NVARCHAR(1000) NULL,
        TargetName         NVARCHAR(300) NULL,
        ProcedureName      NVARCHAR(300) NULL,

        StartedAtUtc       DATETIME2(3) NOT NULL DEFAULT (SYSUTCDATETIME()),
        FinishedAtUtc      DATETIME2(3) NULL,

        DurationSeconds AS (
            CASE
                WHEN FinishedAtUtc IS NULL THEN NULL
                ELSE CONVERT(
                    DECIMAL(18,3),
                    DATEDIFF_BIG(
                        MILLISECOND,
                        StartedAtUtc,
                        FinishedAtUtc
                    )
                ) / 1000
            END
        ),

        RowsRead           BIGINT NULL,
        RowsInserted       BIGINT NULL,
        RowsUpdated        BIGINT NULL,
        RowsRejected       BIGINT NULL,

        ErrorMessage       NVARCHAR(4000) NULL,

        FOREIGN KEY (PackageRunKey)
            REFERENCES etl.PackageRun(PackageRunKey),

        FOREIGN KEY (LoadConfigKey)
            REFERENCES etl.LoadConfig(LoadConfigKey),

        CHECK (
            TaskType IN (
                'CSV_LOAD',
                'SQL_PROC',
                'OTHER'
            )
        ),

        CHECK (
            Status IN (
                'RUNNING',
                'SUCCEEDED',
                'FAILED',
                'SKIPPED'
            )
        )
    );
END;
GO


-- =========================================================
-- Indeksy logów
-- =========================================================
IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IX_PackageRun_Status_StartedAtUtc'
      AND object_id = OBJECT_ID('etl.PackageRun')
)
BEGIN
    CREATE INDEX IX_PackageRun_Status_StartedAtUtc
        ON etl.PackageRun (Status, StartedAtUtc DESC);
END;
GO


IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IX_TaskRun_PackageRunKey'
      AND object_id = OBJECT_ID('etl.TaskRun')
)
BEGIN
    CREATE INDEX IX_TaskRun_PackageRunKey
        ON etl.TaskRun (PackageRunKey);
END;
GO


-- =========================================================
-- Konfiguracja datasetów
-- FilePattern obsługuje wiele sezonów:
-- np. laps_2024.csv, laps_2025.csv, laps_2026.csv
-- =========================================================
MERGE etl.LoadConfig AS target
USING (
    VALUES
        (N'Meetings',          N'data\processed', N'meetings_*.csv',           N'stg', N'Meetings',          10, 1, 1, N',', 1),
        (N'Sessions',          N'data\processed', N'sessions_*.csv',           N'stg', N'Sessions',          20, 1, 1, N',', 1),
        (N'Drivers',           N'data\processed', N'drivers_*.csv',            N'stg', N'Drivers',           30, 1, 1, N',', 1),
        (N'RaceControl',       N'data\processed', N'race_control_*.csv',       N'stg', N'RaceControl',       40, 1, 1, N',', 1),
        (N'RaceResults',       N'data\processed', N'race_results_*.csv',       N'stg', N'RaceResults',       50, 1, 1, N',', 1),
        (N'Laps',              N'data\processed', N'laps_*.csv',               N'stg', N'Laps',              60, 1, 1, N',', 1),
        (N'Stints',            N'data\processed', N'stints_*.csv',             N'stg', N'Stints',            70, 1, 1, N',', 1),
        (N'PitStops',          N'data\processed', N'pit_stops_*.csv',          N'stg', N'PitStops',          80, 1, 1, N',', 1),
        (N'Weather',           N'data\processed', N'weather_*.csv',            N'stg', N'Weather',           90, 1, 1, N',', 1),
        (N'QualifyingResults', N'data\processed', N'qualifying_results_*.csv', N'stg', N'QualifyingResults', 100, 1, 1, N',', 1),
        (N'StartingGrid',      N'data\processed', N'starting_grid_*.csv',      N'stg', N'StartingGrid',     110, 1, 1, N',', 1),
        (N'Attendance',        N'data\processed', N'attendance_*.csv',         N'stg', N'Attendance',       120, 1, 1, N',', 1)
) AS source (
    DatasetName,
    SourceFolder,
    FilePattern,
    TargetSchema,
    TargetTable,
    LoadOrder,
    TruncateBeforeLoad,
    HasHeader,
    Delimiter,
    IsActive
)
ON target.DatasetName = source.DatasetName

WHEN MATCHED THEN
    UPDATE SET
        target.SourceFolder = source.SourceFolder,
        target.FilePattern = source.FilePattern,
        target.TargetSchema = source.TargetSchema,
        target.TargetTable = source.TargetTable,
        target.LoadOrder = source.LoadOrder,
        target.TruncateBeforeLoad = source.TruncateBeforeLoad,
        target.HasHeader = source.HasHeader,
        target.Delimiter = source.Delimiter,
        target.IsActive = source.IsActive

WHEN NOT MATCHED THEN
    INSERT (
        DatasetName,
        SourceFolder,
        FilePattern,
        TargetSchema,
        TargetTable,
        LoadOrder,
        TruncateBeforeLoad,
        HasHeader,
        Delimiter,
        IsActive
    )
    VALUES (
        source.DatasetName,
        source.SourceFolder,
        source.FilePattern,
        source.TargetSchema,
        source.TargetTable,
        source.LoadOrder,
        source.TruncateBeforeLoad,
        source.HasHeader,
        source.Delimiter,
        source.IsActive
    );
GO


-- =========================================================
-- Kontrola konfiguracji
-- =========================================================
SELECT
    LoadConfigKey,
    DatasetName,
    SourceFolder,
    FilePattern,
    TargetSchema,
    TargetTable,
    LoadOrder,
    TruncateBeforeLoad,
    IsActive
FROM etl.LoadConfig
ORDER BY LoadOrder;
GO


-- =========================================================
-- Kontrola tabel ETL
-- =========================================================
SELECT
    s.name AS schema_name,
    t.name AS table_name
FROM sys.tables AS t
JOIN sys.schemas AS s
    ON t.schema_id = s.schema_id
WHERE s.name = 'etl'
ORDER BY t.name;
GO
