USE F1Analytics;
GO


-- Meetings
CREATE TABLE stg.Meetings (
    meeting_key         INT,
    meeting_name        NVARCHAR(150),
    location            NVARCHAR(100),
    country_code        VARCHAR(10),
    country_name        NVARCHAR(100),
    country_flag        NVARCHAR(500),
    circuit_key         INT,
    circuit_short_name  NVARCHAR(100),
    circuit_type        NVARCHAR(50),
    circuit_image       NVARCHAR(500),
    date_start          DATETIMEOFFSET(6),
    date_end            DATETIMEOFFSET(6),
    year                INT,
    is_cancelled        BIT
);
GO


-- Sessions
CREATE TABLE stg.Sessions (
    session_key     INT,
    meeting_key     INT,
    session_type    NVARCHAR(50),
    session_name    NVARCHAR(100),
    date_start      DATETIMEOFFSET(6),
    date_end        DATETIMEOFFSET(6),
    year            INT,
    is_cancelled    BIT
);
GO


-- Drivers
CREATE TABLE stg.Drivers (
    meeting_key     INT,
    session_key     INT,
    driver_number   INT,
    full_name       NVARCHAR(100),
    name_acronym    VARCHAR(10),
    first_name      NVARCHAR(100),
    last_name       NVARCHAR(100),
    team_name       NVARCHAR(100),
    team_colour     VARCHAR(20),
    headshot_url    NVARCHAR(500)
);
GO


-- Race Control
CREATE TABLE stg.RaceControl (
    meeting_key     INT,
    session_key     INT,
    date            DATETIMEOFFSET(6),
    driver_number   INT NULL,
    lap_number      INT NULL,
    category        NVARCHAR(100),
    flag            NVARCHAR(50),
    scope           NVARCHAR(50),
    sector          INT NULL,
    message         NVARCHAR(1000)
);
GO


-- Race Results
CREATE TABLE stg.RaceResults (
    meeting_key     INT,
    session_key     INT,
    driver_number   INT,
    position        INT NULL,
    number_of_laps  INT NULL,
    points          DECIMAL(8, 2),
    dnf             BIT,
    dns             BIT,
    dsq             BIT,
    duration        DECIMAL(12, 3) NULL,
    gap_to_leader   NVARCHAR(50)
);
GO


-- Laps
CREATE TABLE stg.Laps (
    meeting_key        INT,
    session_key        INT,
    driver_number      INT,
    lap_number         INT,
    date_start         DATETIMEOFFSET(6) NULL,
    lap_duration       DECIMAL(10, 3) NULL,
    duration_sector_1  DECIMAL(10, 3) NULL,
    duration_sector_2  DECIMAL(10, 3) NULL,
    duration_sector_3  DECIMAL(10, 3) NULL,
    i1_speed           INT NULL,
    i2_speed           INT NULL,
    st_speed           INT NULL,
    is_pit_out_lap     BIT
);
GO


-- Stints
CREATE TABLE stg.Stints (
    meeting_key       INT,
    session_key       INT,
    driver_number     INT,
    stint_number      INT NULL,
    compound          NVARCHAR(30),
    lap_start         INT NULL,
    lap_end           INT NULL,
    tyre_age_at_start INT NULL
);
GO


-- Pit Stops
CREATE TABLE stg.PitStops (
    meeting_key     INT,
    session_key     INT,
    driver_number   INT,
    lap_number      INT,
    date            DATETIMEOFFSET(6),
    lane_duration   DECIMAL(10, 3) NULL,
    stop_duration   DECIMAL(10, 3) NULL
);
GO


-- Weather
CREATE TABLE stg.Weather (
    meeting_key       INT,
    session_key       INT,
    date              DATETIMEOFFSET(6),
    air_temperature   DECIMAL(6, 2) NULL,
    track_temperature DECIMAL(6, 2) NULL,
    humidity          DECIMAL(6, 2) NULL,
    pressure          DECIMAL(8, 2) NULL,
    rainfall          INT NULL,
    wind_direction    INT NULL,
    wind_speed        DECIMAL(8, 3) NULL
);
GO


-- Qualifying Results
CREATE TABLE stg.QualifyingResults (
    meeting_key            INT,
    session_key            INT,
    driver_number          INT,
    position               INT NULL,
    number_of_laps         INT NULL,
    phase_1_duration       DECIMAL(10, 3) NULL,
    phase_2_duration       DECIMAL(10, 3) NULL,
    phase_3_duration       DECIMAL(10, 3) NULL,
    phase_1_gap_to_leader  NVARCHAR(50),
    phase_2_gap_to_leader  NVARCHAR(50),
    phase_3_gap_to_leader  NVARCHAR(50),
    dnf                     BIT,
    dns                     BIT,
    dsq                     BIT
);
GO


-- Starting Grid
CREATE TABLE stg.StartingGrid (
    meeting_key     INT,
    session_key     INT,
    round           INT,
    race_name       NVARCHAR(150),
    driver_number   INT,
    driver_code     VARCHAR(10),
    driver_name     NVARCHAR(100),
    team_name       NVARCHAR(100),
    grid_position   INT NULL
);
GO


-- Attendance
CREATE TABLE stg.Attendance (
    meeting_key          INT,
    meeting_name         NVARCHAR(150),
    country_name         NVARCHAR(100),
    circuit_short_name   NVARCHAR(100),
    weekend_attendance   INT NULL,
    race_day_attendance  INT NULL,
    source_url           NVARCHAR(1000),
    source_date          DATE NULL,
    notes                NVARCHAR(2000)
);
GO