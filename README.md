# tckts

A minimal, plain-text ticket tracker for the command line. No databases, no servers - just JSONL files in your repo.

## Features

- **Plain text storage** - Files are readable and editable by hand
- **Multi-project support** - Organize tickets by project prefix (e.g., BACKEND-1, UI-23)
- **Ticket types** - Categorize as bug, feature, task, chore, or epic
- **Status workflow** - pending → in_progress → done with timestamps
- **Dependencies** - Define which tickets block others
- **Zero dependencies** - Built with Zig stdlib only

## Installation

### Quick Install (Recommended)

```bash
curl -fsSL https://raw.githubusercontent.com/calumpwebb/tckts/main/install.sh | sh
```

This downloads the latest release binary for your platform and installs it to `~/.local/bin`.

To update, run the same command again.

### Manual Download

Download the binary for your platform from [GitHub Releases](https://github.com/calumpwebb/tckts/releases):

| Platform | Binary |
|----------|--------|
| macOS (Apple Silicon) | `tckts-macos-aarch64` |
| macOS (Intel) | `tckts-macos-x86_64` |
| Linux (x86_64) | `tckts-linux-x86_64` |
| Linux (ARM64) | `tckts-linux-aarch64` |
| Windows | `tckts-windows-x86_64.exe` |

Then make it executable and move to your PATH:

```bash
chmod +x tckts-*
mv tckts-* ~/.local/bin/tckts
```

### Build from Source

Requires [Zig 0.15](https://ziglang.org/download/) or later.

```bash
zig build -Doptimize=ReleaseFast
```

The binary will be at `zig-out/bin/tckts`.

## Quick Start

```bash
# Initialize a new project
tckts init MYPROJECT

# Add some tickets (note: -p is required)
tckts add "User authentication" -p MYPROJECT -t feature
tckts add "Fix crash on startup" -p MYPROJECT -t bug
tckts add "Write tests" -p MYPROJECT -t task -d MYPROJECT-1

# List tickets
tckts list MYPROJECT

# Show ticket details
tckts show MYPROJECT-1

# Start working on a ticket
tckts start MYPROJECT-1

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

Creates `.tckts/<PREFIX>.jsonl` file.

### add

Create a new ticket.

```bash
tckts add <title> -p <PREFIX> [options]
```

**Options:**
- `-p, --project <PREFIX>` - Project prefix (required)
- `-t, --type <TYPE>` - Ticket type: bug, feature, task, chore, epic
- `-d, --depends <IDs>` - Comma-separated dependency IDs
- `-m, --message <DESC>` - Ticket description
- `--priority <low|medium|high>` - Set priority

**Examples:**

```bash
# Simple ticket
tckts add "Add pagination" -p API -t feature -m "Support page and limit params"

# Bug with high priority
tckts add "Memory leak" -p API -t bug --priority high

# Task that depends on another ticket
tckts add "Update docs" -p API -t task -d API-1

# Epic with multiple dependencies
tckts add "New module" -p API -t epic -d "API-1, API-2"
```

### list

List tickets in a project.

```bash
tckts list [PREFIX] [--all] [--status <STATUS>] [--blocked]
```

By default shows only pending tickets. Use `--all` to show all tickets, or `--status` to filter by status (pending, in_progress, done).

### show

Display full details of a ticket.

```bash
tckts show <TICKET-ID>
```

### start

Mark a ticket as in_progress.

```bash
tckts start <TICKET-ID>
```

Records the `started_at` timestamp.

### done

Mark a ticket as completed.

```bash
tckts done <TICKET-ID>
```

Records the `completed_at` timestamp. If the ticket has incomplete dependencies, you'll see which tickets are blocking it.

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

### quickstart

Show LLM onboarding guide with workflow instructions.

```bash
tckts quickstart
```

Outputs a comprehensive guide for LLMs on how to use tckts, including workflow best practices and command examples. Useful for onboarding AI assistants to your project.

### help

Show usage information.

```bash
tckts help
```

## File Format

Tickets are stored in `.tckts/<PREFIX>.jsonl` files using [JSON Lines](https://jsonlines.org/) format - one JSON object per line:

```jsonl
{"prefix":"MYPROJECT","version":1}
{"id":"MYPROJECT-1","type":"feature","status":"in_progress","title":"User authentication","created_at":"2024-12-23T10:30:45Z","started_at":"2024-12-23T14:00:00Z","priority":"high","description":"Implement OAuth2 login flow with support for Google and GitHub providers."}
{"id":"MYPROJECT-2","type":"bug","status":"done","title":"Fix crash on startup","created_at":"2024-12-23T10:30:45Z","completed_at":"2024-12-23T16:00:00Z","depends":["MYPROJECT-1"]}
```

The first line is the project header. Each subsequent line is a ticket.

### Fields

| Field | Required | Description |
|-------|----------|-------------|
| id | Yes | Ticket ID (PREFIX-NUMBER) |
| type | Yes | bug, feature, task, chore, or epic |
| status | Yes | pending, in_progress, or done |
| title | Yes | Short summary (max 280 chars) |
| created_at | Yes | UTC timestamp (ISO 8601) |
| started_at | No | When moved to in_progress |
| completed_at | No | When marked as done |
| depends | No | Array of ticket IDs |
| priority | No | low, medium, or high |
| description | No | Free-form text description |

### Limits

| Limit | Value |
|-------|-------|
| Title length | 280 characters |
| Description length | 64 KB |
| Tickets per project | 10,000 |
| Dependencies per ticket | 100 |
| Prefix length | 32 characters |

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
zig build run -- add "Test" -p MYPROJECT -t feature
```

## License

MIT
