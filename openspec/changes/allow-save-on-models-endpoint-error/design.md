## Context

The `CustomProviderSheet` currently runs a connection test before saving: it hits the provider's `/models` endpoint and blocks if the response is not 2xx. Some compliant providers don't expose this endpoint (404) or return other errors, yet work perfectly for chat completions. The alert on failure has only an OK button, making it impossible to save these providers.

**Current flow:**
1. User fills provider form → clicks Save
2. Basic field validation runs; if invalid → alert (OK only)
3. `testConnection()` fires a GET to `/models` with the provider's auth
4. Success (2xx) → save & dismiss; failure → alert with `testError` (OK only), no save

## Goals / Non-Goals

**Goals:**
- Allow the user to forcibly save a provider even when the connection test returns a non-success status
- Keep the existing happy path unchanged (success → auto-save)
- Minimal change: modify only the alert presentation

**Non-Goals:**
- Changing when or how the connection test is run
- Adding a "skip test" checkbox or preference
- Altering basic field validation behavior (invalid fields still block save)

## Decisions

### Decision 1: "Save Anyway" button on test-error alert

**Chosen:** When `testError` is non-nil, the alert presents two buttons: "OK" (dismiss, no save) and "Save Anyway" (invokes `onSave` + dismiss).

**Alternatives considered:**
- *Skip the test entirely* — too blunt; the test still has value for catching auth errors (401/403) and confirming the URL is reachable before the user starts using the provider
- *Make the test optional per provider* — adds UI complexity for a rare case; "Save Anyway" is simpler and accomplishes the same goal
- *Separate "Test Connection" button* — good long-term direction but a larger change; "Save Anyway" solves the immediate pain

### Decision 2: "Save Anyway" applies to ALL test failures

Rather than special-casing only 404, the "Save Anyway" button appears for any test error (endpointNotFound, unauthorized, serverError, etc.). Users understand their providers best; any blocking error may be a false positive.

### Decision 3: Validation errors still block save

Basic field validation (empty name, missing key, invalid URL format) is structural and unambiguous — these remain blocking with a single OK button. The "Save Anyway" path only appears for connection-test failures.

## Risks / Trade-offs

- **User saves a genuinely broken provider** → The provider simply won't work when used for chat. User can edit/delete it later. Low risk.
- **Test timeout (15s) blocks save briefly** → URIError timeout also sets `testError` via the catch handler, so "Save Anyway" is equally available. No special case needed.

## Localization

Follow existing `.xcstrings` + `.localized()` pattern used throughout the codebase:

- Key: `action.saveAnyway`
- File: `Quotio/Localizable.xcstrings` — insert after `action.ok` entry (alphabetical)
- Usage in Swift: `"action.saveAnyway".localized()`
- Translations:

| Language | Value |
|----------|-------|
| en | Save Anyway |
| fr | Enregistrer quand même |
| vi | Vẫn lưu |
| zh-Hans | 仍要保存 |
