# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Test Commands

```bash
zig build              # Build the binary (output: zig-out/bin/tckts)
zig build test         # Run all tests
zig build run          # Build and run
zig build run -- <args>  # Run with arguments (e.g., -- add "My ticket")
zig build -Doptimize=ReleaseFast  # Build optimized release
```

## Architecture

**tckts** is a plain-text ticket tracker CLI written in Zig with zero external dependencies.

### Three-Layer Design

1. **Core Library** (`src/root.zig`) - Data structures, file I/O, project/ticket operations
   - `Ticket`, `TicketId`, `Project` structs
   - `parseFile()` / `serializeProject()` for the `.tckts` file format
   - Validation (title max 280 chars, description max 64KB, max 10K tickets)

2. **CLI Layer** (`src/cli/mod.zig`) - Command parsing, I/O helpers, dispatch utilities
   - Command enum with aliases (e.g., `ls` → `list`, `complete` → `done`)

3. **Command Handlers** (`src/cli/commands/*.zig`) - One file per command
   - Each command has `run(allocator, args, writer)` signature
   - Commands dispatch via `src/cli/commands/mod.zig`

4. **Entry Point** (`src/main.zig`) - Argument parsing, error handling, exit codes

### Data Storage

Projects stored in `.tckts/PREFIX.tckts` files using a human-readable format:
```
# tckts | prefix: TODO | version: 1

---
id: TODO-1
type: task
status: pending
title: Example ticket
created_at: 2024-12-23T10:30:45Z
priority: medium
depends: OTHER-1
---
```

## Zig Code Conventions

Follow the rules in `.claude/rules/zig-files.md`. Key points:

- **File structure order**: imports → `// --- constants ---` → `// --- types ---` → `// --- tests ---`
- **Imports order**: std first, then packages, then local
- **Naming**: `PascalCase` types, `snake_case` functions/constants
- **Numeric constants require unit suffixes**: `_ms`, `_ns`, `_bytes`, `_ticks`
- **Memory**: `errdefer` immediately after allocation, all resource structs need `deinit()`
- **Errors**: Custom error sets per module, no `anyerror`
- **Tests**: Named `test "TypeName: description"`, use `std.testing.allocator`
