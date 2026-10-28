USE F1Analytics;
GO

/*
    F1 Analytics - load stg -> dw facts

    Aktualne procedury:
    - dw.usp_LoadFactSessionResult
    - dw.usp_LoadFactRaceResult
    - dw.usp_LoadFactQualifyingResult
    - dw.usp_LoadFactLap
    - dw.usp_LoadFactStint
    - dw.usp_LoadFactPitStop
    - dw.usp_LoadFactWeather
    - dw.usp_LoadFactRaceControl
    - dw.usp_LoadFactAttendance
    - dw.usp_LoadAllFacts

    Konwencja czasu:
    - kolumny czasowe w DW są typu DATETIME2(6),
    - przechowują lokalny czas Polski (CET/CEST),
    - offset nie jest przechowywany w nazwie ani w typie kolumny.

    Strategia:
    full refresh factów po poprawnym załadowaniu stagingu i dimensions.
*/


-- =========================================================
-- FactRaceResult
-- =========================================================

CREATE OR ALTER PROCEDURE dw.usp_LoadFactRaceResult
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE @SourceRows INT;
        DECLARE @MappedRows INT;

        SELECT @SourceRows = COUNT(*)
        FROM stg.RaceResults;

        IF EXISTS (
            SELECT 1
            FROM stg.StartingGrid
            GROUP BY meeting_key, driver_number
            HAVING COUNT(*) > 1
        )
        BEGIN
            THROW 51001,
                'FactRaceResult: duplicate rows in stg.StartingGrid for meeting_key + driver_number.',
                1;
        END;

        IF EXISTS (
            SELECT rr.session_key, rr.driver_number
            FROM stg.RaceResults AS rr
            JOIN stg.Drivers AS d
                ON d.session_key = rr.session_key
               AND d.driver_number = rr.driver_number
            GROUP BY rr.session_key, rr.driver_number
            HAVING COUNT(*) > 1
        )
        BEGIN
            THROW 51002,
                'FactRaceResult: duplicate driver mapping in stg.Drivers for session_key + driver_number.',
                1;
        END;

        DROP TABLE IF EXISTS #RaceResultSource;

        SELECT
            rw.RaceWeekendKey,
            ds.SessionKey,
            dd.DriverKey,
            dt.TeamKey,
            tc.TeamColourKey,

            TRY_CONVERT(
                SMALLINT,
                NULLIF(LTRIM(RTRIM(sg.grid_position)), N'')
            ) AS GridPosition,

            TRY_CONVERT(
                SMALLINT,
                NULLIF(LTRIM(RTRIM(rr.position)), N'')
            ) AS FinishPosition,

            TRY_CONVERT(SMALLINT, rr.number_of_laps) AS NumberOfLaps,
            TRY_CONVERT(DECIMAL(6,2), rr.points) AS Points,

            rr.dnf AS DNF,
            rr.dns AS DNS,
            rr.dsq AS DSQ,

            TRY_CONVERT(DECIMAL(12,3), rr.duration) AS DurationSeconds,

            TRY_CONVERT(
                DECIMAL(12,3),
                REPLACE(
                    REPLACE(
                        NULLIF(LTRIM(RTRIM(rr.gap_to_leader)), N''),
                        N'+', N''
                    ),
                    N',', N'.'
                )
            ) AS GapToLeaderSeconds,

            CASE
                WHEN NULLIF(LTRIM(RTRIM(rr.gap_to_leader)), N'') IS NULL
                    THEN NULL
                WHEN TRY_CONVERT(
                        DECIMAL(12,3),
                        REPLACE(
                            REPLACE(
                                NULLIF(LTRIM(RTRIM(rr.gap_to_leader)), N''),
                                N'+', N''
                            ),
                            N',', N'.'
                        )
                     ) IS NULL
                    THEN LEFT(LTRIM(RTRIM(rr.gap_to_leader)), 50)
                ELSE NULL
            END AS GapToLeaderText

        INTO #RaceResultSource

        FROM stg.RaceResults AS rr

        JOIN dw.DimSession AS ds
            ON ds.SourceSessionKey = rr.session_key

        JOIN dw.DimRaceWeekend AS rw
            ON rw.RaceWeekendKey = ds.RaceWeekendKey
           AND rw.SourceMeetingKey = rr.meeting_key

        JOIN stg.Drivers AS d
            ON d.meeting_key = rr.meeting_key
           AND d.session_key = rr.session_key
           AND d.driver_number = rr.driver_number

        JOIN dw.DimDriver AS dd
            ON dd.DriverBusinessKey = LEFT(LTRIM(RTRIM(d.full_name)), 100)
           AND ds.DateStart >= dd.ValidFrom
           AND (dd.ValidTo IS NULL OR ds.DateStart < dd.ValidTo)

        JOIN dw.DimTeam AS dt
            ON dt.TeamName = LEFT(LTRIM(RTRIM(d.team_name)), 100)

        LEFT JOIN dw.DimTeamColour AS tc
            ON tc.TeamKey = dt.TeamKey
           AND tc.TeamColour = UPPER(
                CONVERT(
                    VARCHAR(20),
                    LEFT(LTRIM(RTRIM(d.team_colour)), 20)
                )
           )

        JOIN stg.StartingGrid AS sg
            ON sg.meeting_key = rr.meeting_key
           AND sg.driver_number = rr.driver_number;

        SELECT @MappedRows = COUNT(*)
        FROM #RaceResultSource;

        IF @MappedRows <> @SourceRows
        BEGIN
            DECLARE @RaceErrorMessage NVARCHAR(2048);

            SET @RaceErrorMessage =
                N'FactRaceResult: mapping mismatch. Source rows = '
                + CONVERT(NVARCHAR(20), @SourceRows)
                + N', mapped rows = '
                + CONVERT(NVARCHAR(20), @MappedRows)
                + N'.';

            THROW 51003, @RaceErrorMessage, 1;
        END;

        IF EXISTS (
            SELECT 1
            FROM #RaceResultSource
            GROUP BY SessionKey, DriverKey
            HAVING COUNT(*) > 1
        )
        BEGIN
            THROW 51004,
                'FactRaceResult: duplicate SessionKey + DriverKey after dimension mapping.',
                1;
        END;

        TRUNCATE TABLE dw.FactRaceResult;

        INSERT INTO dw.FactRaceResult (
            RaceWeekendKey,
            SessionKey,
            DriverKey,
            TeamKey,
            TeamColourKey,
            GridPosition,
            FinishPosition,
            NumberOfLaps,
            Points,
            DNF,
            DNS,
            DSQ,
            DurationSeconds,
            GapToLeaderSeconds,
            GapToLeaderText
        )
        SELECT
            RaceWeekendKey,
            SessionKey,
            DriverKey,
            TeamKey,
            TeamColourKey,
            GridPosition,
            FinishPosition,
            NumberOfLaps,
            Points,
            DNF,
            DNS,
            DSQ,
            DurationSeconds,
            GapToLeaderSeconds,
            GapToLeaderText
        FROM #RaceResultSource;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO


-- =========================================================
-- FactQualifyingResult
-- Grain: 1 kierowca x 1 sesja kwalifikacyjna
-- =========================================================

CREATE OR ALTER PROCEDURE dw.usp_LoadFactQualifyingResult
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE @SourceRows INT;
        DECLARE @MappedRows INT;

        SELECT @SourceRows = COUNT(*)
        FROM stg.QualifyingResults;

        IF EXISTS (
            SELECT 1
            FROM stg.QualifyingResults
            GROUP BY session_key, driver_number
            HAVING COUNT(*) > 1
        )
        BEGIN
            THROW 51101,
                'FactQualifyingResult: duplicate rows in stg.QualifyingResults for session_key + driver_number.',
                1;
        END;

        IF EXISTS (
            SELECT q.session_key, q.driver_number
            FROM stg.QualifyingResults AS q
            JOIN stg.Drivers AS d
                ON d.session_key = q.session_key
               AND d.driver_number = q.driver_number
            GROUP BY q.session_key, q.driver_number
            HAVING COUNT(*) > 1
        )
        BEGIN
            THROW 51102,
                'FactQualifyingResult: duplicate driver mapping in stg.Drivers for session_key + driver_number.',
                1;
        END;

        DROP TABLE IF EXISTS #QualifyingResultSource;

        SELECT
            rw.RaceWeekendKey,
            ds.SessionKey,
            dd.DriverKey,
            dt.TeamKey,
            tc.TeamColourKey,

            TRY_CONVERT(
                SMALLINT,
                NULLIF(LTRIM(RTRIM(q.position)), N'')
            ) AS Position,

            TRY_CONVERT(
                SMALLINT,
                NULLIF(LTRIM(RTRIM(q.number_of_laps)), N'')
            ) AS NumberOfLaps,

            TRY_CONVERT(
                DECIMAL(12,3),
                NULLIF(LTRIM(RTRIM(q.phase_1_duration)), N'')
            ) AS Phase1DurationSeconds,

            TRY_CONVERT(
                DECIMAL(12,3),
                NULLIF(LTRIM(RTRIM(q.phase_2_duration)), N'')
            ) AS Phase2DurationSeconds,

            TRY_CONVERT(
                DECIMAL(12,3),
                NULLIF(LTRIM(RTRIM(q.phase_3_duration)), N'')
            ) AS Phase3DurationSeconds,

            TRY_CONVERT(
                DECIMAL(12,3),
                NULLIF(LTRIM(RTRIM(q.phase_1_gap_to_leader)), N'')
            ) AS Phase1GapToLeaderSeconds,

            TRY_CONVERT(
                DECIMAL(12,3),
                NULLIF(LTRIM(RTRIM(q.phase_2_gap_to_leader)), N'')
            ) AS Phase2GapToLeaderSeconds,

            TRY_CONVERT(
                DECIMAL(12,3),
                NULLIF(LTRIM(RTRIM(q.phase_3_gap_to_leader)), N'')
            ) AS Phase3GapToLeaderSeconds,

            q.dnf AS DNF,
            q.dns AS DNS,
            q.dsq AS DSQ

        INTO #QualifyingResultSource

        FROM stg.QualifyingResults AS q

        JOIN dw.DimSession AS ds
            ON ds.SourceSessionKey = q.session_key

        JOIN dw.DimRaceWeekend AS rw
            ON rw.RaceWeekendKey = ds.RaceWeekendKey
           AND rw.SourceMeetingKey = q.meeting_key

        JOIN stg.Drivers AS d
            ON d.meeting_key = q.meeting_key
           AND d.session_key = q.session_key
           AND d.driver_number = q.driver_number

        JOIN dw.DimDriver AS dd
            ON dd.DriverBusinessKey = LEFT(LTRIM(RTRIM(d.full_name)), 100)
           AND ds.DateStart >= dd.ValidFrom
           AND (dd.ValidTo IS NULL OR ds.DateStart < dd.ValidTo)

        JOIN dw.DimTeam AS dt
            ON dt.TeamName = LEFT(LTRIM(RTRIM(d.team_name)), 100)

        LEFT JOIN dw.DimTeamColour AS tc
            ON tc.TeamKey = dt.TeamKey
           AND tc.TeamColour = UPPER(
                CONVERT(
                    VARCHAR(20),
                    LEFT(LTRIM(RTRIM(d.team_colour)), 20)
                )
           );

        SELECT @MappedRows = COUNT(*)
        FROM #QualifyingResultSource;

        IF @MappedRows <> @SourceRows
        BEGIN
            DECLARE @QualifyingErrorMessage NVARCHAR(2048);

            SET @QualifyingErrorMessage =
                N'FactQualifyingResult: mapping mismatch. Source rows = '
                + CONVERT(NVARCHAR(20), @SourceRows)
                + N', mapped rows = '
                + CONVERT(NVARCHAR(20), @MappedRows)
                + N'.';

            THROW 51103, @QualifyingErrorMessage, 1;
        END;

        IF EXISTS (
            SELECT 1
            FROM #QualifyingResultSource
            GROUP BY SessionKey, DriverKey
            HAVING COUNT(*) > 1
        )
        BEGIN
            THROW 51104,
                'FactQualifyingResult: duplicate SessionKey + DriverKey after dimension mapping.',
                1;
        END;

        TRUNCATE TABLE dw.FactQualifyingResult;

        INSERT INTO dw.FactQualifyingResult (
            RaceWeekendKey,
            SessionKey,
            DriverKey,
            TeamKey,
            TeamColourKey,
            Position,
            NumberOfLaps,
            Phase1DurationSeconds,
            Phase2DurationSeconds,
            Phase3DurationSeconds,
            Phase1GapToLeaderSeconds,
            Phase2GapToLeaderSeconds,
            Phase3GapToLeaderSeconds,
            DNF,
            DNS,
            DSQ
        )
        SELECT
            RaceWeekendKey,
            SessionKey,
            DriverKey,
            TeamKey,
            TeamColourKey,
            Position,
            NumberOfLaps,
            Phase1DurationSeconds,
            Phase2DurationSeconds,
            Phase3DurationSeconds,
            Phase1GapToLeaderSeconds,
            Phase2GapToLeaderSeconds,
            Phase3GapToLeaderSeconds,
            DNF,
            DNS,
            DSQ
        FROM #QualifyingResultSource;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO


-- =========================================================
-- FactLap
-- Grain: 1 kierowca x 1 okrążenie x 1 sesja
-- =========================================================

CREATE OR ALTER PROCEDURE dw.usp_LoadFactLap
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE @SourceRows INT;
        DECLARE @RejectedRows INT;
        DECLARE @EligibleRows INT;
        DECLARE @MappedRows INT;

        SELECT @SourceRows = COUNT(*)
        FROM stg.Laps;


        -- Source grain musi być unikalny.
        IF EXISTS (
            SELECT 1
            FROM stg.Laps
            GROUP BY
                session_key,
                driver_number,
                lap_number
            HAVING COUNT(*) > 1
        )
        BEGIN
            THROW 51201,
                'FactLap: duplicate rows in stg.Laps for session_key + driver_number + lap_number.',
                1;
        END;


        -- Wymagane elementy grainu nie mogą być puste.
        IF EXISTS (
            SELECT 1
            FROM stg.Laps
            WHERE meeting_key IS NULL
               OR session_key IS NULL
               OR driver_number IS NULL
               OR lap_number IS NULL
        )
        BEGIN
            THROW 51202,
                'FactLap: NULL in meeting_key, session_key, driver_number or lap_number.',
                1;
        END;


        -- Tylko pełne rekordy Drivers (full_name + team_name) są
        -- kwalifikowane do telemetrycznych factów. Rekord bez takiego
        -- mapowania może być zanieczyszczeniem endpointu OpenF1.
        SELECT @RejectedRows = COUNT(*)
        FROM stg.Laps AS l
        WHERE NOT EXISTS (
            SELECT 1
            FROM stg.Drivers AS d
            WHERE d.meeting_key = l.meeting_key
              AND d.session_key = l.session_key
              AND d.driver_number = l.driver_number
              AND NULLIF(LTRIM(RTRIM(d.full_name)), N'') IS NOT NULL
              AND NULLIF(LTRIM(RTRIM(d.team_name)), N'') IS NOT NULL
        );

        -- Jeżeli odrzucany rekord ma oficjalny SessionResult, nie wolno
        -- go po cichu pomijać: oznacza to realny problem mapowania.
        IF EXISTS (
            SELECT 1
            FROM stg.Laps AS l
            WHERE NOT EXISTS (
                SELECT 1
                FROM stg.Drivers AS d
                WHERE d.meeting_key = l.meeting_key
                  AND d.session_key = l.session_key
                  AND d.driver_number = l.driver_number
                  AND NULLIF(LTRIM(RTRIM(d.full_name)), N'') IS NOT NULL
                  AND NULLIF(LTRIM(RTRIM(d.team_name)), N'') IS NOT NULL
            )
              AND EXISTS (
                SELECT 1
                FROM stg.SessionResults AS sr
                WHERE sr.meeting_key = l.meeting_key
                  AND sr.session_key = l.session_key
                  AND sr.driver_number = l.driver_number
            )
        )
        BEGIN
            THROW 51203,
                'FactLap: rejected telemetry row has an official SessionResult; driver/team mapping requires investigation.',
                1;
        END;

        SET @EligibleRows = @SourceRows - @RejectedRows;

        -- Dla rekordów kwalifikowanych mapowanie Drivers musi być 1:1.
        IF EXISTS (
            SELECT 1
            FROM stg.Drivers AS d
            WHERE NULLIF(LTRIM(RTRIM(d.full_name)), N'') IS NOT NULL
              AND NULLIF(LTRIM(RTRIM(d.team_name)), N'') IS NOT NULL
              AND EXISTS (
                SELECT 1
                FROM stg.Laps AS l
                WHERE l.meeting_key = d.meeting_key
                  AND l.session_key = d.session_key
                  AND l.driver_number = d.driver_number
            )
            GROUP BY
                d.meeting_key,
                d.session_key,
                d.driver_number
            HAVING COUNT(*) > 1
        )
        BEGIN
            THROW 51207,
                'FactLap: duplicate valid driver mapping in stg.Drivers.',
                1;
        END;


        DROP TABLE IF EXISTS #LapSource;

        SELECT
            rw.RaceWeekendKey,
            ds.SessionKey,
            dd.DriverKey,
            dt.TeamKey,
            tc.TeamColourKey,

            TRY_CONVERT(SMALLINT, l.lap_number) AS LapNumber,

            -- Timestamp źródłowy jest przeliczany na lokalny czas Polski.
            CONVERT(
                DATETIME2(6),
                TRY_CONVERT(
                    DATETIMEOFFSET(6),
                    NULLIF(LTRIM(RTRIM(l.date_start)), N'')
                ) AT TIME ZONE 'Central European Standard Time'
            ) AS LapStartTime,

            TRY_CONVERT(
                DECIMAL(12,3),
                NULLIF(LTRIM(RTRIM(l.lap_duration)), N'')
            ) AS LapDurationSeconds,

            TRY_CONVERT(
                DECIMAL(12,3),
                NULLIF(LTRIM(RTRIM(l.duration_sector_1)), N'')
            ) AS Sector1DurationSeconds,

            TRY_CONVERT(
                DECIMAL(12,3),
                NULLIF(LTRIM(RTRIM(l.duration_sector_2)), N'')
            ) AS Sector2DurationSeconds,

            TRY_CONVERT(
                DECIMAL(12,3),
                NULLIF(LTRIM(RTRIM(l.duration_sector_3)), N'')
            ) AS Sector3DurationSeconds,

            TRY_CONVERT(
                DECIMAL(8,3),
                NULLIF(LTRIM(RTRIM(l.i1_speed)), N'')
            ) AS I1Speed,

            TRY_CONVERT(
                DECIMAL(8,3),
                NULLIF(LTRIM(RTRIM(l.i2_speed)), N'')
            ) AS I2Speed,

            TRY_CONVERT(
                DECIMAL(8,3),
                NULLIF(LTRIM(RTRIM(l.st_speed)), N'')
            ) AS STSpeed,

            l.is_pit_out_lap AS IsPitOutLap

        INTO #LapSource

        FROM stg.Laps AS l

        JOIN dw.DimSession AS ds
            ON ds.SourceSessionKey = l.session_key

        JOIN dw.DimRaceWeekend AS rw
            ON rw.RaceWeekendKey = ds.RaceWeekendKey
           AND rw.SourceMeetingKey = l.meeting_key

        JOIN stg.Drivers AS d
            ON d.meeting_key = l.meeting_key
           AND d.session_key = l.session_key
           AND d.driver_number = l.driver_number
           AND NULLIF(LTRIM(RTRIM(d.full_name)), N'') IS NOT NULL
           AND NULLIF(LTRIM(RTRIM(d.team_name)), N'') IS NOT NULL

        JOIN dw.DimDriver AS dd
            ON dd.DriverBusinessKey = LEFT(LTRIM(RTRIM(d.full_name)), 100)
           AND ds.DateStart >= dd.ValidFrom
           AND (dd.ValidTo IS NULL OR ds.DateStart < dd.ValidTo)

        JOIN dw.DimTeam AS dt
            ON dt.TeamName = LEFT(LTRIM(RTRIM(d.team_name)), 100)

        LEFT JOIN dw.DimTeamColour AS tc
            ON tc.TeamKey = dt.TeamKey
           AND tc.TeamColour = UPPER(
                CONVERT(
                    VARCHAR(20),
                    LEFT(LTRIM(RTRIM(d.team_colour)), 20)
                )
           );


        SELECT @MappedRows = COUNT(*)
        FROM #LapSource;


        -- Każdy rekord source musi zostać zmapowany.
        IF @MappedRows <> @EligibleRows
        BEGIN
            DECLARE @LapErrorMessage NVARCHAR(2048);

            SET @LapErrorMessage =
                N'FactLap: mapping mismatch. Source rows = '
                + CONVERT(NVARCHAR(20), @SourceRows)
                + N', intentionally rejected rows = '
                + CONVERT(NVARCHAR(20), @RejectedRows)
                + N', eligible rows = '
                + CONVERT(NVARCHAR(20), @EligibleRows)
                + N', mapped rows = '
                + CONVERT(NVARCHAR(20), @MappedRows)
                + N'.';

            THROW 51204, @LapErrorMessage, 1;
        END;


        -- Grain po mapowaniu nadal musi być unikalny.
        IF EXISTS (
            SELECT 1
            FROM #LapSource
            GROUP BY
                SessionKey,
                DriverKey,
                LapNumber
            HAVING COUNT(*) > 1
        )
        BEGIN
            THROW 51205,
                'FactLap: duplicate SessionKey + DriverKey + LapNumber after dimension mapping.',
                1;
        END;


        TRUNCATE TABLE dw.FactLap;


        INSERT INTO dw.FactLap (
            RaceWeekendKey,
            SessionKey,
            DriverKey,
            TeamKey,
            TeamColourKey,
            LapNumber,
            LapStartTime,
            LapDurationSeconds,
            Sector1DurationSeconds,
            Sector2DurationSeconds,
            Sector3DurationSeconds,
            I1Speed,
            I2Speed,
            STSpeed,
            IsPitOutLap
        )
        SELECT
            RaceWeekendKey,
            SessionKey,
            DriverKey,
            TeamKey,
            TeamColourKey,
            LapNumber,
            LapStartTime,
            LapDurationSeconds,
            Sector1DurationSeconds,
            Sector2DurationSeconds,
            Sector3DurationSeconds,
            I1Speed,
            I2Speed,
            STSpeed,
            IsPitOutLap
        FROM #LapSource;


        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        THROW;
    END CATCH;
END;
GO


-- =========================================================
-- FactStint
-- Grain: 1 kierowca x 1 stint x 1 sesja
--
-- Uwaga:
-- staging może zawierać rekordy stintów, których nie należy
-- ładować do facta:
-- 1) brak dokładnego rekordu kierowcy w stg.Drivers,
-- 2) rekord kierowcy istnieje, ale team_name jest pusty, przez co
--    nie istnieje poprawne mapowanie do dw.DimTeam.
--
-- Takie rekordy są świadomie odrzucane tylko wtedy, gdy nie mają
-- oficjalnego SessionResult. Jeżeli taki rekord ma oficjalny
-- wynik sesji, procedura przerywa ETL, aby nie ukrywać realnego
-- problemu mapowania kierowcy lub zespołu.
--
-- StintLaps:
-- liczba okrążeń przejechanych w stincie:
-- LapEnd - LapStart + 1.
--
-- Jeżeli LapStart lub LapEnd jest NULL albo LapEnd < LapStart,
-- StintLaps pozostaje NULL.
-- =========================================================

CREATE OR ALTER PROCEDURE dw.usp_LoadFactStint
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE @SourceRows INT;
        DECLARE @RejectedRows INT;
        DECLARE @EligibleRows INT;
        DECLARE @MappedRows INT;


        SELECT
            @SourceRows = COUNT(*)
        FROM stg.Stints;


        -- =====================================================
        -- Source grain musi być unikalny.
        -- =====================================================
        IF EXISTS (
            SELECT 1
            FROM stg.Stints
            GROUP BY
                session_key,
                driver_number,
                stint_number
            HAVING COUNT(*) > 1
        )
        BEGIN
            THROW 51301,
                'FactStint: duplicate rows in stg.Stints for session_key + driver_number + stint_number.',
                1;
        END;


        IF EXISTS (
            SELECT 1
            FROM stg.Stints
            WHERE meeting_key IS NULL
               OR session_key IS NULL
               OR driver_number IS NULL
               OR stint_number IS NULL
        )
        BEGIN
            THROW 51305,
                'FactStint: NULL in meeting_key, session_key, driver_number or stint_number.',
                1;
        END;


        -- =====================================================
        -- Telemetryczny rekord jest kwalifikowany tylko wtedy,
        -- gdy istnieje pełny rekord Drivers (full_name + team_name).
        -- Brak takiego mapowania może być zanieczyszczeniem źródła.
        -- =====================================================
        SELECT @RejectedRows = COUNT(*)
        FROM stg.Stints AS st
        WHERE NOT EXISTS (
            SELECT 1
            FROM stg.Drivers AS d
            WHERE d.meeting_key = st.meeting_key
              AND d.session_key = st.session_key
              AND d.driver_number = st.driver_number
              AND NULLIF(LTRIM(RTRIM(d.full_name)), N'') IS NOT NULL
              AND NULLIF(LTRIM(RTRIM(d.team_name)), N'') IS NOT NULL
        );

        -- Jeżeli odrzucany rekord ma oficjalny SessionResult,
        -- nie wolno go automatycznie pomijać.
        IF EXISTS (
            SELECT 1
            FROM stg.Stints AS st
            WHERE NOT EXISTS (
                SELECT 1
                FROM stg.Drivers AS d
                WHERE d.meeting_key = st.meeting_key
                  AND d.session_key = st.session_key
                  AND d.driver_number = st.driver_number
                  AND NULLIF(LTRIM(RTRIM(d.full_name)), N'') IS NOT NULL
                  AND NULLIF(LTRIM(RTRIM(d.team_name)), N'') IS NOT NULL
            )
              AND EXISTS (
                SELECT 1
                FROM stg.SessionResults AS sr
                WHERE sr.meeting_key = st.meeting_key
                  AND sr.session_key = st.session_key
                  AND sr.driver_number = st.driver_number
            )
        )
        BEGIN
            THROW 51302,
                'FactStint: rejected telemetry row has an official SessionResult; driver/team mapping requires investigation.',
                1;
        END;


        SET @EligibleRows = @SourceRows - @RejectedRows;


        -- =====================================================
        -- Budowa źródła FactStint.
        -- =====================================================
        DROP TABLE IF EXISTS #StintSource;


        SELECT
            rw.RaceWeekendKey,
            ds.SessionKey,
            dd.DriverKey,
            dt.TeamKey,
            tc.TeamColourKey,

            TRY_CONVERT(
                SMALLINT,
                st.stint_number
            ) AS StintNumber,

            NULLIF(
                LTRIM(RTRIM(st.compound)),
                N''
            ) AS Compound,

            lap.LapStart,

            lap.LapEnd,

            CASE
                WHEN lap.LapStart IS NULL
                  OR lap.LapEnd IS NULL
                  OR lap.LapEnd < lap.LapStart
                    THEN NULL
                ELSE
                    CONVERT(INT, lap.LapEnd)
                    - CONVERT(INT, lap.LapStart)
                    + 1
            END AS StintLaps,

            TRY_CONVERT(
                DECIMAL(6,2),
                NULLIF(
                    LTRIM(RTRIM(st.tyre_age_at_start)),
                    N''
                )
            ) AS TyreAgeAtStart

        INTO #StintSource

        FROM stg.Stints AS st

        CROSS APPLY (
            SELECT
                TRY_CONVERT(
                    SMALLINT,
                    NULLIF(
                        LTRIM(RTRIM(st.lap_start)),
                        N''
                    )
                ) AS LapStart,

                TRY_CONVERT(
                    SMALLINT,
                    NULLIF(
                        LTRIM(RTRIM(st.lap_end)),
                        N''
                    )
                ) AS LapEnd
        ) AS lap

        JOIN dw.DimSession AS ds
            ON ds.SourceSessionKey = st.session_key

        JOIN dw.DimRaceWeekend AS rw
            ON rw.RaceWeekendKey = ds.RaceWeekendKey
           AND rw.SourceMeetingKey = st.meeting_key

        JOIN stg.Drivers AS d
            ON d.meeting_key = st.meeting_key
           AND d.session_key = st.session_key
           AND d.driver_number = st.driver_number
           AND NULLIF(LTRIM(RTRIM(d.full_name)), N'') IS NOT NULL
           AND NULLIF(LTRIM(RTRIM(d.team_name)), N'') IS NOT NULL

        JOIN dw.DimDriver AS dd
            ON dd.DriverBusinessKey =
                LEFT(
                    LTRIM(RTRIM(d.full_name)),
                    100
                )
           AND ds.DateStart >= dd.ValidFrom
           AND (
                dd.ValidTo IS NULL
                OR ds.DateStart < dd.ValidTo
           )

        JOIN dw.DimTeam AS dt
            ON dt.TeamName =
                LEFT(
                    LTRIM(RTRIM(d.team_name)),
                    100
                )

        LEFT JOIN dw.DimTeamColour AS tc
            ON tc.TeamKey = dt.TeamKey
           AND tc.TeamColour =
                UPPER(
                    CONVERT(
                        VARCHAR(20),
                        LEFT(
                            LTRIM(RTRIM(d.team_colour)),
                            20
                        )
                    )
                );


        -- =====================================================
        -- Kontrola liczby rekordów po mapowaniu.
        -- =====================================================
        SELECT
            @MappedRows = COUNT(*)
        FROM #StintSource;


        IF @MappedRows <> @EligibleRows
        BEGIN
            DECLARE @StintErrorMessage NVARCHAR(2048);

            SET @StintErrorMessage =
                N'FactStint: mapping mismatch. Source rows = '
                + CONVERT(NVARCHAR(20), @SourceRows)
                + N', intentionally rejected rows = '
                + CONVERT(NVARCHAR(20), @RejectedRows)
                + N', eligible rows = '
                + CONVERT(NVARCHAR(20), @EligibleRows)
                + N', mapped rows = '
                + CONVERT(NVARCHAR(20), @MappedRows)
                + N'.';

            THROW 51303, @StintErrorMessage, 1;
        END;


        -- =====================================================
        -- Grain po mapowaniu nadal musi być unikalny.
        -- =====================================================
        IF EXISTS (
            SELECT 1
            FROM #StintSource
            GROUP BY
                SessionKey,
                DriverKey,
                StintNumber
            HAVING COUNT(*) > 1
        )
        BEGIN
            THROW 51304,
                'FactStint: duplicate SessionKey + DriverKey + StintNumber after dimension mapping.',
                1;
        END;


        -- =====================================================
        -- Pełne przeładowanie FactStint.
        -- =====================================================
        TRUNCATE TABLE dw.FactStint;


        INSERT INTO dw.FactStint (
            RaceWeekendKey,
            SessionKey,
            DriverKey,
            TeamKey,
            TeamColourKey,
            StintNumber,
            Compound,
            LapStart,
            LapEnd,
            StintLaps,
            TyreAgeAtStart
        )
        SELECT
            RaceWeekendKey,
            SessionKey,
            DriverKey,
            TeamKey,
            TeamColourKey,
            StintNumber,
            Compound,
            LapStart,
            LapEnd,
            StintLaps,
            TyreAgeAtStart
        FROM #StintSource;


        COMMIT TRANSACTION;

    END TRY
    BEGIN CATCH

        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        THROW;

    END CATCH;
END;
GO


-- =========================================================
-- FactPitStop
-- Grain:
-- 1 kierowca x 1 okrążenie x 1 sesja
-- =========================================================

CREATE OR ALTER PROCEDURE dw.usp_LoadFactPitStop
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE @SourceRows INT;
        DECLARE @RejectedRows INT;
        DECLARE @EligibleRows INT;
        DECLARE @MappedRows INT;

        SELECT @SourceRows = COUNT(*)
        FROM stg.PitStops;


        -- Source grain musi być unikalny.
        IF EXISTS (
            SELECT 1
            FROM stg.PitStops
            GROUP BY
                session_key,
                driver_number,
                lap_number
            HAVING COUNT(*) > 1
        )
        BEGIN
            THROW 51401,
                'FactPitStop: duplicate rows in stg.PitStops for session_key + driver_number + lap_number.',
                1;
        END;


        IF EXISTS (
            SELECT 1
            FROM stg.PitStops
            WHERE meeting_key IS NULL
               OR session_key IS NULL
               OR driver_number IS NULL
               OR lap_number IS NULL
        )
        BEGIN
            THROW 51407,
                'FactPitStop: NULL in meeting_key, session_key, driver_number or lap_number.',
                1;
        END;


        -- Telemetryczny rekord jest kwalifikowany tylko wtedy,
        -- gdy istnieje pełny Drivers (full_name + team_name).
        SELECT @RejectedRows = COUNT(*)
        FROM stg.PitStops AS p
        WHERE NOT EXISTS (
            SELECT 1
            FROM stg.Drivers AS d
            WHERE d.meeting_key = p.meeting_key
              AND d.session_key = p.session_key
              AND d.driver_number = p.driver_number
              AND NULLIF(LTRIM(RTRIM(d.full_name)), N'') IS NOT NULL
              AND NULLIF(LTRIM(RTRIM(d.team_name)), N'') IS NOT NULL
        );

        -- Odrzucenie jest dozwolone wyłącznie dla rekordów bez
        -- oficjalnego SessionResult. Oficjalny wynik = realny problem.
        IF EXISTS (
            SELECT 1
            FROM stg.PitStops AS p
            WHERE NOT EXISTS (
                SELECT 1
                FROM stg.Drivers AS d
                WHERE d.meeting_key = p.meeting_key
                  AND d.session_key = p.session_key
                  AND d.driver_number = p.driver_number
                  AND NULLIF(LTRIM(RTRIM(d.full_name)), N'') IS NOT NULL
                  AND NULLIF(LTRIM(RTRIM(d.team_name)), N'') IS NOT NULL
            )
              AND EXISTS (
                SELECT 1
                FROM stg.SessionResults AS sr
                WHERE sr.meeting_key = p.meeting_key
                  AND sr.session_key = p.session_key
                  AND sr.driver_number = p.driver_number
            )
        )
        BEGIN
            THROW 51402,
                'FactPitStop: rejected telemetry row has an official SessionResult; driver/team mapping requires investigation.',
                1;
        END;

        SET @EligibleRows = @SourceRows - @RejectedRows;


        -- Niepuste timestampy muszą być konwertowalne.
        IF EXISTS (
            SELECT 1
            FROM stg.PitStops
            WHERE NULLIF(LTRIM(RTRIM([date])), N'') IS NOT NULL
              AND TRY_CONVERT(
                    DATETIMEOFFSET(6),
                    NULLIF(LTRIM(RTRIM([date])), N'')
                  ) IS NULL
        )
        BEGIN
            THROW 51403,
                'FactPitStop: invalid date value in stg.PitStops.',
                1;
        END;


        -- Niepuste duration muszą być liczbami.
        IF EXISTS (
            SELECT 1
            FROM stg.PitStops
            WHERE (
                    NULLIF(LTRIM(RTRIM(lane_duration)), N'') IS NOT NULL
                    AND TRY_CONVERT(
                        DECIMAL(12,3),
                        NULLIF(LTRIM(RTRIM(lane_duration)), N'')
                    ) IS NULL
                  )
               OR (
                    NULLIF(LTRIM(RTRIM(stop_duration)), N'') IS NOT NULL
                    AND TRY_CONVERT(
                        DECIMAL(12,3),
                        NULLIF(LTRIM(RTRIM(stop_duration)), N'')
                    ) IS NULL
                  )
        )
        BEGIN
            THROW 51404,
                'FactPitStop: invalid duration value in stg.PitStops.',
                1;
        END;


        DROP TABLE IF EXISTS #PitStopSource;

        SELECT
            rw.RaceWeekendKey,
            ds.SessionKey,
            dd.DriverKey,
            dt.TeamKey,
            tc.TeamColourKey,

            TRY_CONVERT(
                SMALLINT,
                p.lap_number
            ) AS LapNumber,

            CONVERT(
                DATETIME2(6),
                TRY_CONVERT(
                    DATETIMEOFFSET(6),
                    NULLIF(LTRIM(RTRIM(p.[date])), N'')
                ) AT TIME ZONE 'Central European Standard Time'
            ) AS PitStopTime,

            TRY_CONVERT(
                DECIMAL(12,3),
                NULLIF(LTRIM(RTRIM(p.lane_duration)), N'')
            ) AS LaneDurationSeconds,

            TRY_CONVERT(
                DECIMAL(12,3),
                NULLIF(LTRIM(RTRIM(p.stop_duration)), N'')
            ) AS StopDurationSeconds

        INTO #PitStopSource

        FROM stg.PitStops AS p

        JOIN dw.DimSession AS ds
            ON ds.SourceSessionKey = p.session_key

        JOIN dw.DimRaceWeekend AS rw
            ON rw.RaceWeekendKey = ds.RaceWeekendKey
           AND rw.SourceMeetingKey = p.meeting_key

        JOIN stg.Drivers AS d
            ON d.meeting_key = p.meeting_key
           AND d.session_key = p.session_key
           AND d.driver_number = p.driver_number
           AND NULLIF(LTRIM(RTRIM(d.full_name)), N'') IS NOT NULL
           AND NULLIF(LTRIM(RTRIM(d.team_name)), N'') IS NOT NULL

        JOIN dw.DimDriver AS dd
            ON dd.DriverBusinessKey = LEFT(LTRIM(RTRIM(d.full_name)), 100)
           AND ds.DateStart >= dd.ValidFrom
           AND (
                dd.ValidTo IS NULL
                OR ds.DateStart < dd.ValidTo
           )

        JOIN dw.DimTeam AS dt
            ON dt.TeamName = LEFT(LTRIM(RTRIM(d.team_name)), 100)

        LEFT JOIN dw.DimTeamColour AS tc
            ON tc.TeamKey = dt.TeamKey
           AND tc.TeamColour = UPPER(
                CONVERT(
                    VARCHAR(20),
                    LEFT(LTRIM(RTRIM(d.team_colour)), 20)
                )
           );


        SELECT @MappedRows = COUNT(*)
        FROM #PitStopSource;


        IF @MappedRows <> @EligibleRows
        BEGIN
            DECLARE @PitStopErrorMessage NVARCHAR(2048);

            SET @PitStopErrorMessage =
                N'FactPitStop: mapping mismatch. Source rows = '
                + CONVERT(NVARCHAR(20), @SourceRows)
                + N', intentionally rejected rows = '
                + CONVERT(NVARCHAR(20), @RejectedRows)
                + N', eligible rows = '
                + CONVERT(NVARCHAR(20), @EligibleRows)
                + N', mapped rows = '
                + CONVERT(NVARCHAR(20), @MappedRows)
                + N'.';

            THROW 51405, @PitStopErrorMessage, 1;
        END;


        -- Grain po mapowaniu nadal musi być unikalny.
        IF EXISTS (
            SELECT 1
            FROM #PitStopSource
            GROUP BY
                SessionKey,
                DriverKey,
                LapNumber
            HAVING COUNT(*) > 1
        )
        BEGIN
            THROW 51406,
                'FactPitStop: duplicate SessionKey + DriverKey + LapNumber after dimension mapping.',
                1;
        END;


        TRUNCATE TABLE dw.FactPitStop;


        INSERT INTO dw.FactPitStop (
            RaceWeekendKey,
            SessionKey,
            DriverKey,
            TeamKey,
            TeamColourKey,
            LapNumber,
            PitStopTime,
            LaneDurationSeconds,
            StopDurationSeconds
        )
        SELECT
            RaceWeekendKey,
            SessionKey,
            DriverKey,
            TeamKey,
            TeamColourKey,
            LapNumber,
            PitStopTime,
            LaneDurationSeconds,
            StopDurationSeconds
        FROM #PitStopSource;


        COMMIT TRANSACTION;

    END TRY
    BEGIN CATCH

        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        THROW;

    END CATCH;
END;
GO


-- =========================================================
-- FactWeather
-- Grain:
-- 1 pomiar pogody x 1 moment x 1 sesja
-- =========================================================

CREATE OR ALTER PROCEDURE dw.usp_LoadFactWeather
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE @SourceRows INT;
        DECLARE @MappedRows INT;

        SELECT @SourceRows = COUNT(*)
        FROM stg.Weather;


        -- Source grain musi być unikalny.
        IF EXISTS (
            SELECT 1
            FROM stg.Weather
            GROUP BY
                session_key,
                [date]
            HAVING COUNT(*) > 1
        )
        BEGIN
            THROW 51501,
                'FactWeather: duplicate rows in stg.Weather for session_key + date.',
                1;
        END;


        -- Każdy rekord musi mapować się do istniejącej sesji.
        IF EXISTS (
            SELECT 1
            FROM stg.Weather AS w
            LEFT JOIN dw.DimSession AS ds
                ON ds.SourceSessionKey = w.session_key
            WHERE ds.SessionKey IS NULL
        )
        BEGIN
            THROW 51502,
                'FactWeather: missing session mapping in dw.DimSession.',
                1;
        END;


        -- Timestamp musi być obecny i konwertowalny.
        IF EXISTS (
            SELECT 1
            FROM stg.Weather
            WHERE NULLIF(LTRIM(RTRIM([date])), N'') IS NULL
               OR TRY_CONVERT(
                    DATETIMEOFFSET(6),
                    NULLIF(LTRIM(RTRIM([date])), N'')
                  ) IS NULL
        )
        BEGIN
            THROW 51503,
                'FactWeather: invalid or missing date value in stg.Weather.',
                1;
        END;


        -- Pola pogodowe, jeśli występują, muszą być liczbowe.
        IF EXISTS (
            SELECT 1
            FROM stg.Weather
            WHERE
                   (
                       NULLIF(LTRIM(RTRIM(air_temperature)), N'') IS NOT NULL
                       AND TRY_CONVERT(DECIMAL(6,2), air_temperature) IS NULL
                   )
                OR (
                       NULLIF(LTRIM(RTRIM(track_temperature)), N'') IS NOT NULL
                       AND TRY_CONVERT(DECIMAL(6,2), track_temperature) IS NULL
                   )
                OR (
                       NULLIF(LTRIM(RTRIM(humidity)), N'') IS NOT NULL
                       AND TRY_CONVERT(DECIMAL(6,2), humidity) IS NULL
                   )
                OR (
                       NULLIF(LTRIM(RTRIM(pressure)), N'') IS NOT NULL
                       AND TRY_CONVERT(DECIMAL(8,2), pressure) IS NULL
                   )
                OR (
                       NULLIF(LTRIM(RTRIM(wind_direction)), N'') IS NOT NULL
                       AND TRY_CONVERT(DECIMAL(6,2), wind_direction) IS NULL
                   )
                OR (
                       NULLIF(LTRIM(RTRIM(wind_speed)), N'') IS NOT NULL
                       AND TRY_CONVERT(DECIMAL(8,3), wind_speed) IS NULL
                   )
        )
        BEGIN
            THROW 51504,
                'FactWeather: invalid numeric weather value in stg.Weather.',
                1;
        END;


        -- Rainfall w źródle ma być wyłącznie 0 / 1 / puste.
        IF EXISTS (
            SELECT 1
            FROM stg.Weather
            WHERE NULLIF(LTRIM(RTRIM(rainfall)), N'') IS NOT NULL
              AND LTRIM(RTRIM(rainfall)) NOT IN (N'0', N'1')
        )
        BEGIN
            THROW 51505,
                'FactWeather: unexpected rainfall value in stg.Weather.',
                1;
        END;


        DROP TABLE IF EXISTS #WeatherSource;

        SELECT
            rw.RaceWeekendKey,
            ds.SessionKey,

            CONVERT(
                DATETIME2(6),
                TRY_CONVERT(
                    DATETIMEOFFSET(6),
                    NULLIF(LTRIM(RTRIM(w.[date])), N'')
                ) AT TIME ZONE 'Central European Standard Time'
            ) AS WeatherTime,

            TRY_CONVERT(
                DECIMAL(6,2),
                NULLIF(LTRIM(RTRIM(w.air_temperature)), N'')
            ) AS AirTemperature,

            TRY_CONVERT(
                DECIMAL(6,2),
                NULLIF(LTRIM(RTRIM(w.track_temperature)), N'')
            ) AS TrackTemperature,

            TRY_CONVERT(
                DECIMAL(6,2),
                NULLIF(LTRIM(RTRIM(w.humidity)), N'')
            ) AS Humidity,

            TRY_CONVERT(
                DECIMAL(8,2),
                NULLIF(LTRIM(RTRIM(w.pressure)), N'')
            ) AS Pressure,

            TRY_CONVERT(
                BIT,
                NULLIF(LTRIM(RTRIM(w.rainfall)), N'')
            ) AS Rainfall,

            TRY_CONVERT(
                DECIMAL(6,2),
                NULLIF(LTRIM(RTRIM(w.wind_direction)), N'')
            ) AS WindDirection,

            TRY_CONVERT(
                DECIMAL(8,3),
                NULLIF(LTRIM(RTRIM(w.wind_speed)), N'')
            ) AS WindSpeed

        INTO #WeatherSource

        FROM stg.Weather AS w

        JOIN dw.DimSession AS ds
            ON ds.SourceSessionKey = w.session_key

        JOIN dw.DimRaceWeekend AS rw
            ON rw.RaceWeekendKey = ds.RaceWeekendKey
           AND rw.SourceMeetingKey = w.meeting_key;


        SELECT @MappedRows = COUNT(*)
        FROM #WeatherSource;


        IF @MappedRows <> @SourceRows
        BEGIN
            DECLARE @WeatherErrorMessage NVARCHAR(2048);

            SET @WeatherErrorMessage =
                N'FactWeather: mapping mismatch. Source rows = '
                + CONVERT(NVARCHAR(20), @SourceRows)
                + N', mapped rows = '
                + CONVERT(NVARCHAR(20), @MappedRows)
                + N'.';

            THROW 51506, @WeatherErrorMessage, 1;
        END;


        -- Grain po mapowaniu nadal musi być unikalny.
        IF EXISTS (
            SELECT 1
            FROM #WeatherSource
            GROUP BY
                SessionKey,
                WeatherTime
            HAVING COUNT(*) > 1
        )
        BEGIN
            THROW 51507,
                'FactWeather: duplicate SessionKey + WeatherTime after dimension mapping.',
                1;
        END;


        TRUNCATE TABLE dw.FactWeather;


        INSERT INTO dw.FactWeather (
            RaceWeekendKey,
            SessionKey,
            WeatherTime,
            AirTemperature,
            TrackTemperature,
            Humidity,
            Pressure,
            Rainfall,
            WindDirection,
            WindSpeed
        )
        SELECT
            RaceWeekendKey,
            SessionKey,
            WeatherTime,
            AirTemperature,
            TrackTemperature,
            Humidity,
            Pressure,
            Rainfall,
            WindDirection,
            WindSpeed
        FROM #WeatherSource;


        COMMIT TRANSACTION;

    END TRY
    BEGIN CATCH

        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        THROW;

    END CATCH;
END;
GO


-- =========================================================
-- FactRaceControl
-- Grain:
-- 1 komunikat / zdarzenie Race Control
--
-- Ważna konwencja źródła:
-- driver_number = 0 nie jest numerem kierowcy.
-- Oznacza komunikat globalny / bez przypisanego kierowcy.
-- Nie próbujemy wyciągać kierowcy z tekstu Message.
-- =========================================================

CREATE OR ALTER PROCEDURE dw.usp_LoadFactRaceControl
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE @SourceRows INT;
        DECLARE @RejectedRows INT;
        DECLARE @EligibleRows INT;
        DECLARE @MappedRows INT;

        SELECT @SourceRows = COUNT(*)
        FROM stg.RaceControl;


        -- Dokładne duplikaty źródłowych eventów są niedozwolone.
        IF EXISTS (
            SELECT 1
            FROM stg.RaceControl
            GROUP BY
                session_key,
                [date],
                driver_number,
                lap_number,
                category,
                flag,
                scope,
                sector,
                message
            HAVING COUNT(*) > 1
        )
        BEGIN
            THROW 51601,
                'FactRaceControl: exact duplicate Race Control events found in staging.',
                1;
        END;


        -- Timestamp musi istnieć i być konwertowalny.
        IF EXISTS (
            SELECT 1
            FROM stg.RaceControl
            WHERE NULLIF(LTRIM(RTRIM([date])), N'') IS NULL
               OR TRY_CONVERT(
                    DATETIMEOFFSET(6),
                    NULLIF(LTRIM(RTRIM([date])), N'')
                  ) IS NULL
        )
        BEGIN
            THROW 51602,
                'FactRaceControl: invalid or missing date value.',
                1;
        END;


        -- Dodatni driver_number oznacza komunikat przypisany do kierowcy.
        -- Jeżeli brak pełnego Drivers (full_name + team_name), traktujemy
        -- rekord jako kandydat do odrzucenia źródłowego.
        SELECT @RejectedRows = COUNT(*)
        FROM stg.RaceControl AS rc
        WHERE rc.driver_number > 0
          AND NOT EXISTS (
                SELECT 1
                FROM stg.Drivers AS d
                WHERE d.meeting_key = rc.meeting_key
                  AND d.session_key = rc.session_key
                  AND d.driver_number = rc.driver_number
                  AND NULLIF(LTRIM(RTRIM(d.full_name)), N'') IS NOT NULL
                  AND NULLIF(LTRIM(RTRIM(d.team_name)), N'') IS NOT NULL
          );

        -- Oficjalny SessionResult dla odrzucanego kierowcy oznacza,
        -- że to nie jest bezpieczny śmieć źródłowy i ETL ma się zatrzymać.
        IF EXISTS (
            SELECT 1
            FROM stg.RaceControl AS rc
            WHERE rc.driver_number > 0
              AND NOT EXISTS (
                    SELECT 1
                    FROM stg.Drivers AS d
                    WHERE d.meeting_key = rc.meeting_key
                      AND d.session_key = rc.session_key
                      AND d.driver_number = rc.driver_number
                      AND NULLIF(LTRIM(RTRIM(d.full_name)), N'') IS NOT NULL
                      AND NULLIF(LTRIM(RTRIM(d.team_name)), N'') IS NOT NULL
              )
              AND EXISTS (
                    SELECT 1
                    FROM stg.SessionResults AS sr
                    WHERE sr.meeting_key = rc.meeting_key
                      AND sr.session_key = rc.session_key
                      AND sr.driver_number = rc.driver_number
              )
        )
        BEGIN
            THROW 51603,
                'FactRaceControl: rejected driver-specific event has an official SessionResult; mapping requires investigation.',
                1;
        END;

        SET @EligibleRows = @SourceRows - @RejectedRows;


        -- Niepusta kategoria musi istnieć w wymiarze.
        IF EXISTS (
            SELECT 1
            FROM stg.RaceControl AS rc
            LEFT JOIN dw.DimRaceControlCategory AS c
                ON c.CategoryName = LTRIM(RTRIM(rc.category))
            WHERE NULLIF(LTRIM(RTRIM(rc.category)), N'') IS NOT NULL
              AND c.RaceControlCategoryKey IS NULL
        )
        BEGIN
            THROW 51604,
                'FactRaceControl: category not found in dw.DimRaceControlCategory.',
                1;
        END;


        -- Niepusta flaga musi istnieć w wymiarze.
        IF EXISTS (
            SELECT 1
            FROM stg.RaceControl AS rc
            LEFT JOIN dw.DimFlag AS f
                ON f.FlagName = LTRIM(RTRIM(rc.flag))
            WHERE NULLIF(LTRIM(RTRIM(rc.flag)), N'') IS NOT NULL
              AND f.FlagKey IS NULL
        )
        BEGIN
            THROW 51605,
                'FactRaceControl: flag not found in dw.DimFlag.',
                1;
        END;


        DROP TABLE IF EXISTS #RaceControlSource;

        SELECT
            rw.RaceWeekendKey,
            ds.SessionKey,

            rc.driver_number AS SourceDriverNumber,

            CASE
                WHEN rc.driver_number > 0 THEN dd.DriverKey
                ELSE NULL
            END AS DriverKey,

            CASE
                WHEN rc.driver_number > 0 THEN dt.TeamKey
                ELSE NULL
            END AS TeamKey,

            CASE
                WHEN rc.driver_number > 0 THEN tc.TeamColourKey
                ELSE NULL
            END AS TeamColourKey,

            cat.RaceControlCategoryKey,
            flg.FlagKey,

            CONVERT(
                DATETIME2(6),
                TRY_CONVERT(
                    DATETIMEOFFSET(6),
                    NULLIF(LTRIM(RTRIM(rc.[date])), N'')
                ) AT TIME ZONE 'Central European Standard Time'
            ) AS EventTime,

            TRY_CONVERT(
                SMALLINT,
                rc.lap_number
            ) AS LapNumber,

            NULLIF(
                LEFT(LTRIM(RTRIM(rc.scope)), 50),
                N''
            ) AS Scope,

            TRY_CONVERT(
                SMALLINT,
                NULLIF(rc.sector, 0)
            ) AS Sector,

            rc.message AS Message

        INTO #RaceControlSource

        FROM stg.RaceControl AS rc

        JOIN dw.DimSession AS ds
            ON ds.SourceSessionKey = rc.session_key

        JOIN dw.DimRaceWeekend AS rw
            ON rw.RaceWeekendKey = ds.RaceWeekendKey
           AND rw.SourceMeetingKey = rc.meeting_key

        LEFT JOIN stg.Drivers AS d
            ON rc.driver_number > 0
           AND d.meeting_key = rc.meeting_key
           AND d.session_key = rc.session_key
           AND d.driver_number = rc.driver_number
           AND NULLIF(LTRIM(RTRIM(d.full_name)), N'') IS NOT NULL
           AND NULLIF(LTRIM(RTRIM(d.team_name)), N'') IS NOT NULL

        LEFT JOIN dw.DimDriver AS dd
            ON rc.driver_number > 0
           AND dd.DriverBusinessKey = LEFT(LTRIM(RTRIM(d.full_name)), 100)
           AND ds.DateStart >= dd.ValidFrom
           AND (
                dd.ValidTo IS NULL
                OR ds.DateStart < dd.ValidTo
           )

        LEFT JOIN dw.DimTeam AS dt
            ON rc.driver_number > 0
           AND dt.TeamName = LEFT(LTRIM(RTRIM(d.team_name)), 100)

        LEFT JOIN dw.DimTeamColour AS tc
            ON rc.driver_number > 0
           AND tc.TeamKey = dt.TeamKey
           AND tc.TeamColour = UPPER(
                CONVERT(
                    VARCHAR(20),
                    LEFT(LTRIM(RTRIM(d.team_colour)), 20)
                )
           )

        LEFT JOIN dw.DimRaceControlCategory AS cat
            ON cat.CategoryName = LTRIM(RTRIM(rc.category))

        LEFT JOIN dw.DimFlag AS flg
            ON flg.FlagName = LTRIM(RTRIM(rc.flag))

        WHERE rc.driver_number IS NULL
           OR rc.driver_number <= 0
           OR d.driver_number IS NOT NULL;


        SELECT @MappedRows = COUNT(*)
        FROM #RaceControlSource;


        IF @MappedRows <> @EligibleRows
        BEGIN
            DECLARE @RaceControlErrorMessage NVARCHAR(2048);

            SET @RaceControlErrorMessage =
                N'FactRaceControl: mapping mismatch. Source rows = '
                + CONVERT(NVARCHAR(20), @SourceRows)
                + N', intentionally rejected rows = '
                + CONVERT(NVARCHAR(20), @RejectedRows)
                + N', eligible rows = '
                + CONVERT(NVARCHAR(20), @EligibleRows)
                + N', mapped rows = '
                + CONVERT(NVARCHAR(20), @MappedRows)
                + N'.';

            THROW 51606, @RaceControlErrorMessage, 1;
        END;


        -- Każdy dodatni driver_number musi finalnie dostać DriverKey
        -- i TeamKey. driver_number = 0 świadomie pozostaje NULL.
        IF EXISTS (
            SELECT 1
            FROM #RaceControlSource
            WHERE SourceDriverNumber > 0
              AND (
                    DriverKey IS NULL
                    OR TeamKey IS NULL
                  )
        )
        BEGIN
            THROW 51607,
                'FactRaceControl: positive driver_number failed dimension mapping.',
                1;
        END;


        TRUNCATE TABLE dw.FactRaceControl;


        INSERT INTO dw.FactRaceControl (
            RaceWeekendKey,
            SessionKey,
            DriverKey,
            TeamKey,
            TeamColourKey,
            RaceControlCategoryKey,
            FlagKey,
            EventTime,
            LapNumber,
            Scope,
            Sector,
            Message
        )
        SELECT
            RaceWeekendKey,
            SessionKey,
            DriverKey,
            TeamKey,
            TeamColourKey,
            RaceControlCategoryKey,
            FlagKey,
            EventTime,
            LapNumber,
            Scope,
            Sector,
            Message
        FROM #RaceControlSource;


        COMMIT TRANSACTION;

    END TRY
    BEGIN CATCH

        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        THROW;

    END CATCH;
END;
GO


-- =========================================================
-- FactAttendance
-- Grain:
-- 1 rekord x 1 weekend Grand Prix
--
-- Brakujące wartości frekwencji są zachowywane jako NULL.
-- NULL oznacza brak danych, nie zero widzów.
-- =========================================================

CREATE OR ALTER PROCEDURE dw.usp_LoadFactAttendance
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE @SourceRows INT;
        DECLARE @MappedRows INT;

        SELECT @SourceRows = COUNT(*)
        FROM stg.Attendance;


        -- Jeden rekord źródłowy na weekend.
        IF EXISTS (
            SELECT 1
            FROM stg.Attendance
            GROUP BY meeting_key
            HAVING COUNT(*) > 1
        )
        BEGIN
            THROW 51701,
                'FactAttendance: duplicate rows in stg.Attendance for meeting_key.',
                1;
        END;


        -- Każdy rekord musi mapować się do DimRaceWeekend.
        IF EXISTS (
            SELECT 1
            FROM stg.Attendance AS a
            LEFT JOIN dw.DimRaceWeekend AS rw
                ON rw.SourceMeetingKey = a.meeting_key
            WHERE rw.RaceWeekendKey IS NULL
        )
        BEGIN
            THROW 51702,
                'FactAttendance: missing RaceWeekend mapping.',
                1;
        END;


        -- Niepuste attendance musi być konwertowalne do INT.
        IF EXISTS (
            SELECT 1
            FROM stg.Attendance
            WHERE
                   (
                       NULLIF(LTRIM(RTRIM(weekend_attendance)), N'') IS NOT NULL
                       AND TRY_CONVERT(
                           INT,
                           REPLACE(LTRIM(RTRIM(weekend_attendance)), N',', N'')
                       ) IS NULL
                   )
                OR (
                       NULLIF(LTRIM(RTRIM(race_day_attendance)), N'') IS NOT NULL
                       AND TRY_CONVERT(
                           INT,
                           REPLACE(LTRIM(RTRIM(race_day_attendance)), N',', N'')
                       ) IS NULL
                   )
        )
        BEGIN
            THROW 51703,
                'FactAttendance: invalid attendance value.',
                1;
        END;


        -- Niepusta data źródła musi być konwertowalna.
        IF EXISTS (
            SELECT 1
            FROM stg.Attendance
            WHERE NULLIF(LTRIM(RTRIM(source_date)), N'') IS NOT NULL
              AND TRY_CONVERT(
                    DATE,
                    NULLIF(LTRIM(RTRIM(source_date)), N'')
                  ) IS NULL
        )
        BEGIN
            THROW 51704,
                'FactAttendance: invalid source_date value.',
                1;
        END;


        DROP TABLE IF EXISTS #AttendanceSource;

        SELECT
            rw.RaceWeekendKey,

            TRY_CONVERT(
                INT,
                REPLACE(
                    NULLIF(LTRIM(RTRIM(a.weekend_attendance)), N''),
                    N',',
                    N''
                )
            ) AS WeekendAttendance,

            TRY_CONVERT(
                INT,
                REPLACE(
                    NULLIF(LTRIM(RTRIM(a.race_day_attendance)), N''),
                    N',',
                    N''
                )
            ) AS RaceDayAttendance,

            TRY_CONVERT(
                DATE,
                NULLIF(LTRIM(RTRIM(a.source_date)), N'')
            ) AS SourceDate,

            NULLIF(
                LEFT(LTRIM(RTRIM(a.source_url)), 2000),
                N''
            ) AS SourceUrl,

            NULLIF(
                LTRIM(RTRIM(a.notes)),
                N''
            ) AS Notes

        INTO #AttendanceSource

        FROM stg.Attendance AS a

        JOIN dw.DimRaceWeekend AS rw
            ON rw.SourceMeetingKey = a.meeting_key;


        SELECT @MappedRows = COUNT(*)
        FROM #AttendanceSource;


        IF @MappedRows <> @SourceRows
        BEGIN
            DECLARE @AttendanceErrorMessage NVARCHAR(2048);

            SET @AttendanceErrorMessage =
                N'FactAttendance: mapping mismatch. Source rows = '
                + CONVERT(NVARCHAR(20), @SourceRows)
                + N', mapped rows = '
                + CONVERT(NVARCHAR(20), @MappedRows)
                + N'.';

            THROW 51705, @AttendanceErrorMessage, 1;
        END;


        TRUNCATE TABLE dw.FactAttendance;


        INSERT INTO dw.FactAttendance (
            RaceWeekendKey,
            WeekendAttendance,
            RaceDayAttendance,
            SourceDate,
            SourceUrl,
            Notes
        )
        SELECT
            RaceWeekendKey,
            WeekendAttendance,
            RaceDayAttendance,
            SourceDate,
            SourceUrl,
            Notes
        FROM #AttendanceSource;


        COMMIT TRANSACTION;

    END TRY
    BEGIN CATCH

        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        THROW;

    END CATCH;
END;
GO


-- =========================================================
-- FactSessionResult
-- Grain: 1 driver x 1 session (all OpenF1 session types).
-- Loading: validated full reload, single transaction.
-- =========================================================

CREATE OR ALTER PROCEDURE dw.usp_LoadFactSessionResult
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE @SourceRows INT;
        DECLARE @MappedRows INT;
        DECLARE @BadMappings INT;
        DECLARE @ErrorMessage NVARCHAR(2048);

        SELECT @SourceRows = COUNT(*)
        FROM stg.SessionResults;

        IF @SourceRows = 0
            THROW 51800, N'FactSessionResult: stg.SessionResults is empty; refusing to clear DW fact.', 1;

        IF EXISTS (
            SELECT 1
            FROM stg.SessionResults
            GROUP BY session_key, driver_number
            HAVING COUNT(*) > 1
        )
            THROW 51801, N'FactSessionResult: duplicate session_key + driver_number in staging.', 1;

        IF EXISTS (
            SELECT 1
            FROM stg.SessionResults AS sr
            LEFT JOIN stg.Sessions AS s
                ON s.session_key = sr.session_key
               AND s.meeting_key = sr.meeting_key
               AND s.session_type = sr.session_type
               AND s.session_name = sr.session_name
            WHERE s.session_key IS NULL
        )
            THROW 51802, N'FactSessionResult: meeting/session/type/name mismatch with stg.Sessions.', 1;

        IF EXISTS (
            SELECT 1
            FROM stg.SessionResults AS sr
            INNER JOIN stg.Drivers AS d
                ON d.meeting_key = sr.meeting_key
               AND d.session_key = sr.session_key
               AND d.driver_number = sr.driver_number
            GROUP BY sr.session_key, sr.driver_number
            HAVING COUNT(*) > 1
        )
            THROW 51803, N'FactSessionResult: duplicate staging driver mapping by meeting/session/driver.', 1;

        -- Starting grid is optional; a missing grid must not eliminate a result.
        IF EXISTS (
            SELECT 1
            FROM stg.SessionResults AS sr
            INNER JOIN stg.StartingGrid AS sg
                ON sg.session_key = sr.session_key
               AND sg.driver_number = sr.driver_number
            GROUP BY sr.session_key, sr.driver_number
            HAVING COUNT(*) > 1
        )
            THROW 51804, N'FactSessionResult: duplicate starting grid by session_key + driver_number.', 1;

        DROP TABLE IF EXISTS #SessionResultSource;

        SELECT
            sr.meeting_key AS SourceMeetingKey,
            sr.session_key AS SourceSessionKey,
            sr.driver_number AS SourceDriverNumber,

            rw.RaceWeekendKey,
            ds.SessionKey,
            dd.DriverKey,
            dt.TeamKey,
            tc.TeamColourKey,

            TRY_CONVERT(SMALLINT, sg.grid_position) AS GridPosition,
            TRY_CONVERT(SMALLINT, sr.position) AS Position,
            TRY_CONVERT(SMALLINT, sr.number_of_laps) AS NumberOfLaps,
            TRY_CONVERT(DECIMAL(8,2), sr.points) AS Points,

            sr.dnf AS DNF,
            sr.dns AS DNS,
            sr.dsq AS DSQ,

            TRY_CONVERT(DECIMAL(12,3), sr.duration_seconds) AS DurationSeconds,
            TRY_CONVERT(DECIMAL(12,3), sr.gap_to_leader_seconds) AS GapToLeaderSeconds,
            sr.gap_to_leader_text AS GapToLeaderText,

            TRY_CONVERT(DECIMAL(12,3), sr.phase_1_duration_seconds) AS Phase1DurationSeconds,
            TRY_CONVERT(DECIMAL(12,3), sr.phase_2_duration_seconds) AS Phase2DurationSeconds,
            TRY_CONVERT(DECIMAL(12,3), sr.phase_3_duration_seconds) AS Phase3DurationSeconds,

            TRY_CONVERT(DECIMAL(12,3), sr.phase_1_gap_to_leader_seconds) AS Phase1GapToLeaderSeconds,
            sr.phase_1_gap_to_leader_text AS Phase1GapToLeaderText,
            TRY_CONVERT(DECIMAL(12,3), sr.phase_2_gap_to_leader_seconds) AS Phase2GapToLeaderSeconds,
            sr.phase_2_gap_to_leader_text AS Phase2GapToLeaderText,
            TRY_CONVERT(DECIMAL(12,3), sr.phase_3_gap_to_leader_seconds) AS Phase3GapToLeaderSeconds,
            sr.phase_3_gap_to_leader_text AS Phase3GapToLeaderText

        INTO #SessionResultSource
        FROM stg.SessionResults AS sr

        LEFT JOIN dw.DimSession AS ds
            ON ds.SourceSessionKey = sr.session_key

        LEFT JOIN dw.DimRaceWeekend AS rw
            ON rw.RaceWeekendKey = ds.RaceWeekendKey
           AND rw.SourceMeetingKey = sr.meeting_key

        LEFT JOIN stg.Drivers AS d
            ON d.meeting_key = sr.meeting_key
           AND d.session_key = sr.session_key
           AND d.driver_number = sr.driver_number

        LEFT JOIN dw.DimDriver AS dd
            ON dd.DriverBusinessKey = LEFT(LTRIM(RTRIM(d.full_name)), 100)
           AND ds.DateStart >= dd.ValidFrom
           AND (dd.ValidTo IS NULL OR ds.DateStart < dd.ValidTo)

        LEFT JOIN dw.DimTeam AS dt
            ON dt.TeamName = LEFT(LTRIM(RTRIM(d.team_name)), 100)

        LEFT JOIN dw.DimTeamColour AS tc
            ON tc.TeamKey = dt.TeamKey
           AND tc.TeamColour = UPPER(
                CONVERT(VARCHAR(20), LEFT(LTRIM(RTRIM(d.team_colour)), 20))
           )

        LEFT JOIN stg.StartingGrid AS sg
            ON sg.session_key = sr.session_key
           AND sg.driver_number = sr.driver_number;

        SELECT @MappedRows = COUNT(*)
        FROM #SessionResultSource;

        IF @MappedRows <> @SourceRows
        BEGIN
            SET @ErrorMessage = N'FactSessionResult: mapping row count mismatch. Source='
                + CONVERT(NVARCHAR(20), @SourceRows)
                + N'; joined='
                + CONVERT(NVARCHAR(20), @MappedRows)
                + N'. Check SCD2 drivers, staging sessions and team mapping.';
            THROW 51805, @ErrorMessage, 1;
        END;

        SELECT @BadMappings = COUNT(*)
        FROM #SessionResultSource
        WHERE RaceWeekendKey IS NULL
           OR SessionKey IS NULL
           OR DriverKey IS NULL
           OR TeamKey IS NULL;

        IF @BadMappings > 0
        BEGIN
            SELECT TOP (25)
                SourceMeetingKey,
                SourceSessionKey,
                SourceDriverNumber,
                RaceWeekendKey,
                SessionKey,
                DriverKey,
                TeamKey
            FROM #SessionResultSource
            WHERE RaceWeekendKey IS NULL
               OR SessionKey IS NULL
               OR DriverKey IS NULL
               OR TeamKey IS NULL
            ORDER BY SourceSessionKey, SourceDriverNumber;

            SET @ErrorMessage = N'FactSessionResult: missing dimension mapping in '
                + CONVERT(NVARCHAR(20), @BadMappings)
                + N' source records (sample returned as result set).';
            THROW 51806, @ErrorMessage, 1;
        END;

        IF EXISTS (
            SELECT 1
            FROM #SessionResultSource
            GROUP BY SessionKey, DriverKey
            HAVING COUNT(*) > 1
        )
            THROW 51807, N'FactSessionResult: duplicate SessionKey + DriverKey after DW mapping.', 1;

        -- Atomic full reload; rollback leaves previous fact intact on failure.
        TRUNCATE TABLE dw.FactSessionResult;

        INSERT INTO dw.FactSessionResult (
            RaceWeekendKey,
            SessionKey,
            DriverKey,
            TeamKey,
            TeamColourKey,
            GridPosition,
            Position,
            NumberOfLaps,
            Points,
            DNF,
            DNS,
            DSQ,
            DurationSeconds,
            GapToLeaderSeconds,
            GapToLeaderText,
            Phase1DurationSeconds,
            Phase2DurationSeconds,
            Phase3DurationSeconds,
            Phase1GapToLeaderSeconds,
            Phase1GapToLeaderText,
            Phase2GapToLeaderSeconds,
            Phase2GapToLeaderText,
            Phase3GapToLeaderSeconds,
            Phase3GapToLeaderText
        )
        SELECT
            RaceWeekendKey,
            SessionKey,
            DriverKey,
            TeamKey,
            TeamColourKey,
            GridPosition,
            Position,
            NumberOfLaps,
            Points,
            DNF,
            DNS,
            DSQ,
            DurationSeconds,
            GapToLeaderSeconds,
            GapToLeaderText,
            Phase1DurationSeconds,
            Phase2DurationSeconds,
            Phase3DurationSeconds,
            Phase1GapToLeaderSeconds,
            Phase1GapToLeaderText,
            Phase2GapToLeaderSeconds,
            Phase2GapToLeaderText,
            Phase3GapToLeaderSeconds,
            Phase3GapToLeaderText
        FROM #SessionResultSource;

        IF @@ROWCOUNT <> @SourceRows
            THROW 51808, N'FactSessionResult: unexpected insert row count.', 1;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO

-- =========================================================
-- Wrapper wszystkich factów
-- =========================================================

CREATE OR ALTER PROCEDURE dw.usp_LoadAllFacts
AS
BEGIN
    SET NOCOUNT ON;

    EXEC dw.usp_LoadFactSessionResult;
    EXEC dw.usp_LoadFactLap;
    EXEC dw.usp_LoadFactStint;
    EXEC dw.usp_LoadFactPitStop;
    EXEC dw.usp_LoadFactWeather;
    EXEC dw.usp_LoadFactRaceControl;
    EXEC dw.usp_LoadFactAttendance;
END;
GO
/*
    TESTY / kontrola liczności po pełnym loadzie

    EXEC dw.usp_LoadAllFacts;

    SELECT 'FactSessionResult' AS TableName, COUNT(*) AS RecordCount
    FROM dw.FactSessionResult

    UNION ALL

    SELECT 'FactLap', COUNT(*)
    FROM dw.FactLap

    UNION ALL

    SELECT 'FactStint', COUNT(*)
    FROM dw.FactStint

    UNION ALL

    SELECT 'FactPitStop', COUNT(*)
    FROM dw.FactPitStop

    UNION ALL

    SELECT 'FactWeather', COUNT(*)
    FROM dw.FactWeather

    UNION ALL

    SELECT 'FactRaceControl', COUNT(*)
    FROM dw.FactRaceControl

    UNION ALL

    SELECT 'FactAttendance', COUNT(*)
    FROM dw.FactAttendance;

    -- Braki attendance są dozwolone i pozostają jako NULL.
    SELECT
        SUM(CASE WHEN WeekendAttendance IS NULL THEN 1 ELSE 0 END) AS MissingWeekendAttendance,
        SUM(CASE WHEN RaceDayAttendance IS NULL THEN 1 ELSE 0 END) AS MissingRaceDayAttendance
    FROM dw.FactAttendance;
*/
