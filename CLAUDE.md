# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Multiple Sessions

If you see uncommitted changes, weird reverts, or unexpected edits - it's probably another AI working in another session. Don't be alarmed. Ask Calum for help if you can't figure it out.

## First Message Rule

**On the FIRST message of every session—even a single character, empty message, or greeting—you MUST check your available skills using the Skill tool and you MUST use the `session-start` skill.** This is non-negotiable. Do not respond, ask questions, or take any action until you have checked for and used applicable skills.

## Build & Test Commands

```bash
zig build              # Build the binary (output: zig-out/bin/tckts)
zig build test         # Run unit tests
zig build e2e          # Run e2e tests (requires binary built first)
zig build run          # Build and run
zig build run -- <args>  # Run with arguments (e.g., -- add "My ticket")
zig build -Doptimize=ReleaseFast  # Build optimized release
zig build -Doptimize=ReleaseFast -p /usr/local  # Build and install to /usr/local/bin
```

**IMPORTANT:** Bump the version in `src/main.zig` when completing features or releases.

## Architecture

**tckts** is a plain-text ticket tracker CLI written in Zig with zero external dependencies.

### Three-Layer Design

1. **Core Library** (`src/root.zig`) - Data structures, file I/O, project/ticket operations

   - `Ticket`, `TicketId`, `Project` structs
   - `parseFile()` / `serializeProject()` for JSONL storage
   - Validation (title max 280 chars, description max 64KB, max 10K tickets)

2. **CLI Layer** (`src/cli/mod.zig`) - Command parsing, I/O helpers, dispatch utilities

   - Command enum with aliases (e.g., `ls` → `list`, `complete` → `done`)

3. **Command Handlers** (`src/cli/commands/*.zig`) - One file per command

   - Each command has `run(allocator, args, writer)` signature
   - Commands dispatch via `src/cli/commands/mod.zig`

4. **Entry Point** (`src/main.zig`) - Argument parsing, error handling, exit codes

### Data Storage

Projects stored in `.tckts/PREFIX.tckts` files using [JSON Lines](https://jsonlines.org/) format:

```jsonl
{
  "id": "TODO-1",
  "type": "task",
  "status": "pending",
  "title": "Example ticket",
  "created_at": "2024-12-23T10:30:45Z",
  "priority": "medium",
  "depends": [
    "OTHER-1"
  ]
}
```

Project metadata stored in `.tckts/config.json`:

```json
{ "default_project": "TODO", "projects": { "TODO": { "version": 1 } } }
```

## ZLS MCP Server

**Use the ZLS MCP tools for all Zig-related work:**

- `mcp__zls__definition` - Find symbol definitions
- `mcp__zls__references` - Find all usages of a symbol
- `mcp__zls__hover` - Get type info and docs
- `mcp__zls__diagnostics` - Get compiler errors for a file
- `mcp__zls__rename_symbol` - Rename across codebase
- `mcp__zls__edit_file` - Apply edits with LSP awareness

Prefer these over manual grep/read when navigating Zig code.

## Zig Code Conventions

Follow the rules in `.claude/rules/zig-files.md`. Key points:

- **File structure order**: imports → `// --- constants ---` → `// --- types ---` → `// --- tests ---`
- **Imports order**: std first, then packages, then local
- **Naming**: `PascalCase` types, `snake_case` functions/constants
- **Numeric constants require unit suffixes**: `_ms`, `_ns`, `_bytes`, `_ticks`
- **Memory**: `errdefer` immediately after allocation, all resource structs need `deinit()`
- **Errors**: Custom error sets per module, no `anyerror`
- **Tests**: Named `test "TypeName: description"`, use `std.testing.allocator`
