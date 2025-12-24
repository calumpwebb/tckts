# Centralized Argument Parser Design

**Epic:** TCKTS-71
**Date:** 2024-12-24
**Status:** Draft

## Problem

The current CLI argument parsing has several issues:

1. **Titles starting with `-` fail silently** - `tckts add "-h fix"` fails because the parser treats `-h` as a flag
2. **No `-h`/`--help` in subcommands** - `tckts list -h` does nothing
3. **Unknown flags silently ignored** - `tckts add --foo "title"` doesn't error
4. **Duplicated help text** - `main.zig:printHelp()` duplicates info that should live with commands
5. **Duplicated patterns** - Default project resolution, ticket ID parsing repeated across commands
6. **Rigid argument order** - Manual `while (args.next())` loops in every command

## Solution

A centralized `ArgParser` with:

- **CommandMeta struct** - Single source of truth for command help
- **Builder pattern** - Define flags, parse args, get values
- **Automatic `-h`/`--help`** - Every command gets help for free
- **`--` separator support** - Standard POSIX convention for positional args
- **Unknown flag errors** - Fail fast on typos
- **GlobalArgs placeholder** - Future support for `--json`, `--quiet`, etc.

## Design

### CommandMeta Struct

Each command exports its metadata:

```zig
// src/cli/args.zig

pub const OptionMeta = struct {
    short: ?[]const u8 = null,    // e.g., "-p"
    long: ?[]const u8 = null,     // e.g., "--project"
    arg: ?[]const u8 = null,      // e.g., "<PREFIX>" (null = boolean flag)
    desc: []const u8,             // e.g., "Project prefix"
};

pub const CommandMeta = struct {
    name: []const u8,             // e.g., "add"
    usage: []const u8,            // e.g., "add <title> [options]"
    short: []const u8,            // e.g., "Add a new ticket"
    options: []const OptionMeta,
    examples: []const []const u8,
};
```

### ArgParser

```zig
// src/cli/args.zig

pub const ArgParser = struct {
    allocator: Allocator,
    args: *ArgIterator,
    meta: CommandMeta,

    // Collected values
    options: std.StringHashMap(?[]const u8),
    positionals: std.ArrayList([]const u8),

    // State
    is_after_separator: bool = false,

    pub fn init(allocator: Allocator, args: *ArgIterator, meta: CommandMeta) ArgParser {
        // ...
    }

    pub fn deinit(self: *ArgParser) void {
        // ...
    }

    /// Parse all arguments. Returns error.HelpRequested if -h/--help was passed.
    pub fn parse(self: *ArgParser) !void {
        while (self.args.next()) |arg| {
            if (self.is_after_separator) {
                // Everything after -- is positional
                try self.positionals.append(self.allocator, arg);
                continue;
            }

            if (mem.eql(u8, arg, "--")) {
                self.is_after_separator = true;
                continue;
            }

            if (mem.eql(u8, arg, "-h") or mem.eql(u8, arg, "--help")) {
                self.printHelp();
                return error.HelpRequested;
            }

            if (mem.startsWith(u8, arg, "-")) {
                try self.parseFlag(arg);
            } else {
                try self.positionals.append(self.allocator, arg);
            }
        }
    }

    /// Get option value by long name (without --)
    pub fn get(self: *ArgParser, name: []const u8) ?[]const u8 {
        return self.options.get(name) orelse null;
    }

    /// Check if boolean flag was set
    pub fn flag(self: *ArgParser, name: []const u8) bool {
        return self.options.contains(name);
    }

    /// Get first positional argument
    pub fn positional(self: *ArgParser, index: usize) ?[]const u8 {
        if (index >= self.positionals.items.len) return null;
        return self.positionals.items[index];
    }

    fn parseFlag(self: *ArgParser, arg: []const u8) !void {
        // Match against meta.options
        // If not found, error with "Unknown flag: {arg}"
        // If found and expects value, consume next arg
    }

    fn printHelp(self: *ArgParser) void {
        // Print formatted help from self.meta
    }
};
```

### Command Usage (add.zig)

```zig
const cli = @import("../mod.zig");
const args_mod = @import("../args.zig");

pub const meta = args_mod.CommandMeta{
    .name = "add",
    .usage = "add <title> [options]",
    .short = "Add a new ticket",
    .options = &.{
        .{ .short = "-p", .long = "--project", .arg = "<PREFIX>", .desc = "Project prefix" },
        .{ .short = "-t", .long = "--type", .arg = "<TYPE>", .desc = "bug, feature, task, chore, epic" },
        .{ .short = "-m", .long = "--message", .arg = "<DESC>", .desc = "Ticket description" },
        .{ .short = "-d", .long = "--depends", .arg = "<IDs>", .desc = "Comma-separated dependency IDs" },
        .{ .long = "--priority", .arg = "<LEVEL>", .desc = "low, medium, high" },
    },
    .examples = &.{
        "tckts add \"Fix login bug\" -t bug",
        "tckts add \"Auth feature\" -t feature -d PROJ-1",
    },
};

pub fn run(allocator: Allocator, raw_args: anytype) !void {
    var parser = args_mod.ArgParser.init(allocator, raw_args, meta);
    defer parser.deinit();

    parser.parse() catch |err| switch (err) {
        error.HelpRequested => return,
        else => return err,
    };

    // Get positional (title)
    const title = parser.positional(0) orelse {
        cli.eprint("Error: Missing ticket title.\n", .{});
        cli.eprint("Usage: tckts {s}\n", .{meta.usage});
        return error.MissingArgument;
    };

    // Get options with defaults
    const prefix = parser.get("project") orelse
        try cli.getDefaultProjectOrError(allocator);

    const ticket_type: tckts.TicketType = if (parser.get("type")) |t|
        tckts.TicketType.fromString(t) orelse {
            cli.eprint("Error: Invalid type '{s}'.\n", .{t});
            return error.InvalidArgument;
        }
    else .task;

    const description = parser.get("message") orelse "";
    const depends_str = parser.get("depends");
    const priority_str = parser.get("priority");

    // ... rest of command logic
}
```

### Generated Help Output

```
$ tckts add -h

Usage: tckts add <title> [options]

Add a new ticket.

Options:
  -p, --project <PREFIX>   Project prefix
  -t, --type <TYPE>        bug, feature, task, chore, epic
  -m, --message <DESC>     Ticket description
  -d, --depends <IDs>      Comma-separated dependency IDs
  --priority <LEVEL>       low, medium, high

Examples:
  tckts add "Fix login bug" -t bug
  tckts add "Auth feature" -t feature -d PROJ-1
```

### Global Help Generation

`main.zig:printHelp()` iterates all command metas:

```zig
// src/cli/commands/mod.zig
pub const all_commands = .{
    .{ "add", @import("add.zig") },
    .{ "list", @import("list.zig") },
    .{ "show", @import("show.zig") },
    // ...
};

// main.zig
fn printHelp() void {
    cli.print("tckts - CLI ticket tracker {s}\n\n", .{version});
    cli.print("USAGE:\n    tckts <command> [options]\n\n", .{});
    cli.print("COMMANDS:\n", .{});

    inline for (commands.all_commands) |cmd| {
        const module = cmd[1];
        if (@hasDecl(module, "meta")) {
            cli.print("    {s: <20} {s}\n", .{module.meta.usage, module.meta.short});
        }
    }
    // ...
}
```

### GlobalArgs (Placeholder)

```zig
// src/cli/args.zig

pub const GlobalArgs = struct {
    // Future global flags
    // is_json: bool = false,
    // is_quiet: bool = false,
    // tckts_dir: ?[]const u8 = null,
};

pub const global_options = &[_]OptionMeta{
    // Future:
    // .{ .long = "--json", .desc = "Output in JSON format" },
    // .{ .short = "-q", .long = "--quiet", .desc = "Suppress non-essential output" },
};
```

### Error Messages

```
$ tckts add --foo "title"
Error: Unknown flag: --foo
Run 'tckts add -h' for usage.

$ tckts add -t
Error: Flag -t requires a value.
Run 'tckts add -h' for usage.
```

## File Structure

```
src/cli/
├── mod.zig           # CLI helpers (print, eprint, etc.)
├── args.zig          # NEW: ArgParser, CommandMeta, GlobalArgs
└── commands/
    ├── mod.zig       # Command dispatch + all_commands
    ├── add.zig       # exports meta + run()
    ├── list.zig      # exports meta + run()
    └── ...
```

## Implementation Order

1. **TCKTS-72**: Create `CommandMeta` and `OptionMeta` structs
2. **TCKTS-73**: Create `ArgParser` with core parsing logic
3. **TCKTS-74**: Unit tests for ArgParser
4. **TCKTS-75**: `-h`/`--help` handling
5. **TCKTS-76**: `--` separator support
6. **TCKTS-77**: Unknown flag errors
7. **TCKTS-78**: GlobalArgs placeholder
8. **TCKTS-79**: Migrate `add` command
9. **TCKTS-80**: Migrate `list` command
10. **TCKTS-81**: Migrate remaining commands
11. **TCKTS-82**: Generate `tckts help` from metas
12. **TCKTS-83**: e2e tests for `-h`
13. **TCKTS-84**: e2e tests for `--` separator

## Testing Strategy

### Unit Tests (TCKTS-74)

```zig
test "ArgParser: parses short flag with value" { ... }
test "ArgParser: parses long flag with value" { ... }
test "ArgParser: collects positionals" { ... }
test "ArgParser: -- separator treats rest as positional" { ... }
test "ArgParser: -h returns HelpRequested" { ... }
test "ArgParser: unknown flag returns error" { ... }
test "ArgParser: flag without required value returns error" { ... }
```

### E2E Tests (TCKTS-83, TCKTS-84)

```zig
test "e2e: tckts add -h prints help" { ... }
test "e2e: tckts list --help prints help" { ... }
test "e2e: tckts add -- '-h title' creates ticket" { ... }
test "e2e: tckts add --unknown errors" { ... }
```

## Open Questions

None - design validated through brainstorming session.
