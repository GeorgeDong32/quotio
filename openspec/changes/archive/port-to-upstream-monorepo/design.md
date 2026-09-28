# Design — Port the fork onto the upstream monorepo architecture

## Context

Fork side (v0.22.0, branch `integrate/upstream-v0.28`): the fork owns a
fallback subsystem — an in-process raw-TCP forwarding proxy
(`Quotio/Services/Proxy/ProxyBridge.swift`, ~1100 lines: user port 8080 →
internal port `userPort + 10000` on 127.0.0.1, `Connection: close` injection,
virtual-model fallback retry loop driven by response-pattern classification),
fallback settings (`FallbackSettingsManager`, UserDefaults JSON + lock-guarded
60-min route cache), request logging (`RequestTracker`/`RequestLog`, 50-entry
JSON store), a remote-proxy operating mode (management-API client pointed at a
remote CLIProxyAPI), a bundled 49 MB `cli-proxy-api-plus` binary (version+sha
pinned in code), and a Gemini CLI quota fetcher (three credential paths).
Crucially, ProxyBridge reads **only** FallbackSettingsManager — it never reads
account or quota state — so the subsystem's coupling to the rest of the app is
narrow by construction.

Upstream side (master tip `efe2f82`, 2026-09-29): the repo is a monorepo. The
macOS app target is ~1.2k lines; all logic lives in `Packages/QuotioCore`
(Domain/Application/Infrastructure/Presentation, Swift 6 language mode,
macOS 14+, layering enforced by `apps/macos/scripts/check_architecture.sh` and
guarded by architecture tests). Composition is manual in
`apps/macos/Quotio/App/CompositionRoot.makeProduction()` with `.environment()`
injection. The quota pipeline is host-only: the Rust `quotio` helper (bundled
at `Contents/Helpers/quotio-cli`, HTTP over a random loopback port, bootstrap
handshake v2) owns accounts, discovery, and quota snapshots; the supplemental
observation channel is **Rust→Swift read-only** (no Swift injection endpoint
exists in the v2 contract). Proxy lifecycle is an actor
(`ProxyLifecycleController` implementing `ProxyControlling`) whose binary is
always downloaded from GitHub releases into `…/Quotio/proxy/upstream/v*/` with
a `current` symlink; config YAML is regex-patched at
`…/Quotio/config.yaml`; management API is `URLSessionProxyManagementAPI`
against `http://127.0.0.1:<port>/v0/management`. Operating mode selection was
retired (`b7baa90 refactor(macos)!: retire operating mode selection`) — the
app is monitor-mode-only via the host. Note: the v0.33.0 tag predates
"finish Quotio HTTP migration" and the service retirements; the migration
end-state landed only on master afterwards (~150 commits past the tag).

## Goals

1. Fork behavior survives on the new base: fallback routing + request logs +
   remote mode + Gemini quota + fork identity/update/telemetry decisions.
2. Future upstream syncs are ordinary merges with a small known conflict
   surface (shared ancestry + isolated fork code + narrow seams).
3. Every phase ends with a green build and a committable state.

## Non-Goals

- Upstreaming the fallback subsystem or a Rust-side Gemini provider.
- Redesigning fallback semantics — this is a behavior-preserving port.
- Reviving YubiKey writes (upstream retired them; its credential migration
  covers fork users — accepted drop).
- Keeping the old fork settings TabView layout (upstream's provider-hierarchy
  redesign is the new base).

## Decision Register

### D0 — Base and lineage: new branch from upstream master tip, fresh commits

Candidates: (a) rebase fork line onto upstream master; (b) new branch from
master tip with customizations re-committed; (c) base on the v0.33.0 tag.
Choice: **(b)**, based on master tip at kickoff (re-fetch first; `efe2f82` at
planning time). (a) fails mechanically — paths moved, no merge base. (c) is
wrong: v0.33.0 predates the finished host migration and service retirements;
it would be a half-migrated foundation. Given up: git ancestry of the old fork
commits (preserved read-only on a legacy branch for reference). Risk bearer:
us, during the port window — upstream master is hot (~150 commits in the 12
days before planning). Mitigation: pin the base commit; the final act of the
port is one merge-forward from the then-current upstream master, which doubles
as the shakedown of the new sync model.

### D1 — Fork code isolation: `Packages/QuotioForkExtras`

Candidates: (a) fork edits inside QuotioCore targets; (b) a fork-only SPM
package `Packages/QuotioForkExtras` (single target + tests) depending on
QuotioCore's library products; (c) fork code in the app target.
Choice: **(b)**. QuotioCore already exports
Domain/Application/Infrastructure/Presentation as products. Upstream merges
never touch the fork package; compiler catches product-API drift. Upstream
files stay untouched except for a bounded seam list:
`project.pbxproj` (embed package + plus-binary resource),
`CompositionRoot.swift`, `AppRuntime.swift`, `QuotioApp.swift`,
`PresentationValues.swift` (NavigationPage case), `RootNavigationView.swift`
(settingsPages + title), `AppSettingsPage.swift` (render case),
`QuotioCore/Package.swift` + resolved files (Sparkle/PostHog removal),
`AppIdentity.swift`, `Info.plist`/xcconfigs. Given up: (a)'s frictionless
access to internal QuotioCore symbols (must go through public API; acceptable
— QuotioCore is widely public by design). Watch: architecture guard tests
(`2c70edc`) and `check_architecture.sh` must pass with the fork package
present — validated in Phase 0.

### D2 — Proxy topology: coordinator wrapping `ProxyControlling`

Candidates: (a) modify `ProxyLifecycleController` in place for bridge mode;
(b) fork `FallbackProxyLifecycleCoordinator` in QuotioForkExtras implementing
the same `ProxyControlling` protocol, composing the upstream controller and
ProxyBridge; Choice: **(b)**. CompositionRoot constructs the coordinator
instead of the controller directly (2-line seam). Port pair preserved:
bridge listens on the user port, upstream binary gets the internal port
(`userPort + 10000`) written into config.yaml before start; health checks
target the internal port while bridged; agent configs receive the bridge
endpoint. Bridge mode default **on** (fork parity), with the same
`useBridgeMode` UserDefaults key. Given up: in-place access to lifecycle
internals. Risk: `ProxyControlling` protocol evolution — compiler-caught,
seam-sized.

### D3 — Plus binary: keep the committed blob and the pin

Keep `cli-proxy-api-plus` as a committed 49 MB resource with version+sha256
pinned in code (fork parity: `plusLocal` never auto-updates), installed under
`…/Quotio/proxy/plus/v<version>/` parallel to upstream's `proxy/upstream/`
namespace, ad-hoc codesigned, current-symlink promote, never delete current.
Fork resolver lives in QuotioForkExtras; build-time verification script moves
to the monorepo layout. Given up: repository size (already sunk in fork
history). Risk: plus binary (6.9.28) vs the new config.yaml template
(routing.strategy, quota-exceeded, request-retry keys) — verified in Phase 3
by dry-run + `/meta` compat probe before promote.

### D4 — Identity: keep `dev.quotio.desktop`, neutralize the rename migration

Keep the fork bundle id; upstream's `AppIdentity.migrateLegacyUserDefaults()`
(dev.quotio.desktop → app.bytrong.quotio) is disabled/inverted so fork
users' UserDefaults and keychain services stay put. Rust-side naming follows
automatically: helper args use `--account-vault-namespace` /
`--account-data-dir` derived from the effective bundle id, and custom provider
references resolve against the effective bundle domain (upstream `c4433e5`).
Given up: nothing. Risk: new upstream spots hardcoding `app.bytrong` — grep
each sync (currently only `QuotioCLIServerProcess` constants).

### D5 — Sparkle / PostHog: no-op adapters, then dependency removal

Candidates: (a) delete controllers + UI wholesale (fork's historical
approach); (b) inject no-op implementations of `ApplicationUpdateChecking` /
`TelemetryTracking` at the CompositionRoot seam, hide the UI sections, then
drop the package deps, Info.plist keys, xcconfig vars, workflow env, and
script plumbing per the mapped checklist. Choice: **(b)** — smallest diff,
keeps upstream structure. Given up: some dead controller code retained.
Token in `check_architecture.sh` guards moves from `Sparkle`/`PostHog` to
`QuotioForkExtras` guards.

### D6 — Remote mode: fork-owned mode manager, connection-carried base URL

Upstream retired mode selection; do **not** resurrect its OperatingModeManager.
QuotioForkExtras ships `ForkOperatingModeManager`
(monitor/localProxy/remoteProxy + `remoteConnectionConfig` UserDefaults +
management-key keychain). For outbound calls, prefer a fork wrapper client
(subclass/wrap of `URLSessionProxyManagementAPI` taking a connection with a
remote base URL + verifySSL) over editing upstream's `ProxyEndpoint` — keeps
the seam list minimal; only edit upstream if the wrapper proves impossible.
Port RemoteConnectionSheet, the onboarding remote step, and the dashboard
remote branch into the fork package. Given up: upstream UI evolution for
those screens must be re-merged by hand (they no longer exist upstream —
nothing to merge; the cost is semantic drift only). Risk: moderate.

### D7 — Gemini: Swift-side kit, presentation-level merge

Candidates: (a) Rust-side provider in `apps/cli`; (b) Swift injection via the
supplemental channel; (c) Swift-side `GeminiKit` in QuotioForkExtras merging
results at the presentation layer. Choice: **(c)**. (b) is impossible — the
supplemental channel is Rust→Swift read-only (verified against the v2 contract
and openapi.json). (a) maximizes conflict surface against the fastest-moving
upstream directory. Port the fetcher's pure-Swift credential paths (native
`~/.gemini` files with direct Google token refresh; monitor vault accounts
imported via upstream's legacy migration) plus the management-API-relayed
path against the plus binary (`/api-call` with `$TOKEN$` substitution — fork
adds the endpoint to its wrapper client). Display merge point is the main
design risk: spike first (merged tiles vs a dedicated Gemini section) at the
start of Phase 6. Given up: Gemini living in the host snapshot as data of
record. Note: the `gemini`/`antigravity` external keychain read stays
fork-side discovery.

### D8 — Request logs: port as-is, new navigation seam

`RequestTracker`/`RequestLog` port unchanged (50-entry JSON at
`…/Quotio/request-history.json`, same callback wiring from ProxyBridge). The
Logs page returns as a fork screen via the NavigationPage seam
(case + settingsPages/title + render case). Gating: local-proxy mode +
loggingToFile (fork parity).

### D9 — Upgrade path: upstream migration machinery + same-key carry-over

Fork v0.22.0 users land on the ported build with the same bundle id, hence
the same UserDefaults domain, keychain services, and app-support dir.
Upstream's `QuotioCLILegacyAccountMigration` already imports the fork's
`Monitor/accounts-v1.json` + `<bundle>.monitor-auth` entries (same format the
fork inherited). `fallbackConfiguration`, `remoteConnectionConfig`,
`useBridgeMode` keys carry over untouched. Proxy storage: fork's
`proxy/plus/v6.9.28-0` installs remain valid; config.yaml at the same path is
re-patched by the new repository (template drift verified in Phase 3).
Validated in Phase 7 against a snapshot of a real fork-0.22.0 data dir.

### D10 — Accepted drops (explicit)

YubiKey secret vault (upstream retired writes; migration imports credentials);
old settings TabView; fork's manual-model-entry + save-anyway implementation
(upstream ships `manualModelEntry` with no save gating — UX parity check in
Phase 1, extend only if a gap is found); telemetry (stays off); Sparkle
(stays removed); v1.0.0-beta update channel (fork ships via its own pipeline).

## Risks / Mitigations

| # | Risk | Mitigation |
|---|------|------------|
| R1 | Upstream master velocity (~150 commits / 12 days) during the port | Pin base commit; merge-forward once at the end as the sync shakedown; quarterly merges after |
| R2 | Architecture guard tests / check_architecture.sh reject the fork package | Validate in Phase 0 before any porting; extend guards for QuotioForkExtras |
| R3 | Swift 6 strict concurrency on ported NWListener/NWConnection code | Rewrite route cache as a locked store or actor; bridge callbacks via @Sendable continuations; unit-test concurrency in Phase 2 |
| R4 | Plus binary vs new config.yaml template | Dry-run + /meta compat probe before promote (Phase 3) |
| R5 | Gemini presentation merge point design | Spike at Phase 6 start; dedicated section is the fallback design |
| R6 | Rust toolchain in the fork release pipeline | build_cli_helper.sh already parameterizes archs/binary; add rustup bootstrap to fork scripts (Phase 8) |
| R7 | Seam-file churn on every future sync (~10 files, small hunks) | Bounded by design; seam list documented here |
| R8 | Helper contract keeps breaking (bootstrap v2 landed 2026-09-25) | Pin base; re-run helper handshake tests after merge-forward |
| R9 | Upgrade-path edge cases (keychain accessibility, disabled accounts) | Phase 7 tests against a real data snapshot |
| R10 | DMG size / notarization with two embedded binaries | Fork already shipped 49 MB; notarize app + helper per upstream flow, plus binary rides as a signed resource |

## Rollback

Everything happens on the port branch; fork `master` is untouched until the
final merge PR. Each phase is tagged (`port/phase-N-green`). The legacy fork
line stays intact as `legacy/fork-v0.22` for hotfix-only reference. Aborting
at any point = delete the port branch; zero impact on shipping builds.
