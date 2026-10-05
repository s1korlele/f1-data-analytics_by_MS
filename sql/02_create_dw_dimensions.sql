USE F1Analytics;
GO

/*
    F1 Analytics - Data Warehouse dimensions

    Założenia modelu:
    - model obsługuje wiele sezonów,
    - kraj, tor, weekend Grand Prix i sesja są osobnymi bytami,
    - typ sesji jest osobnym słownikiem,
    - kierowca i zespół są osobnymi wymiarami,
    - przypisanie kierowcy do zespołu będzie przechowywane w faktach,
      dzięki czemu zmiana zespołu w trakcie sezonu nie wymaga osobnej tabeli relacji,
    - flagi i kategorie Race Control są osobnymi słownikami.

*/

-- =========================================================
-- DimSeason
-- 1 rekord = 1 sezon Formula 1
-- =========================================================
CREATE TABLE dw.DimSeason (
    SeasonKey       INT IDENTITY(1,1) NOT NULL,
    SeasonYear      SMALLINT NOT NULL,

    CONSTRAINT PK_DimSeason
        PRIMARY KEY (SeasonKey),

    CONSTRAINT UQ_DimSeason_SeasonYear
        UNIQUE (SeasonYear)
);
GO


-- =========================================================
-- DimCountry
-- 1 rekord = 1 kraj
-- =========================================================
CREATE TABLE dw.DimCountry (
    CountryKey      INT IDENTITY(1,1) NOT NULL,
    CountryCode     VARCHAR(10) NOT NULL,
    CountryName     NVARCHAR(100) NOT NULL,
    CountryFlag     NVARCHAR(500) NULL,

    CONSTRAINT PK_DimCountry
        PRIMARY KEY (CountryKey),

    CONSTRAINT UQ_DimCountry_CountryCode
        UNIQUE (CountryCode)
);
GO


-- =========================================================
-- DimCircuit
-- 1 rekord = 1 tor
-- =========================================================
CREATE TABLE dw.DimCircuit (
    CircuitKey          INT IDENTITY(1,1) NOT NULL,
    SourceCircuitKey    INT NOT NULL,
    CountryKey          INT NOT NULL,
    CircuitShortName    NVARCHAR(100) NOT NULL,
    CircuitType         NVARCHAR(50) NULL,
    CircuitImage        NVARCHAR(500) NULL,
    Location            NVARCHAR(100) NULL,

    CONSTRAINT PK_DimCircuit
        PRIMARY KEY (CircuitKey),

    CONSTRAINT UQ_DimCircuit_SourceCircuitKey
        UNIQUE (SourceCircuitKey),

    CONSTRAINT FK_DimCircuit_DimCountry
        FOREIGN KEY (CountryKey)
        REFERENCES dw.DimCountry(CountryKey)
);
GO


-- =========================================================
-- DimRace
-- 1 rekord = 1 weekend Grand Prix w konkretnym sezonie
-- =========================================================
CREATE TABLE dw.DimRace (
    RaceKey             INT IDENTITY(1,1) NOT NULL,
    SourceMeetingKey    INT NOT NULL,
    SeasonKey           INT NOT NULL,
    CircuitKey          INT NOT NULL,
    RoundNumber         TINYINT NULL,
    RaceName            NVARCHAR(150) NOT NULL,
    DateStart           DATETIMEOFFSET(6) NULL,
    DateEnd             DATETIMEOFFSET(6) NULL,
    IsCancelled         BIT NOT NULL,

    CONSTRAINT PK_DimRace
        PRIMARY KEY (RaceKey),

    CONSTRAINT UQ_DimRace_SourceMeetingKey
        UNIQUE (SourceMeetingKey),

    CONSTRAINT UQ_DimRace_SeasonRound
        UNIQUE (SeasonKey, RoundNumber),

    CONSTRAINT FK_DimRace_DimSeason
        FOREIGN KEY (SeasonKey)
        REFERENCES dw.DimSeason(SeasonKey),

    CONSTRAINT FK_DimRace_DimCircuit
        FOREIGN KEY (CircuitKey)
        REFERENCES dw.DimCircuit(CircuitKey)
);
GO


-- =========================================================
-- DimSessionType
-- 1 rekord = 1 typ sesji
-- np. Practice, Qualifying, Sprint, Race
-- =========================================================
CREATE TABLE dw.DimSessionType (
    SessionTypeKey      INT IDENTITY(1,1) NOT NULL,
    SessionTypeName     NVARCHAR(50) NOT NULL,

    CONSTRAINT PK_DimSessionType
        PRIMARY KEY (SessionTypeKey),

    CONSTRAINT UQ_DimSessionType_SessionTypeName
        UNIQUE (SessionTypeName)
);
GO


-- =========================================================
-- DimSession
-- 1 rekord = 1 konkretna sesja podczas weekendu Grand Prix
-- np. Australian GP 2025 - Practice 1
-- =========================================================
CREATE TABLE dw.DimSession (
    SessionKey          INT IDENTITY(1,1) NOT NULL,
    SourceSessionKey    INT NOT NULL,
    RaceKey             INT NOT NULL,
    SessionTypeKey      INT NOT NULL,
    SessionName         NVARCHAR(100) NOT NULL,
    DateStart           DATETIMEOFFSET(6) NULL,
    DateEnd             DATETIMEOFFSET(6) NULL,
    IsCancelled         BIT NOT NULL,

    CONSTRAINT PK_DimSession
        PRIMARY KEY (SessionKey),

    CONSTRAINT UQ_DimSession_SourceSessionKey
        UNIQUE (SourceSessionKey),

    CONSTRAINT FK_DimSession_DimRace
        FOREIGN KEY (RaceKey)
        REFERENCES dw.DimRace(RaceKey),

    CONSTRAINT FK_DimSession_DimSessionType
        FOREIGN KEY (SessionTypeKey)
        REFERENCES dw.DimSessionType(SessionTypeKey)
);
GO


-- =========================================================
-- DimDriver
-- 1 rekord = 1 kierowca
-- Zespół NIE jest tutaj przechowywany.
-- Zespół kierowcy będzie wynikał z tabel faktów.
-- =========================================================
CREATE TABLE dw.DimDriver (
    DriverKey           INT IDENTITY(1,1) NOT NULL,
    DriverNumber        INT NULL,
    FullName            NVARCHAR(100) NOT NULL,
    FirstName           NVARCHAR(100) NULL,
    LastName            NVARCHAR(100) NULL,
    NameAcronym         VARCHAR(10) NULL,
    HeadshotUrl         NVARCHAR(500) NULL,

    CONSTRAINT PK_DimDriver
        PRIMARY KEY (DriverKey),

    CONSTRAINT UQ_DimDriver_FullName
        UNIQUE (FullName)
);
GO


-- =========================================================
-- DimTeam
-- 1 rekord = 1 zespół
-- Przypisanie kierowcy do zespołu będzie w tabelach faktów.
-- =========================================================
CREATE TABLE dw.DimTeam (
    TeamKey             INT IDENTITY(1,1) NOT NULL,
    TeamName            NVARCHAR(100) NOT NULL,
    TeamColour          VARCHAR(20) NULL,

    CONSTRAINT PK_DimTeam
        PRIMARY KEY (TeamKey),

    CONSTRAINT UQ_DimTeam_TeamName
        UNIQUE (TeamName)
);
GO


-- =========================================================
-- DimFlag
-- Słownik flag wykorzystywany przez FactRaceControl
-- =========================================================
CREATE TABLE dw.DimFlag (
    FlagKey             INT IDENTITY(1,1) NOT NULL,
    FlagName            NVARCHAR(50) NOT NULL,

    CONSTRAINT PK_DimFlag
        PRIMARY KEY (FlagKey),

    CONSTRAINT UQ_DimFlag_FlagName
        UNIQUE (FlagName)
);
GO


-- =========================================================
-- DimRaceControlCategory
-- Słownik kategorii komunikatów Race Control
-- =========================================================
CREATE TABLE dw.DimRaceControlCategory (
    RaceControlCategoryKey     INT IDENTITY(1,1) NOT NULL,
    CategoryName               NVARCHAR(100) NOT NULL,

    CONSTRAINT PK_DimRaceControlCategory
        PRIMARY KEY (RaceControlCategoryKey),

    CONSTRAINT UQ_DimRaceControlCategory_CategoryName
        UNIQUE (CategoryName)
);
GO


-- =========================================================
-- Kontrola utworzonych wymiarów
-- =========================================================
SELECT
    s.name AS schema_name,
    t.name AS table_name
FROM sys.tables AS t
JOIN sys.schemas AS s
    ON t.schema_id = s.schema_id
WHERE s.name = 'dw'
ORDER BY t.name;
GO
