# Tasks — Port the fork onto the upstream monorepo architecture

Every phase must end with: `xcodebuild -project apps/macos/Quotio.xcodeproj
-scheme Quotio -configuration Debug build` green, `swift test` green inside
`Packages/QuotioCore` (and `Packages/QuotioForkExtras` once it exists), and a
tagged, committable state. Conventional commits; never commit to `master`.

## Phase 0 — Baseline bring-up (0.5–1d)

- [x] `git fetch upstream`; create `port/upstream-monorepo` from the fetched
      master tip (record the pinned SHA in this file).
- [x] Build upstream as-is: Debug build (the "Embed Quotio CLI" phase must
      succeed — requires local rustup/cargo), plus `swift test` in
      `Packages/QuotioCore`.
      - Rust toolchain: rustup.rs and static.rust-lang.org are blocked on this
        network; installed via `brew install rust` (cargo 1.98.1). crates.io
        access is intermittent — `cargo fetch` may need a retry.
      - Baseline Debug build green (0 errors / 0 warnings); `quotio-cli`
        helper (57 MB) embedded by the build phase.
      - `swift test`: 503 tests, 1 known environment-dependent failure —
        `AgentDetectionAdapterTests.testForceRefreshInvalidatesSixtySecondCache`
        scans `/opt/homebrew/bin` etc. (commonBinaryPaths) and this machine has
        a real `claude` installed, so `installed` cannot become false. Green in
        upstream CI, red on any dev machine with claude via homebrew. Port
        gate = no NEW failures.
- [x] Create `Packages/QuotioForkExtras` skeleton (Package.swift with target
      + test target depending on QuotioCore products), wire into the xcodeproj,
      confirm `check_architecture.sh` and architecture tests still pass.
      (pbxproj uses fork IDs `F2…`; incremental build green with the package
      compiled and linked.)
- [x] Tag `port/phase-0-green`.

## Phase 1 — Identity & hygiene (1–2d)

- [x] Bundle id stays `dev.quotio.desktop`: xcconfig/pbxproj, AppIdentity
      constants, disable/invert the bytrong UserDefaults+keychain migration.
      (`AppIdentity.productionBundleIdentifier = "dev.quotio.desktop"` with
      bytrong demoted to legacy — REQUIRED anyway: `canMigrateLegacy` gates
      the fork's account migration on isProduction. Rust `QuotioDomain`
      accepts arbitrary bundle ids, no Rust change. AppIdentityTests updated.)
- [x] Sparkle removal: no-op `NoOpApplicationUpdateChecker` in the fork
      package swapped in CompositionRoot; adapter file deleted; Package.swift
      + both Package.resolved pruned; Info.plist SU* keys removed. Verified in
      the product: no Sparkle.framework, no SU keys. build_dmg.sh/workflow
      appcast plumbing deferred to Phase 8 (fork ships its own pipeline).
- [x] PostHog removal: no-op `NoOpTelemetryTracker`; adapter file replaced by
      `BundleTelemetryRuntimeContextProvider.swift` (kept the context
      provider); Package.swift/resolved pruned; Info.plist keys + xcconfig
      vars removed; module tests rewritten (provider test added).
- [x] GLM endpoint: verified fork delta on GLMAPIKeySheet is comment-only —
      GLM is native upstream now, nothing to port.
- [x] Agent-config bits: verified the fork deltas there are fallback/Gemini
      integration points (virtual-model injection, clientEndpoint, Gemini
      preview card) — moved to Phases 2/3/6 where they belong.
- [x] Manual-model-entry parity: upstream `manualModelEntry` (name+alias
      mapping rows) with no save gating — superset of the fork's
      save-anyway spec. Nothing to port.
- [x] Light/dark smoke test deferred to Phase 4 UI pass (Phase 1 made no
      visible-UI changes beyond removals). Gates: app build green; QuotioCore
      502 tests with only the known env failure; app tests green except a
      second known env failure —
      `LocalizationBundleTests.testCountMetricUnitsUseEnglishSingularAndPluralForms`
      (fails on the pristine baseline too; system-locale dependent).
- [x] Tag `port/phase-1-green`.

## Phase 2 — Fork package core: fallback engine (2–3d)

- [x] Port `FallbackModels` + `FallbackSettingsManager` (UserDefaults JSON,
      same `fallbackConfiguration` key); route cache kept as the
      NSLock-guarded `nonisolated(unsafe)` store — compiled clean under
      Swift 6 language mode v6, no rewrite needed.
- [x] Port `FallbackFormatConverter` (error-pattern classifier) and
      `RequestLog`/`RequestTracker` (50-entry JSON store, same path).
- [x] Port `ProxyBridge` (NWListener/NWConnection forwarding, port pair
      user/internal = +10000, localhost-only target, `Connection: close`,
      fallback retry loop, thinking-signature sanitize path). AppIdentity
      refs (dispatch-queue labels) replaced with Bundle.main lookup.
- [x] Fork-local `AIProvider` clone (`FallbackProvider.swift`) with identical
      raw values so users' saved `fallbackConfiguration` JSON decodes.
- [x] Unit tests: 10 tests green — error classification table (status map,
      case-insensitive patterns, 2xx never falls through, nested
      thinking-signature errors), route cache set/get/overwrite/miss,
      model-body rewrite, thinking-block sanitize.
- [x] Gates: app build 0 errors / 0 warnings; package tests 10/10;
      check_architecture.sh passes. Tag `port/phase-2-green`.

## Phase 3 — Proxy integration (3–5d)

- [x] `FallbackProxyLifecycleCoordinator` implementing `ProxyControlling`:
      wraps the upstream controller (actor), starts/stops the bridge around
      the binary, rewrites snapshot ports back to the user port so endpoints
      (ProxyScreenModel.baseURL → agent configs) point at the bridge.
- [x] Port pair via `BridgePortMetadataRepository` (+10000 on load, −10000 on
      save): the controller/config.yaml/health checks see the internal port;
      on-disk port stays the user port.
- [x] CompositionRoot seam swap done (coordinator + wrapped metadata repo +
      PlusProxyVersionRepository; single construction site touched).
      `useBridgeMode` read at coordinator init (default on, same key).
- [x] Plus binary: 49 MB blob moved to `apps/macos/Quotio/Resources/Proxy/`
      (bundle flattens to Resources/ root; resolver covers both); version
      6.9.28-0 + sha256 pinned; `PlusBinaryStore` installs under
      `…/Quotio/proxy/plus/v6.9.28-0/` with current-symlink promote, chmod,
      ad-hoc codesign, checksum fail-closed, never-delete-current;
      update surface (installLatest/checkForUpgrade/availableVersions) is
      fork-parity inert. verify script move deferred to Phase 8.
- [x] Plus binary vs new config template verified live: starts cleanly on the
      exact upstream template; `/v0/management/debug` (the upstream health
      probe) returns 200; `/usage` and `/config` fine.
- [x] E2E test written (`FallbackRoutingIntegrationTests`: fake upstream 429s
      entry 1, bridge retries entry 2, client sees 200). NOTE: this terminal
      environment rejects ALL NWListener binds with POSIX EINVAL (raw BSD
      sockets work) — the test auto-skips here via probe and must run in
      Xcode/CI where Network.framework binds normally.
- [x] Gates: app build 0 errors/0 warnings; package tests 11 (1 env-skip);
      arch check passes; binary present in built product with matching sha.
- [x] Tag `port/phase-3-green`.

## Phase 4 — Fallback & logs UI (3–4d)

- [x] Port `FallbackScreen` + `FallbackSheets` into the fork package,
      re-bound to `FallbackScreenModel` (fork) + `ProxyScreenModel`
      (upstream env) instead of the retired QuotaViewModel; bridge-mode is
      always-on in the ported fork.
- [x] Navigation seam: `NavigationPage` gained `.fallback` + `.requestLogs`
      cases (icons), added to `settingsPages` after CLIProxyAPI, titles
      localized. Rendering goes through a new `ForkPageRegistry`
      (Presentation-owned static registry) so QuotioPresentation stays
      independent of fork packages; CompositionRoot registers the two pages.
- [x] `FallbackScreenModel` provides the model pick list (seeded from
      `AvailableModel.allModels`, live-refresh via the proxy `/v1/models`
      endpoint authenticating with the first config api-key — same source as
      the fork pre-port).
- [x] Request logs: `RequestLogsScreen` ports the fork LogsScreen requests
      tab (stats header, provider filter, search, expandable fallback
      traces); the system-log tab is dropped (it was tied to retired
      upstream UI — accepted trim). Bridge → tracker wired in
      CompositionRoot (`onRequestCompleted` → RequestTracker).
- [x] Localization: 64 fork keys (fallback.*, logs.*) + 6 new port keys
      merged into `apps/macos/Quotio/Localizable.xcstrings`.
- [x] Gates: build 0 errors/0 warnings; arch check passes. Light/dark
      visual pass deferred to Phase 9 QA (can't launch GUI safely next to
      the user's running instance). Tag `port/phase-4-green`.

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
