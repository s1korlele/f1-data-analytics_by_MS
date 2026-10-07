USE F1Analytics;
GO

/*
    F1 Analytics - load stg -> dw dimensions

    Zasada:
    1 tabela wymiarowa = 1 procedura.

    Procedury:
    - nie robi¹ TRUNCATE wymiarów,
    - mo¿na uruchamiaæ niezale¿nie,
    - zachowuj¹ surrogate keys,
    - s¹ idempotentne dla tego samego pe³nego zestawu danych stagingowych.

    Konwencja czasu DW:
    - staging zachowuje timestampy Ÿród³owe,
    - w warstwie dw wszystkie timestampy s¹ przechowywane jako DATETIME2(6),
    - wartoœci s¹ przeliczane na lokalny czas Polski (CET/CEST),
      z u¿yciem strefy SQL Server 'Central European Standard Time',
    - nazwy kolumn nie zawieraj¹ suffixów UTC/Poland.

    Wa¿ne:
    staging w docelowym modelu jest warstw¹ full-refresh zawieraj¹c¹
    wszystkie dostêpne sezony. Ma to znaczenie szczególnie dla SCD2
    w DimDriver.
*/


-- Usuñ procedury ze starszej wersji modelu, jeœli istniej¹.
DROP PROCEDURE IF EXISTS dw.usp_LoadDimRace;
DROP PROCEDURE IF EXISTS dw.usp_LoadDimTeamVersion;
DROP PROCEDURE IF EXISTS dw.usp_LoadDimTeamLivery;
GO


-- =========================================================
-- DimSeason
-- =========================================================

CREATE OR ALTER PROCEDURE dw.usp_LoadDimSeason
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        INSERT INTO dw.DimSeason (SeasonYear)
        SELECT DISTINCT
            TRY_CONVERT(SMALLINT, m.[year])
        FROM stg.Meetings AS m
        WHERE TRY_CONVERT(SMALLINT, m.[year]) IS NOT NULL
          AND NOT EXISTS (
              SELECT 1
              FROM dw.DimSeason AS d
              WHERE d.SeasonYear = TRY_CONVERT(SMALLINT, m.[year])
          );

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO


-- =========================================================
-- DimCountry
-- =========================================================

CREATE OR ALTER PROCEDURE dw.usp_LoadDimCountry
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        DROP TABLE IF EXISTS #CountrySource;

        SELECT
            LEFT(LTRIM(RTRIM(m.country_code)), 10) AS CountryCode,
            MAX(LEFT(LTRIM(RTRIM(m.country_name)), 100)) AS CountryName,
            MAX(NULLIF(LEFT(LTRIM(RTRIM(m.country_flag)), 500), N'')) AS CountryFlag
        INTO #CountrySource
        FROM stg.Meetings AS m
        WHERE NULLIF(LTRIM(RTRIM(m.country_code)), N'') IS NOT NULL
          AND NULLIF(LTRIM(RTRIM(m.country_name)), N'') IS NOT NULL
        GROUP BY
            LEFT(LTRIM(RTRIM(m.country_code)), 10);

        UPDATE d
        SET
            d.CountryName = s.CountryName,
            d.CountryFlag = s.CountryFlag
        FROM dw.DimCountry AS d
        JOIN #CountrySource AS s
            ON s.CountryCode = d.CountryCode;

        INSERT INTO dw.DimCountry (
            CountryCode,
            CountryName,
            CountryFlag
        )
        SELECT
            s.CountryCode,
            s.CountryName,
            s.CountryFlag
        FROM #CountrySource AS s
        WHERE NOT EXISTS (
            SELECT 1
            FROM dw.DimCountry AS d
            WHERE d.CountryCode = s.CountryCode
        );

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO


-- =========================================================
-- DimCircuit
-- =========================================================

CREATE OR ALTER PROCEDURE dw.usp_LoadDimCircuit
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        DROP TABLE IF EXISTS #CircuitSource;

        SELECT
            m.circuit_key AS SourceCircuitKey,
            MAX(LEFT(LTRIM(RTRIM(m.country_code)), 10)) AS CountryCode,
            MAX(LEFT(LTRIM(RTRIM(m.circuit_short_name)), 100)) AS CircuitShortName,
            MAX(NULLIF(LEFT(LTRIM(RTRIM(m.circuit_type)), 50), N'')) AS CircuitType,
            MAX(NULLIF(LEFT(LTRIM(RTRIM(m.circuit_image)), 500), N'')) AS CircuitImage,
            MAX(NULLIF(LEFT(LTRIM(RTRIM(m.location)), 100), N'')) AS Location
        INTO #CircuitSource
        FROM stg.Meetings AS m
        WHERE m.circuit_key IS NOT NULL
          AND NULLIF(LTRIM(RTRIM(m.country_code)), N'') IS NOT NULL
          AND NULLIF(LTRIM(RTRIM(m.circuit_short_name)), N'') IS NOT NULL
        GROUP BY
            m.circuit_key;

        UPDATE d
        SET
            d.CountryKey = c.CountryKey,
            d.CircuitShortName = s.CircuitShortName,
            d.CircuitType = s.CircuitType,
            d.CircuitImage = s.CircuitImage,
            d.Location = s.Location
        FROM dw.DimCircuit AS d
        JOIN #CircuitSource AS s
            ON s.SourceCircuitKey = d.SourceCircuitKey
        JOIN dw.DimCountry AS c
            ON c.CountryCode = s.CountryCode;

        INSERT INTO dw.DimCircuit (
            SourceCircuitKey,
            CountryKey,
            CircuitShortName,
            CircuitType,
            CircuitImage,
            Location
        )
        SELECT
            s.SourceCircuitKey,
            c.CountryKey,
            s.CircuitShortName,
            s.CircuitType,
            s.CircuitImage,
            s.Location
        FROM #CircuitSource AS s
        JOIN dw.DimCountry AS c
            ON c.CountryCode = s.CountryCode
        WHERE NOT EXISTS (
            SELECT 1
            FROM dw.DimCircuit AS d
            WHERE d.SourceCircuitKey = s.SourceCircuitKey
        );

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO


-- =========================================================
-- DimRaceWeekend
-- =========================================================

CREATE OR ALTER PROCEDURE dw.usp_LoadDimRaceWeekend
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        DROP TABLE IF EXISTS #RaceWeekendSource;

        ;WITH GridRound AS (
            SELECT
                sg.meeting_key,
                MAX(sg.[round]) AS RoundNumber
            FROM stg.StartingGrid AS sg
            WHERE sg.meeting_key IS NOT NULL
            GROUP BY sg.meeting_key
        ),
        MeetingSequence AS (
            SELECT
                m.meeting_key,
                ROW_NUMBER() OVER (
                    PARTITION BY m.[year]
                    ORDER BY
                        TRY_CONVERT(
                            DATETIMEOFFSET(6),
                            NULLIF(LTRIM(RTRIM(m.date_start)), N'')
                        ),
                        m.meeting_key
                ) AS SequenceNumber
            FROM stg.Meetings AS m
            WHERE m.meeting_key IS NOT NULL
        )
        SELECT
            m.meeting_key AS SourceMeetingKey,
            TRY_CONVERT(SMALLINT, m.[year]) AS SeasonYear,
            m.circuit_key AS SourceCircuitKey,
            TRY_CONVERT(
                TINYINT,
                COALESCE(gr.RoundNumber, ms.SequenceNumber)
            ) AS RoundNumber,
            LEFT(LTRIM(RTRIM(m.meeting_name)), 150) AS RaceWeekendName,
            CONVERT(
                DATETIME2(6),
                TRY_CONVERT(
                    DATETIMEOFFSET(6),
                    NULLIF(LTRIM(RTRIM(m.date_start)), N'')
                ) AT TIME ZONE 'Central European Standard Time'
            ) AS DateStart,
            CONVERT(
                DATETIME2(6),
                TRY_CONVERT(
                    DATETIMEOFFSET(6),
                    NULLIF(LTRIM(RTRIM(m.date_end)), N'')
                ) AT TIME ZONE 'Central European Standard Time'
            ) AS DateEnd,
            COALESCE(m.is_cancelled, 0) AS IsCancelled
        INTO #RaceWeekendSource
        FROM stg.Meetings AS m
        LEFT JOIN GridRound AS gr
            ON gr.meeting_key = m.meeting_key
        LEFT JOIN MeetingSequence AS ms
            ON ms.meeting_key = m.meeting_key
        WHERE m.meeting_key IS NOT NULL
          AND m.circuit_key IS NOT NULL
          AND TRY_CONVERT(SMALLINT, m.[year]) IS NOT NULL
          AND NULLIF(LTRIM(RTRIM(m.meeting_name)), N'') IS NOT NULL;

        DELETE FROM #RaceWeekendSource
        WHERE RoundNumber IS NULL;

        UPDATE d
        SET
            d.SeasonKey = se.SeasonKey,
            d.CircuitKey = ci.CircuitKey,
            d.RoundNumber = s.RoundNumber,
            d.RaceWeekendName = s.RaceWeekendName,
            d.DateStart = s.DateStart,
            d.DateEnd = s.DateEnd,
            d.IsCancelled = s.IsCancelled
        FROM dw.DimRaceWeekend AS d
        JOIN #RaceWeekendSource AS s
            ON s.SourceMeetingKey = d.SourceMeetingKey
        JOIN dw.DimSeason AS se
            ON se.SeasonYear = s.SeasonYear
        JOIN dw.DimCircuit AS ci
            ON ci.SourceCircuitKey = s.SourceCircuitKey;

        INSERT INTO dw.DimRaceWeekend (
            SourceMeetingKey,
            SeasonKey,
            CircuitKey,
            RoundNumber,
            RaceWeekendName,
            DateStart,
            DateEnd,
            IsCancelled
        )
        SELECT
            s.SourceMeetingKey,
            se.SeasonKey,
            ci.CircuitKey,
            s.RoundNumber,
            s.RaceWeekendName,
            s.DateStart,
            s.DateEnd,
            s.IsCancelled
        FROM #RaceWeekendSource AS s
        JOIN dw.DimSeason AS se
            ON se.SeasonYear = s.SeasonYear
        JOIN dw.DimCircuit AS ci
            ON ci.SourceCircuitKey = s.SourceCircuitKey
        WHERE NOT EXISTS (
            SELECT 1
            FROM dw.DimRaceWeekend AS d
            WHERE d.SourceMeetingKey = s.SourceMeetingKey
        );

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO


-- =========================================================
-- DimSessionType
-- =========================================================

CREATE OR ALTER PROCEDURE dw.usp_LoadDimSessionType
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        INSERT INTO dw.DimSessionType (SessionTypeName)
        SELECT DISTINCT
            LEFT(LTRIM(RTRIM(s.session_type)), 50)
        FROM stg.Sessions AS s
        WHERE NULLIF(LTRIM(RTRIM(s.session_type)), N'') IS NOT NULL
          AND NOT EXISTS (
              SELECT 1
              FROM dw.DimSessionType AS d
              WHERE d.SessionTypeName =
                    LEFT(LTRIM(RTRIM(s.session_type)), 50)
          );

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO


-- =========================================================
-- DimSession
-- =========================================================

CREATE OR ALTER PROCEDURE dw.usp_LoadDimSession
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        DROP TABLE IF EXISTS #SessionSource;

        SELECT
            s.session_key AS SourceSessionKey,
            s.meeting_key AS SourceMeetingKey,
            LEFT(LTRIM(RTRIM(s.session_type)), 50) AS SessionTypeName,
            LEFT(LTRIM(RTRIM(s.session_name)), 100) AS SessionName,
            CONVERT(
                DATETIME2(6),
                TRY_CONVERT(
                    DATETIMEOFFSET(6),
                    NULLIF(LTRIM(RTRIM(s.date_start)), N'')
                ) AT TIME ZONE 'Central European Standard Time'
            ) AS DateStart,
            CONVERT(
                DATETIME2(6),
                TRY_CONVERT(
                    DATETIMEOFFSET(6),
                    NULLIF(LTRIM(RTRIM(s.date_end)), N'')
                ) AT TIME ZONE 'Central European Standard Time'
            ) AS DateEnd,
            COALESCE(s.is_cancelled, 0) AS IsCancelled
        INTO #SessionSource
        FROM stg.Sessions AS s
        WHERE s.session_key IS NOT NULL
          AND s.meeting_key IS NOT NULL
          AND NULLIF(LTRIM(RTRIM(s.session_type)), N'') IS NOT NULL
          AND NULLIF(LTRIM(RTRIM(s.session_name)), N'') IS NOT NULL;

        UPDATE d
        SET
            d.RaceWeekendKey = rw.RaceWeekendKey,
            d.SessionTypeKey = st.SessionTypeKey,
            d.SessionName = s.SessionName,
            d.DateStart = s.DateStart,
            d.DateEnd = s.DateEnd,
            d.IsCancelled = s.IsCancelled
        FROM dw.DimSession AS d
        JOIN #SessionSource AS s
            ON s.SourceSessionKey = d.SourceSessionKey
        JOIN dw.DimRaceWeekend AS rw
            ON rw.SourceMeetingKey = s.SourceMeetingKey
        JOIN dw.DimSessionType AS st
            ON st.SessionTypeName = s.SessionTypeName;

        INSERT INTO dw.DimSession (
            SourceSessionKey,
            RaceWeekendKey,
            SessionTypeKey,
            SessionName,
            DateStart,
            DateEnd,
            IsCancelled
        )
        SELECT
            s.SourceSessionKey,
            rw.RaceWeekendKey,
            st.SessionTypeKey,
            s.SessionName,
            s.DateStart,
            s.DateEnd,
            s.IsCancelled
        FROM #SessionSource AS s
        JOIN dw.DimRaceWeekend AS rw
            ON rw.SourceMeetingKey = s.SourceMeetingKey
        JOIN dw.DimSessionType AS st
            ON st.SessionTypeName = s.SessionTypeName
        WHERE NOT EXISTS (
            SELECT 1
            FROM dw.DimSession AS d
            WHERE d.SourceSessionKey = s.SourceSessionKey
        );

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO


-- =========================================================
-- DimDriver - SCD Type 2
--
-- Œledzimy:
-- DriverNumber, FirstName, LastName, NameAcronym, HeadshotUrl.
--
-- TeamName i TeamColour NIE bior¹ udzia³u w wersjonowaniu kierowcy.
--
-- Na pocz¹tku nowego sezonu wymuszamy now¹ wersjê kierowcy.
-- =========================================================

CREATE OR ALTER PROCEDURE dw.usp_LoadDimDriver
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        DROP TABLE IF EXISTS #DriverVersions;

        ;WITH DriverObservation AS (
            SELECT
                LEFT(LTRIM(RTRIM(dr.full_name)), 100) AS DriverBusinessKey,
                dr.session_key AS SourceSessionKey,
                TRY_CONVERT(SMALLINT, s.[year]) AS SeasonYear,
                CONVERT(
                    DATETIME2(6),
                    TRY_CONVERT(
                        DATETIMEOFFSET(6),
                        NULLIF(LTRIM(RTRIM(s.date_start)), N'')
                    ) AT TIME ZONE 'Central European Standard Time'
                ) AS SessionStart,

                MAX(dr.driver_number) AS DriverNumber,
                LEFT(LTRIM(RTRIM(dr.full_name)), 100) AS FullName,
                MAX(NULLIF(LEFT(LTRIM(RTRIM(dr.first_name)), 100), N'')) AS FirstName,
                MAX(NULLIF(LEFT(LTRIM(RTRIM(dr.last_name)), 100), N'')) AS LastName,
                MAX(
                    CONVERT(
                        VARCHAR(10),
                        NULLIF(LEFT(LTRIM(RTRIM(dr.name_acronym)), 10), N'')
                    )
                ) AS NameAcronym,
                MAX(NULLIF(LEFT(LTRIM(RTRIM(dr.headshot_url)), 500), N'')) AS HeadshotUrl

            FROM stg.Drivers AS dr
            JOIN stg.Sessions AS s
                ON s.session_key = dr.session_key

            WHERE NULLIF(LTRIM(RTRIM(dr.full_name)), N'') IS NOT NULL
              AND TRY_CONVERT(
                    DATETIMEOFFSET(6),
                    NULLIF(LTRIM(RTRIM(s.date_start)), N'')
                  ) IS NOT NULL
              AND TRY_CONVERT(SMALLINT, s.[year]) IS NOT NULL

            GROUP BY
                LEFT(LTRIM(RTRIM(dr.full_name)), 100),
                dr.session_key,
                TRY_CONVERT(SMALLINT, s.[year]),
                CONVERT(
                    DATETIME2(6),
                    TRY_CONVERT(
                        DATETIMEOFFSET(6),
                        NULLIF(LTRIM(RTRIM(s.date_start)), N'')
                    ) AT TIME ZONE 'Central European Standard Time'
                )
        ),
        DriverPrevious AS (
            SELECT
                o.*,

                LAG(o.SourceSessionKey) OVER (
                    PARTITION BY o.DriverBusinessKey
                    ORDER BY o.SessionStart, o.SourceSessionKey
                ) AS PreviousSessionKey,

                LAG(o.SeasonYear) OVER (
                    PARTITION BY o.DriverBusinessKey
                    ORDER BY o.SessionStart, o.SourceSessionKey
                ) AS PreviousSeasonYear,

                LAG(o.DriverNumber) OVER (
                    PARTITION BY o.DriverBusinessKey
                    ORDER BY o.SessionStart, o.SourceSessionKey
                ) AS PreviousDriverNumber,

                LAG(o.FirstName) OVER (
                    PARTITION BY o.DriverBusinessKey
                    ORDER BY o.SessionStart, o.SourceSessionKey
                ) AS PreviousFirstName,

                LAG(o.LastName) OVER (
                    PARTITION BY o.DriverBusinessKey
                    ORDER BY o.SessionStart, o.SourceSessionKey
                ) AS PreviousLastName,

                LAG(o.NameAcronym) OVER (
                    PARTITION BY o.DriverBusinessKey
                    ORDER BY o.SessionStart, o.SourceSessionKey
                ) AS PreviousNameAcronym,

                LAG(o.HeadshotUrl) OVER (
                    PARTITION BY o.DriverBusinessKey
                    ORDER BY o.SessionStart, o.SourceSessionKey
                ) AS PreviousHeadshotUrl

            FROM DriverObservation AS o
        ),
        DriverMarked AS (
            SELECT
                p.*,
                CASE
                    WHEN p.PreviousSessionKey IS NULL THEN 1
                    WHEN p.PreviousSeasonYear <> p.SeasonYear THEN 1

                    WHEN ISNULL(CONVERT(VARCHAR(20), p.PreviousDriverNumber), '<NULL>')
                       <> ISNULL(CONVERT(VARCHAR(20), p.DriverNumber), '<NULL>')
                        THEN 1

                    WHEN ISNULL(p.PreviousFirstName, N'<NULL>')
                       <> ISNULL(p.FirstName, N'<NULL>')
                        THEN 1

                    WHEN ISNULL(p.PreviousLastName, N'<NULL>')
                       <> ISNULL(p.LastName, N'<NULL>')
                        THEN 1

                    WHEN ISNULL(p.PreviousNameAcronym, '<NULL>')
                       <> ISNULL(p.NameAcronym, '<NULL>')
                        THEN 1

                    WHEN ISNULL(p.PreviousHeadshotUrl, N'<NULL>')
                       <> ISNULL(p.HeadshotUrl, N'<NULL>')
                        THEN 1

                    ELSE 0
                END AS ChangeFlag
            FROM DriverPrevious AS p
        ),
        DriverSegmented AS (
            SELECT
                m.*,
                SUM(m.ChangeFlag) OVER (
                    PARTITION BY m.DriverBusinessKey
                    ORDER BY m.SessionStart, m.SourceSessionKey
                    ROWS UNBOUNDED PRECEDING
                ) AS SegmentNumber
            FROM DriverMarked AS m
        ),
        DriverSegmentStart AS (
            SELECT
                x.*,
                ROW_NUMBER() OVER (
                    PARTITION BY x.DriverBusinessKey, x.SegmentNumber
                    ORDER BY x.SessionStart, x.SourceSessionKey
                ) AS SegmentRowNumber
            FROM DriverSegmented AS x
        ),
        DriverVersionBase AS (
            SELECT
                DriverBusinessKey,
                DriverNumber,
                FullName,
                FirstName,
                LastName,
                NameAcronym,
                HeadshotUrl,
                SessionStart AS ValidFrom
            FROM DriverSegmentStart
            WHERE SegmentRowNumber = 1
        ),
        DriverVersionWithEnd AS (
            SELECT
                v.*,
                LEAD(v.ValidFrom) OVER (
                    PARTITION BY v.DriverBusinessKey
                    ORDER BY v.ValidFrom
                ) AS ValidTo
            FROM DriverVersionBase AS v
        )
        SELECT
            DriverBusinessKey,
            DriverNumber,
            FullName,
            FirstName,
            LastName,
            NameAcronym,
            HeadshotUrl,
            ValidFrom,
            ValidTo,
            CONVERT(BIT, CASE WHEN ValidTo IS NULL THEN 1 ELSE 0 END) AS IsCurrent
        INTO #DriverVersions
        FROM DriverVersionWithEnd;

        /*
            Najpierw zamykamy / aktualizujemy istniej¹ce wersje,
            dopiero potem wstawiamy nowe.
        */
        UPDATE d
        SET
            d.DriverNumber = s.DriverNumber,
            d.FullName = s.FullName,
            d.FirstName = s.FirstName,
            d.LastName = s.LastName,
            d.NameAcronym = s.NameAcronym,
            d.HeadshotUrl = s.HeadshotUrl,
            d.ValidTo = s.ValidTo,
            d.IsCurrent = s.IsCurrent
        FROM dw.DimDriver AS d
        JOIN #DriverVersions AS s
            ON s.DriverBusinessKey = d.DriverBusinessKey
           AND s.ValidFrom = d.ValidFrom;

        INSERT INTO dw.DimDriver (
            DriverBusinessKey,
            DriverNumber,
            FullName,
            FirstName,
            LastName,
            NameAcronym,
            HeadshotUrl,
            ValidFrom,
            ValidTo,
            IsCurrent
        )
        SELECT
            s.DriverBusinessKey,
            s.DriverNumber,
            s.FullName,
            s.FirstName,
            s.LastName,
            s.NameAcronym,
            s.HeadshotUrl,
            s.ValidFrom,
            s.ValidTo,
            s.IsCurrent
        FROM #DriverVersions AS s
        WHERE NOT EXISTS (
            SELECT 1
            FROM dw.DimDriver AS d
            WHERE d.DriverBusinessKey = s.DriverBusinessKey
              AND d.ValidFrom = s.ValidFrom
        );

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO


-- =========================================================
-- DimTeam
-- =========================================================

CREATE OR ALTER PROCEDURE dw.usp_LoadDimTeam
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        INSERT INTO dw.DimTeam (TeamName)
        SELECT DISTINCT
            LEFT(LTRIM(RTRIM(dr.team_name)), 100)
        FROM stg.Drivers AS dr
        WHERE NULLIF(LTRIM(RTRIM(dr.team_name)), N'') IS NOT NULL
          AND NOT EXISTS (
              SELECT 1
              FROM dw.DimTeam AS d
              WHERE d.TeamName =
                    LEFT(LTRIM(RTRIM(dr.team_name)), 100)
          );

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO


-- =========================================================
-- DimTeamColour
--
-- Przechowuje unikalne wartoœci team_colour zwracane dla zespo³u.
-- Nie ma okresów obowi¹zywania.
--
-- Przyk³ad:
-- McLaren / FF8000
-- McLaren / F47600
--
-- Gdy ta sama wartoœæ team_colour pojawi siê ponownie, nie tworzymy nowego rekordu.
-- Fact ponownie wska¿e ten sam TeamColourKey.
-- =========================================================

CREATE OR ALTER PROCEDURE dw.usp_LoadDimTeamColour
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        INSERT INTO dw.DimTeamColour (
            TeamKey,
            TeamColour
        )
        SELECT DISTINCT
            t.TeamKey,
            UPPER(
                CONVERT(
                    VARCHAR(20),
                    LEFT(LTRIM(RTRIM(dr.team_colour)), 20)
                )
            ) AS TeamColour
        FROM stg.Drivers AS dr
        JOIN dw.DimTeam AS t
            ON t.TeamName = LEFT(LTRIM(RTRIM(dr.team_name)), 100)
        WHERE NULLIF(LTRIM(RTRIM(dr.team_name)), N'') IS NOT NULL
          AND NULLIF(LTRIM(RTRIM(dr.team_colour)), N'') IS NOT NULL
          AND NOT EXISTS (
              SELECT 1
              FROM dw.DimTeamColour AS l
              WHERE l.TeamKey = t.TeamKey
                AND l.TeamColour =
                    UPPER(
                        CONVERT(
                            VARCHAR(20),
                            LEFT(LTRIM(RTRIM(dr.team_colour)), 20)
                        )
                    )
          );

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO


-- =========================================================
-- DimFlag
-- =========================================================

CREATE OR ALTER PROCEDURE dw.usp_LoadDimFlag
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        INSERT INTO dw.DimFlag (FlagName)
        SELECT DISTINCT
            LEFT(LTRIM(RTRIM(rc.flag)), 50)
        FROM stg.RaceControl AS rc
        WHERE NULLIF(LTRIM(RTRIM(rc.flag)), N'') IS NOT NULL
          AND NOT EXISTS (
              SELECT 1
              FROM dw.DimFlag AS d
              WHERE d.FlagName =
                    LEFT(LTRIM(RTRIM(rc.flag)), 50)
          );

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO


-- =========================================================
-- DimRaceControlCategory
-- =========================================================

CREATE OR ALTER PROCEDURE dw.usp_LoadDimRaceControlCategory
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        INSERT INTO dw.DimRaceControlCategory (CategoryName)
        SELECT DISTINCT
            LEFT(LTRIM(RTRIM(rc.category)), 100)
        FROM stg.RaceControl AS rc
        WHERE NULLIF(LTRIM(RTRIM(rc.category)), N'') IS NOT NULL
          AND NOT EXISTS (
              SELECT 1
              FROM dw.DimRaceControlCategory AS d
              WHERE d.CategoryName =
                    LEFT(LTRIM(RTRIM(rc.category)), 100)
          );

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO


-- =========================================================
-- Procedura zbiorcza
-- =========================================================

CREATE OR ALTER PROCEDURE dw.usp_LoadAllDimensions
AS
BEGIN
    SET NOCOUNT ON;

    EXEC dw.usp_LoadDimSeason;
    EXEC dw.usp_LoadDimCountry;
    EXEC dw.usp_LoadDimCircuit;
    EXEC dw.usp_LoadDimRaceWeekend;

    EXEC dw.usp_LoadDimSessionType;
    EXEC dw.usp_LoadDimSession;

    EXEC dw.usp_LoadDimDriver;

    EXEC dw.usp_LoadDimTeam;
    EXEC dw.usp_LoadDimTeamColour;

    EXEC dw.usp_LoadDimFlag;
    EXEC dw.usp_LoadDimRaceControlCategory;
END;
GO


/*
    =========================================================
    TESTY - uruchamiaj rêcznie
    =========================================================

    EXEC dw.usp_LoadAllDimensions;


    -- Licznoœci
    SELECT 'DimSeason' AS TableName, COUNT(*) AS RecordCount FROM dw.DimSeason
    UNION ALL SELECT 'DimCountry', COUNT(*) FROM dw.DimCountry
    UNION ALL SELECT 'DimCircuit', COUNT(*) FROM dw.DimCircuit
    UNION ALL SELECT 'DimRaceWeekend', COUNT(*) FROM dw.DimRaceWeekend
    UNION ALL SELECT 'DimSessionType', COUNT(*) FROM dw.DimSessionType
    UNION ALL SELECT 'DimSession', COUNT(*) FROM dw.DimSession
    UNION ALL SELECT 'DimDriver', COUNT(*) FROM dw.DimDriver
    UNION ALL SELECT 'DimTeam', COUNT(*) FROM dw.DimTeam
    UNION ALL SELECT 'DimTeamColour', COUNT(*) FROM dw.DimTeamColour
    UNION ALL SELECT 'DimFlag', COUNT(*) FROM dw.DimFlag
    UNION ALL SELECT 'DimRaceControlCategory', COUNT(*) FROM dw.DimRaceControlCategory;


    -- Kolory zespo³ów z OpenF1
    SELECT
        t.TeamName,
        l.TeamColourKey,
        l.TeamColour
    FROM dw.DimTeamColour AS l
    JOIN dw.DimTeam AS t
        ON t.TeamKey = l.TeamKey
    ORDER BY
        t.TeamName,
        l.TeamColour;


    -- Kontrola: nie powinno byæ duplikatów Team + Colour
    SELECT
        t.TeamName,
        l.TeamColour,
        COUNT(*) AS DuplicateCount
    FROM dw.DimTeamColour AS l
    JOIN dw.DimTeam AS t
        ON t.TeamKey = l.TeamKey
    GROUP BY
        t.TeamName,
        l.TeamColour
    HAVING COUNT(*) > 1;


    -- Kontrola SCD2 kierowców:
    -- maksymalnie jeden rekord IsCurrent = 1 na osobê
    SELECT
        DriverBusinessKey,
        COUNT(*) AS CurrentRows
    FROM dw.DimDriver
    WHERE IsCurrent = 1
    GROUP BY DriverBusinessKey
    HAVING COUNT(*) <> 1;
*/
