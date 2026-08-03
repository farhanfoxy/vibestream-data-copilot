/*
  VibeStream Data Copilot
  Migration: 001_add_copilot_event_model.sql
  Purpose: add streaming events, secure analytics views, audit logging,
           and least-privilege database roles.
*/

USE [VibeStreamDB];
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF SCHEMA_ID(N'analytics') IS NULL
    EXEC(N'CREATE SCHEMA [analytics] AUTHORIZATION [dbo];');
GO

/* 1. Streaming listening events */
IF OBJECT_ID(N'[vibestream].[ListeningEvent]', N'U') IS NULL
BEGIN
    CREATE TABLE [vibestream].[ListeningEvent] (
        [ListeningEventID] BIGINT IDENTITY(1,1) NOT NULL,
        [UserID] INT NOT NULL,
        [SongID] INT NOT NULL,
        [PlaylistID] INT NULL,
        [StartedAt] DATETIME2(0) NOT NULL
            CONSTRAINT [DF_ListeningEvent_StartedAt]
            DEFAULT (SYSUTCDATETIME()),
        [ListenedSeconds] INT NOT NULL,
        [Source] VARCHAR(20) NOT NULL
            CONSTRAINT [DF_ListeningEvent_Source]
            DEFAULT ('home'),

        CONSTRAINT [PK_ListeningEvent]
            PRIMARY KEY CLUSTERED ([ListeningEventID]),

        CONSTRAINT [FK_ListeningEvent_User]
            FOREIGN KEY ([UserID])
            REFERENCES [vibestream].[User] ([UserID]),

        CONSTRAINT [FK_ListeningEvent_Song]
            FOREIGN KEY ([SongID])
            REFERENCES [vibestream].[Song] ([SongID]),

        CONSTRAINT [FK_ListeningEvent_Playlist]
            FOREIGN KEY ([PlaylistID])
            REFERENCES [vibestream].[Playlist] ([PlaylistID]),

        CONSTRAINT [CK_ListeningEvent_ListenedSeconds]
            CHECK ([ListenedSeconds] >= 0 AND [ListenedSeconds] <= 7200),

        CONSTRAINT [CK_ListeningEvent_Source]
            CHECK ([Source] IN ('home', 'search', 'playlist', 'artist', 'library', 'other'))
    );
END;
GO

/* 2. Artist-follow events */
IF OBJECT_ID(N'[vibestream].[ArtistFollow]', N'U') IS NULL
BEGIN
    CREATE TABLE [vibestream].[ArtistFollow] (
        [UserID] INT NOT NULL,
        [ArtistID] INT NOT NULL,
        [FollowedAt] DATETIME2(0) NOT NULL
            CONSTRAINT [DF_ArtistFollow_FollowedAt]
            DEFAULT (SYSUTCDATETIME()),

        CONSTRAINT [PK_ArtistFollow]
            PRIMARY KEY CLUSTERED ([UserID], [ArtistID]),

        CONSTRAINT [FK_ArtistFollow_User]
            FOREIGN KEY ([UserID])
            REFERENCES [vibestream].[User] ([UserID]),

        CONSTRAINT [FK_ArtistFollow_Artist]
            FOREIGN KEY ([ArtistID])
            REFERENCES [vibestream].[Artist] ([ArtistID])
    );
END;
GO

/* 3. Audit trail for every Copilot request */
IF OBJECT_ID(N'[vibestream].[CopilotQueryAudit]', N'U') IS NULL
BEGIN
    CREATE TABLE [vibestream].[CopilotQueryAudit] (
        [CopilotQueryAuditID] BIGINT IDENTITY(1,1) NOT NULL,
        [RequestedAt] DATETIME2(0) NOT NULL
            CONSTRAINT [DF_CopilotQueryAudit_RequestedAt]
            DEFAULT (SYSUTCDATETIME()),
        [ActorRole] VARCHAR(30) NOT NULL
            CONSTRAINT [DF_CopilotQueryAudit_ActorRole]
            DEFAULT ('internal_analyst'),
        [QuestionHash] CHAR(64) NOT NULL,
        [ToolName] VARCHAR(100) NOT NULL,
        [ParametersJson] NVARCHAR(MAX) NULL,
        [ResultRowCount] INT NULL,
        [DurationMs] INT NULL,
        [Status] VARCHAR(20) NOT NULL
            CONSTRAINT [DF_CopilotQueryAudit_Status]
            DEFAULT ('Succeeded'),
        [ErrorMessage] NVARCHAR(1000) NULL,

        CONSTRAINT [PK_CopilotQueryAudit]
            PRIMARY KEY CLUSTERED ([CopilotQueryAuditID]),

        CONSTRAINT [CK_CopilotQueryAudit_ParametersJson]
            CHECK ([ParametersJson] IS NULL OR ISJSON([ParametersJson]) = 1),

        CONSTRAINT [CK_CopilotQueryAudit_ResultRowCount]
            CHECK ([ResultRowCount] IS NULL OR [ResultRowCount] >= 0),

        CONSTRAINT [CK_CopilotQueryAudit_DurationMs]
            CHECK ([DurationMs] IS NULL OR [DurationMs] >= 0),

        CONSTRAINT [CK_CopilotQueryAudit_Status]
            CHECK ([Status] IN ('Succeeded', 'Failed', 'Blocked'))
    );
END;
GO

/* 4. Performance indexes */
IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = N'IX_ListeningEvent_StartedAt_SongID'
      AND object_id = OBJECT_ID(N'[vibestream].[ListeningEvent]')
)
BEGIN
    CREATE INDEX [IX_ListeningEvent_StartedAt_SongID]
        ON [vibestream].[ListeningEvent] ([StartedAt], [SongID])
        INCLUDE ([UserID], [PlaylistID], [ListenedSeconds], [Source]);
END;
GO

IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = N'IX_ListeningEvent_PlaylistID_StartedAt'
      AND object_id = OBJECT_ID(N'[vibestream].[ListeningEvent]')
)
BEGIN
    CREATE INDEX [IX_ListeningEvent_PlaylistID_StartedAt]
        ON [vibestream].[ListeningEvent] ([PlaylistID], [StartedAt])
        WHERE [PlaylistID] IS NOT NULL;
END;
GO

IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = N'IX_ArtistFollow_ArtistID_FollowedAt'
      AND object_id = OBJECT_ID(N'[vibestream].[ArtistFollow]')
)
BEGIN
    CREATE INDEX [IX_ArtistFollow_ArtistID_FollowedAt]
        ON [vibestream].[ArtistFollow] ([ArtistID], [FollowedAt]);
END;
GO

IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = N'IX_CopilotQueryAudit_RequestedAt'
      AND object_id = OBJECT_ID(N'[vibestream].[CopilotQueryAudit]')
)
BEGIN
    CREATE INDEX [IX_CopilotQueryAudit_RequestedAt]
        ON [vibestream].[CopilotQueryAudit] ([RequestedAt]);
END;
GO

/* 5. Approved read-only analytics views: no email or raw user identity */

CREATE OR ALTER VIEW [analytics].[vw_CopilotArtistPerformance]
AS
SELECT
    CAST(le.[StartedAt] AS date) AS [EventDate],
    a.[ArtistID],
    a.[ArtistName],
    a.[Country],
    COUNT_BIG(*) AS [StreamCount],
    COUNT(DISTINCT le.[UserID]) AS [UniqueListeners],
    SUM(CASE
        WHEN le.[ListenedSeconds] >= CEILING(s.[Duration] * 0.90) THEN 1
        ELSE 0
    END) AS [CompletedStreams],
    SUM(CASE
        WHEN le.[ListenedSeconds] < 30
         AND le.[ListenedSeconds] < s.[Duration] THEN 1
        ELSE 0
    END) AS [SkippedStreams],
    SUM(CAST(le.[ListenedSeconds] AS BIGINT)) AS [TotalListenedSeconds],
    CAST(
        100.0 * SUM(CASE
            WHEN le.[ListenedSeconds] >= CEILING(s.[Duration] * 0.90) THEN 1
            ELSE 0
        END) / NULLIF(COUNT_BIG(*), 0)
        AS DECIMAL(5,2)
    ) AS [CompletionRatePct]
FROM [vibestream].[ListeningEvent] AS le
JOIN [vibestream].[Song] AS s
    ON s.[SongID] = le.[SongID]
JOIN [vibestream].[Artist] AS a
    ON a.[ArtistID] = s.[ArtistID]
GROUP BY
    CAST(le.[StartedAt] AS date),
    a.[ArtistID],
    a.[ArtistName],
    a.[Country];
GO

CREATE OR ALTER VIEW [analytics].[vw_CopilotPlaylistPerformance]
AS
SELECT
    CAST(le.[StartedAt] AS date) AS [EventDate],
    p.[PlaylistID],
    p.[PlaylistName],
    COUNT_BIG(*) AS [StreamCount],
    COUNT(DISTINCT le.[UserID]) AS [UniqueListeners],
    SUM(CASE
        WHEN le.[ListenedSeconds] >= CEILING(s.[Duration] * 0.90) THEN 1
        ELSE 0
    END) AS [CompletedStreams],
    SUM(CASE
        WHEN le.[ListenedSeconds] < 30
         AND le.[ListenedSeconds] < s.[Duration] THEN 1
        ELSE 0
    END) AS [SkippedStreams],
    CAST(
        100.0 * SUM(CASE
            WHEN le.[ListenedSeconds] >= CEILING(s.[Duration] * 0.90) THEN 1
            ELSE 0
        END) / NULLIF(COUNT_BIG(*), 0)
        AS DECIMAL(5,2)
    ) AS [CompletionRatePct]
FROM [vibestream].[ListeningEvent] AS le
JOIN [vibestream].[Playlist] AS p
    ON p.[PlaylistID] = le.[PlaylistID]
JOIN [vibestream].[Song] AS s
    ON s.[SongID] = le.[SongID]
WHERE le.[PlaylistID] IS NOT NULL
GROUP BY
    CAST(le.[StartedAt] AS date),
    p.[PlaylistID],
    p.[PlaylistName];
GO

CREATE OR ALTER VIEW [analytics].[vw_CopilotGenreEngagement]
AS
SELECT
    CAST(le.[StartedAt] AS date) AS [EventDate],
    s.[Genre],
    COUNT_BIG(*) AS [StreamCount],
    COUNT(DISTINCT le.[UserID]) AS [UniqueListeners],
    SUM(CAST(le.[ListenedSeconds] AS BIGINT)) AS [TotalListenedSeconds],
    CAST(
        100.0 * SUM(CASE
            WHEN le.[ListenedSeconds] >= CEILING(s.[Duration] * 0.90) THEN 1
            ELSE 0
        END) / NULLIF(COUNT_BIG(*), 0)
        AS DECIMAL(5,2)
    ) AS [CompletionRatePct]
FROM [vibestream].[ListeningEvent] AS le
JOIN [vibestream].[Song] AS s
    ON s.[SongID] = le.[SongID]
GROUP BY
    CAST(le.[StartedAt] AS date),
    s.[Genre];
GO

CREATE OR ALTER VIEW [analytics].[vw_CopilotDataFreshness]
AS
SELECT
    N'ListeningEvent' AS [DatasetName],
    MAX([StartedAt]) AS [LatestRecordAt],
    COUNT_BIG(*) AS [RecordCount]
FROM [vibestream].[ListeningEvent]

UNION ALL

SELECT
    N'ArtistFollow',
    MAX([FollowedAt]),
    COUNT_BIG(*)
FROM [vibestream].[ArtistFollow]

UNION ALL

SELECT
    N'CopilotQueryAudit',
    MAX([RequestedAt]),
    COUNT_BIG(*)
FROM [vibestream].[CopilotQueryAudit];
GO

/* 6. Least-privilege roles for the future Copilot application */
IF DATABASE_PRINCIPAL_ID(N'vibestream_copilot_reader') IS NULL
    CREATE ROLE [vibestream_copilot_reader];
GO

IF DATABASE_PRINCIPAL_ID(N'vibestream_copilot_auditor') IS NULL
    CREATE ROLE [vibestream_copilot_auditor];
GO

GRANT SELECT ON SCHEMA::[analytics]
    TO [vibestream_copilot_reader];

GRANT INSERT ON OBJECT::[vibestream].[CopilotQueryAudit]
    TO [vibestream_copilot_auditor];
GO
