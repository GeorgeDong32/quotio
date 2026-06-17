## ADDED Requirements

### Requirement: Models-endpoint probe uses canonical URL first
The system SHALL issue the models-list probe against the URL produced by the existing `makeModelsURL(baseURL:providerType:)` heuristic on every Custom Provider add / test action.

#### Scenario: Canonical URL responds 200
- **WHEN** the canonical URL `<base>/v1/models` (or `<base>/models` when the base path already contains a version segment) returns HTTP 200
- **THEN** the system accepts the response and lists the models without issuing any additional probe request

### Requirement: Probe falls back to alternate endpoint shape on HTTP 404
The system SHALL retry the models-list probe with the alternate URL shape when the first attempt returns HTTP 404, and SHALL treat the alternate attempt as final.

#### Scenario: Canonical URL returns 404, alternate URL returns 200
- **WHEN** the canonical URL returns HTTP 404 and the alternate URL shape (with or without `/v1` segment, whichever was not used first) returns HTTP 200
- **THEN** the system accepts the alternate response, lists the models, and the provider save flow proceeds without surfacing `endpointNotFound`

#### Scenario: Both canonical and alternate URLs return 404
- **WHEN** both the canonical URL and the alternate URL return HTTP 404
- **THEN** the system surfaces `CustomProviderTestError.endpointNotFound` with the existing message **"Models endpoint not found at this URL"** and blocks the provider save

### Requirement: Non-404 errors fail fast without retry
The system SHALL NOT retry the models-list probe on any status code other than 404, and SHALL preserve the existing error mapping for those codes.

#### Scenario: Probe returns 401 or 403
- **WHEN** the canonical URL returns HTTP 401 or 403
- **THEN** the system surfaces `CustomProviderTestError.unauthorized` with the existing message **"API key is invalid or unauthorized"** and does not issue an alternate request

#### Scenario: Probe returns 5xx or other non-404 code
- **WHEN** the canonical URL returns HTTP 500 (or any code other than 200/401/403/404)
- **THEN** the system surfaces `CustomProviderTestError.serverError(code, body)` with the existing message format **"Server error (code): body"** and does not issue an alternate request

### Requirement: Fetch-from-API flow inherits the same fallback
The "Fetch from API" affordance in the Custom Provider sheet SHALL use the same shared probe helper as the save-time `testConnection`, so the user-visible model list and the save validation cannot diverge.

#### Scenario: Fetch-from-API resolves via alternate URL
- **WHEN** the user clicks "Fetch from API" with a base URL whose canonical probe returns 404 but whose alternate probe returns 200
- **THEN** the system populates `availableModels` from the alternate response and does not display a `modelFetchError`

#### Scenario: Fetch-from-API surfaces canonical-only 404 message
- **WHEN** the user clicks "Fetch from API" and the canonical probe returns 404
- **THEN** the system immediately displays `modelFetchError = "Failed to fetch models: HTTP 404"` without waiting for or attempting the alternate URL

Note: the Fetch-from-API banner is intentionally more aggressive than the save flow — it shows the first-attempt status to help the user diagnose path issues, while the save flow optimistically retries so a valid provider can still be added.