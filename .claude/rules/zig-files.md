---
paths: "**/*.zig"
---

# Zig File Rules

These rules are **enforced** when working with `.zig` files in Nebula.

## File Structure (Strict Order)

1. **Imports** — std first, then packages, then local (blank lines between groups)
2. **Constants** — after `// --- constants ---`
3. **Types** — after `// --- types ---`, main type first
4. **Tests** — after `// --- tests ---` at bottom

## Naming (Enforced)

- **Types**: PascalCase (`TaskScheduler`)
- **Functions**: snake_case (`process_event`)
- **Constants**: snake_case with units (`timeout_ms`, `buffer_size_bytes`)
- **Enums**: PascalCase type, snake_case values

## Required Unit Suffixes

All numeric constants MUST have unit suffix:

- `_ms` — milliseconds
- `_ns` — nanoseconds
- `_bytes` — byte counts
- `_ticks` — timer ticks

```zig
// ✓ Required
const timeout_ms = 5000;

// ✗ Rejected
const timeout = 5000;
```

## No Magic Numbers

Only `0` and `1` allowed inline. All others must be named constants.

## Error Handling

- Custom error sets per module (no `anyerror` in core logic)
- Use `orelse unreachable` (not `.?`) for invariants
- `@panic` only for impossible states / bugs

## Memory

- `errdefer` immediately after allocation
- Pre-allocate hot paths
- Structs with resources must have `deinit()`

## Assertions

Average 2+ assertions per function. Assert preconditions, postconditions, invariants.

## Methods Order (Within Structs)

1. Internal type definitions
2. Fields
3. `init` / `deinit` (lifecycle)
4. Public methods
5. Private methods

## Tests

- Located at file bottom after `// --- tests ---`
- Named: `test "Type: behavior description"`
- Use `const testing = std.testing;`
- Shared helpers encouraged

## Comments

- `///` doc comments on public API only
- `//` comments explain WHY, not WHAT
- Section markers: `// --- section ---`

## Visibility

Default to private. Only `pub` what's needed externally.
