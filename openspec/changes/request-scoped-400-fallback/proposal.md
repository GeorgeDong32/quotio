## Why

HTTP 400 errors often indicate a request-level incompatibility (content, parameters, or feature not supported by a specific model) rather than a provider-level outage. When fallback is triggered by a 400 and the next entry succeeds, the current code writes that entry into the route cache — causing subsequent requests to permanently avoid the preferred model even though most requests work fine with it.

## What Changes

- Fallback triggered by HTTP 400 will suppress route cache writes for the current request.
- Successful fallback from non-400 errors (429, 500, 503, 401, 403, 422) continues to update route cache as before.
- Fallback attempt logging remains unchanged — all attempts are still recorded with their trigger reasons.
- No changes to the set of status codes that trigger fallback.
- No changes to route caching UI or cache TTL/eviction behavior.

## Capabilities

### New Capabilities
- `fallback-cache-suppression`: request-scoped suppression of route cache writes when fallback is triggered by HTTP 400.

### Modified Capabilities
<!-- No existing spec-level behavior changes required. -->

## Impact

- `Quotio/Services/Proxy/ProxyBridge.swift` — FallbackContext state propagation and recordCompletion cache gate.
- `Quotio/Models/FallbackModels.swift` — FallbackContext struct if defined here (currently inline in ProxyBridge).
- No API or dependency changes.
- No UI changes.
