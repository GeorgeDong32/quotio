## Why

When configuring a custom provider, users must pass a connection test that hits the provider's `/models` endpoint. Some OpenAI-compatible providers do not implement this endpoint and return HTTP 404 — but are otherwise fully functional. Currently the UI blocks saving with a dead-end alert, leaving users unable to use these providers at all.

## What Changes

- Add a "Save Anyway" button to the connection test error alert, allowing users to bypass the test failure and persist the provider configuration
- The existing "OK" button remains as the dismiss/cancel path
- Add `action.saveAnyway` localization key to `Localizable.xcstrings` with `en`/`fr`/`vi`/`zh-Hans` translations

## Capabilities

### New Capabilities

- `provider-save-on-test-failure`: Allow saving a custom provider configuration even when the connection test fails (e.g., models endpoint not found, server error, timeout)

### Modified Capabilities

<!-- No existing specs to modify -->

## Impact

- `Quotio/Views/Components/CustomProviderSheet.swift` — modify `.alert` on `showValidationAlert` to present dual buttons (OK / Save Anyway) when the error is a connection test failure; invoke `onSave` on the "Save Anyway" path; add `pendingSaveProvider` state
- `Quotio/Localizable.xcstrings` — add `action.saveAnyway` key with 4-language translations
- No API, dependency, or data model changes
