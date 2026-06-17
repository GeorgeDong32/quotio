## Why

When users add a Custom Provider in Quotio, the app probes the OpenAI/Codex-compatible `/v1/models` endpoint to validate the base URL and list available models. `CustomProviderSheet.testConnection` currently throws `endpointNotFound` on the first HTTP 404 and `fetchModelsFromAPI` surfaces a generic `"Failed to fetch models: HTTP 404"` — neither retries the alternate endpoint shape (with vs. without an explicit `/v1` segment).

This blocks legitimately correct base URLs whose path prefixes do not end in a `v<N>` segment that the heuristic at `CustomProviderSheet.baseURLIncludesVersion` recognises — e.g. multi-segment prefixes (`/api/openai/v1`), vendor gateways (`/openai/v1` behind a proxy), or paths containing trailing letters after the version (`/v1beta`). Upstream commit `c7959d8` fixed the `openaiCompatibility` normalisation but did not add any 404 recovery, so users still see **"Models endpoint not found at this URL"** and cannot save the provider.

## What Changes

- Add a single models-endpoint probe helper that, on HTTP 404, retries the alternate URL shape (swap between `<base>/models` and `<base>/v1/models`) before failing.
- Refactor `testConnection(provider:)` and `fetchModelsFromAPI()` to use this helper so both code paths share the fallback logic.
- Keep all non-404 error semantics unchanged (401/403 still surface as `unauthorized`, 5xx and other codes still surface as `serverError`), so real auth or upstream problems are not masked.
- No change to `normalizedBaseURL`, `makeModelsURL`, or `baseURLIncludesVersion` — the existing heuristic is preserved as the first attempt, fallback only kicks in when the heuristic guesses wrong.

## Capabilities

### New Capabilities

- `custom-provider-models-endpoint`: Behavior of the models-list probe used when adding or testing a Custom Provider — covers URL construction, single-attempt retry on HTTP 404, and error mapping back to the UI.

### Modified Capabilities

(none — no existing spec covers this code path)

## Impact

- Source files:
  - `Quotio/Views/Components/CustomProviderSheet.swift` — refactor `testConnection` (around line 907) and `fetchModelsFromAPI` (around line 760) to share a new probe helper. The error enum at line 969 (`CustomProviderTestError`) is unchanged.
- User-visible behavior:
  - Provider add flow tolerates non-standard path prefixes (one extra HTTP round-trip on 404).
  - Save flow no longer blocks on a single 404; only fails if both endpoint shapes return 404.
- No new dependencies, no migration, no API surface change.
- Risk: a misbehaving server that returns 404 to GET `/models` but routes `/v1/models` differently could be retried unnecessarily — bounded to one extra GET, scoped to HTTP 404 only, no impact on auth or 5xx paths.