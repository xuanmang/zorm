# query-context-api Specification

## Purpose
TBD - created by archiving change implement-query-context. Update Purpose after archive.
## Requirements
### Requirement: QueryContext Structure

QueryContext MUST provide a wrapper around ArenaAllocator for query-scoped memory management.

#### Scenario: Create QueryContext with base allocator

**Given** a base allocator (e.g., `std.heap.GeneralPurposeAllocator`)
**When** `QueryContext.init(base_allocator)` is called
**Then** a QueryContext instance is returned
**And** the QueryContext wraps an initialized ArenaAllocator
**And** the base allocator is stored for reference

**Code Example**:
```zig
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
defer _ = gpa.deinit();
const allocator = gpa.allocator();

var ctx = QueryContext.init(allocator);
defer ctx.deinit();

try std.testing.expect(ctx.base_allocator.ptr == allocator.ptr);
```

#### Scenario: Deinitialize QueryContext

**Given** a QueryContext with allocated memory
**When** `ctx.deinit()` is called
**Then** all memory allocated via `ctx.allocator()` is freed
**And** the Arena is deinitialized
**And** no memory leaks occur

**Code Example**:
```zig
const allocator = std.testing.allocator;

var ctx = QueryContext.init(allocator);
defer ctx.deinit();

const buf1 = try ctx.allocator().alloc(u8, 100);
const buf2 = try ctx.allocator().alloc(u8, 200);

// Both allocations freed by ctx.deinit()
```

---

### Requirement: QueryContext Allocator Method

QueryContext MUST provide an `allocator()` method that returns the Arena's allocator interface.

#### Scenario: Get allocator from QueryContext

**Given** an initialized QueryContext
**When** `ctx.allocator()` is called
**Then** a valid `std.mem.Allocator` is returned
**And** allocations using this allocator are managed by the Arena

**Code Example**:
```zig
var ctx = QueryContext.init(std.testing.allocator);
defer ctx.deinit();

const temp_allocator = ctx.allocator();
const buffer = try temp_allocator.alloc(u8, 50);

try std.testing.expectEqual(@as(usize, 50), buffer.len);
// buffer freed automatically by ctx.deinit()
```

#### Scenario: Multiple allocations with QueryContext allocator

**Given** a QueryContext allocator
**When** multiple allocations are made
**Then** all allocations succeed
**And** all are freed with a single `ctx.deinit()`

**Code Example**:
```zig
var ctx = QueryContext.init(std.testing.allocator);
defer ctx.deinit();

const alloc = ctx.allocator();
const str1 = try alloc.dupe(u8, "SELECT");
const str2 = try alloc.dupe(u8, "FROM");
const str3 = try alloc.dupe(u8, "users");

// All three strings freed by ctx.deinit()
try std.testing.expectEqualStrings("SELECT", str1);
```

---

### Requirement: QueryContext Reset

QueryContext MUST provide a `reset()` method to clear allocations while retaining capacity.

#### Scenario: Reset QueryContext for reuse

**Given** a QueryContext with allocated memory
**When** `ctx.reset()` is called
**Then** all previously allocated memory is marked as free
**And** the Arena's capacity is retained
**And** new allocations can be made immediately

**Code Example**:
```zig
var ctx = QueryContext.init(std.testing.allocator);
defer ctx.deinit();

// First query
{
    const sql1 = try ctx.allocator().dupe(u8, "SELECT * FROM users");
    try std.testing.expectEqualStrings("SELECT * FROM users", sql1);
}

// Reset and reuse
ctx.reset();

// Second query
{
    const sql2 = try ctx.allocator().dupe(u8, "SELECT * FROM posts");
    try std.testing.expectEqualStrings("SELECT * FROM posts", sql2);
}
```

#### Scenario: Reset retains capacity

**Given** a QueryContext with allocated memory
**When** `ctx.reset()` is called
**Then** the Arena's internal capacity is preserved
**And** subsequent allocations do not trigger new system allocations (up to capacity)

**Code Example**:
```zig
var ctx = QueryContext.init(std.testing.allocator);
defer ctx.deinit();

// Allocate 1KB
_ = try ctx.allocator().alloc(u8, 1024);

// Reset but keep capacity
ctx.reset();

// Allocate again (should reuse capacity)
_ = try ctx.allocator().alloc(u8, 512);

// No additional system allocations for the second alloc
```

---

### Requirement: Integration with Query Builders

Query builders MUST support optional QueryContext for temporary allocations.

#### Scenario: Query builder uses QueryContext for SQL building

**Given** a query builder and a QueryContext
**When** `buildSQL(ctx.allocator())` is called
**Then** SQL string is allocated using the QueryContext
**And** the SQL string is freed when `ctx.deinit()` is called

**Code Example**:
```zig
var ctx = QueryContext.init(std.testing.allocator);
defer ctx.deinit();

var db = try DB(.postgresql).init(std.testing.allocator, mock_conn, .{});
defer db.deinit();

var query = try db.newSelect(User);
defer query.deinit();

try query.where("age > ?", .{18});

// Use QueryContext for SQL building
const sql = try query.buildSQL(ctx.allocator());

try std.testing.expectEqual(true, std.mem.indexOf(u8, sql, "SELECT") != null);
// sql freed by ctx.deinit()
```

#### Scenario: Query builder without QueryContext (backward compatible)

**Given** a query builder without QueryContext
**When** `buildSQL(db.allocator)` is called
**Then** SQL string is allocated using DB's allocator
**And** caller is responsible for freeing the SQL string

**Code Example**:
```zig
var db = try DB(.postgresql).init(std.testing.allocator, mock_conn, .{});
defer db.deinit();

var query = try db.newSelect(User);
defer query.deinit();

// Traditional approach (no QueryContext)
const sql = try query.buildSQL(db.allocator);
defer db.allocator.free(sql); // Caller frees manually

try std.testing.expectEqual(true, std.mem.indexOf(u8, sql, "SELECT") != null);
```

---

### Requirement: Memory Leak Detection

QueryContext MUST work correctly with `std.testing.allocator` to detect memory leaks.

#### Scenario: No leaks with proper cleanup

**Given** QueryContext with std.testing.allocator
**When** allocations are made and `ctx.deinit()` is called
**Then** no memory leaks are detected
**And** the test passes

**Code Example**:
```zig
test "QueryContext no memory leaks" {
    const allocator = std.testing.allocator;

    var ctx = QueryContext.init(allocator);
    defer ctx.deinit();

    const buf1 = try ctx.allocator().alloc(u8, 100);
    const buf2 = try ctx.allocator().alloc(u8, 200);

    _ = buf1;
    _ = buf2;

    // std.testing.allocator will fail the test if ctx.deinit() is forgotten
}
```

#### Scenario: Test fails if deinit is forgotten

**Given** QueryContext with allocations
**When** `ctx.deinit()` is NOT called
**Then** std.testing.allocator detects the leak
**And** the test fails with a memory leak error

**Code Example**:
```zig
test "QueryContext leak detection" {
    const allocator = std.testing.allocator;

    var ctx = QueryContext.init(allocator);
    // defer ctx.deinit(); // Intentionally commented out

    _ = try ctx.allocator().alloc(u8, 100);

    // This test SHOULD fail due to missing deinit
}
```

---

### Requirement: Error Handling

QueryContext allocation failures MUST propagate errors correctly.

#### Scenario: Handle allocation failure gracefully

**Given** QueryContext with limited memory
**When** an allocation fails
**Then** the error is propagated to the caller
**And** previously allocated memory remains valid
**And** `ctx.deinit()` still works correctly

**Code Example**:
```zig
var ctx = QueryContext.init(std.testing.allocator);
defer ctx.deinit();

const buf = try ctx.allocator().alloc(u8, 100);

// Simulate allocation failure (contrived example)
const large_buf = ctx.allocator().alloc(u8, std.math.maxInt(usize)) catch |err| {
    try std.testing.expectEqual(error.OutOfMemory, err);
    // ctx.deinit() still safe to call
    return;
};

_ = buf;
_ = large_buf;
```

#### Scenario: errdefer cleanup with QueryContext

**Given** a function using QueryContext
**When** an error occurs after allocations
**Then** `errdefer ctx.deinit()` cleans up properly
**And** no memory is leaked

**Code Example**:
```zig
fn complexQuery(allocator: Allocator) ![]const u8 {
    var ctx = QueryContext.init(allocator);
    errdefer ctx.deinit();

    const sql_parts = try ctx.allocator().alloc([]const u8, 5);
    sql_parts[0] = "SELECT";
    sql_parts[1] = "FROM";
    // ... more parts

    // Simulate error
    if (sql_parts.len < 10) {
        return error.QueryBuildError;
        // ctx.deinit() called automatically via errdefer
    }

    defer ctx.deinit();
    return try std.mem.join(allocator, " ", sql_parts);
}
```

---

### Requirement: Documentation and Examples

QueryContext MUST have comprehensive documentation with usage examples.

#### Scenario: Basic usage example in documentation

**Given** QueryContext API documentation
**When** a developer reads the documentation
**Then** clear examples demonstrate basic usage
**And** examples show both with and without QueryContext

**Code Example**:
```zig
/// QueryContext - Arena-based memory management for query building
///
/// ## Basic Usage
/// ```zig
/// var ctx = QueryContext.init(allocator);
/// defer ctx.deinit();
///
/// const sql = try buildComplexSQL(ctx.allocator());
/// // sql freed automatically by ctx.deinit()
/// ```
///
/// ## Reusable Context
/// ```zig
/// var ctx = QueryContext.init(allocator);
/// defer ctx.deinit();
///
/// for (queries) |_| {
///     const sql = try buildSQL(ctx.allocator());
///     try execute(sql);
///     ctx.reset(); // Reuse for next query
/// }
/// ```
pub const QueryContext = struct {
    // ... implementation
};
```

#### Scenario: Performance comparison example

**Given** QueryContext documentation
**When** developers evaluate QueryContext vs direct allocation
**Then** benchmark examples demonstrate performance benefits

**Code Example**:
```zig
/// ## Performance Comparison
///
/// ### With QueryContext (Recommended)
/// ```zig
/// var ctx = QueryContext.init(allocator);
/// defer ctx.deinit();
///
/// for (0..1000) |_| {
///     const sql = try buildSQL(ctx.allocator());
///     try execute(sql);
///     ctx.reset();
/// }
/// // Single deinit at the end
/// ```
///
/// ### Without QueryContext
/// ```zig
/// for (0..1000) |_| {
///     const sql = try buildSQL(allocator);
///     defer allocator.free(sql); // 1000 individual frees
///     try execute(sql);
/// }
/// ```
```

