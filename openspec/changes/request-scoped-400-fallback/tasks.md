## 1. FallbackContext State Update

- [x] 1.1 Add `suppressRouteCacheWrite: Bool` field to `FallbackContext` struct in `Quotio/Services/Proxy/ProxyBridge.swift`
- [x] 1.2 Update `FallbackContext.empty` to initialize `suppressRouteCacheWrite = false`
- [x] 1.3 Update `createFallbackContext(body:)` to initialize `suppressRouteCacheWrite = false`
- [x] 1.4 Update `next()` to preserve `suppressRouteCacheWrite` in the returned context
- [x] 1.5 Update `appendingAttempt(_:)` to preserve `suppressRouteCacheWrite` in the returned context
- [x] 1.6 Update `withSanitizationAttempted()` to preserve `suppressRouteCacheWrite` in the returned context

## 2. Fallback Trigger Logic

- [x] 2.1 In `receiveResponse(...)`, when `fallbackReason` is `.httpStatus(400)` and `hasMoreFallbacks` is true, set `suppressRouteCacheWrite = true` on the context before calling `next()`

## 3. Cache Write Gate

- [x] 3.1 In `recordCompletion(...)`, add `!fallbackContext.suppressRouteCacheWrite` to the route cache write condition alongside existing checks

## 4. Route State UI Gate

- [x] 4.1 In `receiveResponse(...)`, guard the `updateRouteState` call with `!finalContext.suppressRouteCacheWrite` to prevent 400-triggered fallbacks from updating the UI route state

## 5. Verification

- [x] 5.1 Build the project with `xcodebuild -project Quotio.xcodeproj -scheme Quotio -configuration Debug build`
