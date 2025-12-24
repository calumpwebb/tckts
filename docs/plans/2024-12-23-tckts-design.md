# tckts - CLI Ticket Tracker Design

## Overview

`tckts` is a plain-text CLI ticket tracker designed for developers. Tickets are stored in human-readable files that live in the repository, making them easy to read by both humans and LLMs working on the codebase.

## Design Goals

1. **Human-readable storage** - No JSON/YAML/TOML, just plain text you can read and edit
2. **LLM-friendly** - Easy for AI assistants to parse and understand context
3. **Multi-project support** - One repo can have multiple independent ticket lists with prefixes
4. **Dependency tracking** - Tickets can depend on other tickets
5. **Zero dependencies** - Zig stdlib only
6. **Simple UX** - Intuitive commands, helpful errors

## File Format

### Location

All ticket files are stored in `.tckts/` at the repository root:
```
.tckts/
  MAIN.tckts       # Default project with prefix MAIN
  BACKEND.tckts    # Project with prefix BACKEND
  UI.tckts         # Project with prefix UI
```

The filename IS the prefix (uppercase).

### Format Specification

```
# tckts | prefix: <PREFIX> | version: 1

--- <PREFIX>-<number>
status: pending|done
title: <single line title>
created: <YYYY-MM-DD>
depends: <PREFIX>-<n>, <PREFIX>-<n>
priority: low|medium|high

<description - multiple lines until next --- or EOF>
---
```

**Header Line:**
- Starts with `# tckts`
- Contains `prefix: <PREFIX>` - the ticket prefix (e.g., BACKEND)
- Contains `version: 1` - format version for future compatibility

**Ticket Block:**
- Starts with `--- <ID>` where ID is `PREFIX-NUMBER`
- Metadata lines in `key: value` format
- Empty line separates metadata from description
- Description continues until next `---` or end of file

**Required Fields:**
- `status` - `pending` or `done`
- `title` - single line ticket title
- `created` - creation date

**Optional Fields:**
- `depends` - comma-separated ticket IDs
- `priority` - low, medium, or high

**Example File:**
```
# tckts | prefix: BACKEND | version: 1

--- BACKEND-1
status: done
title: Set up project structure
created: 2024-12-23

Initialize the Zig project with proper directory layout
and build configuration.
---

--- BACKEND-2
status: done
title: Implement user model
created: 2024-12-23
depends: BACKEND-1

Create the User struct with fields:
- id: unique identifier
- email: validated email string
- created_at: timestamp
---

--- BACKEND-3
status: pending
title: Add authentication
created: 2024-12-23
depends: BACKEND-2
priority: high

Implement JWT-based authentication:
1. Login endpoint
2. Token validation middleware
3. Refresh token flow
---

--- BACKEND-4
status: pending
title: Write API tests
created: 2024-12-23
depends: BACKEND-2, BACKEND-3

Cover all endpoints with integration tests.
---
```

**Parsing Rules:**
- Lines starting with `#` (other than header) are comments, ignored
- Empty lines within description are preserved
- Whitespace around `:` in metadata is trimmed
- Unknown metadata keys are preserved but ignored

## CLI Interface

### Commands

```
tckts init <PREFIX>                 Initialize a new project with given prefix
tckts add <title> [options]         Add a new ticket
tckts list [PREFIX] [options]       List tickets
tckts show <ID>                     Show ticket details
tckts done <ID>                     Mark ticket as complete
tckts rm <ID>                       Remove a ticket
tckts projects                      List all projects/prefixes
tckts help [command]                Show help
```

### Global Options

```
-p, --project <PREFIX>    Specify project prefix (default: MAIN)
-h, --help                Show help for command
```

### Command-Specific Options

**add:**
```
-d, --depends <IDs>       Comma-separated dependency IDs (e.g., BACKEND-1,BACKEND-2)
-m, --description <text>  Ticket description (or prompted interactively)
--priority <level>        Set priority (low, medium, high)
```

**list:**
```
-a, --all                    Show all tickets (including completed)
-s, --status <STATUS>        Filter by status (pending, in-progress, done)
--blocked                    Show only blocked tickets
```

### Exit Codes

- `0` - Success
- `1` - User error (invalid input, ticket not found, etc.)
- `2` - System error (file I/O, etc.)

## Dependency System

### Rules

1. A ticket cannot be marked complete if any of its dependencies are incomplete
2. Dependencies can cross projects (BACKEND-1 can depend on INFRA-3)
3. Circular dependencies are rejected at add time
4. Deleting a ticket removes it from all dependency lists
5. Dependencies must reference existing ticket IDs

### Display

When listing tickets, blocked tickets are marked:
```
[ ] BACKEND-3 | Add authentication [BLOCKED by: BACKEND-2]
```

## Error Handling

**User-friendly error messages:**
```
Error: Cannot complete BACKEND-3 - depends on incomplete tickets: BACKEND-2
Error: Ticket BACKEND-99 not found
Error: Project 'FRONTEND' not initialized. Run: tckts init FRONTEND
Error: Circular dependency detected: BACKEND-3 -> BACKEND-4 -> BACKEND-3
```

## Testing Strategy

### Unit Tests
- File format parsing/serialization
- Dependency cycle detection
- Ticket state transitions
- Cross-project dependency resolution

### Integration Tests
- Full CLI command execution
- Multi-project scenarios
- Error conditions

### End-to-End Test
A realistic workflow:
1. Init project with prefix
2. Add multiple tickets with dependencies
3. Try to complete blocked ticket (should fail)
4. Complete dependencies in order
5. Show ticket details
6. List and verify state
7. Delete ticket and verify dependency cleanup

## Future Considerations (Not Implemented)

These are noted for potential future versions but explicitly NOT in scope:
- Due dates
- Tags/labels
- Assignees
- Import/export
- Sync between repos
