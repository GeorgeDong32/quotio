# proxy-fallback Specification

## Purpose

Fork-owned model-fallback routing: requests to a virtual model are retried
against an ordered chain of concrete providers, driven by response-pattern
classification, without persisting routing decisions caused by the failures
that trigger fallback. Implemented in
`Packages/QuotioForkExtras/Sources/QuotioForkExtras/Fallback/` (engine) and
`…/ProxyIntegration/` (lifecycle), with `ProxyBridge` as the in-process
forwarding proxy.

## Requirements

### Requirement: Bridge topology

The app shall run an in-process bridge (`ProxyBridge`) that listens on the
user-configured proxy port, while the proxy binary binds `userPort + 10000`
on 127.0.0.1 only. The user port is user data (Settings → CLIProxyAPI);
no code path shall assume a fixed port value.

#### Scenario: Proxy starts in bridge mode

- **WHEN** the app starts the proxy with user port P configured
- **THEN** the proxy binary binds P + 10000 on 127.0.0.1 only
- **AND** `ProxyBridge` accepts connections on P and forwards to the binary

#### Scenario: Model rewriting is app-side

- **WHEN** a request names a virtual model
- **THEN** the bridge rewrites and classifies it before forwarding
- **AND** behavior is identical regardless of which binary source
  (official or plus) is active

### Requirement: Virtual-model fallback routing

The bridge shall retry a failing request for a virtual model against the
configured fallback chain, choosing the next provider from the response
pattern, and shall serve the first successful response to the caller.

#### Scenario: Provider fails, fallback chain succeeds

- **WHEN** a provider returns a failure whose pattern is classified as
  fallback-eligible
- **THEN** the bridge retries the request against the next entry in the
  fallback chain
- **AND** the served response and the provider that produced it are recorded
  in the request log

### Requirement: HTTP 400 fallback suppression

When a fallback is triggered by an HTTP-400-class failure, the app shall
suppress both the route-cache write and the route-state UI update, guarded by
`suppressRouteCacheWrite` in `Fallback/ProxyBridge.swift`. This is a fork
invariant: upstream syncs must never drop it.

#### Scenario: 400 triggers fallback

- **WHEN** a provider returns HTTP 400 and the request falls back to another
  provider
- **THEN** no route-cache entry is written for the failed attempt
- **AND** the route-state UI does not change as a result of the 400

#### Scenario: Non-400 failures behave normally

- **WHEN** a fallback is triggered by a non-400 failure class
- **THEN** ordinary route-cache and route-state behavior applies
