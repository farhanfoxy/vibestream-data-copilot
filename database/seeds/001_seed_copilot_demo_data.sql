/*
  VibeStream Data Copilot
  Seed: 001_seed_copilot_demo_data.sql

  Safe behavior:
  - Never deletes existing records
  - Only inserts demo events when the target tables are empty
  - Does not create or expose personal data
*/

USE [VibeStreamDB];
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF OBJECT_ID(N'[vibestream].[ListeningEvent]', N'U') IS NULL
    THROW 51000, 'ListeningEvent is missing. Run the Copilot event-model migration first.', 1;

IF OBJECT_ID(N'[vibestream].[ArtistFollow]', N'U') IS NULL
    THROW 51001, 'ArtistFollow is missing. Run the Copilot event-model migration first.', 1;

IF NOT EXISTS (SELECT 1 FROM [vibestream].[User])
   OR NOT EXISTS (SELECT 1 FROM [vibestream].[Artist])
   OR NOT EXISTS (SELECT 1 FROM [vibestream].[Song])
   OR NOT EXISTS (SELECT 1 FROM [vibestream].[Playlist])
BEGIN
    THROW 51002, 'Users, artists, songs, and playlists must contain base data before seeding.', 1;
END;
GO

BEGIN TRY
    BEGIN TRANSACTION;

    /* 3,000 synthetic streaming events across roughly the last 94 days */
    IF NOT EXISTS (SELECT 1 FROM [vibestream].[ListeningEvent])
    BEGIN
        ;WITH
        [Numbers] AS (
            SELECT TOP (3000)
                ROW_NUMBER() OVER (
                    ORDER BY a.[object_id], b.[object_id]
                ) AS [EventNo]
            FROM sys.all_objects AS a
            CROSS JOIN sys.all_objects AS b
        ),
        [Users] AS (
            SELECT
                [UserID],
                ROW_NUMBER() OVER (ORDER BY [UserID]) AS [Seq],
                COUNT(*) OVER () AS [TotalRows]
            FROM [vibestream].[User]
        ),
        [Songs] AS (
            SELECT
                [SongID],
                [Duration],
                ROW_NUMBER() OVER (ORDER BY [SongID]) AS [Seq],
                COUNT(*) OVER () AS [TotalRows]
            FROM [vibestream].[Song]
        ),
        [Playlists] AS (
            SELECT
                [PlaylistID],
                ROW_NUMBER() OVER (ORDER BY [PlaylistID]) AS [Seq],
                COUNT(*) OVER () AS [TotalRows]
            FROM [vibestream].[Playlist]
        )
        INSERT INTO [vibestream].[ListeningEvent] (
            [UserID],
            [SongID],
            [PlaylistID],
            [StartedAt],
            [ListenedSeconds],
            [Source]
        )
        SELECT
            u.[UserID],
            s.[SongID],
            CASE
                WHEN n.[EventNo] % 10 < 7 THEN p.[PlaylistID]
                ELSE NULL
            END,
            DATEADD(
                MINUTE,
                -CONVERT(INT, (n.[EventNo] * 45) + (n.[EventNo] % 17)),
                SYSUTCDATETIME()
            ),
            CASE
                /* 18% skips */
                WHEN n.[EventNo] % 100 < 18 THEN
                    CASE
                        WHEN s.[Duration] <= 30 THEN 0
                        ELSE 5 + CONVERT(INT, (n.[EventNo] * 11) % 25)
                    END

                /* 62% completed streams */
                WHEN n.[EventNo] % 100 < 80 THEN
                    CONVERT(INT, CEILING(s.[Duration] * 0.95))

                /* 20% partial listens */
                ELSE
                    CASE
                        WHEN s.[Duration] <= 100
                            THEN CONVERT(INT, CEILING(s.[Duration] * 0.60))
                        ELSE CONVERT(
                            INT,
                            FLOOR(
                                s.[Duration] *
                                (0.45 + ((n.[EventNo] % 20) / 100.0))
                            )
                        )
                    END
            END,
            CASE
                WHEN n.[EventNo] % 10 < 7 THEN 'playlist'
                WHEN n.[EventNo] % 10 = 7 THEN 'home'
                WHEN n.[EventNo] % 10 = 8 THEN 'search'
                ELSE 'artist'
            END
        FROM [Numbers] AS n
        JOIN [Users] AS u
            ON u.[Seq] = ((n.[EventNo] - 1) % u.[TotalRows]) + 1
        JOIN [Songs] AS s
            ON s.[Seq] =
                CASE
                    /* Makes the first ranked song/artist visibly trend upward recently */
                    WHEN n.[EventNo] <= 600 AND n.[EventNo] % 3 <> 0 THEN 1
                    ELSE ((n.[EventNo] * 7 - 1) % s.[TotalRows]) + 1
                END
        JOIN [Playlists] AS p
            ON p.[Seq] = ((n.[EventNo] * 11 - 1) % p.[TotalRows]) + 1;
    END
    ELSE
        PRINT 'ListeningEvent already contains data; demo events were not inserted.';

    /* Synthetic artist follows */
    IF NOT EXISTS (SELECT 1 FROM [vibestream].[ArtistFollow])
    BEGIN
        ;WITH
        [Users] AS (
            SELECT
                [UserID],
                ROW_NUMBER() OVER (ORDER BY [UserID]) AS [Seq]
            FROM [vibestream].[User]
        ),
        [Artists] AS (
            SELECT
                [ArtistID],
                ROW_NUMBER() OVER (ORDER BY [ArtistID]) AS [Seq]
            FROM [vibestream].[Artist]
        )
        INSERT INTO [vibestream].[ArtistFollow] (
            [UserID],
            [ArtistID],
            [FollowedAt]
        )
        SELECT
            u.[UserID],
            a.[ArtistID],
            DATEADD(
                DAY,
                -CONVERT(INT, ((u.[Seq] * 19) + (a.[Seq] * 7)) % 90),
                SYSUTCDATETIME()
            )
        FROM [Users] AS u
        CROSS JOIN [Artists] AS a
        WHERE ((u.[Seq] * 7) + (a.[Seq] * 3)) % 5 <> 0;
    END
    ELSE
        PRINT 'ArtistFollow already contains data; demo follows were not inserted.';

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;
GO

/* Validation: these views must return non-zero analytics results */
SELECT
    [DatasetName],
    [LatestRecordAt],
    [RecordCount]
FROM [analytics].[vw_CopilotDataFreshness];

SELECT TOP (10)
    [EventDate],
    [ArtistName],
    [StreamCount],
    [UniqueListeners],
    [CompletionRatePct]
FROM [analytics].[vw_CopilotArtistPerformance]
ORDER BY [EventDate] DESC, [StreamCount] DESC;

SELECT TOP (10)
    [EventDate],
    [PlaylistName],
    [StreamCount],
    [UniqueListeners],
    [CompletionRatePct]
FROM [analytics].[vw_CopilotPlaylistPerformance]
ORDER BY [EventDate] DESC, [StreamCount] DESC;

SELECT TOP (10)
    [EventDate],
    [Genre],
    [StreamCount],
    [UniqueListeners],
    [CompletionRatePct]
FROM [analytics].[vw_CopilotGenreEngagement]
ORDER BY [EventDate] DESC, [StreamCount] DESC;
GO
/* Validation: inspect approved analytics views without depending on aliases */

SELECT
    N'ListeningEvent' AS [DatasetName],
    COUNT_BIG(*) AS [RecordCount],
    MAX([StartedAt]) AS [LatestRecordAt]
FROM [vibestream].[ListeningEvent]

UNION ALL

SELECT
    N'ArtistFollow',
    COUNT_BIG(*),
    MAX([FollowedAt])
FROM [vibestream].[ArtistFollow]

UNION ALL

SELECT
    N'CopilotQueryAudit',
    COUNT_BIG(*),
    MAX([RequestedAt])
FROM [vibestream].[CopilotQueryAudit];
GO

SELECT TOP (10) *
FROM [analytics].[vw_CopilotArtistPerformance];

SELECT TOP (10) *
FROM [analytics].[vw_CopilotPlaylistPerformance];

SELECT TOP (10) *
FROM [analytics].[vw_CopilotGenreEngagement];

SELECT *
FROM [analytics].[vw_CopilotDataFreshness];
GO
