const std = @import("std");

const fs = std.fs;
const json = std.json;
const mem = std.mem;
const fmt = std.fmt;
const testing = std.testing;

// --- constants ---

const format_version = 1;
const file_extension = ".tckts";
const config_filename = "config.json";

pub const default_tckts_dir = ".tckts";
pub const tckts_dir_env_var = "TCKTS_DIR";

/// Get the tckts directory - checks TCKTS_DIR env var, falls back to .tckts
fn getTcktsDirName() []const u8 {
    return std.posix.getenv(tckts_dir_env_var) orelse default_tckts_dir;
}

// Limits - ensure predictable memory usage and prevent abuse

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
const max_file_size_multiplier = 1000;

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

// JSONL format uses standard JSON - no escaping needed

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
    blocked,
    done,

    pub fn fromString(s: []const u8) ?Status {
        if (mem.eql(u8, s, "pending")) return .pending;
        if (mem.eql(u8, s, "in_progress")) return .in_progress;
        if (mem.eql(u8, s, "blocked")) return .blocked;
        if (mem.eql(u8, s, "done")) return .done;
        return null;
    }

    pub fn toString(self: Status) []const u8 {
        return switch (self) {
            .pending => "pending",
            .in_progress => "in_progress",
            .blocked => "blocked",
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

pub const ProjectMeta = struct {
    version: u32,
};

pub const Config = struct {
    default_project: ?[]const u8,
    projects: std.StringHashMap(ProjectMeta),

    pub fn deinit(self: *Config, allocator: std.mem.Allocator) void {
        if (self.default_project) |p| allocator.free(p);
        var iter = self.projects.keyIterator();
        while (iter.next()) |key| allocator.free(key.*);
        self.projects.deinit();
        self.* = undefined;
    }
};

const JsonProjectMeta = struct {
    version: u32 = format_version,
};

const JsonConfig = struct {
    default_project: ?[]const u8 = null,
    projects: ?std.json.ArrayHashMap(JsonProjectMeta) = null,
};

pub const ConfigError = error{
    ConfigNotFound,
    InvalidConfig,
};

/// Load config from .tckts/config.json
pub fn loadConfig(allocator: std.mem.Allocator) ConfigError!Config {
    const config_path = fmt.allocPrint(allocator, "{s}/{s}", .{ getTcktsDirName(), config_filename }) catch return error.ConfigNotFound;
    defer allocator.free(config_path);

    const cwd = fs.cwd();
    const file = cwd.openFile(config_path, .{}) catch return error.ConfigNotFound;
    defer file.close();

    const content = file.readToEndAlloc(allocator, 4096) catch return error.InvalidConfig;
    defer allocator.free(content);

    const parsed = json.parseFromSlice(JsonConfig, allocator, content, .{}) catch return error.InvalidConfig;
    defer parsed.deinit();

    const default_project: ?[]u8 = if (parsed.value.default_project) |p|
        allocator.dupe(u8, p) catch return error.InvalidConfig
    else
        null;
    errdefer if (default_project) |p| allocator.free(p);

    var projects = std.StringHashMap(ProjectMeta).init(allocator);
    errdefer {
        var iter = projects.keyIterator();
        while (iter.next()) |key| allocator.free(key.*);
        projects.deinit();
    }

    if (parsed.value.projects) |json_projects| {
        for (json_projects.map.keys(), json_projects.map.values()) |key, value| {
            const key_copy = allocator.dupe(u8, key) catch return error.InvalidConfig;
            projects.put(key_copy, ProjectMeta{ .version = value.version }) catch return error.InvalidConfig;
        }
    }

    return Config{ .default_project = default_project, .projects = projects };
}

/// Save config to .tckts/config.json
pub fn saveConfig(allocator: std.mem.Allocator, config: *const Config) !void {
    const tckts_dir = getTcktsDirName();
    const config_path = try fmt.allocPrint(allocator, "{s}/{s}", .{ tckts_dir, config_filename });
    defer allocator.free(config_path);

    const cwd = fs.cwd();

    // Ensure tckts directory exists
    cwd.makeDir(tckts_dir) catch |e| switch (e) {
        error.PathAlreadyExists => {},
        else => return e,
    };

    const file = try cwd.createFile(config_path, .{});
    defer file.close();

    // Build projects map for JSON output
    var json_projects: ?std.json.ArrayHashMap(JsonProjectMeta) = null;
    defer if (json_projects) |*jp| jp.deinit(allocator);

    if (config.projects.count() > 0) {
        var map = std.json.ArrayHashMap(JsonProjectMeta){};
        var iter = config.projects.iterator();
        while (iter.next()) |entry| {
            try map.map.put(allocator, entry.key_ptr.*, JsonProjectMeta{ .version = entry.value_ptr.version });
        }
        json_projects = map;
    }

    const json_options = json.Stringify.Options{ .emit_null_optional_fields = false };
    const json_content = try json.Stringify.valueAlloc(allocator, JsonConfig{
        .default_project = config.default_project,
        .projects = json_projects,
    }, json_options);
    defer allocator.free(json_content);

    try file.writeAll(json_content);
    try file.writeAll("\n");
}

pub const ParseError = error{
    InvalidHeader,
    InvalidTicket,
    InvalidTicketId,
    MissingRequiredField,
    OutOfMemory,
    InvalidFormat,
    InvalidJson,
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

// JSON structures for parsing JSONL format
const JsonHeader = struct {
    prefix: []const u8,
    version: u32,
};

const JsonTicket = struct {
    id: []const u8,
    type: []const u8,
    status: []const u8,
    title: []const u8,
    created_at: []const u8,
    started_at: ?[]const u8 = null,
    completed_at: ?[]const u8 = null,
    depends: ?[]const []const u8 = null,
    priority: ?[]const u8 = null,
    description: ?[]const u8 = null,
};

/// Parse a JSONL file into a Project
/// Format: Each line is a ticket JSON object (no header line)
pub fn parseFile(allocator: std.mem.Allocator, prefix: []const u8, content: []const u8) ParseError!Project {
    var project = Project.init(allocator, prefix) catch return error.OutOfMemory;
    errdefer project.deinit();

    var lines = mem.splitSequence(u8, content, "\n");

    // Parse ticket lines
    while (lines.next()) |line| {
        const trimmed = mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;

        const ticket = parseTicketJson(allocator, trimmed, project.prefix) catch |e| {
            return e;
        };
        project.tickets.append(allocator, ticket) catch return error.OutOfMemory;
        if (ticket.id.number >= project.next_number) {
            project.next_number = ticket.id.number + 1;
        }
    }

    return project;
}

fn parseTicketJson(allocator: std.mem.Allocator, line: []const u8, expected_prefix: []const u8) ParseError!Ticket {
    const parsed = json.parseFromSlice(JsonTicket, allocator, line, .{}) catch {
        return error.InvalidJson;
    };
    defer parsed.deinit();

    const jt = parsed.value;

    // Parse and validate ID
    var id = TicketId.parse(allocator, jt.id) catch return error.InvalidTicketId;
    errdefer id.deinit(allocator);

    // Verify prefix matches
    if (!mem.eql(u8, id.prefix, expected_prefix)) return error.InvalidTicketId;

    // Parse type and status
    const ticket_type = TicketType.fromString(jt.type) orelse return error.InvalidTicket;
    const status = Status.fromString(jt.status) orelse return error.InvalidTicket;

    // Copy strings
    const title_copy = allocator.dupe(u8, jt.title) catch return error.OutOfMemory;
    errdefer allocator.free(title_copy);

    const created_at_copy = allocator.dupe(u8, jt.created_at) catch return error.OutOfMemory;
    errdefer allocator.free(created_at_copy);

    const started_at_copy: ?[]u8 = if (jt.started_at) |s|
        allocator.dupe(u8, s) catch return error.OutOfMemory
    else
        null;
    errdefer if (started_at_copy) |s| allocator.free(s);

    const completed_at_copy: ?[]u8 = if (jt.completed_at) |c|
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

    if (jt.depends) |deps| {
        for (deps) |dep_str| {
            const dep_id = TicketId.parse(allocator, dep_str) catch return error.InvalidTicketId;
            depends.append(allocator, dep_id) catch return error.OutOfMemory;
        }
    }

    // Parse priority
    const priority: ?Priority = if (jt.priority) |p| Priority.fromString(p) else null;

    // Copy description
    const description = if (jt.description) |d|
        allocator.dupe(u8, d) catch return error.OutOfMemory
    else
        allocator.dupe(u8, "") catch return error.OutOfMemory;

    return Ticket{
        .id = id,
        .ticket_type = ticket_type,
        .status = status,
        .title = title_copy,
        .created_at = created_at_copy,
        .started_at = started_at_copy,
        .completed_at = completed_at_copy,
        .depends = depends.toOwnedSlice(allocator) catch return error.OutOfMemory,
        .priority = priority,
        .description = description,
    };
}

/// Serialize a Project to JSONL format
/// Each line is a ticket, sorted by created_at (no header line)
pub fn serializeProject(allocator: std.mem.Allocator, project: *const Project) ![]u8 {
    var buffer: std.ArrayList(u8) = .empty;
    errdefer buffer.deinit(allocator);

    const writer = buffer.writer(allocator);
    const json_options = json.Stringify.Options{ .emit_null_optional_fields = false };

    // Sort tickets by created_at (ascending) for deterministic output
    const sorted_indices = try allocator.alloc(usize, project.tickets.items.len);
    defer allocator.free(sorted_indices);
    for (sorted_indices, 0..) |*idx, i| {
        idx.* = i;
    }

    mem.sort(usize, sorted_indices, project.tickets.items, struct {
        pub fn lessThan(tickets: []const Ticket, a: usize, b: usize) bool {
            return mem.lessThan(u8, tickets[a].created_at, tickets[b].created_at);
        }
    }.lessThan);

    // Write tickets
    for (sorted_indices) |idx| {
        const ticket = project.tickets.items[idx];
        try writeTicketJson(allocator, writer, ticket, json_options);
        try writer.writeAll("\n");
    }

    return buffer.toOwnedSlice(allocator);
}

fn writeTicketJson(allocator: std.mem.Allocator, writer: anytype, ticket: Ticket, options: json.Stringify.Options) !void {
    // Build depends array as strings
    var depends_strs: ?[][]const u8 = null;
    defer if (depends_strs) |ds| allocator.free(ds);

    if (ticket.depends.len > 0) {
        var dep_list = try allocator.alloc([]const u8, ticket.depends.len);
        for (ticket.depends, 0..) |dep, i| {
            // Format as "PREFIX-N"
            dep_list[i] = try fmt.allocPrint(allocator, "{s}-{d}", .{ dep.prefix, dep.number });
        }
        depends_strs = dep_list;
    }
    defer if (depends_strs) |ds| {
        for (ds) |s| allocator.free(s);
    };

    // Format ticket ID
    const id_str = try fmt.allocPrint(allocator, "{s}-{d}", .{ ticket.id.prefix, ticket.id.number });
    defer allocator.free(id_str);

    // Build JSON object with proper field ordering
    const json_ticket = .{
        .id = id_str,
        .type = ticket.ticket_type.toString(),
        .status = ticket.status.toString(),
        .title = ticket.title,
        .created_at = ticket.created_at,
        .started_at = ticket.started_at,
        .completed_at = ticket.completed_at,
        .depends = depends_strs,
        .priority = if (ticket.priority) |p| p.toString() else null,
        .description = if (ticket.description.len > 0) ticket.description else null,
    };

    const ticket_json = try json.Stringify.valueAlloc(allocator, json_ticket, options);
    defer allocator.free(ticket_json);
    try writer.writeAll(ticket_json);
}

/// Get the path to the tckts directory
pub fn getTcktsDir(allocator: std.mem.Allocator) ![]u8 {
    const tckts_dir = getTcktsDirName();
    const cwd = fs.cwd();
    return cwd.realpathAlloc(allocator, tckts_dir) catch |e| switch (e) {
        error.FileNotFound => return allocator.dupe(u8, tckts_dir),
        else => return e,
    };
}

/// Get the path to a project file
pub fn getProjectPath(allocator: std.mem.Allocator, prefix: []const u8) ![]u8 {
    return fmt.allocPrint(allocator, "{s}/{s}{s}", .{ getTcktsDirName(), prefix, file_extension });
}

/// Initialize a new project
pub fn initProject(allocator: std.mem.Allocator, prefix: []const u8) !void {
    const tckts_dir = getTcktsDirName();
    const cwd = fs.cwd();

    // Create tckts directory if it doesn't exist
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

    // Add project to config
    var config = loadConfig(allocator) catch |e| switch (e) {
        error.ConfigNotFound => Config{
            .default_project = null,
            .projects = std.StringHashMap(ProjectMeta).init(allocator),
        },
        else => return e,
    };
    defer config.deinit(allocator);

    const prefix_copy = try allocator.dupe(u8, prefix);
    try config.projects.put(prefix_copy, ProjectMeta{ .version = format_version });
    try saveConfig(allocator, &config);

    // Write initial content (empty file - no tickets yet)
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

    const content = try file.readToEndAlloc(allocator, max_description_length_bytes * max_file_size_multiplier);
    defer allocator.free(content);

    return parseFile(allocator, prefix, content);
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
    var dir = cwd.openDir(getTcktsDirName(), .{ .iterate = true }) catch |e| switch (e) {
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

test "parseFile: valid JSONL file" {
    const allocator = testing.allocator;
    const content =
        \\{"id":"TEST-1","type":"feature","status":"done","title":"First ticket","created_at":"2024-12-23T10:30:00Z","description":"This is the description."}
        \\{"id":"TEST-2","type":"bug","status":"pending","title":"Second ticket","created_at":"2024-12-23T10:30:00Z","depends":["TEST-1"],"priority":"high","description":"Another description."}
    ;

    var project = try parseFile(allocator, "TEST", content);
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

    var parsed = try parseFile(allocator, "ROUND", serialized);
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

test "parseFile: missing required field" {
    const allocator = testing.allocator;
    const content =
        \\{"id":"TEST-1","type":"feature","status":"done","created_at":"2024-12-23T10:30:00Z"}
    ;
    // Missing title field - JSON parser will reject
    try testing.expectError(error.InvalidJson, parseFile(allocator, "TEST", content));
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

    // Empty file - no tickets, no header
    try testing.expectEqualStrings("", serialized);

    var parsed = try parseFile(allocator, "EMPTY", serialized);
    defer parsed.deinit();

    try testing.expectEqualStrings("EMPTY", parsed.prefix);
    try testing.expectEqual(@as(usize, 0), parsed.tickets.items.len);
}

test "parseFile: ticket with empty description" {
    const allocator = testing.allocator;
    const content =
        \\{"id":"TEST-1","type":"task","status":"pending","title":"No description ticket","created_at":"2024-12-23T10:30:00Z"}
    ;

    var project = try parseFile(allocator, "TEST", content);
    defer project.deinit();

    const t = project.findTicket(1).?;
    try testing.expectEqualStrings("", t.description);
}

test "parseFile: ticket with multiline description" {
    const allocator = testing.allocator;
    const content =
        \\{"id":"TEST-1","type":"feature","status":"pending","title":"Multi-line description","created_at":"2024-12-23T10:30:00Z","description":"Line one.\nLine two.\nLine three."}
    ;

    var project = try parseFile(allocator, "TEST", content);
    defer project.deinit();

    const t = project.findTicket(1).?;
    try testing.expectEqualStrings("Line one.\nLine two.\nLine three.", t.description);
}

test "parseFile: multiple dependencies" {
    const allocator = testing.allocator;
    const content =
        \\{"id":"TEST-1","type":"task","status":"done","title":"First","created_at":"2024-12-23T10:30:00Z"}
        \\{"id":"TEST-2","type":"task","status":"done","title":"Second","created_at":"2024-12-23T10:30:00Z"}
        \\{"id":"TEST-3","type":"task","status":"pending","title":"Third depends on both","created_at":"2024-12-23T10:30:00Z","depends":["TEST-1","TEST-2"]}
    ;

    var project = try parseFile(allocator, "TEST", content);
    defer project.deinit();

    const t3 = project.findTicket(3).?;
    try testing.expectEqual(@as(usize, 2), t3.depends.len);
}
