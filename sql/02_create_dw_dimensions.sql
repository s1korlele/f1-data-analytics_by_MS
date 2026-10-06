USE F1Analytics;
GO

/*
    F1 Analytics - DW dimensions
    Wersja po finalnych ustaleniach dotyczących wymiarów.

    Model:
    - DimSeason
    - DimCountry
    - DimCircuit
    - DimRaceWeekend
    - DimSessionType
    - DimSession
    - DimDriver               -> SCD Type 2
    - DimTeam                 -> stabilna tożsamość zespołu
    - DimTeamColour           -> unikalne wartości team_colour zespołu
    - DimFlag
    - DimRaceControlCategory

    Ważne:
    - Nie tworzymy żadnej tabeli mapującej Team/Livery do sesji.
      Dokładne połączenie Session + Driver + Team + TeamLivery
      zostanie wykonane dopiero przy budowie factów.
    - TeamColour nie jest SCD2. Jeśli kolor wraca po specjalnym malowaniu,
      używamy ponownie tego samego TeamColourKey.
    - DimDriver pozostaje SCD2, ponieważ chcemy zachować historię takich
      atrybutów jak HeadshotUrl czy DriverNumber.
*/

IF SCHEMA_ID(N'dw') IS NULL
    EXEC(N'CREATE SCHEMA dw');
GO


/*
    UWAGA:
    Ten skrypt przebudowuje aktualne tabele wymiarów.
    Na obecnym etapie jest to bezpieczne, ponieważ facty nie zostały
    jeszcze utworzone / załadowane.
*/

DROP TABLE IF EXISTS dw.BridgeDriverTeamSession;
DROP TABLE IF EXISTS dw.DriverTeamSession;
DROP TABLE IF EXISTS dw.BridgeTeamSessionLivery;
DROP TABLE IF EXISTS dw.DimDriverSeason;
DROP TABLE IF EXISTS dw.DimTeamSeason;
DROP TABLE IF EXISTS dw.DimTeamVersion;

DROP TABLE IF EXISTS dw.DimTeamColour;
DROP TABLE IF EXISTS dw.DimSession;
DROP TABLE IF EXISTS dw.DimRaceWeekend;
DROP TABLE IF EXISTS dw.DimRace;
DROP TABLE IF EXISTS dw.DimCircuit;
DROP TABLE IF EXISTS dw.DimCountry;
DROP TABLE IF EXISTS dw.DimSessionType;
DROP TABLE IF EXISTS dw.DimDriver;
DROP TABLE IF EXISTS dw.DimTeam;
DROP TABLE IF EXISTS dw.DimFlag;
DROP TABLE IF EXISTS dw.DimRaceControlCategory;
DROP TABLE IF EXISTS dw.DimSeason;
GO


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
-- SourceCircuitKey = circuit_key ze źródła OpenF1
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
-- DimRaceWeekend
-- 1 rekord = 1 weekend Grand Prix
-- =========================================================

CREATE TABLE dw.DimRaceWeekend (
    RaceWeekendKey      INT IDENTITY(1,1) NOT NULL,
    SourceMeetingKey    INT NOT NULL,
    SeasonKey           INT NOT NULL,
    CircuitKey          INT NOT NULL,
    RoundNumber         TINYINT NOT NULL,
    RaceWeekendName     NVARCHAR(150) NOT NULL,
    DateStart           DATETIMEOFFSET(6) NULL,
    DateEnd             DATETIMEOFFSET(6) NULL,
    IsCancelled         BIT NOT NULL,

    CONSTRAINT PK_DimRaceWeekend
        PRIMARY KEY (RaceWeekendKey),

    CONSTRAINT UQ_DimRaceWeekend_SourceMeetingKey
        UNIQUE (SourceMeetingKey),

    CONSTRAINT UQ_DimRaceWeekend_SeasonRound
        UNIQUE (SeasonKey, RoundNumber),

    CONSTRAINT FK_DimRaceWeekend_DimSeason
        FOREIGN KEY (SeasonKey)
        REFERENCES dw.DimSeason(SeasonKey),

    CONSTRAINT FK_DimRaceWeekend_DimCircuit
        FOREIGN KEY (CircuitKey)
        REFERENCES dw.DimCircuit(CircuitKey)
);
GO


-- =========================================================
-- DimSessionType
-- 1 rekord = 1 typ sesji
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
-- 1 rekord = 1 konkretna sesja podczas weekendu GP
-- SourceSessionKey = session_key ze źródła OpenF1
-- =========================================================

CREATE TABLE dw.DimSession (
    SessionKey          INT IDENTITY(1,1) NOT NULL,
    SourceSessionKey    INT NOT NULL,
    RaceWeekendKey      INT NOT NULL,
    SessionTypeKey      INT NOT NULL,
    SessionName         NVARCHAR(100) NOT NULL,
    DateStart           DATETIMEOFFSET(6) NULL,
    DateEnd             DATETIMEOFFSET(6) NULL,
    IsCancelled         BIT NOT NULL,

    CONSTRAINT PK_DimSession
        PRIMARY KEY (SessionKey),

    CONSTRAINT UQ_DimSession_SourceSessionKey
        UNIQUE (SourceSessionKey),

    CONSTRAINT FK_DimSession_DimRaceWeekend
        FOREIGN KEY (RaceWeekendKey)
        REFERENCES dw.DimRaceWeekend(RaceWeekendKey),

    CONSTRAINT FK_DimSession_DimSessionType
        FOREIGN KEY (SessionTypeKey)
        REFERENCES dw.DimSessionType(SessionTypeKey)
);
GO


-- =========================================================
-- DimDriver - SCD Type 2
--
-- DriverBusinessKey:
-- obecnie używamy oczyszczonego FullName, ponieważ staging
-- nie zawiera trwałego driver_id ze źródła.
--
-- TeamName i TeamColour NIE należą do DimDriver.
-- =========================================================

CREATE TABLE dw.DimDriver (
    DriverKey           INT IDENTITY(1,1) NOT NULL,
    DriverBusinessKey   NVARCHAR(100) NOT NULL,

    DriverNumber        INT NULL,
    FullName            NVARCHAR(100) NOT NULL,
    FirstName           NVARCHAR(100) NULL,
    LastName            NVARCHAR(100) NULL,
    NameAcronym         VARCHAR(10) NULL,
    HeadshotUrl         NVARCHAR(500) NULL,

    ValidFrom           DATETIMEOFFSET(6) NOT NULL,
    ValidTo             DATETIMEOFFSET(6) NULL,
    IsCurrent           BIT NOT NULL,

    CONSTRAINT PK_DimDriver
        PRIMARY KEY (DriverKey),

    CONSTRAINT UQ_DimDriver_BusinessKey_ValidFrom
        UNIQUE (DriverBusinessKey, ValidFrom),

    CONSTRAINT CK_DimDriver_Validity
        CHECK (
            (IsCurrent = 1 AND ValidTo IS NULL)
            OR
            (IsCurrent = 0 AND ValidTo IS NOT NULL)
        ),

    CONSTRAINT CK_DimDriver_ValidRange
        CHECK (
            ValidTo IS NULL
            OR ValidTo > ValidFrom
        )
);
GO

CREATE UNIQUE INDEX UX_DimDriver_Current
    ON dw.DimDriver (DriverBusinessKey)
    WHERE IsCurrent = 1;
GO


-- =========================================================
-- DimTeam
-- Stabilna tożsamość zespołu.
-- TeamColour NIE jest tutaj przechowywany.
-- =========================================================

CREATE TABLE dw.DimTeam (
    TeamKey             INT IDENTITY(1,1) NOT NULL,
    TeamName            NVARCHAR(100) NOT NULL,

    CONSTRAINT PK_DimTeam
        PRIMARY KEY (TeamKey),

    CONSTRAINT UQ_DimTeam_TeamName
        UNIQUE (TeamName)
);
GO


-- =========================================================
-- DimTeamColour
-- 1 rekord = 1 unikalna wartość team_colour dla danego zespołu.
--
-- Brak ValidFrom / ValidTo / IsCurrent.
-- Jeśli ta sama wartość team_colour pojawi się ponownie, późniejszy fact
-- ponownie użyje tego samego TeamColourKey.
-- =========================================================

CREATE TABLE dw.DimTeamColour (
    TeamColourKey       INT IDENTITY(1,1) NOT NULL,
    TeamKey             INT NOT NULL,
    TeamColour          VARCHAR(20) NOT NULL,

    CONSTRAINT PK_DimTeamColour
        PRIMARY KEY (TeamColourKey),

    CONSTRAINT UQ_DimTeamColour_Team_Colour
        UNIQUE (TeamKey, TeamColour),

    CONSTRAINT FK_DimTeamColour_DimTeam
        FOREIGN KEY (TeamKey)
        REFERENCES dw.DimTeam(TeamKey)
);
GO


-- =========================================================
-- DimFlag
-- Słownik flag Race Control
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
-- Słownik kategorii Race Control
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
    s.name AS SchemaName,
    t.name AS TableName
FROM sys.tables AS t
JOIN sys.schemas AS s
    ON s.schema_id = t.schema_id
WHERE s.name = N'dw'
ORDER BY t.name;
GO
