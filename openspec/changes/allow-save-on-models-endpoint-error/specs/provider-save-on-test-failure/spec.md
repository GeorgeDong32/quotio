## ADDED Requirements

### Requirement: User can save provider despite failed connection test
When the connection test fails for any reason (404, 401, server error, timeout, etc.), the system SHALL present the user with both a cancel option and a "Save Anyway" option that persists the provider configuration.

#### Scenario: User saves after 404 models endpoint
- **WHEN** user fills valid provider fields and clicks Save, AND the connection test returns HTTP 404
- **THEN** an alert displays "Models endpoint not found at this URL" with two buttons: "Cancel" (dismisses without saving) and "Save Anyway" (saves the provider and dismisses the sheet)

#### Scenario: User cancels after test failure
- **WHEN** the test-failure alert is displayed with both "OK" and "Save Anyway" buttons
- **THEN** clicking "OK" dismisses the alert and returns to the provider form without saving

#### Scenario: User saves after 401 unauthorized test
- **WHEN** user fills valid provider fields and clicks Save, AND the connection test returns HTTP 401
- **THEN** an alert displays "API key is invalid or unauthorized" with both "OK" and "Save Anyway" buttons

#### Scenario: User saves after server error test
- **WHEN** user fills valid provider fields and clicks Save, AND the connection test returns a 5xx server error
- **THEN** an alert displays the server error message with both "OK" and "Save Anyway" buttons

#### Scenario: User saves after connection timeout
- **WHEN** user fills valid provider fields and clicks Save, AND the connection test times out (15s) or encounters a network error
- **THEN** an alert displays the system error message with both "OK" and "Save Anyway" buttons

#### Scenario: Basic validation errors still block save
- **WHEN** user clicks Save with missing required fields (e.g., no provider name, no API key)
- **THEN** an alert displays the validation errors with only an "OK" button and no "Save Anyway" option

#### Scenario: Successful test auto-saves as before
- **WHEN** user fills valid provider fields and clicks Save, AND the connection test returns HTTP 2xx
- **THEN** the provider is saved immediately and the sheet dismisses without showing any alert
