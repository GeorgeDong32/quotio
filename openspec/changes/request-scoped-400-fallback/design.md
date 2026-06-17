## Context

Quotio's virtual model fallback system routes requests through a chain of provider/model entries. When an entry returns an error (429, 500, 503, 400, 401, 403, 422), the proxy cancels the connection and tries the next entry. On success, it may cache the winning entry so subsequent requests start from it.

HTTP 400 is different from other error codes: it usually means the *request content* is incompatible with a model, not that the model is unavailable. Caching the fallback entry after a 400 causes the preferred model to be permanently avoided for all future requests, even though most requests would work fine with it.

## Goals / Non-Goals

**Goals:**
- Fallback triggered by HTTP 400 must still succeed for the current request.
- The successful fallback entry after a 400-triggered fallback must NOT be written to the route cache.
- Non-400 fallbacks (429, 500, 503, 401, 403, 422) continue to update route cache as today.
- Fallback attempt logging remains unchanged.

**Non-Goals:**
- No conditional fallback rules (error-code-to-model mapping).
- No UI changes for route caching or fallback configuration.
- No changes to which status codes trigger fallback.
- No cache TTL or eviction changes.

## Decisions

### 1. Request-scoped suppression flag on FallbackContext

**Decision**: Add a `suppressRouteCacheWrite: Bool` field to `FallbackContext`, propagated through `next()`, `appendingAttempt()`, `withSanitizationAttempted()`, and initialized to `false` in `.empty` and `createFallbackContext()`.

**Rationale**: The flag travels with the fallback context for the lifetime of a single request. It requires no changes to FallbackSettingsManager or the cache data model. It is the smallest possible change.

**Alternative considered**: Record all trigger reasons in the context and check them at `recordCompletion`. Rejected because it requires accumulating state across multiple fallback hops for a binary decision.

### 2. Set the flag on 400-triggered fallback only

**Decision**: In `receiveResponse(...)`, when the fallback reason is `.httpStatus(400)` and there are more fallbacks, set `suppressRouteCacheWrite = true` on the context passed to `next()`.

**Rationale**: Only 400 is request-specific. Other codes indicate provider-level issues where caching the fallback is desirable.

### 3. Gate route cache write in recordCompletion

**Decision**: Add `!fallbackContext.suppressRouteCacheWrite` to the existing cache-write condition in `recordCompletion(...)`.

**Rationale**: Minimal change — one additional boolean check in an already-existing condition block.

## Risks / Trade-offs

- [Flag propagation bug] → All context-copying methods (`next`, `appendingAttempt`, `withSanitizationAttempted`) must correctly forward the flag. Missing one would silently revert to old behavior. Mitigation: the flag defaults to `false`, so a missed propagation behaves like the current (safe) behavior.
- [Future error codes may need similar treatment] → The current design hardcodes 400 as the suppression trigger. If 422 or other codes need the same treatment later, the flag can be set based on a set of codes instead of a single match.
