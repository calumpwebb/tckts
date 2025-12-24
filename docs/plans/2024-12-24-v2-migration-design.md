# V2 Schema Migration Design

## Summary

Add a migration framework to tckts that:
1. Tracks status history with timestamps (TCKTS-3)
2. Cleans up top-level ticket fields
3. Provides automatic migration on every command
4. Includes manual `tckts migrate` command

## Schema Changes

### V1 (Current)
```json
{
  "id": "TCKTS-1",
  "status": "done",
  "created_at": "2024-12-23T10:00:00Z",
  "started_at": "2024-12-23T11:00:00Z",
  "completed_at": "2024-12-23T12:00:00Z",
  ...
}
```

### V2 (New)
```json
{
  "id": "TCKTS-1",
  "status": "done",
  "created_at": "2024-12-23T10:00:00Z",
  "history": [
    {"status": "pending", "at": "2024-12-23T10:00:00Z"},
    {"status": "in_progress", "at": "2024-12-23T11:00:00Z"},
    {"status": "done", "at": "2024-12-23T12:00:00Z"}
  ],
  ...
}
```

**Removed fields:** `started_at`, `completed_at` (moved into history)

**Added fields:** `history` array

## Migration Framework

### Command Hook

Every command runs migration check before dispatch:

```
main()
  → check if any project needs migration
  → if migration needed:
      → verify git repo exists (error if not)
      → verify .tckts/ is clean (error if dirty)
      → run migrations in sequence
      → update version in config.json
      → print "Migrated PROJECT to schema v2"
  → proceed with command
```

### Migration Registry

```zig
const migrations = [_]Migration{
    .{ .from_version = 1, .to_version = 2, .run = migrateV1ToV2 },
    // Future: .{ .from_version = 2, .to_version = 3, .run = migrateV2ToV3 },
};
```

### V1 → V2 Migration Logic

For each ticket:
1. Create `history` array
2. Add `{"status": "pending", "at": created_at}`
3. If `started_at` exists, add `{"status": "in_progress", "at": started_at}`
4. If `completed_at` exists, add `{"status": "done", "at": completed_at}`
5. Remove `started_at` and `completed_at` fields
6. Write updated ticket

Update config.json: `"version": 1` → `"version": 2`

## Manual Migration Command

```bash
tckts migrate              # Run pending migrations (with git safety)
tckts migrate --force      # Skip git safety checks
```

## Git Safety

Before auto-migration:
1. Check if in git repo → error: "Migration requires git repository"
2. Check `.tckts/` is clean → error: "Cannot migrate with uncommitted changes in .tckts/. Please commit or stash first."

`--force` flag bypasses both checks.

## Testing Strategy

### Fixtures

Generate real v1 test data using v1.3.0 CLI:

```bash
# Create test fixtures
tckts init TEST
tckts add "Pending ticket" -p TEST -t task
tckts add "Started ticket" -p TEST -t feature
tckts start TEST-2
tckts add "Done ticket" -p TEST -t bug
tckts start TEST-3
tckts done TEST-3
```

Save `.tckts/TEST.tckts` and `.tckts/config.json` as test fixtures.

### Migration Tests

```zig
test "migration: v1 to v2" {
    // Load v1 fixture
    // Run migration
    // Verify:
    //   - history array exists
    //   - started_at/completed_at removed
    //   - history entries match original timestamps
    //   - config version is 2
}

test "migration: already v2 is no-op" {
    // Verify v2 data passes through unchanged
}

test "migration: chain v1 → v2 → v3" {
    // Future: verify multi-step migrations work
}
```

## File Changes

| File | Changes |
|------|---------|
| `src/root.zig` | Add `history` field to Ticket, update parse/serialize |
| `src/migrations.zig` | New file - migration registry and logic |
| `src/main.zig` | Add migration hook before command dispatch |
| `src/cli/commands/migrate.zig` | New command |
| `src/cli/commands/show.zig` | Display history in ticket details |
| `test_fixtures/v1/` | V1 test data |

## Implementation Order

1. Generate v1 test fixtures (using current CLI)
2. Add `migrations.zig` with framework + v1→v2 migration
3. Add migration hook to `main.zig`
4. Update `Ticket` struct with history field
5. Update `parseFile`/`serializeProject` for v2
6. Add `migrate` command
7. Update `show` command to display history
8. Write migration tests
9. Manual testing
10. Release as v1.4.0 or v2.0.0
