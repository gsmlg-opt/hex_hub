# Data Model: Public MCP API for Package Information

**Date**: 2026-01-19
**Feature**: 008-mcp-public-api

## Overview

This feature does not introduce new data entities. It exposes existing package data through the MCP interface. This document describes the data structures used in MCP tool inputs and outputs.

---

## Existing Entities (Read-Only Access via MCP)

### Package

| Field | Type | Description |
|-------|------|-------------|
| name | string | Unique package name |
| repository | string | Repository name (default: "hexpm") |
| description | string | Package description |
| licenses | list(string) | License identifiers |
| links | map | External links (GitHub, homepage, etc.) |
| downloads | integer | Total download count |
| inserted_at | datetime | Creation timestamp |
| updated_at | datetime | Last update timestamp |

**Source**: Mnesia `:packages` table

### Release

| Field | Type | Description |
|-------|------|-------------|
| package_name | string | Parent package name |
| version | string | Semantic version |
| has_docs | boolean | Documentation uploaded |
| requirements | map | Dependency requirements |
| metadata | map | Build metadata (Elixir/OTP versions) |
| retirement | map | Retirement info (if retired) |
| inserted_at | datetime | Publication timestamp |

**Source**: Mnesia `:package_releases` table

### Repository

| Field | Type | Description |
|-------|------|-------------|
| name | string | Repository identifier |
| url | string | Repository URL |
| public | boolean | Public visibility |

**Source**: Mnesia `:repositories` table

---

## MCP Tool Schemas

### Input Schemas

#### search_packages
```json
{
  "type": "object",
  "properties": {
    "query": {
      "type": "string",
      "description": "Search query"
    },
    "limit": {
      "type": "integer",
      "description": "Maximum results (default: 20)"
    },
    "filters": {
      "type": "object",
      "description": "Optional filters"
    }
  },
  "required": ["query"]
}
```

#### get_package
```json
{
  "type": "object",
  "properties": {
    "name": {
      "type": "string",
      "description": "Package name"
    },
    "repository": {
      "type": "string",
      "description": "Repository name (optional)"
    }
  },
  "required": ["name"]
}
```

#### list_packages
```json
{
  "type": "object",
  "properties": {
    "page": {
      "type": "integer",
      "description": "Page number"
    },
    "per_page": {
      "type": "integer",
      "description": "Items per page"
    },
    "sort": {
      "type": "string",
      "description": "Sort field (name, downloads, updated_at)"
    },
    "order": {
      "type": "string",
      "description": "Sort order (asc, desc)"
    }
  }
}
```

#### get_package_metadata
```json
{
  "type": "object",
  "properties": {
    "name": {
      "type": "string",
      "description": "Package name"
    },
    "version": {
      "type": "string",
      "description": "Specific version (optional, defaults to latest)"
    }
  },
  "required": ["name"]
}
```

### Output Schemas

#### Package Search Result
```json
{
  "packages": [
    {
      "name": "phoenix",
      "repository": "hexpm",
      "description": "Web framework for Elixir",
      "licenses": ["MIT"],
      "links": {"GitHub": "https://github.com/phoenixframework/phoenix"},
      "downloads": 1000000,
      "url": "/api/packages/phoenix",
      "html_url": "/packages/phoenix"
    }
  ],
  "total": 150,
  "query": "phoenix",
  "filters": {}
}
```

#### Package Detail Result
```json
{
  "package": {
    "name": "phoenix",
    "repository": "hexpm",
    "description": "Web framework for Elixir",
    "licenses": ["MIT"],
    "links": {},
    "downloads": 1000000,
    "inserted_at": "2014-08-01T00:00:00Z",
    "updated_at": "2024-01-15T00:00:00Z",
    "url": "/api/packages/phoenix",
    "html_url": "/packages/phoenix"
  },
  "releases": [
    {
      "version": "1.7.12",
      "has_docs": true,
      "inserted_at": "2024-01-15T00:00:00Z",
      "retirement_info": null,
      "url": "/api/packages/phoenix/releases/1.7.12",
      "html_url": "/packages/phoenix/releases/1.7.12"
    }
  ],
  "total_releases": 100,
  "latest_version": "1.7.12",
  "repository": {
    "name": "hexpm",
    "url": "https://hex.pm",
    "public": true
  }
}
```

---

## Rate Limit State

### rate_limit (Existing Mnesia Table)

| Field | Type | Description |
|-------|------|-------------|
| key | string | Rate limit key (e.g., "mcp:ip:192.168.1.1") |
| type | atom | Limit type (:mcp, :ip, :user) |
| id | string | Identifier |
| count | integer | Request count in window |
| start | integer | Window start timestamp |
| updated | datetime | Last update time |

**Usage**: MCP rate limiting uses key prefix `mcp:ip:{ip_address}` to track requests.

---

## No Schema Changes Required

This feature:
- Uses existing Mnesia tables for package data
- Uses existing rate limit infrastructure
- Does not introduce new persistent entities
