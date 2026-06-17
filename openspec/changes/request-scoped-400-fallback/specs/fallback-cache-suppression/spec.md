## ADDED Requirements

### Requirement: HTTP 400 fallback must suppress route cache write
When a virtual model fallback is triggered by HTTP 400 and the subsequent fallback entry succeeds, the system SHALL NOT write the successful fallback entry to the route cache.

#### Scenario: 400 triggers fallback, next entry succeeds, cache is not written
- **WHEN** a virtual model request is sent to entry A and entry A returns HTTP 400
- **AND** the fallback system switches to entry B
- **AND** entry B returns HTTP 2xx
- **THEN** the request completes successfully using entry B
- **AND** the route cache is NOT updated with entry B's ID

#### Scenario: subsequent request after 400 fallback uses normal route
- **WHEN** a previous request triggered a 400 fallback to entry B without caching
- **THEN** the next request to the same virtual model starts from the normal first entry or existing cached entry, NOT from entry B

### Requirement: Non-400 fallback continues to update route cache
When a virtual model fallback is triggered by any error code other than 400 and the subsequent fallback entry succeeds, the system SHALL write the successful fallback entry to the route cache as per existing behavior.

#### Scenario: 429 triggers fallback, next entry succeeds, cache is written
- **WHEN** a virtual model request is sent to entry A and entry A returns HTTP 429
- **AND** the fallback system switches to entry B
- **AND** entry B returns HTTP 2xx
- **AND** route caching is enabled
- **THEN** entry B's ID is written to the route cache

#### Scenario: 500 triggers fallback, next entry succeeds, cache is written
- **WHEN** a virtual model request is sent to entry A and entry A returns HTTP 500
- **AND** the fallback system switches to entry B
- **AND** entry B returns HTTP 2xx
- **AND** route caching is enabled
- **THEN** entry B's ID is written to the route cache

### Requirement: 400 fallback attempts are still logged
Fallback attempts triggered by HTTP 400 SHALL be recorded in the request log with the same detail as other fallback attempts.

#### Scenario: 400 fallback attempt logged with correct reason
- **WHEN** entry A returns HTTP 400 and fallback switches to entry B
- **THEN** a FallbackAttempt with outcome `.failed` and reason `.httpStatus(400)` is recorded for entry A
- **AND** the subsequent attempt for entry B is recorded normally

### Requirement: HTTP 400 fallback must suppress route state UI update
When a virtual model fallback is triggered by HTTP 400, the system SHALL NOT update the route state UI display. The route state (`routeStates` in FallbackSettingsManager) tracks active fallback routes shown in the fallback screen. A 400-triggered fallback must not appear as an active route.

#### Scenario: 400 triggers fallback, UI does not show active route
- **WHEN** a virtual model request is sent to entry A and entry A returns HTTP 400
- **AND** the fallback system switches to entry B
- **THEN** the route state UI is NOT updated for this virtual model
- **AND** the fallback screen does NOT display entry B as an active fallback route

#### Scenario: non-400 fallback updates route state UI as normal
- **WHEN** a virtual model request is sent to entry A and entry A returns HTTP 429
- **AND** the fallback system switches to entry B
- **THEN** the route state UI is updated to show entry B as the active fallback route
