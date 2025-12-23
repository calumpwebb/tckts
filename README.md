# tckts

A minimal, plain-text ticket tracker for the command line. No databases, no JSON, no YAML - just human-readable text files.

## Features

- **Plain text storage** - Files are readable and editable by hand
- **Multi-project support** - Organize tickets by project prefix (e.g., BACKEND-1, UI-23)
- **Ticket types** - Categorize as bug, feature, task, or chore
- **Dependencies** - Define which tickets block others
- **Zero dependencies** - Built with Zig stdlib only

## Installation

Requires [Zig 0.15](https://ziglang.org/download/) or later.

```bash
# Build
zig build

# Install to zig-out/bin/
zig build

# Or build optimized release
zig build -Doptimize=ReleaseFast
```

The binary will be at `zig-out/bin/tckts`.

## Quick Start

```bash
# Initialize a new project
tckts init MYPROJECT

# Add some tickets
tckts add MYPROJECT feature "User authentication" "Implement login flow"
tckts add MYPROJECT bug "Fix crash on startup" ""
tckts add MYPROJECT task "Write tests" "" --depends MYPROJECT-1

# List tickets
tckts list MYPROJECT

# Show ticket details
tckts show MYPROJECT-1

# Complete a ticket
tckts done MYPROJECT-2

# Remove a ticket
tckts rm MYPROJECT-3
```

## Commands

### init

Initialize a new project with a prefix.

```bash
tckts init <PREFIX>
```

Creates `.tckts/<PREFIX>.tckts` file.

### add

Create a new ticket.

```bash
tckts add <PREFIX> <type> <title> <description> [options]
```

**Types:** `bug`, `feature`, `task`, `chore`

**Options:**
- `--depends <ID>` - Add dependency (can be repeated)
- `--priority <low|medium|high>` - Set priority

**Examples:**

```bash
# Simple ticket
tckts add API feature "Add pagination" "Support page and limit params"

# Bug with high priority
tckts add API bug "Memory leak" "In connection pool" --priority high

# Task that depends on another ticket
tckts add API task "Update docs" "" --depends API-1

# Feature with multiple dependencies
tckts add API feature "New endpoint" "" --depends API-1 --depends API-2
```

### list

List tickets in a project.

```bash
tckts list <PREFIX> [--all | --done]
```

By default shows only pending tickets. Use `--all` to show all tickets or `--done` to show only completed tickets.

### show

Display full details of a ticket.

```bash
tckts show <TICKET-ID>
```

Example:

```bash
tckts show API-1
```

### done

Mark a ticket as completed.

```bash
tckts done <TICKET-ID>
```

If the ticket has incomplete dependencies, you'll see a warning listing the blocking tickets.

### rm

Remove a ticket from a project.

```bash
tckts rm <TICKET-ID>
```

Removing a ticket also removes it from other tickets' dependency lists.

### projects

List all projects.

```bash
tckts projects
```

### help

Show usage information.

```bash
tckts help
```

## File Format

Tickets are stored in `.tckts/<PREFIX>.tckts` files using a simple block format:

```
# tckts | prefix: MYPROJECT | version: 1

--- MYPROJECT-1
type: feature
status: pending
title: User authentication
created: 2024-12-23
priority: high

Implement OAuth2 login flow with support for
Google and GitHub providers.
---

--- MYPROJECT-2
type: bug
status: done
title: Fix crash on startup
created: 2024-12-23
depends: MYPROJECT-1
---
```

### Fields

| Field | Required | Description |
|-------|----------|-------------|
| type | Yes | bug, feature, task, or chore |
| status | Yes | pending or done |
| title | Yes | Short summary |
| created | Yes | Date in YYYY-MM-DD format |
| depends | No | Comma-separated list of ticket IDs |
| priority | No | low, medium, or high |
| description | No | Free-form text after blank line |

## Dependencies

Tickets can depend on other tickets. When you try to complete a ticket with incomplete dependencies, you'll see which tickets are blocking it:

```bash
$ tckts done API-3
Cannot complete API-3: blocked by incomplete dependencies:
  - API-1
  - API-2
```

Complete the dependencies first, then mark the ticket as done.

## Development

```bash
# Run tests
zig build test

# Build and run
zig build run -- help

# Build with arguments
zig build run -- add TEST feature "Test" ""
```

## License

MIT
