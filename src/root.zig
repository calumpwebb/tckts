const std = @import("std");

const fs = std.fs;
const mem = std.mem;
const fmt = std.fmt;
const testing = std.testing;

// --- constants ---

const format_version = 1;
const tckts_dir = ".tckts";
const file_extension = ".tckts";
const default_prefix = "MAIN";
const max_line_length_bytes = 4096;
const max_description_length_bytes = 65536;

// --- types ---

pub const Priority = enum {
    low,
    medium,
    high,

    pub fn fromString(s: []const u8) ?Priority {
        if (mem.eql(u8, s, "low")) return .low;
        if (mem.eql(u8, s, "medium")) return .medium;
        if (mem.eql(u8, s, "high")) return .high;
        return null;
    }

    pub fn toString(self: Priority) []const u8 {
        return switch (self) {
            .low => "low",
            .medium => "medium",
            .high => "high",
        };
    }
};

pub const TicketType = enum {
    bug,
    feature,
    task,
    chore,

    pub fn fromString(s: []const u8) ?TicketType {
        if (mem.eql(u8, s, "bug")) return .bug;
        if (mem.eql(u8, s, "feature")) return .feature;
        if (mem.eql(u8, s, "task")) return .task;
        if (mem.eql(u8, s, "chore")) return .chore;
        return null;
    }

    pub fn toString(self: TicketType) []const u8 {
        return switch (self) {
            .bug => "bug",
            .feature => "feature",
            .task => "task",
            .chore => "chore",
        };
    }
};

pub const Status = enum {
    pending,
    done,

    pub fn fromString(s: []const u8) ?Status {
        if (mem.eql(u8, s, "pending")) return .pending;
        if (mem.eql(u8, s, "done")) return .done;
        return null;
    }

    pub fn toString(self: Status) []const u8 {
        return switch (self) {
            .pending => "pending",
            .done => "done",
        };
    }
};

pub const TicketId = struct {
    prefix: []const u8,
    number: u32,

    pub fn format(
        self: TicketId,
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        try writer.print("{s}-{d}", .{ self.prefix, self.number });
    }

    pub fn parse(allocator: std.mem.Allocator, s: []const u8) !TicketId {
        const dash_idx = mem.lastIndexOf(u8, s, "-") orelse return error.InvalidTicketId;
        if (dash_idx == 0 or dash_idx == s.len - 1) return error.InvalidTicketId;

        const prefix = s[0..dash_idx];
        const number_str = s[dash_idx + 1 ..];
        const number = fmt.parseInt(u32, number_str, 10) catch return error.InvalidTicketId;

        const prefix_copy = try allocator.dupe(u8, prefix);
        return TicketId{ .prefix = prefix_copy, .number = number };
    }

    pub fn eql(self: TicketId, other: TicketId) bool {
        return self.number == other.number and mem.eql(u8, self.prefix, other.prefix);
    }

    pub fn deinit(self: *TicketId, allocator: std.mem.Allocator) void {
        allocator.free(self.prefix);
        self.* = undefined;
    }
};

pub const Ticket = struct {
    id: TicketId,
    ticket_type: TicketType,
    status: Status,
    title: []const u8,
    created: []const u8,
    depends: []TicketId,
    priority: ?Priority,
    description: []const u8,

    pub fn deinit(self: *Ticket, allocator: std.mem.Allocator) void {
        allocator.free(self.id.prefix);
        allocator.free(self.title);
        allocator.free(self.created);
        for (self.depends) |*dep| {
            allocator.free(dep.prefix);
        }
        allocator.free(self.depends);
        allocator.free(self.description);
        self.* = undefined;
    }
};

pub const Project = struct {
    allocator: std.mem.Allocator,
    prefix: []const u8,
    tickets: std.ArrayList(Ticket),
    next_number: u32,

    pub fn init(allocator: std.mem.Allocator, prefix: []const u8) !Project {
        const prefix_copy = try allocator.dupe(u8, prefix);
        return Project{
            .allocator = allocator,
            .prefix = prefix_copy,
            .tickets = .empty,
            .next_number = 1,
        };
    }

    pub fn deinit(self: *Project) void {
        for (self.tickets.items) |*ticket| {
            ticket.deinit(self.allocator);
        }
        self.tickets.deinit(self.allocator);
        self.allocator.free(self.prefix);
        self.* = undefined;
    }

    pub fn findTicket(self: *const Project, number: u32) ?*Ticket {
        for (self.tickets.items) |*ticket| {
            if (ticket.id.number == number) return ticket;
        }
        return null;
    }

    pub fn findTicketById(self: *const Project, id: TicketId) ?*Ticket {
        if (!mem.eql(u8, id.prefix, self.prefix)) return null;
        return self.findTicket(id.number);
    }

    pub fn addTicket(self: *Project, ticket_type: TicketType, title: []const u8, description: []const u8, depends: []const TicketId, priority: ?Priority) !*Ticket {
        const title_copy = try self.allocator.dupe(u8, title);
        errdefer self.allocator.free(title_copy);

        const desc_copy = try self.allocator.dupe(u8, description);
        errdefer self.allocator.free(desc_copy);

        const prefix_copy = try self.allocator.dupe(u8, self.prefix);
        errdefer self.allocator.free(prefix_copy);

        var depends_copy = try self.allocator.alloc(TicketId, depends.len);
        errdefer self.allocator.free(depends_copy);

        for (depends, 0..) |dep, i| {
            depends_copy[i] = TicketId{
                .prefix = try self.allocator.dupe(u8, dep.prefix),
                .number = dep.number,
            };
        }

        // Get current date
        const timestamp = std.time.timestamp();
        const epoch_secs: u64 = @intCast(timestamp);
        const epoch_day = std.time.epoch.EpochDay{ .day = @intCast(epoch_secs / std.time.s_per_day) };
        const year_day = epoch_day.calculateYearDay();
        const month_day = year_day.calculateMonthDay();

        var date_buf: [10]u8 = undefined;
        const date_str = fmt.bufPrint(&date_buf, "{d:0>4}-{d:0>2}-{d:0>2}", .{
            year_day.year,
            @intFromEnum(month_day.month),
            month_day.day_index + 1,
        }) catch unreachable;

        const created = try self.allocator.dupe(u8, date_str);
        errdefer self.allocator.free(created);

        const ticket = Ticket{
            .id = TicketId{ .prefix = prefix_copy, .number = self.next_number },
            .ticket_type = ticket_type,
            .status = .pending,
            .title = title_copy,
            .created = created,
            .depends = depends_copy,
            .priority = priority,
            .description = desc_copy,
        };

        try self.tickets.append(self.allocator, ticket);
        self.next_number += 1;

        return &self.tickets.items[self.tickets.items.len - 1];
    }

    pub fn removeTicket(self: *Project, number: u32) !void {
        var idx: ?usize = null;
        for (self.tickets.items, 0..) |*ticket, i| {
            if (ticket.id.number == number) {
                idx = i;
                break;
            }
        }

        if (idx) |i| {
            // Remove this ticket from all dependency lists
            const removed_id = self.tickets.items[i].id;
            for (self.tickets.items) |*ticket| {
                var new_depends: std.ArrayList(TicketId) = .empty;
                for (ticket.depends) |dep| {
                    if (!dep.eql(removed_id)) {
                        const dep_copy = TicketId{
                            .prefix = try self.allocator.dupe(u8, dep.prefix),
                            .number = dep.number,
                        };
                        try new_depends.append(self.allocator, dep_copy);
                    }
                }
                // Free old depends
                for (ticket.depends) |*dep| {
                    self.allocator.free(dep.prefix);
                }
                self.allocator.free(ticket.depends);
                ticket.depends = try new_depends.toOwnedSlice(self.allocator);
            }

            // Free and remove the ticket
            self.tickets.items[i].deinit(self.allocator);
            _ = self.tickets.orderedRemove(i);
        } else {
            return error.TicketNotFound;
        }
    }

    /// Check if completing a ticket would violate dependencies
    pub fn canComplete(self: *const Project, number: u32) ![]const TicketId {
        const ticket = self.findTicket(number) orelse return error.TicketNotFound;

        var blocking: std.ArrayList(TicketId) = .empty;
        errdefer blocking.deinit(self.allocator);

        for (ticket.depends) |dep| {
            // Check if dependency is in this project
            if (mem.eql(u8, dep.prefix, self.prefix)) {
                if (self.findTicket(dep.number)) |dep_ticket| {
                    if (dep_ticket.status != .done) {
                        try blocking.append(self.allocator, dep);
                    }
                }
            }
            // Cross-project dependencies would need to be checked by the caller
        }

        return blocking.toOwnedSlice(self.allocator);
    }

    pub fn markDone(self: *Project, number: u32) !void {
        const ticket = self.findTicket(number) orelse return error.TicketNotFound;
        ticket.status = .done;
    }
};

pub const ParseError = error{
    InvalidHeader,
    InvalidTicketBlock,
    InvalidTicketId,
    MissingRequiredField,
    OutOfMemory,
    InvalidFormat,
};

pub const FileError = error{
    ProjectNotFound,
    ProjectAlreadyExists,
    IoError,
};

/// Parse a .tckts file into a Project
pub fn parseFile(allocator: std.mem.Allocator, content: []const u8) ParseError!Project {
    var lines = mem.splitSequence(u8, content, "\n");

    // Parse header
    const header = lines.next() orelse return error.InvalidHeader;
    const prefix = parseHeader(header) orelse return error.InvalidHeader;

    var project = Project.init(allocator, prefix) catch return error.OutOfMemory;
    errdefer project.deinit();

    // Parse ticket blocks
    var current_block: ?[]const u8 = null;
    var block_start: usize = 0;
    var pos: usize = header.len + 1;

    while (lines.next()) |line| {
        const trimmed = mem.trim(u8, line, " \t");
        if (mem.startsWith(u8, trimmed, "---")) {
            // Check if this is a block start (--- PREFIX-N) or just a terminator (---)
            const after_dashes = mem.trim(u8, trimmed["---".len..], " \t");
            const is_block_start = after_dashes.len > 0 and mem.indexOf(u8, after_dashes, "-") != null;

            if (is_block_start) {
                // Process previous block if exists
                if (current_block) |_| {
                    const block_content = content[block_start..pos];
                    const ticket = parseTicketBlock(allocator, block_content, prefix) catch |e| {
                        return e;
                    };
                    project.tickets.append(allocator, ticket) catch return error.OutOfMemory;
                    if (ticket.id.number >= project.next_number) {
                        project.next_number = ticket.id.number + 1;
                    }
                }
                current_block = line;
                block_start = pos;
            }
        }
        pos += line.len + 1;
    }

    // Process last block
    if (current_block) |_| {
        const block_content = content[block_start..];
        const ticket = parseTicketBlock(allocator, block_content, prefix) catch |e| {
            return e;
        };
        project.tickets.append(allocator, ticket) catch return error.OutOfMemory;
        if (ticket.id.number >= project.next_number) {
            project.next_number = ticket.id.number + 1;
        }
    }

    return project;
}

fn parseHeader(line: []const u8) ?[]const u8 {
    // Expected: # tckts | prefix: <PREFIX> | version: 1
    if (!mem.startsWith(u8, line, "# tckts")) return null;

    var parts = mem.splitSequence(u8, line, "|");
    _ = parts.next(); // Skip "# tckts"

    var prefix: ?[]const u8 = null;
    var version_ok = false;

    while (parts.next()) |part| {
        const trimmed = mem.trim(u8, part, " \t");
        if (mem.startsWith(u8, trimmed, "prefix:")) {
            prefix = mem.trim(u8, trimmed["prefix:".len..], " \t");
        } else if (mem.startsWith(u8, trimmed, "version:")) {
            const ver_str = mem.trim(u8, trimmed["version:".len..], " \t");
            const ver = fmt.parseInt(u32, ver_str, 10) catch continue;
            version_ok = (ver == format_version);
        }
    }

    if (prefix != null and version_ok) return prefix;
    return null;
}

fn parseTicketBlock(allocator: std.mem.Allocator, block: []const u8, expected_prefix: []const u8) ParseError!Ticket {
    var lines = mem.splitSequence(u8, block, "\n");

    // First line: --- PREFIX-N
    const first_line = lines.next() orelse return error.InvalidTicketBlock;
    const trimmed_first = mem.trim(u8, first_line, " \t");
    if (!mem.startsWith(u8, trimmed_first, "---")) return error.InvalidTicketBlock;

    const id_str = mem.trim(u8, trimmed_first["---".len..], " \t");
    if (id_str.len == 0) return error.InvalidTicketBlock;

    var id = TicketId.parse(allocator, id_str) catch return error.InvalidTicketId;
    errdefer id.deinit(allocator);

    // Verify prefix matches
    if (!mem.eql(u8, id.prefix, expected_prefix)) return error.InvalidTicketId;

    // Parse metadata lines until empty line
    var ticket_type: ?TicketType = null;
    var status: ?Status = null;
    var title: ?[]const u8 = null;
    var created: ?[]const u8 = null;
    var depends_str: ?[]const u8 = null;
    var priority: ?Priority = null;
    var in_description = false;
    var description_lines: std.ArrayList([]const u8) = .empty;
    defer description_lines.deinit(allocator);

    while (lines.next()) |line| {
        const trimmed = mem.trim(u8, line, " \t");

        // Check for end of block marker
        if (mem.startsWith(u8, trimmed, "---")) break;

        if (in_description) {
            description_lines.append(allocator, line) catch return error.OutOfMemory;
            continue;
        }

        if (trimmed.len == 0) {
            in_description = true;
            continue;
        }

        // Parse metadata
        if (mem.startsWith(u8, trimmed, "type:")) {
            const val = mem.trim(u8, trimmed["type:".len..], " \t");
            ticket_type = TicketType.fromString(val);
        } else if (mem.startsWith(u8, trimmed, "status:")) {
            const val = mem.trim(u8, trimmed["status:".len..], " \t");
            status = Status.fromString(val);
        } else if (mem.startsWith(u8, trimmed, "title:")) {
            title = mem.trim(u8, trimmed["title:".len..], " \t");
        } else if (mem.startsWith(u8, trimmed, "created:")) {
            created = mem.trim(u8, trimmed["created:".len..], " \t");
        } else if (mem.startsWith(u8, trimmed, "depends:")) {
            depends_str = mem.trim(u8, trimmed["depends:".len..], " \t");
        } else if (mem.startsWith(u8, trimmed, "priority:")) {
            const val = mem.trim(u8, trimmed["priority:".len..], " \t");
            priority = Priority.fromString(val);
        }
    }

    // Validate required fields
    if (ticket_type == null or status == null or title == null or created == null) {
        return error.MissingRequiredField;
    }

    // Copy strings
    const title_copy = allocator.dupe(u8, title.?) catch return error.OutOfMemory;
    errdefer allocator.free(title_copy);

    const created_copy = allocator.dupe(u8, created.?) catch return error.OutOfMemory;
    errdefer allocator.free(created_copy);

    // Parse depends
    var depends: std.ArrayList(TicketId) = .empty;
    errdefer {
        for (depends.items) |*d| d.deinit(allocator);
        depends.deinit(allocator);
    }

    if (depends_str) |ds| {
        var dep_parts = mem.splitSequence(u8, ds, ",");
        while (dep_parts.next()) |dep_str| {
            const dep_trimmed = mem.trim(u8, dep_str, " \t");
            if (dep_trimmed.len == 0) continue;
            const dep_id = TicketId.parse(allocator, dep_trimmed) catch return error.InvalidTicketId;
            depends.append(allocator, dep_id) catch return error.OutOfMemory;
        }
    }

    // Build description
    var desc_builder: std.ArrayList(u8) = .empty;
    errdefer desc_builder.deinit(allocator);

    for (description_lines.items, 0..) |desc_line, i| {
        if (i > 0) desc_builder.append(allocator, '\n') catch return error.OutOfMemory;
        desc_builder.appendSlice(allocator, desc_line) catch return error.OutOfMemory;
    }

    // Trim trailing whitespace from description
    var desc_slice = desc_builder.toOwnedSlice(allocator) catch return error.OutOfMemory;
    const desc_trimmed = mem.trimRight(u8, desc_slice, " \t\n");
    if (desc_trimmed.len < desc_slice.len) {
        const new_desc = allocator.dupe(u8, desc_trimmed) catch return error.OutOfMemory;
        allocator.free(desc_slice);
        desc_slice = new_desc;
    }

    return Ticket{
        .id = id,
        .ticket_type = ticket_type.?,
        .status = status.?,
        .title = title_copy,
        .created = created_copy,
        .depends = depends.toOwnedSlice(allocator) catch return error.OutOfMemory,
        .priority = priority,
        .description = desc_slice,
    };
}

/// Serialize a Project to .tckts file format
pub fn serializeProject(allocator: std.mem.Allocator, project: *const Project) ![]u8 {
    var buffer: std.ArrayList(u8) = .empty;
    errdefer buffer.deinit(allocator);

    const writer = buffer.writer(allocator);

    // Write header
    try writer.print("# tckts | prefix: {s} | version: {d}\n", .{ project.prefix, format_version });

    // Write tickets
    for (project.tickets.items) |ticket| {
        try writer.print("\n--- {s}-{d}\n", .{ ticket.id.prefix, ticket.id.number });
        try writer.print("type: {s}\n", .{ticket.ticket_type.toString()});
        try writer.print("status: {s}\n", .{ticket.status.toString()});
        try writer.print("title: {s}\n", .{ticket.title});
        try writer.print("created: {s}\n", .{ticket.created});

        if (ticket.depends.len > 0) {
            try writer.writeAll("depends: ");
            for (ticket.depends, 0..) |dep, i| {
                if (i > 0) try writer.writeAll(", ");
                try writer.print("{s}-{d}", .{ dep.prefix, dep.number });
            }
            try writer.writeAll("\n");
        }

        if (ticket.priority) |p| {
            try writer.print("priority: {s}\n", .{p.toString()});
        }

        if (ticket.description.len > 0) {
            try writer.writeAll("\n");
            try writer.writeAll(ticket.description);
            try writer.writeAll("\n");
        }

        try writer.writeAll("---\n");
    }

    return buffer.toOwnedSlice(allocator);
}

/// Get the path to the .tckts directory
pub fn getTcktsDir(allocator: std.mem.Allocator) ![]u8 {
    const cwd = fs.cwd();
    return cwd.realpathAlloc(allocator, tckts_dir) catch |e| switch (e) {
        error.FileNotFound => return allocator.dupe(u8, tckts_dir),
        else => return e,
    };
}

/// Get the path to a project file
pub fn getProjectPath(allocator: std.mem.Allocator, prefix: []const u8) ![]u8 {
    return fmt.allocPrint(allocator, "{s}/{s}{s}", .{ tckts_dir, prefix, file_extension });
}

/// Initialize a new project
pub fn initProject(allocator: std.mem.Allocator, prefix: []const u8) !void {
    const cwd = fs.cwd();

    // Create .tckts directory if it doesn't exist
    cwd.makeDir(tckts_dir) catch |e| switch (e) {
        error.PathAlreadyExists => {},
        else => return e,
    };

    // Check if project already exists
    const project_path = try getProjectPath(allocator, prefix);
    defer allocator.free(project_path);

    const file = cwd.createFile(project_path, .{ .exclusive = true }) catch |e| switch (e) {
        error.PathAlreadyExists => return error.ProjectAlreadyExists,
        else => return e,
    };
    defer file.close();

    // Write initial content
    var project = try Project.init(allocator, prefix);
    defer project.deinit();

    const content = try serializeProject(allocator, &project);
    defer allocator.free(content);

    try file.writeAll(content);
}

/// Load a project from disk
pub fn loadProject(allocator: std.mem.Allocator, prefix: []const u8) !Project {
    const project_path = try getProjectPath(allocator, prefix);
    defer allocator.free(project_path);

    const cwd = fs.cwd();
    const file = cwd.openFile(project_path, .{}) catch |e| switch (e) {
        error.FileNotFound => return error.ProjectNotFound,
        else => return e,
    };
    defer file.close();

    const content = try file.readToEndAlloc(allocator, max_description_length_bytes * 1000);
    defer allocator.free(content);

    return parseFile(allocator, content);
}

/// Save a project to disk
pub fn saveProject(allocator: std.mem.Allocator, project: *const Project) !void {
    const project_path = try getProjectPath(allocator, project.prefix);
    defer allocator.free(project_path);

    const cwd = fs.cwd();
    const file = try cwd.createFile(project_path, .{});
    defer file.close();

    const content = try serializeProject(allocator, project);
    defer allocator.free(content);

    try file.writeAll(content);
}

/// List all projects (prefixes)
pub fn listProjects(allocator: std.mem.Allocator) ![][]const u8 {
    var projects: std.ArrayList([]const u8) = .empty;
    errdefer {
        for (projects.items) |p| allocator.free(p);
        projects.deinit(allocator);
    }

    const cwd = fs.cwd();
    var dir = cwd.openDir(tckts_dir, .{ .iterate = true }) catch |e| switch (e) {
        error.FileNotFound => return projects.toOwnedSlice(allocator),
        else => return e,
    };
    defer dir.close();

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind != .file) continue;
        if (!mem.endsWith(u8, entry.name, file_extension)) continue;

        const prefix = entry.name[0 .. entry.name.len - file_extension.len];
        try projects.append(allocator, try allocator.dupe(u8, prefix));
    }

    return projects.toOwnedSlice(allocator);
}

// --- tests ---

test "TicketId: parse valid id" {
    const allocator = testing.allocator;
    var id = try TicketId.parse(allocator, "BACKEND-123");
    defer id.deinit(allocator);

    try testing.expectEqualStrings("BACKEND", id.prefix);
    try testing.expectEqual(@as(u32, 123), id.number);
}

test "TicketId: parse invalid id - no dash" {
    const allocator = testing.allocator;
    try testing.expectError(error.InvalidTicketId, TicketId.parse(allocator, "BACKEND123"));
}

test "TicketId: parse invalid id - no number" {
    const allocator = testing.allocator;
    try testing.expectError(error.InvalidTicketId, TicketId.parse(allocator, "BACKEND-"));
}

test "TicketId: equality" {
    const allocator = testing.allocator;
    var id1 = try TicketId.parse(allocator, "TEST-1");
    defer id1.deinit(allocator);
    var id2 = try TicketId.parse(allocator, "TEST-1");
    defer id2.deinit(allocator);
    var id3 = try TicketId.parse(allocator, "TEST-2");
    defer id3.deinit(allocator);

    try testing.expect(id1.eql(id2));
    try testing.expect(!id1.eql(id3));
}

test "Priority: fromString and toString" {
    try testing.expectEqual(Priority.low, Priority.fromString("low").?);
    try testing.expectEqual(Priority.medium, Priority.fromString("medium").?);
    try testing.expectEqual(Priority.high, Priority.fromString("high").?);
    try testing.expectEqual(@as(?Priority, null), Priority.fromString("invalid"));

    try testing.expectEqualStrings("low", Priority.low.toString());
    try testing.expectEqualStrings("medium", Priority.medium.toString());
    try testing.expectEqualStrings("high", Priority.high.toString());
}

test "Status: fromString and toString" {
    try testing.expectEqual(Status.pending, Status.fromString("pending").?);
    try testing.expectEqual(Status.done, Status.fromString("done").?);
    try testing.expectEqual(@as(?Status, null), Status.fromString("invalid"));

    try testing.expectEqualStrings("pending", Status.pending.toString());
    try testing.expectEqualStrings("done", Status.done.toString());
}

test "TicketType: fromString and toString" {
    try testing.expectEqual(TicketType.bug, TicketType.fromString("bug").?);
    try testing.expectEqual(TicketType.feature, TicketType.fromString("feature").?);
    try testing.expectEqual(TicketType.task, TicketType.fromString("task").?);
    try testing.expectEqual(TicketType.chore, TicketType.fromString("chore").?);
    try testing.expectEqual(@as(?TicketType, null), TicketType.fromString("invalid"));

    try testing.expectEqualStrings("bug", TicketType.bug.toString());
    try testing.expectEqualStrings("feature", TicketType.feature.toString());
    try testing.expectEqualStrings("task", TicketType.task.toString());
    try testing.expectEqualStrings("chore", TicketType.chore.toString());
}

test "Project: add and find ticket" {
    const allocator = testing.allocator;
    var project = try Project.init(allocator, "TEST");
    defer project.deinit();

    const ticket = try project.addTicket(.task, "Test ticket", "Description", &.{}, null);
    try testing.expectEqual(@as(u32, 1), ticket.id.number);
    try testing.expectEqualStrings("TEST", ticket.id.prefix);
    try testing.expectEqualStrings("Test ticket", ticket.title);
    try testing.expectEqual(Status.pending, ticket.status);
    try testing.expectEqual(TicketType.task, ticket.ticket_type);

    const found = project.findTicket(1);
    try testing.expect(found != null);
    try testing.expectEqualStrings("Test ticket", found.?.title);

    const not_found = project.findTicket(999);
    try testing.expect(not_found == null);
}

test "Project: remove ticket" {
    const allocator = testing.allocator;
    var project = try Project.init(allocator, "TEST");
    defer project.deinit();

    _ = try project.addTicket(.task, "Ticket 1", "", &.{}, null);
    _ = try project.addTicket(.bug, "Ticket 2", "", &.{}, null);

    try testing.expectEqual(@as(usize, 2), project.tickets.items.len);

    try project.removeTicket(1);

    try testing.expectEqual(@as(usize, 1), project.tickets.items.len);
    try testing.expectEqual(@as(u32, 2), project.tickets.items[0].id.number);
}

test "parseFile: valid file" {
    const allocator = testing.allocator;
    const content =
        \\# tckts | prefix: TEST | version: 1
        \\
        \\--- TEST-1
        \\type: feature
        \\status: done
        \\title: First ticket
        \\created: 2024-12-23
        \\
        \\This is the description.
        \\---
        \\
        \\--- TEST-2
        \\type: bug
        \\status: pending
        \\title: Second ticket
        \\created: 2024-12-23
        \\depends: TEST-1
        \\priority: high
        \\
        \\Another description.
        \\---
    ;

    var project = try parseFile(allocator, content);
    defer project.deinit();

    try testing.expectEqualStrings("TEST", project.prefix);
    try testing.expectEqual(@as(usize, 2), project.tickets.items.len);

    const t1 = project.findTicket(1).?;
    try testing.expectEqualStrings("First ticket", t1.title);
    try testing.expectEqual(Status.done, t1.status);
    try testing.expectEqual(TicketType.feature, t1.ticket_type);
    try testing.expectEqualStrings("This is the description.", t1.description);

    const t2 = project.findTicket(2).?;
    try testing.expectEqualStrings("Second ticket", t2.title);
    try testing.expectEqual(Status.pending, t2.status);
    try testing.expectEqual(TicketType.bug, t2.ticket_type);
    try testing.expectEqual(@as(usize, 1), t2.depends.len);
    try testing.expectEqual(Priority.high, t2.priority.?);
}

test "serializeProject: roundtrip" {
    const allocator = testing.allocator;

    var project = try Project.init(allocator, "ROUND");
    defer project.deinit();

    var dep_id = try TicketId.parse(allocator, "ROUND-1");
    defer dep_id.deinit(allocator);

    _ = try project.addTicket(.feature, "First ticket", "Description one", &.{}, .low);
    _ = try project.addTicket(.bug, "Second ticket", "Description two", &.{dep_id}, .high);

    // Mark first as done
    try project.markDone(1);

    const serialized = try serializeProject(allocator, &project);
    defer allocator.free(serialized);

    var parsed = try parseFile(allocator, serialized);
    defer parsed.deinit();

    try testing.expectEqualStrings("ROUND", parsed.prefix);
    try testing.expectEqual(@as(usize, 2), parsed.tickets.items.len);

    const t1 = parsed.findTicket(1).?;
    try testing.expectEqual(Status.done, t1.status);
    try testing.expectEqual(TicketType.feature, t1.ticket_type);
    try testing.expectEqual(Priority.low, t1.priority.?);

    const t2 = parsed.findTicket(2).?;
    try testing.expectEqual(Status.pending, t2.status);
    try testing.expectEqual(TicketType.bug, t2.ticket_type);
    try testing.expectEqual(@as(usize, 1), t2.depends.len);
}
