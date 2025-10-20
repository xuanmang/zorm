# Proposal: Implement QueryContext for Query Builder Memory Management

## Problem Statement

According to the functional specification section 2.1.2 (Memory Management Strategy), ZORM requires a `QueryContext` structure to optimize temporary memory allocations during query building using Arena allocators. Currently:

1. Query builders allocate temporary memory directly using the DB's allocator
2. Each SQL string, parameter array, and intermediate buffer requires individual deallocation
3. No mechanism exists for batch cleanup of query-scoped temporary allocations
4. Memory management overhead is higher than necessary for query building operations

This creates unnecessary complexity and potential for memory leaks in query construction.

## Proposed Solution

Implement `QueryContext` as defined in the functional specification:

1. Create a `QueryContext` struct that wraps `std.heap.ArenaAllocator`
2. Provide initialization with a base allocator and automatic cleanup via `deinit()`
3. Expose an `allocator()` method for query-scoped allocations
4. Add a `reset()` method for reusing QueryContext across multiple queries
5. Integrate QueryContext into query builder workflows

## Benefits

- **Simplified Memory Management**: Single `defer ctx.deinit()` replaces multiple individual `defer` statements
- **Performance**: Arena allocation is faster than individual allocations
- **Safety**: Impossible to forget freeing query-scoped memory
- **Alignment**: Matches the functional specification design
- **Reusability**: QueryContext can be reset and reused for multiple queries

## Scope

### In Scope
- QueryContext struct implementation in `src/allocator.zig`
- Integration with query builders (SELECT, INSERT, UPDATE, DELETE)
- Comprehensive unit tests
- Documentation and usage examples

### Out of Scope
- Changes to DB-level allocator management
- Connection pool memory management
- Result set memory management (separate concern)

## Implementation Strategy

1. Add QueryContext to `src/allocator.zig` alongside existing utilities
2. Update query builders to accept optional QueryContext parameter
3. Add tests demonstrating memory leak prevention
4. Document usage patterns in query building scenarios

## Dependencies

- Builds on existing `db-memory-management` specification
- No breaking changes to existing APIs
- Backward compatible: QueryContext is optional, defaults to DB allocator

## Risks and Mitigations

**Risk**: Increased API complexity with optional QueryContext parameter
**Mitigation**: Provide clear documentation and examples; QueryContext is optional

**Risk**: Incorrect scope of Arena usage (too broad or too narrow)
**Mitigation**: Follow functional spec guidance; scope to query building only

## Success Criteria

1. QueryContext struct implemented per functional spec
2. All tests pass with `std.testing.allocator` (no leaks)
3. Example code demonstrates QueryContext usage
4. Performance benchmark shows Arena allocation benefits
5. Documentation clearly explains when to use QueryContext

## References

- Functional Specification: `docs/functional_spec.md` Section 2.1.2
- Existing Spec: `openspec/specs/db-memory-management/spec.md`
- Related Code: `src/allocator.zig`, `src/query/*.zig`
