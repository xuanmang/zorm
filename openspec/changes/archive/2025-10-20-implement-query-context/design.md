# Design: QueryContext Implementation

## Overview

This document describes the architectural design for implementing `QueryContext`, a memory management utility that uses Arena allocation to optimize temporary allocations during query building.

## Architecture

### Component Structure

```
┌─────────────────────────────────────────┐
│           Query Builder                 │
│  (SELECT/INSERT/UPDATE/DELETE)          │
└─────────────┬───────────────────────────┘
              │ uses (optional)
              ▼
┌─────────────────────────────────────────┐
│         QueryContext                    │
│  ┌─────────────────────────────────┐   │
│  │   ArenaAllocator                │   │
│  │   - base_allocator: Allocator   │   │
│  │   - arena: ArenaAllocator       │   │
│  └─────────────────────────────────┘   │
└─────────────────────────────────────────┘
              │ wraps
              ▼
┌─────────────────────────────────────────┐
│    std.heap.ArenaAllocator              │
│  - Fast batch allocations               │
│  - Single deinit() cleanup              │
└─────────────────────────────────────────┘
```

### Data Flow

```
1. Query Builder Creation
   DB.newSelect(User)
   → Query builder receives DB allocator

2. QueryContext Usage (Optional)
   var ctx = QueryContext.init(db.allocator);
   defer ctx.deinit();

   → Query builder uses ctx.allocator() for:
      - SQL string building
      - Parameter array allocation
      - WHERE clause buffers
      - JOIN condition buffers

3. Query Execution
   query.scan(&users)
   → Persistent allocations use DB allocator
   → Temporary allocations use QueryContext

4. Cleanup
   ctx.deinit() → Frees all temporary memory at once
```

## API Design

### QueryContext Structure

```zig
pub const QueryContext = struct {
    arena: std.heap.ArenaAllocator,
    base_allocator: Allocator,

    pub fn init(base_allocator: Allocator) QueryContext;
    pub fn deinit(self: *QueryContext) void;
    pub fn allocator(self: *QueryContext) Allocator;
    pub fn reset(self: *QueryContext) void;
};
```

### Integration Points

1. **Query Builders**: Accept optional `?*QueryContext` parameter
2. **SQL Building**: Use `ctx.allocator()` for string operations
3. **Parameter Collection**: Use `ctx.allocator()` for temporary arrays
4. **Result Scanning**: Use DB allocator (persistent data)

## Memory Ownership Model

### Temporary Allocations (QueryContext Arena)
- SQL string buffers during building
- Parameter arrays during query construction
- WHERE clause condition strings
- JOIN clause temporary buffers
- Column name lists during SELECT building

**Lifetime**: From query start to query execution complete

### Persistent Allocations (DB Allocator)
- Query result data (scanned rows)
- User-provided destination buffers
- Connection pool resources
- Query hooks

**Lifetime**: Determined by caller

## Usage Patterns

### Pattern 1: Single Query (Recommended for One-Off Queries)

```zig
pub fn queryUsers(db: *DB) !void {
    var ctx = QueryContext.init(db.allocator);
    defer ctx.deinit();

    var query = try db.newSelect(User);
    defer query.deinit();

    // Use ctx.allocator() for temporary allocations
    try query.where("age > ?", .{18});
    const sql = try query.buildSQL(ctx.allocator());

    var users = std.ArrayList(User).init(db.allocator);
    defer users.deinit();

    try query.scan(&users);
    // ctx.deinit() cleans up all temporary SQL building memory
}
```

### Pattern 2: Reusable Context (Recommended for Multiple Queries)

```zig
pub fn batchQueries(db: *DB) !void {
    var ctx = QueryContext.init(db.allocator);
    defer ctx.deinit();

    for (users) |user| {
        var query = try db.newSelect(Post);
        defer query.deinit();

        try query.where("user_id = ?", .{user.id});
        const sql = try query.buildSQL(ctx.allocator());

        // Execute query...

        ctx.reset(); // Reuse context for next query
    }
}
```

### Pattern 3: Default Behavior (No QueryContext)

```zig
pub fn simpleQuery(db: *DB) !void {
    var query = try db.newSelect(User);
    defer query.deinit();

    // Uses DB allocator directly (backward compatible)
    try query.where("age > ?", .{18});
    const sql = try query.buildSQL(db.allocator);

    // Works, but requires individual memory management
}
```

## Performance Considerations

### Arena Allocation Benefits
- **Batch Deallocation**: Single `deinit()` vs multiple `free()` calls
- **Allocation Speed**: Arena allocation is O(1) for small allocations
- **Cache Locality**: Sequential allocations improve CPU cache usage
- **Reduced Fragmentation**: No heap fragmentation from many small frees

### Measurement Plan
```zig
test "arena vs standard allocator benchmark" {
    // Benchmark 1000 queries with QueryContext
    // vs 1000 queries with standard allocator
    // Expected: 20-30% faster with Arena
}
```

## Testing Strategy

### Unit Tests

1. **Basic Lifecycle**
   ```zig
   test "QueryContext init and deinit"
   test "QueryContext allocator returns valid Allocator"
   test "QueryContext reset clears memory"
   ```

2. **Memory Leak Detection**
   ```zig
   test "no leaks with std.testing.allocator"
   test "multiple allocations cleaned up"
   test "reset does not leak"
   ```

3. **Integration with Queries**
   ```zig
   test "SELECT query uses QueryContext"
   test "INSERT query uses QueryContext"
   test "complex query with multiple allocations"
   ```

### Integration Tests

1. Query building with QueryContext
2. Multiple queries reusing same QueryContext
3. Mixed usage (some queries with, some without QueryContext)

## Error Handling

### Allocation Failures
```zig
var ctx = QueryContext.init(allocator);
defer ctx.deinit();

const buf = ctx.allocator().alloc(u8, size) catch |err| {
    // ctx.deinit() still called via defer
    return err;
};
```

### Query Execution Failures
```zig
const sql = try query.buildSQL(ctx.allocator());
query.execute(sql) catch |err| {
    // ctx.deinit() cleans up SQL string memory
    return err;
};
```

## Backward Compatibility

### No Breaking Changes
- QueryContext is **optional**
- Existing code continues to work unchanged
- Query builders accept `?*QueryContext` (nullable)
- Default to DB allocator if QueryContext is null

### Migration Path
1. **Phase 1**: Add QueryContext, all existing code works
2. **Phase 2**: Gradually adopt QueryContext in examples
3. **Phase 3**: Document best practices and performance benefits

## Design Decisions

### Decision 1: Arena vs Individual Allocations

**Options Considered:**
1. Continue using DB allocator directly
2. Pool of reusable buffers
3. Arena allocator wrapper (chosen)

**Rationale:**
- Arena provides best balance of simplicity and performance
- Matches functional specification design
- Proven pattern in Zig ecosystem

### Decision 2: Optional vs Required QueryContext

**Options Considered:**
1. Make QueryContext required for all queries
2. Make QueryContext optional (chosen)

**Rationale:**
- Backward compatibility preserved
- Gradual adoption path
- Flexibility for different use cases

### Decision 3: Location of QueryContext

**Options Considered:**
1. Separate module `src/query/context.zig`
2. Part of `src/allocator.zig` (chosen)

**Rationale:**
- Logical grouping with other memory utilities
- Easier to discover alongside `allocArgs()`, `dupeString()`, etc.
- Avoids creating many small modules

## Future Extensions

### Possible Enhancements (Out of Current Scope)

1. **QueryContext Pool**: Reuse QueryContext instances across requests
2. **Size Hints**: Pre-allocate Arena capacity based on query complexity
3. **Metrics**: Track Arena usage statistics for optimization
4. **Scoped Contexts**: Nested QueryContext for sub-queries

## References

- Functional Specification: `docs/functional_spec.md` Section 2.1.2
- Zig Arena Allocator: `std.heap.ArenaAllocator`
- Related Spec: `openspec/specs/db-memory-management/spec.md`
