# Tasks — Port the fork onto the upstream monorepo architecture

Every phase must end with: `xcodebuild -project apps/macos/Quotio.xcodeproj
-scheme Quotio -configuration Debug build` green, `swift test` green inside
`Packages/QuotioCore` (and `Packages/QuotioForkExtras` once it exists), and a
tagged, committable state. Conventional commits; never commit to `master`.

## Phase 0 — Baseline bring-up (0.5–1d)

- [ ] `git fetch upstream`; create `port/upstream-monorepo` from the fetched
      master tip (record the pinned SHA in this file).
- [ ] Build upstream as-is: Debug build (the "Embed Quotio CLI" phase must
      succeed — requires local rustup/cargo), plus `swift test` in
      `Packages/QuotioCore`.
- [ ] Create `Packages/QuotioForkExtras` skeleton (Package.swift with target
      + test target depending on QuotioCore products), wire into the xcodeproj,
      confirm `check_architecture.sh` and architecture tests still pass.
- [ ] Tag `port/phase-0-green`.

## Phase 1 — Identity & hygiene (1–2d)

- [ ] Bundle id stays `dev.quotio.desktop`: xcconfig/pbxproj, AppIdentity
      constants, disable/invert the bytrong UserDefaults+keychain migration.
- [ ] Sparkle removal per checklist: no-op `ApplicationUpdateChecking` adapter
      in the fork package, hide updates UI, drop Package.swift/resolved deps,
      Info.plist SU* keys, build_dmg.sh appcast plumbing, workflow env.
- [ ] PostHog removal per checklist: no-op `TelemetryTracking` adapter, drop
      package dep, Info.plist keys, xcconfig vars, privacy toggle hidden.
- [ ] Re-apply GLM endpoint tweak; re-apply agent-config bits.
- [ ] Manual-model-entry UX parity check against upstream
      `CustomProviderSheet` (has `manualModelEntry`, no save gating) — note
      gaps, extend only if a real gap exists.
- [ ] Light/dark smoke test. Tag `port/phase-1-green`.

## Phase 2 — Fork package core: fallback engine (2–3d)

- [ ] Port `FallbackModels` + `FallbackSettingsManager` (UserDefaults JSON,
      same `fallbackConfiguration` key); rewrite the route cache as a locked
      store or actor for Swift 6 strict concurrency.
- [ ] Port `FallbackFormatConverter` (error-pattern classifier) and
      `RequestLog`/`RequestTracker` (50-entry JSON store, same path).
- [ ] Port `ProxyBridge` (NWListener/NWConnection forwarding, port pair
      user/internal = +10000, localhost-only target, `Connection: close`,
      fallback retry loop, thinking-signature sanitize path).
- [ ] Unit tests: error classification table, route-cache TTL/eviction,
      model-body rewrite, header rebuild.
- [ ] Tag `port/phase-2-green`.

## Phase 3 — Proxy integration (3–5d)

- [ ] `FallbackProxyLifecycleCoordinator` implementing `ProxyControlling`:
      wraps upstream controller; bridge-mode start/stop ordering; internal
      port into config.yaml before binary start; health checks target the
      internal port while bridged; shutdown sweeps both ports.
- [ ] Wire coordinator in CompositionRoot (seam swap); expose
      `useBridgeMode` (default on, same key).
- [ ] Plus binary: commit blob + resource entry; pin version/sha; resolver +
      install under `proxy/plus/v*` with current-symlink promote; never
      delete current; move `verify-bundled-proxy.sh` to the monorepo layout
      and call it from the fork build script.
- [ ] Verify plus binary against the new config.yaml template (dry-run on a
      test port + `/meta` compat probe).
- [ ] Route the agent-config endpoint through the bridge port when bridged
      (locate upstream's endpoint source for agent adapters; seam).
- [ ] E2E: real agent request flows through the bridge; forced 429 triggers
      fallback to the next entry; success re-caches the route.
- [ ] Tag `port/phase-3-green`.

## Phase 4 — Fallback & logs UI (3–4d)

- [ ] Port `FallbackScreen` + `FallbackSheets` into the fork package
      (restyled minimally to fit the new settings aesthetic).
- [ ] Navigation seam: `NavigationPage` case + settingsPages/title/render
      case; localization keys.
- [ ] Port `LogsScreen` (request history/stats, fallback-attempt badges);
      page gating local-proxy + loggingToFile.
- [ ] Light/dark + localization pass. Tag `port/phase-4-green`.

## Phase 5 — Remote mode (2–3d)

- [ ] `ForkOperatingModeManager` (monitor/localProxy/remoteProxy; remote
      config in UserDefaults `remoteConnectionConfig`; management keys in the
      fork keychain service pattern).
- [ ] Fork wrapper management client with remote base URL + verifySSL +
      timeouts (prefer wrapper over editing `ProxyEndpoint`; fall back to a
      minimal upstream edit only if wrapping is impossible).
- [ ] Port RemoteConnectionSheet, onboarding remote step, dashboard remote
      branch, sidebar remote status row.
- [ ] E2E: connect to a remote CLIProxyAPI instance; quota/config round-trip;
      management key persisted in keychain. Tag `port/phase-5-green`.

## Phase 6 — Gemini quota kit (2–4d)

- [ ] **Spike first:** presentation merge point (host-snapshot tiles vs
      dedicated Gemini section); record the choice here before building.
- [ ] Port the fetcher's native path (`~/.gemini` files + direct Google token
      refresh, atomic write-back) and the monitor-vault path (accounts
      imported via upstream legacy migration).
- [ ] Add `/api-call` relay (plus binary) to the fork wrapper client for the
      management-API-relayed quota path with `$TOKEN$` substitution.
- [ ] Bucket→series grouping, tier labels, `gemini-2.0-flash` filtering,
      refresh cadence, menu-bar display.
- [ ] Tag `port/phase-6-green`.

## Phase 7 — Upgrade path from fork v0.22.0 (1–2d)

- [ ] Snapshot a real fork-0.22.0 data dir (UserDefaults plist, keychain
      items where feasible, App Support tree).
- [ ] Verify: monitor accounts import via `QuotioCLILegacyAccountMigration`;
      fallback/remote/bridge-mode settings carry over; proxy plus install is
      re-adopted; request history file survives.
- [ ] Fix divergences found; document any manual steps users must take
      (target: none). Tag `port/phase-7-green`.

## Phase 8 — Release pipeline (1–2d)

- [ ] Move fork scripts to the monorepo layout; add rustup/cargo bootstrap;
      build helper per-arch via upstream `build_cli_helper.sh`.
- [ ] Sign + notarize: app, embedded helper, plus binary as signed resource;
      Developer ID flow (already adapted once for #499).
- [ ] DMG packaging + `verify-bundled-proxy.sh` in the build; version bump
      (recommend aligning MARKETING_VERSION to the upstream base version).
- [ ] Tag `port/phase-8-green`.

## Phase 9 — QA, merge-forward, close-out (1–2d)

- [ ] Manual QA matrix: OAuth for 2–3 providers, proxy lifecycle
      (start/stop/crash-restart/port change), fallback E2E matrix (429/503/
      thinking-signature/cache-hit), remote mode, Gemini display, upgrade
      path, light/dark, menu bar rendering.
- [ ] Merge-forward: `git merge upstream/master` (the shakedown of the new
      sync model); resolve seam conflicts; re-run the build+test gates.
- [ ] Open the PR into fork `master`; archive this openspec change; update
      fork docs (AGENTS.md paths, invariants) and the sync-memory notes.

## Pinned base

- Planned against upstream master `efe2f82` (2026-09-29). Re-pin at kickoff
  and record the actual SHA here: `efe2f82f878060f983d38e262f2f69e4e065fb78`
  (branch `port/upstream-monorepo` created from it, 2026-09-29).
