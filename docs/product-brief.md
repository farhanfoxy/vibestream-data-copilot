# VibeStream Data Copilot — Product Brief

## Product Summary

VibeStream Data Copilot is an internal AI analytics assistant for a music-streaming platform. It helps VibeStream admins and data analysts explore streaming data through natural-language questions, verified metrics, charts, and clear evidence.

## Target User

- VibeStream admin
- Data analyst
- Product manager who needs music-streaming insights without manually writing SQL queries

## Problem Statement

Music-streaming data can be difficult and time-consuming to explore. Teams often need SQL knowledge to answer basic performance questions about artists, songs, playlists, and listener behaviour.

## Product Goal

Enable authorized users to ask approved analytics questions in natural language and receive trustworthy, evidence-backed answers from a secure read-only analytics database.

## MVP Scope

### Included

- Natural-language analytics questions
- Artist, song, genre, and playlist performance insights
- Charts for approved metrics
- Metric definitions and data-source evidence
- Query history and audit logs
- Synthetic streaming data for the public demo

### Not Included

- A consumer music-streaming app
- Music recommendation engine
- Direct database writes through AI
- Real user personal data
- Spotify or external music-platform integrations

## Core Questions

The MVP must be able to answer:

1. Which artists have the highest number of streams?
2. Which playlists have the highest completion rate?
3. Which genres have the highest skip rate?
4. How did streaming performance change between two periods?
5. What does a metric mean and when was it last updated?

## Key Metrics

- **Streams:** Total number of listening events.
- **Completion rate:** Percentage of listening events completed by a user.
- **Skip rate:** Percentage of listening events ended before 30 seconds.
- **Artist growth:** Change in artist streams between two selected periods.
- **Playlist performance:** Streams, completion rate, and skip rate from a playlist.

## Primary User Stories

- As a data analyst, I want to identify the fastest-growing artists.
- As an admin, I want to compare playlist performance.
- As an admin, I want to identify genres with high skip rates.
- As a user, I want every Copilot answer to display its metric source and update time.
- As a system owner, I want every Copilot request logged for traceability.

## Trust and Security Principles

- The Copilot only uses approved analytics tools.
- The Copilot has read-only database access.
- Sensitive user information is excluded from model prompts.
- Every request is recorded in an audit log.
- The public demo uses synthetic, non-personal data.

## Success Criteria

- At least five approved analytics questions can be answered correctly.
- Every answer includes a metric source and data freshness indicator.
- The Copilot cannot modify operational data.
- The public demo works with reproducible synthetic data.
