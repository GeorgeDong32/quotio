## Context

`Quotio/Views/Components/CustomProviderSheet.swift` currently contains two duplicated outbound-probe call sites (`fetchModelsFromAPI` at ~line 760 and `testConnection(provider:)` at ~line 907) that both hit `<base>/models` or `<base>/v1/models` once and bail on any non-200 status. The path shape is chosen by `baseURLIncludesVersion` (`^v\d[alnum]*$` on the last path segment) — accurate for canonical OpenAI-style URLs, brittle for any prefix that does not end in a clean version token.

The save flow (`saveProvider` → `testConnection`) surfaces `CustomProviderTestError.endpointNotFound` (defined at line 988 with the user-visible message **"Models endpoint not found at this URL"**) on the first 404, blocking provider creation entirely.

Constraints:
- SwiftUI view-bound state; the helper must run on the same actor (or hop to `MainActor` for state writes as the existing code does).
- Authorization headers differ per `CustomProviderType` (Bearer for openai/codex/claude/glm, `?key=` query for gemini) — the helper must be parameterised on the request builder, not the URL alone.
- The helper must not change semantics for 401/403/5xx — those errors must still surface unchanged so real auth or upstream problems are not masked.

## Goals / Non-Goals

**Goals:**
- One additional HTTP attempt with the *alternate* endpoint shape when the first attempt returns HTTP 404.
- A single shared probe helper used by both `fetchModelsFromAPI` and `testConnection` so retry behaviour stays in sync.
- Preserve existing 401/403 → `unauthorized`, 5xx → `serverError(code, body)` behaviour.
- Preserve existing `modelFetchError` text for the `fetchModelsFromAPI` path; only the success-or-throw envelope changes.

**Non-Goals:**
- No change to `normalizedBaseURL`, `makeModelsURL`, or `baseURLIncludesVersion` heuristic.
- No new provider types, no new auth header schemes, no new error enum cases.
- No persistent caching of probe results.
- No UI changes beyond the existing alert / banner wiring.

## Decisions

### D1. Helper signature: `probeModelsEndpoint(...)` returning a typed result

The helper accepts `(primaryURL: URL, alternateURL: URL, requestBuilder: (URL) -> URLRequest)` and returns `Result<(HTTPURLResponse, Data), CustomProviderTestError>`. It performs:

1. `try await send(primaryURL)` → return on success or non-404 error.
2. On 404, `try await send(alternateURL)` → return that result unconditionally (success, `endpointNotFound`, or `serverError`).

Why a typed `Result` over throwing directly: `testConnection` already converts the response into `CustomProviderTestError`; `fetchModelsFromAPI` instead writes a user-visible string. A shared throwing helper would force both call sites to map the same enum, losing the asymmetric error text (`"Failed to fetch models: HTTP 404"` vs `"Models endpoint not found at this URL"`). Returning `(response, data)` keeps each call site in control of error presentation while sharing the URL plumbing.

Alternatives considered:
- *Inline the retry in both call sites* — rejected: violates DRY, two places to keep in sync, easy to regress.
- *Throw from the helper and let both sites catch* — rejected: `fetchModelsFromAPI` historically surfaces HTTP codes via `modelFetchError` (`"Failed to fetch models: HTTP \(code)"`); wrapping a `CustomProviderTestError` here would force text unification we explicitly don't want.

### D2. Alternate URL construction: only swap the trailing endpoint segment

The two candidate endpoints are `<base>/models` and `<base>/v1/models`. The helper accepts both URLs pre-built so the existing `makeModelsURL` continues to own the canonical guess; the alternate is just the other one.

```swift
let canonical = makeModelsURL(baseURL: rawBaseURL, providerType: providerType)
let alternate = makeAlternateModelsURL(baseURL: rawBaseURL, providerType: providerType)
```

`makeAlternateModelsURL` is a small pure function that mirrors `makeModelsURL` but flips the `baseURLIncludesVersion` decision. This keeps the swap symmetric and trivially testable.

Alternatives considered:
- *Probe `<base>/` first and let the server tell us the version* — rejected: adds a third request, no guarantee of a useful response shape.
- *Strip the last path segment and try again* — rejected: changes the meaning of multi-segment URLs in unexpected ways.

### D3. Retry only on HTTP 404 — everything else fails fast

401/403 stay as `unauthorized` (tested) and shown as `"API key is invalid or unauthorized"`. 5xx and other codes stay as `serverError(code, body)`. Connection failures stay as thrown errors (`URLError`, etc.) — the existing code already lets them bubble up via `try await URLSession.shared.data(...)` and `testConnection` rethrows them; `fetchModelsFromAPI` already swallows them into `modelFetchError = "Invalid response"`.

This is the narrowest change that fixes the reported bug. Widening retry to all status codes would mask transient upstream 5xx that the user genuinely needs to see.

### D4. No new error cases

`CustomProviderTestError.endpointNotFound` keeps its existing message. The fallback only changes *when* it is thrown — both candidate URLs return 404 → throw `endpointNotFound`; either succeeds → return success. No enum cases added.

## Risks / Trade-offs

- **Extra round-trip on misconfigured providers** — every 404 from the canonical URL now costs one more HTTP request. Mitigation: bounded to a single retry, scoped to 404, total worst-case cost = 2 GETs per Save / Fetch action. Acceptable.
- **Servers that return 404 on `/models` but route `/v1/models` to a *different* feature** could succeed in the fallback even when the user's base URL is wrong. Mitigation: low — the fallback is still a models-list probe, so the wrong-base case will surface during the subsequent chat-completion call with a more specific error; we are not silently writing a misconfigured URL.
- **Behavior parity for `fetchModelsFromAPI` vs `testConnection`** — both must call the helper consistently; if one regresses to single-attempt the bug returns. Mitigation: covered by the manual checklist in `tasks.md` (Test Plan section) which exercises both call sites end-to-end.
- **Timeout interaction** — `fetchModelsFromAPI` already sets `request.timeoutInterval = 15`; the retry doubles the worst-case latency to ~30s. Mitigation: keep `URLSession.shared` default and the same per-request timeout; document in tasks.md that this is the intentional worst case for genuinely broken endpoints.

## Migration Plan

No data migration. No configuration migration. The change is fully in-process within `CustomProviderSheet.swift`. Rollback is `git revert <commit>` — the helper is self-contained and the call sites can be reverted to their pre-change shape in one step.

## Open Questions

- *Should we also surface the chosen endpoint shape in the success toast / save log so users can tell which form worked?* — not required for the bug fix; deferred unless requested.
- *Should GLM and Claude compatibility types benefit from the same fallback?* — currently `makeModelsURL` for those types still returns a URL but the heuristic is type-agnostic; the helper applies uniformly. No special-casing needed.