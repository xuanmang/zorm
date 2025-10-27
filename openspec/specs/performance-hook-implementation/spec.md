# performance-hook-implementation Specification

## Purpose
TBD - created by archiving change implement-query-hook-observability. Update Purpose after archive.
## Requirements
### Requirement: PerformanceHook Structure
The system SHALL provide a PerformanceHook implementation that tracks query performance metrics including total queries, total duration, slow queries, and errors.

#### Scenario: PerformanceHook initialization
- **WHEN** PerformanceHook.init(slow_threshold_ms) is called
- **THEN** a new PerformanceHook instance SHALL be created
- **AND** slow_query_threshold_ns SHALL be set to slow_threshold_ms * 1_000_000
- **AND** all statistics SHALL be initialized to zero

#### Scenario: PerformanceHook implements QueryHook interface
- **GIVEN** a PerformanceHook instance
- **WHEN** hook() method is called
- **THEN** it SHALL return a QueryHook interface
- **AND** the QueryHook SHALL be compatible with DB.addHook()

### Requirement: Query Performance Tracking
PerformanceHook MUST track the total number of queries executed, total execution time, minimum query time, maximum query time, and average query time.

#### Scenario: Track first query
- **GIVEN** a newly initialized PerformanceHook
- **WHEN** afterQuery() is called with duration_ns = 1_500_000 (1.5ms)
- **THEN** total_queries SHALL equal 1
- **AND** total_duration_ns SHALL equal 1_500_000
- **AND** min_duration_ns SHALL equal 1_500_000
- **AND** max_duration_ns SHALL equal 1_500_000
- **AND** average_duration_ns SHALL equal 1_500_000

#### Scenario: Track multiple queries
- **GIVEN** a PerformanceHook with 5 queries already tracked
- **WHEN** afterQuery() is called with a new query (duration_ns = 2_000_000)
- **THEN** total_queries SHALL equal 6
- **AND** total_duration_ns SHALL include the new duration
- **AND** min_duration_ns SHALL be updated if the new duration is smaller
- **AND** max_duration_ns SHALL be updated if the new duration is larger
- **AND** average_duration_ns SHALL be recalculated as total_duration_ns / total_queries

#### Scenario: Statistics are thread-safe
- **GIVEN** a PerformanceHook shared across multiple threads
- **WHEN** concurrent queries trigger afterQuery() from different threads
- **THEN** all statistics SHALL be updated atomically
- **AND** total_queries SHALL match the actual number of queries executed
- **AND** no race conditions occur

### Requirement: Slow Query Detection
PerformanceHook MUST identify and count queries exceeding the configured slow query threshold.

#### Scenario: Detect slow query
- **GIVEN** a PerformanceHook with slow_threshold_ms = 1000 (1 second)
- **WHEN** afterQuery() is called with duration_ns = 2_000_000_000 (2 seconds)
- **THEN** slow_query_count SHALL increment by 1
- **AND** a warning log message SHALL be emitted containing the SQL and duration

#### Scenario: Fast query not counted as slow
- **GIVEN** a PerformanceHook with slow_threshold_ms = 1000
- **WHEN** afterQuery() is called with duration_ns = 500_000_000 (0.5 seconds)
- **THEN** slow_query_count SHALL NOT increment
- **AND** no slow query warning is logged

#### Scenario: Slow query threshold is configurable
- **GIVEN** PerformanceHook.init() is called with slow_threshold_ms = 500
- **WHEN** afterQuery() is called with duration_ns = 600_000_000 (0.6 seconds)
- **THEN** the query SHALL be counted as slow
- **AND** slow_query_count SHALL increment

### Requirement: Error Tracking
PerformanceHook MUST track the total number of query errors encountered.

#### Scenario: Track query error
- **GIVEN** a PerformanceHook with total_errors = 0
- **WHEN** onError() is called with any error
- **THEN** total_errors SHALL increment by 1
- **AND** the error SHALL be logged with SQL and arguments

#### Scenario: Multiple errors tracked
- **GIVEN** a PerformanceHook with 3 errors already tracked
- **WHEN** onError() is called again
- **THEN** total_errors SHALL equal 4
- **AND** error count is updated atomically

### Requirement: Statistics Retrieval
PerformanceHook MUST provide a getStats() method that returns a snapshot of current performance statistics.

#### Scenario: Retrieve performance statistics
- **GIVEN** a PerformanceHook with 10 queries executed
- **WHEN** getStats() is called
- **THEN** it SHALL return a PerformanceStats struct
- **AND** stats.total_queries SHALL equal 10
- **AND** stats.total_duration_ns SHALL be the sum of all query durations
- **AND** stats.average_duration_ns SHALL be total_duration_ns / total_queries
- **AND** stats.min_duration_ns and stats.max_duration_ns SHALL reflect actual values
- **AND** stats.slow_query_count and stats.total_errors SHALL be included

#### Scenario: Statistics snapshot is independent
- **GIVEN** a PerformanceStats snapshot is obtained
- **WHEN** new queries are executed after the snapshot
- **THEN** the snapshot values SHALL remain unchanged
- **AND** calling getStats() again SHALL return updated values

### Requirement: Hook Lifecycle Methods
PerformanceHook MUST implement beforeQuery() and onError() methods even though they don't update statistics, to maintain QueryHook interface compliance.

#### Scenario: beforeQuery is a no-op
- **GIVEN** a PerformanceHook instance
- **WHEN** beforeQuery(sql, args) is called
- **THEN** the method SHALL return without error
- **AND** no statistics are updated
- **AND** no side effects occur

#### Scenario: onError logs and counts
- **GIVEN** a PerformanceHook instance
- **WHEN** onError(sql, args, err) is called
- **THEN** total_errors SHALL increment
- **AND** an error log message SHALL be emitted
- **AND** the method completes without throwing

### Requirement: Reset Statistics
PerformanceHook MUST provide a reset() method to clear all statistics, enabling performance measurement for specific time windows.

#### Scenario: Reset all statistics
- **GIVEN** a PerformanceHook with 100 queries tracked
- **WHEN** reset() is called
- **THEN** total_queries SHALL be set to 0
- **AND** total_duration_ns SHALL be set to 0
- **AND** min_duration_ns and max_duration_ns SHALL be reset
- **AND** slow_query_count and total_errors SHALL be set to 0

#### Scenario: Statistics collection resumes after reset
- **GIVEN** a PerformanceHook that was reset
- **WHEN** new queries are executed
- **THEN** statistics SHALL accumulate from zero
- **AND** the first query sets min_duration_ns and max_duration_ns correctly

### Requirement: PerformanceStats Structure
The system SHALL provide a PerformanceStats struct containing all performance metrics for easy consumption by monitoring systems.

#### Scenario: PerformanceStats contains all metrics
- **WHEN** getStats() returns a PerformanceStats instance
- **THEN** it SHALL contain total_queries field (u64)
- **AND** total_duration_ns field (u64)
- **AND** average_duration_ns field (u64)
- **AND** min_duration_ns field (u64)
- **AND** max_duration_ns field (u64)
- **AND** slow_query_count field (u64)
- **AND** total_errors field (u64)

#### Scenario: Stats are formatted for display
- **GIVEN** a PerformanceStats instance
- **WHEN** the stats are formatted for logging or display
- **THEN** durations SHALL be convertible to milliseconds for readability
- **AND** average_duration_ns SHALL be calculated as total_duration_ns / total_queries
- **AND** division by zero is handled (returns 0 if no queries)

