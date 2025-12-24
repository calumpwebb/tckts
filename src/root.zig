const std = @import("std");

const fs = std.fs;
const mem = std.mem;
const fmt = std.fmt;
const testing = std.testing;

// --- constants ---

const format_version = 1;
const tckts_dir = ".tckts";
const file_extension = ".tckts";

// --- limits ---
// These limits ensure predictable memory usage and prevent abuse

/// Max title length (single line, ~Twitter length)
pub const max_title_length_bytes = 280;

/// Max description length (generous - a full document)
pub const max_description_length_bytes = 64 * 1024; // 64KB

/// Max tickets per project
pub const max_tickets_per_project = 10_000;

/// Max prefix length
pub const max_prefix_length_bytes = 32;

/// Max dependencies per ticket
pub const max_dependencies_per_ticket = 100;

// Internal constants
const max_line_length_bytes = 4096;
const timestamp_length_bytes = 20; // "YYYY-MM-DDTHH:MM:SSZ"

// --- helpers ---

/// Format current time as UTC ISO 8601 timestamp (e.g., "2025-12-23T10:30:45Z")
fn formatUtcTimestamp(allocator: std.mem.Allocator) ![]u8 {
    const timestamp = std.time.timestamp();
    const epoch_secs: u64 = @intCast(timestamp);

    const secs_per_day = std.time.s_per_day;
    const secs_per_hour = std.time.s_per_hour;
    const secs_per_min = std.time.s_per_min;

    const epoch_day = std.time.epoch.EpochDay{ .day = @intCast(epoch_secs / secs_per_day) };
    const year_day = epoch_day.calculateYearDay();
    const month_day = year_day.calculateMonthDay();

    const day_secs = epoch_secs % secs_per_day;
    const hour: u8 = @intCast(day_secs / secs_per_hour);
    const minute: u8 = @intCast((day_secs % secs_per_hour) / secs_per_min);
    const second: u8 = @intCast(day_secs % secs_per_min);

    var buf: [timestamp_length_bytes]u8 = undefined;
    const timestamp_str = fmt.bufPrint(&buf, "{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}Z", .{
        year_day.year,
        @intFromEnum(month_day.month),
        month_day.day_index + 1,
        hour,
        minute,
        second,
    }) catch unreachable;

    return allocator.dupe(u8, timestamp_str);
}

/// Escape description content to prevent format injection
fn escapeDescription(allocator: std.mem.Allocator, description: []const u8) ![]u8 {
    // Escape lines starting with "---" by prefixing with a backslash
    var result: std.ArrayList(u8) = .empty;
    errdefer result.deinit(allocator);

    var lines = mem.splitSequence(u8, description, "\n");
    var first = true;
    while (lines.next()) |line| {
        if (!first) try result.append(allocator, '\n');
        first = false;

        const trimmed = mem.trimLeft(u8, line, " \t");
        if (mem.startsWith(u8, trimmed, "---")) {
            try result.append(allocator, '\\');
        }
        try result.appendSlice(allocator, line);
    }

    return result.toOwnedSlice(allocator);
}

/// Unescape description content
fn unescapeDescription(allocator: std.mem.Allocator, escaped: []const u8) ![]u8 {
    var result: std.ArrayList(u8) = .empty;
    errdefer result.deinit(allocator);

    var lines = mem.splitSequence(u8, escaped, "\n");
    var first = true;
    while (lines.next()) |line| {
        if (!first) try result.append(allocator, '\n');
        first = false;

        // Unescape lines that start with \---
        const trimmed = mem.trimLeft(u8, line, " \t");
        const leading_spaces = line.len - trimmed.len;
        if (mem.startsWith(u8, trimmed, "\\---")) {
            try result.appendSlice(allocator, line[0..leading_spaces]);
            try result.appendSlice(allocator, trimmed[1..]);
        } else {
            try result.appendSlice(allocator, line);
        }
    }

    return result.toOwnedSlice(allocator);
}

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
    epic,

    pub fn fromString(s: []const u8) ?TicketType {
        if (mem.eql(u8, s, "bug")) return .bug;
        if (mem.eql(u8, s, "feature")) return .feature;
        if (mem.eql(u8, s, "task")) return .task;
        if (mem.eql(u8, s, "chore")) return .chore;
        if (mem.eql(u8, s, "epic")) return .epic;
        return null;
    }

    pub fn toString(self: TicketType) []const u8 {
        return switch (self) {
            .bug => "bug",
            .feature => "feature",
            .task => "task",
            .chore => "chore",
            .epic => "epic",
        };
    }
};

pub const Status = enum {
    pending,
    in_progress,
    done,

    pub fn fromString(s: []const u8) ?Status {
        if (mem.eql(u8, s, "pending")) return .pending;
        if (mem.eql(u8, s, "in_progress")) return .in_progress;
        if (mem.eql(u8, s, "done")) return .done;
        return null;
    }

    pub fn toString(self: Status) []const u8 {
        return switch (self) {
            .pending => "pending",
            .in_progress => "in_progress",
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
    created_at: []const u8,
    started_at: ?[]const u8,
    completed_at: ?[]const u8,
    depends: []TicketId,
    priority: ?Priority,
    description: []const u8,

    pub fn deinit(self: *Ticket, allocator: std.mem.Allocator) void {
        allocator.free(self.id.prefix);
        allocator.free(self.title);
        allocator.free(self.created_at);
        if (self.started_at) |s| allocator.free(s);
        if (self.completed_at) |c| allocator.free(c);
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
        if (prefix.len > max_prefix_length_bytes) return error.PrefixTooLong;

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
        // Validate limits
        if (title.len > max_title_length_bytes) return error.TitleTooLong;
        if (description.len > max_description_length_bytes) return error.DescriptionTooLong;
        if (self.tickets.items.len >= max_tickets_per_project) return error.TooManyTickets;
        if (depends.len > max_dependencies_per_ticket) return error.TooManyDependencies;

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

        // Get current UTC timestamp
        const created_at = try formatUtcTimestamp(self.allocator);
        errdefer self.allocator.free(created_at);

        const ticket = Ticket{
            .id = TicketId{ .prefix = prefix_copy, .number = self.next_number },
            .ticket_type = ticket_type,
            .status = .pending,
            .title = title_copy,
            .created_at = created_at,
            .started_at = null,
            .completed_at = null,
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

    pub fn markInProgress(self: *Project, number: u32) !void {
        const ticket = self.findTicket(number) orelse return error.TicketNotFound;
        if (ticket.status == .done) return error.AlreadyDone;

        ticket.status = .in_progress;
        if (ticket.started_at) |old| self.allocator.free(old);
        ticket.started_at = try formatUtcTimestamp(self.allocator);
    }

    pub fn markDone(self: *Project, number: u32) !void {
        const ticket = self.findTicket(number) orelse return error.TicketNotFound;
        ticket.status = .done;
        if (ticket.completed_at) |old| self.allocator.free(old);
        ticket.completed_at = try formatUtcTimestamp(self.allocator);
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

pub const ValidationError = error{
    TitleTooLong,
    DescriptionTooLong,
    TooManyTickets,
    TooManyDependencies,
    PrefixTooLong,
};

/// Parse a .tckts file into a Project
pub fn parseFile(allocator: std.mem.Allocator, content: []const u8) ParseError!Project {
    var lines = mem.splitSequence(u8, content, "\n");

    // Parse header
    const header = lines.next() orelse return error.InvalidHeader;
    const prefix = parseHeader(header) orelse return error.InvalidHeader;

    var project = Project.init(allocator, prefix) catch return error.OutOfMemory;
    errdefer project.deinit();

    // Parse ticket blocks - blocks are delimited by --- lines
    var in_block = false;
    var block_start: usize = 0;
    var pos: usize = header.len + 1;

    while (lines.next()) |line| {
        const trimmed = mem.trim(u8, line, " \t");

        // Check for block delimiter (--- but not escaped \---)
        if (mem.eql(u8, trimmed, "---")) {
            if (in_block) {
                // End of block - process it
                const block_content = content[block_start .. pos + line.len];
                const ticket = parseTicketBlock(allocator, block_content, prefix) catch |e| {
                    return e;
                };
                project.tickets.append(allocator, ticket) catch return error.OutOfMemory;
                if (ticket.id.number >= project.next_number) {
                    project.next_number = ticket.id.number + 1;
                }
                in_block = false;
            } else {
                // Start of block
                in_block = true;
                block_start = pos;
            }
        }
        pos += line.len + 1;
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

    // First line: --- (block separator)
    const first_line = lines.next() orelse return error.InvalidTicketBlock;
    const trimmed_first = mem.trim(u8, first_line, " \t");
    if (!mem.startsWith(u8, trimmed_first, "---")) return error.InvalidTicketBlock;

    // Parse metadata lines until empty line
    var id_str: ?[]const u8 = null;
    var ticket_type: ?TicketType = null;
    var status: ?Status = null;
    var title: ?[]const u8 = null;
    var created_at: ?[]const u8 = null;
    var started_at: ?[]const u8 = null;
    var completed_at: ?[]const u8 = null;
    var depends_str: ?[]const u8 = null;
    var priority: ?Priority = null;
    var in_description = false;
    var description_lines: std.ArrayList([]const u8) = .empty;
    defer description_lines.deinit(allocator);

    while (lines.next()) |line| {
        const trimmed = mem.trim(u8, line, " \t");

        // Check for end of block marker (but not escaped \---)
        if (mem.startsWith(u8, trimmed, "---") and !mem.startsWith(u8, trimmed, "\\---")) break;

        if (in_description) {
            description_lines.append(allocator, line) catch return error.OutOfMemory;
            continue;
        }

        if (trimmed.len == 0) {
            in_description = true;
            continue;
        }

        // Parse metadata
        if (mem.startsWith(u8, trimmed, "id:")) {
            id_str = mem.trim(u8, trimmed["id:".len..], " \t");
        } else if (mem.startsWith(u8, trimmed, "type:")) {
            const val = mem.trim(u8, trimmed["type:".len..], " \t");
            ticket_type = TicketType.fromString(val);
        } else if (mem.startsWith(u8, trimmed, "status:")) {
            const val = mem.trim(u8, trimmed["status:".len..], " \t");
            status = Status.fromString(val);
        } else if (mem.startsWith(u8, trimmed, "title:")) {
            title = mem.trim(u8, trimmed["title:".len..], " \t");
        } else if (mem.startsWith(u8, trimmed, "created_at:")) {
            created_at = mem.trim(u8, trimmed["created_at:".len..], " \t");
        } else if (mem.startsWith(u8, trimmed, "started_at:")) {
            started_at = mem.trim(u8, trimmed["started_at:".len..], " \t");
        } else if (mem.startsWith(u8, trimmed, "completed_at:")) {
            completed_at = mem.trim(u8, trimmed["completed_at:".len..], " \t");
        } else if (mem.startsWith(u8, trimmed, "depends:")) {
            depends_str = mem.trim(u8, trimmed["depends:".len..], " \t");
        } else if (mem.startsWith(u8, trimmed, "priority:")) {
            const val = mem.trim(u8, trimmed["priority:".len..], " \t");
            priority = Priority.fromString(val);
        }
    }

    // Validate required fields
    if (id_str == null or ticket_type == null or status == null or title == null or created_at == null) {
        return error.MissingRequiredField;
    }

    // Parse and validate ID
    var id = TicketId.parse(allocator, id_str.?) catch return error.InvalidTicketId;
    errdefer id.deinit(allocator);

    // Verify prefix matches
    if (!mem.eql(u8, id.prefix, expected_prefix)) return error.InvalidTicketId;

    // Copy strings
    const title_copy = allocator.dupe(u8, title.?) catch return error.OutOfMemory;
    errdefer allocator.free(title_copy);

    const created_at_copy = allocator.dupe(u8, created_at.?) catch return error.OutOfMemory;
    errdefer allocator.free(created_at_copy);

    const started_at_copy: ?[]u8 = if (started_at) |s|
        allocator.dupe(u8, s) catch return error.OutOfMemory
    else
        null;
    errdefer if (started_at_copy) |s| allocator.free(s);

    const completed_at_copy: ?[]u8 = if (completed_at) |c|
        allocator.dupe(u8, c) catch return error.OutOfMemory
    else
        null;
    errdefer if (completed_at_copy) |c| allocator.free(c);

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
    const desc_slice = desc_builder.toOwnedSlice(allocator) catch return error.OutOfMemory;
    defer allocator.free(desc_slice);

    const desc_trimmed = mem.trimRight(u8, desc_slice, " \t\n");

    // Unescape description content
    const unescaped_desc = unescapeDescription(allocator, desc_trimmed) catch return error.OutOfMemory;

    return Ticket{
        .id = id,
        .ticket_type = ticket_type.?,
        .status = status.?,
        .title = title_copy,
        .created_at = created_at_copy,
        .started_at = started_at_copy,
        .completed_at = completed_at_copy,
        .depends = depends.toOwnedSlice(allocator) catch return error.OutOfMemory,
        .priority = priority,
        .description = unescaped_desc,
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
        try writer.writeAll("\n---\n");
        try writer.print("id: {s}-{d}\n", .{ ticket.id.prefix, ticket.id.number });
        try writer.print("type: {s}\n", .{ticket.ticket_type.toString()});
        try writer.print("status: {s}\n", .{ticket.status.toString()});
        try writer.print("title: {s}\n", .{ticket.title});
        try writer.print("created_at: {s}\n", .{ticket.created_at});

        if (ticket.started_at) |s| {
            try writer.print("started_at: {s}\n", .{s});
        }

        if (ticket.completed_at) |c| {
            try writer.print("completed_at: {s}\n", .{c});
        }

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
            const escaped = try escapeDescription(allocator, ticket.description);
            defer allocator.free(escaped);
            try writer.writeAll(escaped);
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
        \\---
        \\id: TEST-1
        \\type: feature
        \\status: done
        \\title: First ticket
        \\created_at: 2024-12-23T10:30:00Z
        \\
        \\This is the description.
        \\---
        \\
        \\---
        \\id: TEST-2
        \\type: bug
        \\status: pending
        \\title: Second ticket
        \\created_at: 2024-12-23T10:30:00Z
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

test "parseFile: invalid header - missing prefix" {
    const allocator = testing.allocator;
    const content = "# tckts | version: 1\n";
    try testing.expectError(error.InvalidHeader, parseFile(allocator, content));
}

test "parseFile: invalid header - missing version" {
    const allocator = testing.allocator;
    const content = "# tckts | prefix: TEST\n";
    try testing.expectError(error.InvalidHeader, parseFile(allocator, content));
}

test "parseFile: invalid header - wrong version" {
    const allocator = testing.allocator;
    const content = "# tckts | prefix: TEST | version: 999\n";
    try testing.expectError(error.InvalidHeader, parseFile(allocator, content));
}

test "parseFile: missing required field" {
    const allocator = testing.allocator;
    const content =
        \\# tckts | prefix: TEST | version: 1
        \\
        \\---
        \\id: TEST-1
        \\type: feature
        \\status: done
        \\created_at: 2024-12-23T10:30:00Z
        \\---
    ;
    // Missing title field
    try testing.expectError(error.MissingRequiredField, parseFile(allocator, content));
}

test "Project: canComplete with no dependencies" {
    const allocator = testing.allocator;
    var project = try Project.init(allocator, "TEST");
    defer project.deinit();

    _ = try project.addTicket(.task, "Standalone ticket", "", &.{}, null);

    const blocking = try project.canComplete(1);
    defer allocator.free(blocking);

    try testing.expectEqual(@as(usize, 0), blocking.len);
}

test "Project: canComplete with incomplete dependency" {
    const allocator = testing.allocator;
    var project = try Project.init(allocator, "TEST");
    defer project.deinit();

    _ = try project.addTicket(.task, "First ticket", "", &.{}, null);

    var dep_id = try TicketId.parse(allocator, "TEST-1");
    defer dep_id.deinit(allocator);
    _ = try project.addTicket(.task, "Second ticket", "", &.{dep_id}, null);

    const blocking = try project.canComplete(2);
    defer allocator.free(blocking);

    try testing.expectEqual(@as(usize, 1), blocking.len);
    try testing.expectEqual(@as(u32, 1), blocking[0].number);
}

test "Project: canComplete with completed dependency" {
    const allocator = testing.allocator;
    var project = try Project.init(allocator, "TEST");
    defer project.deinit();

    _ = try project.addTicket(.task, "First ticket", "", &.{}, null);
    try project.markDone(1);

    var dep_id = try TicketId.parse(allocator, "TEST-1");
    defer dep_id.deinit(allocator);
    _ = try project.addTicket(.task, "Second ticket", "", &.{dep_id}, null);

    const blocking = try project.canComplete(2);
    defer allocator.free(blocking);

    try testing.expectEqual(@as(usize, 0), blocking.len);
}

test "Project: remove ticket clears dependencies" {
    const allocator = testing.allocator;
    var project = try Project.init(allocator, "TEST");
    defer project.deinit();

    _ = try project.addTicket(.task, "First ticket", "", &.{}, null);

    var dep_id = try TicketId.parse(allocator, "TEST-1");
    defer dep_id.deinit(allocator);
    _ = try project.addTicket(.task, "Second ticket", "", &.{dep_id}, null);

    // Remove the dependency
    try project.removeTicket(1);

    // Second ticket should no longer have dependencies
    const t2 = project.findTicket(2).?;
    try testing.expectEqual(@as(usize, 0), t2.depends.len);
}

test "Project: multiple tickets with chained dependencies" {
    const allocator = testing.allocator;
    var project = try Project.init(allocator, "CHAIN");
    defer project.deinit();

    _ = try project.addTicket(.task, "Task 1", "", &.{}, null);

    var dep1 = try TicketId.parse(allocator, "CHAIN-1");
    defer dep1.deinit(allocator);
    _ = try project.addTicket(.task, "Task 2 depends on 1", "", &.{dep1}, null);

    var dep2 = try TicketId.parse(allocator, "CHAIN-2");
    defer dep2.deinit(allocator);
    _ = try project.addTicket(.task, "Task 3 depends on 2", "", &.{dep2}, null);

    // Task 3 should be blocked by task 2
    const blocking3 = try project.canComplete(3);
    defer allocator.free(blocking3);
    try testing.expectEqual(@as(usize, 1), blocking3.len);
    try testing.expectEqual(@as(u32, 2), blocking3[0].number);

    // Task 2 should be blocked by task 1
    const blocking2 = try project.canComplete(2);
    defer allocator.free(blocking2);
    try testing.expectEqual(@as(usize, 1), blocking2.len);
    try testing.expectEqual(@as(u32, 1), blocking2[0].number);

    // Task 1 has no blockers
    const blocking1 = try project.canComplete(1);
    defer allocator.free(blocking1);
    try testing.expectEqual(@as(usize, 0), blocking1.len);
}

test "Project: markDone on nonexistent ticket" {
    const allocator = testing.allocator;
    var project = try Project.init(allocator, "TEST");
    defer project.deinit();

    try testing.expectError(error.TicketNotFound, project.markDone(999));
}

test "Project: removeTicket on nonexistent ticket" {
    const allocator = testing.allocator;
    var project = try Project.init(allocator, "TEST");
    defer project.deinit();

    try testing.expectError(error.TicketNotFound, project.removeTicket(999));
}

test "Project: canComplete on nonexistent ticket" {
    const allocator = testing.allocator;
    var project = try Project.init(allocator, "TEST");
    defer project.deinit();

    try testing.expectError(error.TicketNotFound, project.canComplete(999));
}

test "Project: findTicketById matches prefix" {
    const allocator = testing.allocator;
    var project = try Project.init(allocator, "ABC");
    defer project.deinit();

    _ = try project.addTicket(.task, "Test", "", &.{}, null);

    // Correct prefix
    var id1 = try TicketId.parse(allocator, "ABC-1");
    defer id1.deinit(allocator);
    try testing.expect(project.findTicketById(id1) != null);

    // Wrong prefix
    var id2 = try TicketId.parse(allocator, "XYZ-1");
    defer id2.deinit(allocator);
    try testing.expect(project.findTicketById(id2) == null);
}

test "TicketId: parse with hyphen in prefix" {
    const allocator = testing.allocator;
    var id = try TicketId.parse(allocator, "MY-PROJECT-42");
    defer id.deinit(allocator);

    try testing.expectEqualStrings("MY-PROJECT", id.prefix);
    try testing.expectEqual(@as(u32, 42), id.number);
}

test "serializeProject: empty project" {
    const allocator = testing.allocator;

    var project = try Project.init(allocator, "EMPTY");
    defer project.deinit();

    const serialized = try serializeProject(allocator, &project);
    defer allocator.free(serialized);

    try testing.expectEqualStrings("# tckts | prefix: EMPTY | version: 1\n", serialized);

    var parsed = try parseFile(allocator, serialized);
    defer parsed.deinit();

    try testing.expectEqualStrings("EMPTY", parsed.prefix);
    try testing.expectEqual(@as(usize, 0), parsed.tickets.items.len);
}

test "parseFile: ticket with empty description" {
    const allocator = testing.allocator;
    const content =
        \\# tckts | prefix: TEST | version: 1
        \\
        \\---
        \\id: TEST-1
        \\type: task
        \\status: pending
        \\title: No description ticket
        \\created_at: 2024-12-23T10:30:00Z
        \\---
    ;

    var project = try parseFile(allocator, content);
    defer project.deinit();

    const t = project.findTicket(1).?;
    try testing.expectEqualStrings("", t.description);
}

test "parseFile: ticket with multiline description" {
    const allocator = testing.allocator;
    const content =
        \\# tckts | prefix: TEST | version: 1
        \\
        \\---
        \\id: TEST-1
        \\type: feature
        \\status: pending
        \\title: Multi-line description
        \\created_at: 2024-12-23T10:30:00Z
        \\
        \\Line one.
        \\Line two.
        \\Line three.
        \\---
    ;

    var project = try parseFile(allocator, content);
    defer project.deinit();

    const t = project.findTicket(1).?;
    try testing.expectEqualStrings("Line one.\nLine two.\nLine three.", t.description);
}

test "parseFile: multiple dependencies" {
    const allocator = testing.allocator;
    const content =
        \\# tckts | prefix: TEST | version: 1
        \\
        \\---
        \\id: TEST-1
        \\type: task
        \\status: done
        \\title: First
        \\created_at: 2024-12-23T10:30:00Z
        \\---
        \\
        \\---
        \\id: TEST-2
        \\type: task
        \\status: done
        \\title: Second
        \\created_at: 2024-12-23T10:30:00Z
        \\---
        \\
        \\---
        \\id: TEST-3
        \\type: task
        \\status: pending
        \\title: Third depends on both
        \\created_at: 2024-12-23T10:30:00Z
        \\depends: TEST-1, TEST-2
        \\---
    ;

    var project = try parseFile(allocator, content);
    defer project.deinit();

    const t3 = project.findTicket(3).?;
    try testing.expectEqual(@as(usize, 2), t3.depends.len);
}
