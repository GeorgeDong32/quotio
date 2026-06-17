## 1. Helper extraction

- [x] 1.1 Add `makeAlternateModelsURL(baseURL:providerType:)` private method to `CustomProviderSheet` that returns the URL shape NOT chosen by the existing `makeModelsURL` (i.e., flip the `baseURLIncludesVersion` decision).
- [x] 1.2 Add a private `ModelsProbeResult` enum (or tuple) capturing `(HTTPURLResponse, Data)` or a `CustomProviderTestError` so both call sites can map errors uniformly.
- [x] 1.3 Add a private `probeModelsEndpoint(primary:alternate:requestBuilder:) async -> ModelsProbeResult` that performs the primary GET, retries with the alternate URL only on HTTP 404, and propagates all other outcomes unchanged.

## 2. Wire save-time `testConnection` to the helper

- [x] 2.1 Replace the inline `URLSession.shared.data(for:)` call in `testConnection(provider:)` with `probeModelsEndpoint(...)`.
- [x] 2.2 Convert the helper result into the existing 200 / 401 / 403 / 404 / serverError branches so the thrown `CustomProviderTestError` cases are unchanged.

## 3. Wire Fetch-from-API to the helper

- [x] 3.1 Replace the inline `URLSession.shared.data(for:)` call in `fetchModelsFromAPI` with `probeModelsEndpoint(...)`.
- [x] 3.2 Preserve the existing `modelFetchError` text on the first 404 (`"Failed to fetch models: HTTP 404"`) — when the helper returns a 404 on the canonical URL, the banner must show immediately and NOT wait for the alternate attempt, per `specs/custom-provider-models-endpoint/spec.md` Scenario "Fetch-from-API surfaces canonical-only 404 message".
- [x] 3.3 On helper success, parse the response into `availableModels` exactly as the existing code does.

## 4. Build verification

- [x] 4.1 Build the macOS target (`xcodebuild -scheme Quotio -destination 'platform=macOS' build`) and confirm zero warnings / errors introduced by the change.
- [x] 4.2 Confirm the Swift compiler accepts the new private helpers (no `Sendable` or actor-isolation warnings — keep them `@MainActor` or `nonisolated` consistent with the surrounding code).

## 5. Manual test plan

Run inside the macOS app, in the Custom Provider add sheet. For each scenario, document pass/fail in the PR description.

- [ ] 5.1 **Canonical succeeds**: base URL `https://api.example.com/v1` → "Fetch from API" lists models; click Save → provider saves; no alert.
- [ ] 5.2 **Canonical 404, alternate succeeds**: base URL `https://api.example.com/openai/v1` where upstream mounts models at `/openai/v1/models` → "Fetch from API" shows the canonical-404 banner; click Save → provider saves (alternate path used by `testConnection`); no `endpointNotFound` alert.
- [ ] 5.3 **Both 404**: base URL `https://api.example.com/nope` → "Fetch from API" shows canonical-404 banner; click Save → alert **"Models endpoint not found at this URL"** appears.
- [ ] 5.4 **401 still surfaces**: invalid API key against a real endpoint → alert **"API key is invalid or unauthorized"**; no alternate probe issued.
- [ ] 5.5 **5xx still surfaces**: upstream returns 500 → alert **"Server error (500): ..."**; no alternate probe issued.

## 6. Rollback

- [ ] 6.1 If the change must be reverted, run `git revert <merge-commit>` — the helper is self-contained inside `CustomProviderSheet.swift` and the call-site diffs revert cleanly.
- [ ] 6.2 No data migration, no config migration, no user-visible state to clean up on rollback.