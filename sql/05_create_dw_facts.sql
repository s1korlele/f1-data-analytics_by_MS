USE F1Analytics;
GO

/*
    F1 Analytics - DW facts

    Aktualne facty:
    - FactRaceResult
    - FactQualifyingResult
    - FactLap
    - FactStint
    - FactPitStop
    - FactWeather
    - FactRaceControl
    - FactAttendance

    Konwencja czasu:
    - kolumny czasowe w DW są typu DATETIME2(6),
    - przechowują lokalny czas Polski (CET/CEST),
    - offset nie jest przechowywany w nazwie ani w typie kolumny.

    Zasada modelu:
    - RaceWeekendKey przechowujemy bezpośrednio w factach,
      żeby uprościć filtrowanie i relacje w Power BI.
    - SessionKey wskazuje konkretną sesję.
    - DriverKey / TeamKey / TeamColourKey są rozwiązywane podczas ETL.
*/

IF SCHEMA_ID(N'dw') IS NULL
    EXEC(N'CREATE SCHEMA dw');
GO


-- =========================================================
-- Drop facts
-- =========================================================

DROP TABLE IF EXISTS dw.FactAttendance;
DROP TABLE IF EXISTS dw.FactRaceControl;
DROP TABLE IF EXISTS dw.FactWeather;
DROP TABLE IF EXISTS dw.FactPitStop;
DROP TABLE IF EXISTS dw.FactStint;
DROP TABLE IF EXISTS dw.FactLap;
DROP TABLE IF EXISTS dw.FactQualifyingResult;
DROP TABLE IF EXISTS dw.FactRaceResult;
GO


-- =========================================================
-- FactRaceResult
-- Grain: 1 rekord = 1 kierowca w 1 sesji Race
-- =========================================================

CREATE TABLE dw.FactRaceResult (
    RaceResultKey           BIGINT IDENTITY(1,1) NOT NULL,

    RaceWeekendKey          INT NOT NULL,
    SessionKey              INT NOT NULL,
    DriverKey               INT NOT NULL,
    TeamKey                 INT NOT NULL,
    TeamColourKey           INT NULL,

    GridPosition            SMALLINT NULL,
    FinishPosition          SMALLINT NULL,
    NumberOfLaps            SMALLINT NULL,
    Points                  DECIMAL(6,2) NULL,

    DNF                     BIT NULL,
    DNS                     BIT NULL,
    DSQ                     BIT NULL,

    DurationSeconds         DECIMAL(12,3) NULL,
    GapToLeaderSeconds      DECIMAL(12,3) NULL,
    GapToLeaderText         NVARCHAR(50) NULL,

    CONSTRAINT PK_FactRaceResult
        PRIMARY KEY (RaceResultKey),

    CONSTRAINT UQ_FactRaceResult_Session_Driver
        UNIQUE (SessionKey, DriverKey),

    CONSTRAINT FK_FactRaceResult_DimRaceWeekend
        FOREIGN KEY (RaceWeekendKey)
        REFERENCES dw.DimRaceWeekend(RaceWeekendKey),

    CONSTRAINT FK_FactRaceResult_DimSession
        FOREIGN KEY (SessionKey)
        REFERENCES dw.DimSession(SessionKey),

    CONSTRAINT FK_FactRaceResult_DimDriver
        FOREIGN KEY (DriverKey)
        REFERENCES dw.DimDriver(DriverKey),

    CONSTRAINT FK_FactRaceResult_DimTeam
        FOREIGN KEY (TeamKey)
        REFERENCES dw.DimTeam(TeamKey),

    CONSTRAINT FK_FactRaceResult_DimTeamColour
        FOREIGN KEY (TeamColourKey)
        REFERENCES dw.DimTeamColour(TeamColourKey)
);
GO

CREATE INDEX IX_FactRaceResult_RaceWeekend_Driver
    ON dw.FactRaceResult (RaceWeekendKey, DriverKey);
GO

CREATE INDEX IX_FactRaceResult_Session
    ON dw.FactRaceResult (SessionKey);
GO

CREATE INDEX IX_FactRaceResult_Team
    ON dw.FactRaceResult (TeamKey);
GO


-- =========================================================
-- FactQualifyingResult
-- Grain: 1 rekord = 1 kierowca w 1 sesji kwalifikacyjnej
-- Obejmuje Qualifying oraz Sprint Qualifying.
-- =========================================================

CREATE TABLE dw.FactQualifyingResult (
    QualifyingResultKey         BIGINT IDENTITY(1,1) NOT NULL,

    RaceWeekendKey              INT NOT NULL,
    SessionKey                  INT NOT NULL,
    DriverKey                   INT NOT NULL,
    TeamKey                     INT NOT NULL,
    TeamColourKey               INT NULL,

    Position                    SMALLINT NULL,
    NumberOfLaps                SMALLINT NULL,

    Phase1DurationSeconds       DECIMAL(12,3) NULL,
    Phase2DurationSeconds       DECIMAL(12,3) NULL,
    Phase3DurationSeconds       DECIMAL(12,3) NULL,

    Phase1GapToLeaderSeconds    DECIMAL(12,3) NULL,
    Phase2GapToLeaderSeconds    DECIMAL(12,3) NULL,
    Phase3GapToLeaderSeconds    DECIMAL(12,3) NULL,

    DNF                         BIT NULL,
    DNS                         BIT NULL,
    DSQ                         BIT NULL,

    CONSTRAINT PK_FactQualifyingResult
        PRIMARY KEY (QualifyingResultKey),

    CONSTRAINT UQ_FactQualifyingResult_Session_Driver
        UNIQUE (SessionKey, DriverKey),

    CONSTRAINT FK_FactQualifyingResult_DimRaceWeekend
        FOREIGN KEY (RaceWeekendKey)
        REFERENCES dw.DimRaceWeekend(RaceWeekendKey),

    CONSTRAINT FK_FactQualifyingResult_DimSession
        FOREIGN KEY (SessionKey)
        REFERENCES dw.DimSession(SessionKey),

    CONSTRAINT FK_FactQualifyingResult_DimDriver
        FOREIGN KEY (DriverKey)
        REFERENCES dw.DimDriver(DriverKey),

    CONSTRAINT FK_FactQualifyingResult_DimTeam
        FOREIGN KEY (TeamKey)
        REFERENCES dw.DimTeam(TeamKey),

    CONSTRAINT FK_FactQualifyingResult_DimTeamColour
        FOREIGN KEY (TeamColourKey)
        REFERENCES dw.DimTeamColour(TeamColourKey)
);
GO

CREATE INDEX IX_FactQualifyingResult_RaceWeekend_Driver
    ON dw.FactQualifyingResult (RaceWeekendKey, DriverKey);
GO

CREATE INDEX IX_FactQualifyingResult_Session
    ON dw.FactQualifyingResult (SessionKey);
GO

CREATE INDEX IX_FactQualifyingResult_Team
    ON dw.FactQualifyingResult (TeamKey);
GO


-- =========================================================
-- FactLap
-- Grain: 1 rekord = 1 okrążenie kierowcy w 1 sesji
-- =========================================================

CREATE TABLE dw.FactLap (
    LapKey                  BIGINT IDENTITY(1,1) NOT NULL,

    RaceWeekendKey          INT NOT NULL,
    SessionKey              INT NOT NULL,
    DriverKey               INT NOT NULL,
    TeamKey                 INT NOT NULL,
    TeamColourKey           INT NULL,

    LapNumber               SMALLINT NOT NULL,
    LapStartTime            DATETIME2(6) NULL,

    LapDurationSeconds      DECIMAL(12,3) NULL,
    Sector1DurationSeconds  DECIMAL(12,3) NULL,
    Sector2DurationSeconds  DECIMAL(12,3) NULL,
    Sector3DurationSeconds  DECIMAL(12,3) NULL,

    I1Speed                 DECIMAL(8,3) NULL,
    I2Speed                 DECIMAL(8,3) NULL,
    STSpeed                 DECIMAL(8,3) NULL,

    IsPitOutLap             BIT NULL,

    CONSTRAINT PK_FactLap
        PRIMARY KEY (LapKey),

    CONSTRAINT UQ_FactLap_Session_Driver_Lap
        UNIQUE (SessionKey, DriverKey, LapNumber),

    CONSTRAINT FK_FactLap_DimRaceWeekend
        FOREIGN KEY (RaceWeekendKey)
        REFERENCES dw.DimRaceWeekend(RaceWeekendKey),

    CONSTRAINT FK_FactLap_DimSession
        FOREIGN KEY (SessionKey)
        REFERENCES dw.DimSession(SessionKey),

    CONSTRAINT FK_FactLap_DimDriver
        FOREIGN KEY (DriverKey)
        REFERENCES dw.DimDriver(DriverKey),

    CONSTRAINT FK_FactLap_DimTeam
        FOREIGN KEY (TeamKey)
        REFERENCES dw.DimTeam(TeamKey),

    CONSTRAINT FK_FactLap_DimTeamColour
        FOREIGN KEY (TeamColourKey)
        REFERENCES dw.DimTeamColour(TeamColourKey)
);
GO

CREATE INDEX IX_FactLap_RaceWeekend_Driver
    ON dw.FactLap (RaceWeekendKey, DriverKey);
GO

CREATE INDEX IX_FactLap_Session_Driver
    ON dw.FactLap (SessionKey, DriverKey);
GO

CREATE INDEX IX_FactLap_LapStartTime
    ON dw.FactLap (LapStartTime);
GO


-- =========================================================
-- FactStint
-- Grain: 1 rekord = 1 stint kierowcy w 1 sesji
-- =========================================================

CREATE TABLE dw.FactStint (
    StintKey            BIGINT IDENTITY(1,1) NOT NULL,

    RaceWeekendKey      INT NOT NULL,
    SessionKey          INT NOT NULL,
    DriverKey           INT NOT NULL,
    TeamKey             INT NOT NULL,
    TeamColourKey       INT NULL,

    StintNumber         SMALLINT NOT NULL,
    Compound            NVARCHAR(50) NULL,
    LapStart            SMALLINT NULL,
    LapEnd              SMALLINT NULL,
    TyreAgeAtStart      DECIMAL(6,2) NULL,

    CONSTRAINT PK_FactStint
        PRIMARY KEY (StintKey),

    CONSTRAINT UQ_FactStint_Session_Driver_Stint
        UNIQUE (SessionKey, DriverKey, StintNumber),

    CONSTRAINT FK_FactStint_DimRaceWeekend
        FOREIGN KEY (RaceWeekendKey)
        REFERENCES dw.DimRaceWeekend(RaceWeekendKey),

    CONSTRAINT FK_FactStint_DimSession
        FOREIGN KEY (SessionKey)
        REFERENCES dw.DimSession(SessionKey),

    CONSTRAINT FK_FactStint_DimDriver
        FOREIGN KEY (DriverKey)
        REFERENCES dw.DimDriver(DriverKey),

    CONSTRAINT FK_FactStint_DimTeam
        FOREIGN KEY (TeamKey)
        REFERENCES dw.DimTeam(TeamKey),

    CONSTRAINT FK_FactStint_DimTeamColour
        FOREIGN KEY (TeamColourKey)
        REFERENCES dw.DimTeamColour(TeamColourKey),

    CONSTRAINT CK_FactStint_LapRange
        CHECK (
            LapStart IS NULL
            OR LapEnd IS NULL
            OR LapEnd >= LapStart - 1
        )
);
GO

CREATE INDEX IX_FactStint_RaceWeekend_Driver
    ON dw.FactStint (RaceWeekendKey, DriverKey);
GO

CREATE INDEX IX_FactStint_Session_Driver
    ON dw.FactStint (SessionKey, DriverKey);
GO

CREATE INDEX IX_FactStint_Compound
    ON dw.FactStint (Compound);
GO


-- =========================================================
-- FactPitStop
-- Grain:
-- 1 rekord = 1 pit stop kierowcy na 1 okrążeniu w 1 sesji
-- =========================================================

CREATE TABLE dw.FactPitStop (
    PitStopKey              BIGINT IDENTITY(1,1) NOT NULL,

    RaceWeekendKey          INT NOT NULL,
    SessionKey              INT NOT NULL,
    DriverKey               INT NOT NULL,
    TeamKey                 INT NOT NULL,
    TeamColourKey           INT NULL,

    LapNumber               SMALLINT NOT NULL,
    PitStopTime             DATETIME2(6) NULL,
    LaneDurationSeconds     DECIMAL(12,3) NULL,
    StopDurationSeconds     DECIMAL(12,3) NULL,

    CONSTRAINT PK_FactPitStop
        PRIMARY KEY (PitStopKey),

    CONSTRAINT UQ_FactPitStop_Session_Driver_Lap
        UNIQUE (SessionKey, DriverKey, LapNumber),

    CONSTRAINT FK_FactPitStop_DimRaceWeekend
        FOREIGN KEY (RaceWeekendKey)
        REFERENCES dw.DimRaceWeekend(RaceWeekendKey),

    CONSTRAINT FK_FactPitStop_DimSession
        FOREIGN KEY (SessionKey)
        REFERENCES dw.DimSession(SessionKey),

    CONSTRAINT FK_FactPitStop_DimDriver
        FOREIGN KEY (DriverKey)
        REFERENCES dw.DimDriver(DriverKey),

    CONSTRAINT FK_FactPitStop_DimTeam
        FOREIGN KEY (TeamKey)
        REFERENCES dw.DimTeam(TeamKey),

    CONSTRAINT FK_FactPitStop_DimTeamColour
        FOREIGN KEY (TeamColourKey)
        REFERENCES dw.DimTeamColour(TeamColourKey)
);
GO

CREATE INDEX IX_FactPitStop_RaceWeekend_Driver
    ON dw.FactPitStop (RaceWeekendKey, DriverKey);
GO

CREATE INDEX IX_FactPitStop_Session_Driver
    ON dw.FactPitStop (SessionKey, DriverKey);
GO

CREATE INDEX IX_FactPitStop_PitStopTime
    ON dw.FactPitStop (PitStopTime);
GO


-- =========================================================
-- FactWeather
-- Grain:
-- 1 rekord = 1 pomiar pogody w konkretnym momencie sesji
-- =========================================================

CREATE TABLE dw.FactWeather (
    WeatherKey              BIGINT IDENTITY(1,1) NOT NULL,

    RaceWeekendKey          INT NOT NULL,
    SessionKey              INT NOT NULL,

    WeatherTime             DATETIME2(6) NOT NULL,

    AirTemperature          DECIMAL(6,2) NULL,
    TrackTemperature        DECIMAL(6,2) NULL,
    Humidity                DECIMAL(6,2) NULL,
    Pressure                DECIMAL(8,2) NULL,
    Rainfall                BIT NULL,
    WindDirection           DECIMAL(6,2) NULL,
    WindSpeed               DECIMAL(8,3) NULL,

    CONSTRAINT PK_FactWeather
        PRIMARY KEY (WeatherKey),

    CONSTRAINT UQ_FactWeather_Session_Time
        UNIQUE (SessionKey, WeatherTime),

    CONSTRAINT FK_FactWeather_DimRaceWeekend
        FOREIGN KEY (RaceWeekendKey)
        REFERENCES dw.DimRaceWeekend(RaceWeekendKey),

    CONSTRAINT FK_FactWeather_DimSession
        FOREIGN KEY (SessionKey)
        REFERENCES dw.DimSession(SessionKey),

    CONSTRAINT CK_FactWeather_Humidity
        CHECK (
            Humidity IS NULL
            OR (Humidity >= 0 AND Humidity <= 100)
        ),

    CONSTRAINT CK_FactWeather_WindDirection
        CHECK (
            WindDirection IS NULL
            OR (WindDirection >= 0 AND WindDirection <= 360)
        )
);
GO

CREATE INDEX IX_FactWeather_RaceWeekend
    ON dw.FactWeather (RaceWeekendKey);
GO

CREATE INDEX IX_FactWeather_WeatherTime
    ON dw.FactWeather (WeatherTime);
GO


-- =========================================================
-- FactRaceControl
-- Grain:
-- 1 rekord = 1 komunikat / zdarzenie Race Control
-- w konkretnym momencie sesji
--
-- driver_number = 0 w źródle oznacza brak konkretnego
-- kierowcy dla zdarzenia. W DW daje to DriverKey = NULL.
-- =========================================================

CREATE TABLE dw.FactRaceControl (
    RaceControlKey              BIGINT IDENTITY(1,1) NOT NULL,

    RaceWeekendKey              INT NOT NULL,
    SessionKey                  INT NOT NULL,

    DriverKey                   INT NULL,
    TeamKey                     INT NULL,
    TeamColourKey               INT NULL,

    RaceControlCategoryKey      INT NULL,
    FlagKey                     INT NULL,

    EventTime                   DATETIME2(6) NOT NULL,
    LapNumber                   SMALLINT NULL,
    Scope                       NVARCHAR(50) NULL,
    Sector                      SMALLINT NULL,
    Message                     NVARCHAR(MAX) NULL,

    CONSTRAINT PK_FactRaceControl
        PRIMARY KEY (RaceControlKey),

    CONSTRAINT FK_FactRaceControl_DimRaceWeekend
        FOREIGN KEY (RaceWeekendKey)
        REFERENCES dw.DimRaceWeekend(RaceWeekendKey),

    CONSTRAINT FK_FactRaceControl_DimSession
        FOREIGN KEY (SessionKey)
        REFERENCES dw.DimSession(SessionKey),

    CONSTRAINT FK_FactRaceControl_DimDriver
        FOREIGN KEY (DriverKey)
        REFERENCES dw.DimDriver(DriverKey),

    CONSTRAINT FK_FactRaceControl_DimTeam
        FOREIGN KEY (TeamKey)
        REFERENCES dw.DimTeam(TeamKey),

    CONSTRAINT FK_FactRaceControl_DimTeamColour
        FOREIGN KEY (TeamColourKey)
        REFERENCES dw.DimTeamColour(TeamColourKey),

    CONSTRAINT FK_FactRaceControl_DimRaceControlCategory
        FOREIGN KEY (RaceControlCategoryKey)
        REFERENCES dw.DimRaceControlCategory(RaceControlCategoryKey),

    CONSTRAINT FK_FactRaceControl_DimFlag
        FOREIGN KEY (FlagKey)
        REFERENCES dw.DimFlag(FlagKey)
);
GO

CREATE INDEX IX_FactRaceControl_RaceWeekend
    ON dw.FactRaceControl (RaceWeekendKey);
GO

CREATE INDEX IX_FactRaceControl_Session_Time
    ON dw.FactRaceControl (SessionKey, EventTime);
GO

CREATE INDEX IX_FactRaceControl_Driver
    ON dw.FactRaceControl (DriverKey)
    WHERE DriverKey IS NOT NULL;
GO

CREATE INDEX IX_FactRaceControl_Category
    ON dw.FactRaceControl (RaceControlCategoryKey);
GO

CREATE INDEX IX_FactRaceControl_Flag
    ON dw.FactRaceControl (FlagKey)
    WHERE FlagKey IS NOT NULL;
GO


-- =========================================================
-- FactAttendance
-- Grain:
-- 1 rekord = 1 weekend Grand Prix
-- =========================================================

CREATE TABLE dw.FactAttendance (
    AttendanceKey          BIGINT IDENTITY(1,1) NOT NULL,

    RaceWeekendKey         INT NOT NULL,

    WeekendAttendance      INT NULL,
    RaceDayAttendance      INT NULL,

    SourceDate             DATE NULL,
    SourceUrl              NVARCHAR(2000) NULL,
    Notes                  NVARCHAR(MAX) NULL,

    CONSTRAINT PK_FactAttendance
        PRIMARY KEY (AttendanceKey),

    CONSTRAINT UQ_FactAttendance_RaceWeekend
        UNIQUE (RaceWeekendKey),

    CONSTRAINT FK_FactAttendance_DimRaceWeekend
        FOREIGN KEY (RaceWeekendKey)
        REFERENCES dw.DimRaceWeekend(RaceWeekendKey),

    CONSTRAINT CK_FactAttendance_WeekendAttendance
        CHECK (
            WeekendAttendance IS NULL
            OR WeekendAttendance >= 0
        ),

    CONSTRAINT CK_FactAttendance_RaceDayAttendance
        CHECK (
            RaceDayAttendance IS NULL
            OR RaceDayAttendance >= 0
        )
);
GO

CREATE INDEX IX_FactAttendance_RaceWeekend
    ON dw.FactAttendance (RaceWeekendKey);
GO


-- =========================================================
-- Kontrola
-- =========================================================

SELECT
    s.name AS SchemaName,
    t.name AS TableName
FROM sys.tables AS t
JOIN sys.schemas AS s
    ON s.schema_id = t.schema_id
WHERE s.name = N'dw'
  AND t.name LIKE N'Fact%'
ORDER BY t.name;
GO
