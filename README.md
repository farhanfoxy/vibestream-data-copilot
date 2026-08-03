# VibeStream Data Copilot

> AI-powered analytics copilot for VibeStream, turning SQL Server data into secure, evidence-backed insights.

## Overview

VibeStream Data Copilot is an internal analytics assistant for a music-streaming platform. It helps admins and data analysts ask questions in natural language, explore streaming performance, and receive grounded answers with charts and metric evidence.

## Problem

Music-streaming data can be difficult to explore quickly. Teams often need technical SQL knowledge to answer questions such as:

- Which artists are growing the fastest?
- Which playlists have the highest completion rate?
- Which genres are most frequently skipped?
- What changed in streaming behaviour this month?

## Solution

VibeStream Data Copilot converts natural-language questions into safe, approved analytics queries. It returns:

- Clear data insights
- Interactive charts
- Metric definitions and data sources
- Suggested follow-up questions
- Audit logs for traceability

## MVP Features

- Natural-language analytics chat
- SQL Server reporting database
- Artist, song, playlist, and streaming-performance dashboard
- Secure read-only data access
- Evidence-backed answers and charts
- Copilot query history

## Planned Architecture

```mermaid
flowchart TD
    A["VibeStream Operational Database"] --> B["ETL and Data Quality Checks"]
    B --> C["Read-only Analytics Layer"]
    D["AI Copilot"] --> E["Secure Analytics API"]
    C --> E
    E --> F["Dashboard, Charts, and Evidence"]
