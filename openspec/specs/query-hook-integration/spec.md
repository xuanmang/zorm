# query-hook-integration Specification

## Purpose
TBD - created by archiving change implement-query-hook-observability. Update Purpose after archive.
## Requirements
### Requirement: Hook Trigger Before Query Execution
DB MUST trigger all registered query hooks before executing any query, passing the SQL statement and arguments to each hook's beforeQuery method.

#### Scenario: Single hook triggered before SELECT query
- **GIVEN** a LoggingHook is registered via db.addHook()
- **AND** a SELECT query is built
- **WHEN** the query is executed via scan()
- **THEN** the LoggingHook.beforeQuery() method SHALL be called with the SQL and arguments
- **AND** the hook receives the query before database execution

#### Scenario: Multiple hooks triggered in registration order
- **GIVEN** a LoggingHook is registered first
- **AND** a PerformanceHook is registered second
- **WHEN** any query is executed
- **THEN** LoggingHook.beforeQuery() SHALL be called first
- **AND** PerformanceHook.beforeQuery() SHALL be called second
- **AND** the order matches the registration order

#### Scenario: No hooks registered
- **GIVEN** no hooks are registered on the DB instance
- **WHEN** a query is executed
- **THEN** the query SHALL execute normally without calling any hooks
- **AND** no performance overhead is incurred

### Requirement: Hook Trigger After Query Execution
DB MUST trigger all registered query hooks after successfully executing any query, passing the SQL statement, arguments, and execution duration (in nanoseconds) to each hook's afterQuery method.

#### Scenario: Hook receives query duration
- **GIVEN** a PerformanceHook is registered
- **WHEN** a SELECT query is executed
- **THEN** PerformanceHook.afterQuery() SHALL be called with SQL, arguments, and duration_ns
- **AND** duration_ns SHALL be accurate within ±1ms tolerance
- **AND** duration_ns SHALL be measured from query start to completion

#### Scenario: Hooks triggered after INSERT with RETURNING
- **GIVEN** a LoggingHook is registered
- **WHEN** an INSERT query with RETURNING clause is executed
- **THEN** the hook's afterQuery() method SHALL be called after results are retrieved
- **AND** the hook receives the actual execution time including result fetching

#### Scenario: Hooks triggered after all query types
- **GIVEN** a PerformanceHook is registered
- **WHEN** SELECT, INSERT, UPDATE, or DELETE queries are executed
- **THEN** afterQuery() SHALL be triggered for each query type
- **AND** the duration SHALL reflect the actual database operation time

### Requirement: Hook Trigger On Query Error
DB MUST trigger all registered query hooks when a query fails, passing the SQL statement, arguments, and error to each hook's onError method.

#### Scenario: Hook receives error on syntax error
- **GIVEN** a LoggingHook is registered
- **WHEN** a query with invalid SQL syntax is executed
- **THEN** LoggingHook.onError() SHALL be called with SQL, arguments, and the error
- **AND** the error SHALL be the actual database error returned
- **AND** the error is propagated to the caller after hook execution

#### Scenario: Hook receives error on connection failure
- **GIVEN** a PerformanceHook is registered
- **WHEN** a query fails due to connection loss
- **THEN** PerformanceHook.onError() SHALL be called with the connection error
- **AND** error statistics SHALL be updated in the hook

#### Scenario: Multiple hooks all receive error
- **GIVEN** two hooks are registered
- **WHEN** a query fails
- **THEN** both hooks' onError() methods SHALL be called
- **AND** hooks are triggered in registration order
- **AND** if a hook's onError() throws, other hooks still execute

### Requirement: Hook Integration in Transaction Context
Queries executed within a transaction MUST trigger hooks using the DB instance's registered hooks, maintaining consistent observability across transactions.

#### Scenario: Hooks triggered for transaction queries
- **GIVEN** a DB instance with a LoggingHook registered
- **AND** a transaction is started via db.beginTx()
- **WHEN** a query is executed within the transaction
- **THEN** the DB's LoggingHook SHALL be triggered
- **AND** hooks receive transaction queries the same as non-transaction queries

#### Scenario: Transaction commit/rollback do not trigger query hooks
- **GIVEN** a PerformanceHook is registered
- **AND** a transaction is active
- **WHEN** tx.commit() or tx.rollback() is called
- **THEN** no hook SHALL be triggered for the commit/rollback command itself
- **AND** only explicit queries trigger hooks

### Requirement: Hook Trigger Helper Methods
DB MUST provide helper methods (triggerBeforeQuery, triggerAfterQuery, triggerOnError) to consistently trigger hooks across all query execution paths.

#### Scenario: triggerBeforeQuery iterates all hooks
- **GIVEN** three hooks are registered
- **WHEN** triggerBeforeQuery(sql, args) is called
- **THEN** all three hooks' beforeQuery() methods SHALL be called
- **AND** hooks are called in registration order
- **AND** execution stops if a hook throws an error

#### Scenario: triggerAfterQuery measures duration
- **GIVEN** a PerformanceHook is registered
- **WHEN** triggerAfterQuery(sql, args, start_time) is called
- **THEN** the method SHALL calculate duration_ns = current_time - start_time
- **AND** pass duration_ns to the hook's afterQuery() method

#### Scenario: triggerOnError propagates original error
- **GIVEN** a LoggingHook is registered
- **WHEN** triggerOnError(sql, args, err) is called
- **THEN** the hook's onError() SHALL be called with err
- **AND** if hook throws, the original error is still returned
- **AND** hook errors are logged but not propagated

### Requirement: Hook Performance Impact
Hook triggering MUST have minimal performance overhead, adding less than 1% latency to query execution when no hooks are registered, and less than 5% when hooks are registered.

#### Scenario: No performance impact without hooks
- **GIVEN** no hooks are registered
- **WHEN** 1000 SELECT queries are executed
- **THEN** total execution time SHALL be within 1% of queries without hook support
- **AND** no memory allocations occur for hook triggering

#### Scenario: Minimal impact with logging hook
- **GIVEN** a LoggingHook is registered
- **WHEN** 1000 SELECT queries are executed
- **THEN** hook overhead SHALL add less than 5% to total execution time
- **AND** memory usage SHALL not increase significantly

### Requirement: Hook Error Handling
Errors thrown by hooks MUST be logged but SHALL NOT prevent query execution or prevent other hooks from executing.

#### Scenario: Hook error does not block query
- **GIVEN** a custom hook that throws an error in beforeQuery()
- **WHEN** a SELECT query is executed
- **THEN** the hook error SHALL be logged
- **AND** the query SHALL execute normally
- **AND** afterQuery() hooks SHALL still be triggered

#### Scenario: One hook error does not affect other hooks
- **GIVEN** Hook A throws an error in afterQuery()
- **AND** Hook B is registered after Hook A
- **WHEN** a query completes
- **THEN** Hook A's error SHALL be logged
- **AND** Hook B.afterQuery() SHALL still be called
- **AND** both hooks remain registered

