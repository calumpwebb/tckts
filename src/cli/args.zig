const std = @import("std");

const mem = std.mem;

// --- types ---

/// Metadata for a single command-line option/flag
pub const OptionMeta = struct {
    short: ?[]const u8 = null, // e.g., "-p"
    long: ?[]const u8 = null, // e.g., "--project"
    arg: ?[]const u8 = null, // e.g., "<PREFIX>" (null = boolean flag)
    desc: []const u8, // e.g., "Project prefix"

    /// Check if this option matches the given argument
    pub fn matches(self: OptionMeta, argument: []const u8) bool {
        if (self.short) |s| {
            if (mem.eql(u8, argument, s)) return true;
        }
        if (self.long) |l| {
            if (mem.eql(u8, argument, l)) return true;
        }
        return false;
    }

    /// Get the canonical name (long form without --, or short form without -)
    pub fn canonicalName(self: OptionMeta) []const u8 {
        if (self.long) |l| {
            return if (mem.startsWith(u8, l, "--")) l[2..] else l;
        }
        if (self.short) |s| {
            return if (mem.startsWith(u8, s, "-")) s[1..] else s;
        }
        return "";
    }

    /// Returns true if this option expects a value
    pub fn expectsValue(self: OptionMeta) bool {
        return self.arg != null;
    }
};

/// Metadata for a command, used for help generation
pub const CommandMeta = struct {
    name: []const u8, // e.g., "add"
    usage: []const u8, // e.g., "add <title> [options]"
    short: []const u8, // e.g., "Add a new ticket"
    options: []const OptionMeta = &.{},
    examples: []const []const u8 = &.{},
};

/// Placeholder for future global flags (--json, --quiet, etc.)
pub const GlobalArgs = struct {
    // Future global flags:
    // is_json: bool = false,
    // is_quiet: bool = false,
    // tckts_dir: ?[]const u8 = null,
};

/// Global options that apply to all commands (placeholder for future)
pub const global_options: []const OptionMeta = &.{
    // Future:
    // .{ .long = "--json", .desc = "Output in JSON format" },
    // .{ .short = "-q", .long = "--quiet", .desc = "Suppress non-essential output" },
};

pub const ParseError = error{
    HelpRequested,
    UnknownFlag,
    MissingFlagValue,
    OutOfMemory,
};

/// Argument parser that handles flags, positionals, and help generation.
/// Generic over iterator type to support both real args and test mocks.
pub fn ArgParser(comptime ArgsIterator: type) type {
    return struct {
        allocator: std.mem.Allocator,
        args: *ArgsIterator,
        meta: CommandMeta,

        // Collected values
        options: std.StringHashMapUnmanaged(?[]const u8),
        positionals: std.ArrayListUnmanaged([]const u8),

        // State
        is_after_separator: bool,

        // Error context
        last_error_arg: ?[]const u8,

        const Self = @This();

        pub fn init(allocator: std.mem.Allocator, args: *ArgsIterator, meta: CommandMeta) Self {
            return .{
                .allocator = allocator,
                .args = args,
                .meta = meta,
                .options = .empty,
                .positionals = .empty,
                .is_after_separator = false,
                .last_error_arg = null,
            };
        }

        pub fn deinit(self: *Self) void {
            self.options.deinit(self.allocator);
            self.positionals.deinit(self.allocator);
        }

        /// Parse all arguments. Returns error.HelpRequested if -h/--help was passed.
        pub fn parse(self: *Self) ParseError!void {
            while (self.args.next()) |argument| {
                if (self.is_after_separator) {
                    // Everything after -- is positional
                    self.positionals.append(self.allocator, argument) catch return error.OutOfMemory;
                    continue;
                }

                if (mem.eql(u8, argument, "--")) {
                    self.is_after_separator = true;
                    continue;
                }

                if (mem.eql(u8, argument, "-h") or mem.eql(u8, argument, "--help")) {
                    self.printHelp();
                    return error.HelpRequested;
                }

                if (mem.startsWith(u8, argument, "-")) {
                    try self.parseFlag(argument);
                } else {
                    self.positionals.append(self.allocator, argument) catch return error.OutOfMemory;
                }
            }
        }

        /// Get option value by canonical name (e.g., "project" for --project)
        pub fn get(self: *Self, name: []const u8) ?[]const u8 {
            const result = self.options.get(name) orelse return null;
            return result; // result is ?[]const u8, return the inner value
        }

        /// Check if boolean flag was set
        pub fn flag(self: *Self, name: []const u8) bool {
            return self.options.contains(name);
        }

        /// Get positional argument by index
        pub fn positional(self: *Self, index: usize) ?[]const u8 {
            if (index >= self.positionals.items.len) return null;
            return self.positionals.items[index];
        }

        /// Get all positional arguments
        pub fn positionalSlice(self: *Self) []const []const u8 {
            return self.positionals.items;
        }

        /// Get the argument that caused the last error (for error messages)
        pub fn errorArg(self: *Self) ?[]const u8 {
            return self.last_error_arg;
        }

        fn parseFlag(self: *Self, argument: []const u8) ParseError!void {
            // Find matching option in meta
            for (self.meta.options) |opt| {
                if (opt.matches(argument)) {
                    const name = opt.canonicalName();
                    if (opt.expectsValue()) {
                        // Consume next argument as value
                        const value = self.args.next() orelse {
                            self.last_error_arg = argument;
                            return error.MissingFlagValue;
                        };
                        self.options.put(self.allocator, name, value) catch return error.OutOfMemory;
                    } else {
                        // Boolean flag
                        self.options.put(self.allocator, name, null) catch return error.OutOfMemory;
                    }
                    return;
                }
            }

            // Unknown flag
            self.last_error_arg = argument;
            return error.UnknownFlag;
        }

        fn printHelp(self: *Self) void {
            const cli = @import("mod.zig");

            cli.print("\nUsage: tckts {s}\n\n", .{self.meta.usage});
            cli.print("{s}\n", .{self.meta.short});

            if (self.meta.options.len > 0) {
                cli.print("\nOptions:\n", .{});
                for (self.meta.options) |opt| {
                    printOption(opt);
                }
            }

            if (global_options.len > 0) {
                cli.print("\nGlobal Options:\n", .{});
                for (global_options) |opt| {
                    printOption(opt);
                }
            }

            if (self.meta.examples.len > 0) {
                cli.print("\nExamples:\n", .{});
                for (self.meta.examples) |ex| {
                    cli.print("  {s}\n", .{ex});
                }
            }

            cli.print("\n", .{});
        }
    };
}

fn printOption(opt: OptionMeta) void {
    const cli = @import("mod.zig");

    // Format: "  -p, --project <PREFIX>   Project prefix"
    var buf: [64]u8 = undefined;
    var len: usize = 0;

    // Add short form
    if (opt.short) |s| {
        for (s) |c| {
            buf[len] = c;
            len += 1;
        }
    }

    // Add separator if both forms exist
    if (opt.short != null and opt.long != null) {
        buf[len] = ',';
        len += 1;
        buf[len] = ' ';
        len += 1;
    }

    // Add long form
    if (opt.long) |l| {
        for (l) |c| {
            buf[len] = c;
            len += 1;
        }
    }

    // Add argument placeholder
    if (opt.arg) |a| {
        buf[len] = ' ';
        len += 1;
        for (a) |c| {
            buf[len] = c;
            len += 1;
        }
    }

    // Print with padding
    cli.print("  {s: <28} {s}\n", .{ buf[0..len], opt.desc });
}

// --- tests ---

/// Test iterator that wraps a slice of strings
const TestArgIterator = struct {
    args: []const []const u8,
    index: usize = 0,

    pub fn next(self: *TestArgIterator) ?[]const u8 {
        if (self.index >= self.args.len) return null;
        const result = self.args[self.index];
        self.index += 1;
        return result;
    }
};

const TestParser = ArgParser(TestArgIterator);

const test_meta = CommandMeta{
    .name = "test",
    .usage = "test <title> [options]",
    .short = "A test command",
    .options = &.{
        .{ .short = "-p", .long = "--project", .arg = "<PREFIX>", .desc = "Project prefix" },
        .{ .short = "-t", .long = "--type", .arg = "<TYPE>", .desc = "Ticket type" },
        .{ .short = "-v", .long = "--verbose", .desc = "Verbose output" },
    },
    .examples = &.{"tckts test \"hello\" -p FOO"},
};

test "OptionMeta: matches short flag" {
    const opt = OptionMeta{
        .short = "-p",
        .long = "--project",
        .arg = "<PREFIX>",
        .desc = "Project prefix",
    };

    try std.testing.expect(opt.matches("-p"));
    try std.testing.expect(opt.matches("--project"));
    try std.testing.expect(!opt.matches("-x"));
    try std.testing.expect(!opt.matches("--other"));
}

test "OptionMeta: canonicalName" {
    const testing = std.testing;

    const opt1 = OptionMeta{ .short = "-p", .long = "--project", .desc = "test" };
    try testing.expectEqualStrings("project", opt1.canonicalName());

    const opt2 = OptionMeta{ .short = "-v", .desc = "test" };
    try testing.expectEqualStrings("v", opt2.canonicalName());

    const opt3 = OptionMeta{ .long = "--verbose", .desc = "test" };
    try testing.expectEqualStrings("verbose", opt3.canonicalName());
}

test "OptionMeta: expectsValue" {
    const testing = std.testing;

    const flag_opt = OptionMeta{ .short = "-v", .desc = "verbose" };
    try testing.expect(!flag_opt.expectsValue());

    const value_opt = OptionMeta{ .short = "-p", .arg = "<PREFIX>", .desc = "project" };
    try testing.expect(value_opt.expectsValue());
}

test "ArgParser: parses positional argument" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var iter = TestArgIterator{ .args = &.{"hello"} };
    var parser = TestParser.init(allocator, &iter, test_meta);
    defer parser.deinit();

    try parser.parse();

    try testing.expectEqualStrings("hello", parser.positional(0).?);
    try testing.expectEqual(@as(?[]const u8, null), parser.positional(1));
}

test "ArgParser: parses short flag with value" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var iter = TestArgIterator{ .args = &.{ "-p", "PROJ", "title" } };
    var parser = TestParser.init(allocator, &iter, test_meta);
    defer parser.deinit();

    try parser.parse();

    try testing.expectEqualStrings("PROJ", parser.get("project").?);
    try testing.expectEqualStrings("title", parser.positional(0).?);
}

test "ArgParser: parses long flag with value" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var iter = TestArgIterator{ .args = &.{ "--project", "PROJ", "--type", "bug" } };
    var parser = TestParser.init(allocator, &iter, test_meta);
    defer parser.deinit();

    try parser.parse();

    try testing.expectEqualStrings("PROJ", parser.get("project").?);
    try testing.expectEqualStrings("bug", parser.get("type").?);
}

test "ArgParser: parses boolean flag" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var iter = TestArgIterator{ .args = &.{ "-v", "title" } };
    var parser = TestParser.init(allocator, &iter, test_meta);
    defer parser.deinit();

    try parser.parse();

    try testing.expect(parser.flag("verbose"));
    try testing.expect(!parser.flag("project"));
    try testing.expectEqualStrings("title", parser.positional(0).?);
}

test "ArgParser: -- separator treats rest as positional" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var iter = TestArgIterator{ .args = &.{ "--", "-h", "--help", "-p" } };
    var parser = TestParser.init(allocator, &iter, test_meta);
    defer parser.deinit();

    try parser.parse();

    // All args after -- should be positionals, even flag-like ones
    try testing.expectEqualStrings("-h", parser.positional(0).?);
    try testing.expectEqualStrings("--help", parser.positional(1).?);
    try testing.expectEqualStrings("-p", parser.positional(2).?);
    try testing.expect(!parser.flag("verbose"));
}

test "ArgParser: -h returns HelpRequested" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var iter = TestArgIterator{ .args = &.{"-h"} };
    var parser = TestParser.init(allocator, &iter, test_meta);
    defer parser.deinit();

    const result = parser.parse();
    try testing.expectError(error.HelpRequested, result);
}

test "ArgParser: --help returns HelpRequested" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var iter = TestArgIterator{ .args = &.{"--help"} };
    var parser = TestParser.init(allocator, &iter, test_meta);
    defer parser.deinit();

    const result = parser.parse();
    try testing.expectError(error.HelpRequested, result);
}

test "ArgParser: unknown flag returns error" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var iter = TestArgIterator{ .args = &.{"--unknown"} };
    var parser = TestParser.init(allocator, &iter, test_meta);
    defer parser.deinit();

    const result = parser.parse();
    try testing.expectError(error.UnknownFlag, result);
    try testing.expectEqualStrings("--unknown", parser.errorArg().?);
}

test "ArgParser: flag without required value returns error" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var iter = TestArgIterator{ .args = &.{"-p"} }; // -p requires value
    var parser = TestParser.init(allocator, &iter, test_meta);
    defer parser.deinit();

    const result = parser.parse();
    try testing.expectError(error.MissingFlagValue, result);
    try testing.expectEqualStrings("-p", parser.errorArg().?);
}

test "ArgParser: mixed flags and positionals in any order" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var iter = TestArgIterator{ .args = &.{ "title", "-p", "PROJ", "-v", "extra" } };
    var parser = TestParser.init(allocator, &iter, test_meta);
    defer parser.deinit();

    try parser.parse();

    try testing.expectEqualStrings("PROJ", parser.get("project").?);
    try testing.expect(parser.flag("verbose"));
    try testing.expectEqualStrings("title", parser.positional(0).?);
    try testing.expectEqualStrings("extra", parser.positional(1).?);
}

test "ArgParser: title starting with dash after --" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // This is the original bug - titles starting with - were rejected
    var iter = TestArgIterator{ .args = &.{ "--", "-h and --help don't work" } };
    var parser = TestParser.init(allocator, &iter, test_meta);
    defer parser.deinit();

    try parser.parse();

    try testing.expectEqualStrings("-h and --help don't work", parser.positional(0).?);
}
