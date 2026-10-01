# QuotioForkExtras

Fork-owned features for the [GeorgeDong32/quotio](https://github.com/GeorgeDong32/quotio)
fork of Quotio. Everything the fork adds lives in this package (plus bounded
wiring in `apps/macos/Quotio/App/CompositionRoot.swift`), so that merging
`upstream/master` stays cheap and conflicts stay confined to a known seam list.

The seam list (upstream files the fork is allowed to touch) is documented in
[`openspec/changes/archive/port-to-upstream-monorepo/design.md`](../../openspec/changes/archive/port-to-upstream-monorepo/design.md).
Living specifications for fork-owned capabilities live in
[`openspec/specs/`](../../openspec/specs/).

## Module map

| Module | Purpose |
| --- | --- |
| `Fallback/` | The fallback engine: virtual-model routing, response-pattern classification, retry loop, and the fallback settings UI. `ProxyBridge` is the in-process forwarding proxy; `FallbackProvider`/`FallbackModels` drive the routing decisions. |
| `ProxyIntegration/` | Proxy binary lifecycle: `ForkProxyBinarySource` + `ForkProxyVersionRepository` (source selection), `FallbackProxyLifecycleCoordinator` (source-aware coordinator wrapping the upstream lifecycle controller), `PlusBinaryStore` (bundled, sha-pinned plus binary), `BridgePortMetadataRepository`. |
| `ApiKeys/` | The fork-owned API Keys page (`APIKeysScreen` / `APIKeysScreenModel`). UX is frozen — see the contract below and the [`api-keys-page` spec](../../openspec/specs/api-keys-page/spec.md). |
| `RequestLogs/` | Per-request logging and the request-history screen (`RequestTracker`, `RequestLog`). |
| `RemoteMode/` | Remote CLIProxyAPI connection settings (`ForkRemoteConnection`, `RemoteConnectionScreen`) — point the app at a proxy running on another machine. |
| `Adapters/` | No-op stand-ins for upstream integrations the fork ships without: `NoOpApplicationUpdateChecker` (replaces Sparkle) and `NoOpTelemetryTracker` (replaces PostHog). |
| `ForkExtras.swift` | Package-level entry point / re-exports. |

## Bridge topology

`ProxyBridge` listens on the **user port** (Settings → CLIProxyAPI; the port is
user data stored in `defaults … proxyPort` — never assume a specific value).
The proxy binary binds **`userPort + 10000`** on **127.0.0.1 only**. The app
rewrites virtual models inside `ProxyBridge`, so fallback routing is
binary-agnostic: it works identically with the official CLIProxyAPI binary and
the bundled plus build.

## The fork contract — invariants for any upstream sync

These five behaviors are fork-owned acceptance criteria. Sync conflicts here
always resolve fork-side; never silently drop them.

1. **HTTP 400 fallback suppression.** When a fallback is triggered by an
   HTTP-400-class failure, `suppressRouteCacheWrite` in
   `Fallback/ProxyBridge.swift` must guard **both** the route-cache write and
   the route-state UI update. Upstream (and pre-port fork code) treats a 400 as
   a routing decision worth persisting; that poisons the cache when the 400 is
   actually the trigger for fallback. Spec:
   [`proxy-fallback`](../../openspec/specs/proxy-fallback/spec.md).
2. **No save-gating on custom providers.** Upstream's `manualModelEntry`
   (CustomProviderSheet) already satisfies this: a custom provider can be
   saved even when its `/v1/models` endpoint cannot be fetched. Never
   reintroduce models-fetch-gated saving.
3. **Sparkle + PostHog stay removed.** The fork ships without both, via the
   no-op adapters in `Adapters/`. Upstream signing/appcast/release commits will
   periodically try to re-add them — resolve fork-side.
4. **The API Keys page is fork-owned and its UX is frozen.** Two-row layout:
   row 1 is a full-width key input (`.labelsHidden()`, monospaced, middle
   truncation), row 2 is right-aligned **Generate** + prominent **Add**.
   Generate fills and focuses the field as an **editable draft** — nothing is
   saved until Add. The input box must never resize on content. SwiftUI
   lesson: a Form row never grants width to a field sharing it; only a lone
   full-width field or `frame(width:) + .fixedSize()` holds. Spec:
   [`api-keys-page`](../../openspec/specs/api-keys-page/spec.md).
5. **Proxy binary source selection is functional-layer only — no picker
   page.** A dedicated settings page for this was explicitly rejected as
   redundant. `ForkProxyBinarySource` (UserDefaults key
   `selectedProxyBinarySource`, raw values `upstream` / `plusLocal`, default
   `upstream`) selects which binary the coordinator runs;
   `ForkProxyVersionRepository` delegates to `FileProxyVersionRepository`
   (official GitHub flow) or `PlusProxyVersionRepository` (bundled). Version
   list / install / rollback / delete live in the **existing**
   Settings → CLIProxyAPI manage-versions sheet. Never delete the active
   version; verify the bundled binary with
   `apps/macos/scripts/verify-bundled-proxy.sh`. Spec:
   [`proxy-binary-source`](../../openspec/specs/proxy-binary-source/spec.md).

### Deliberate absence: Gemini CLI quota

Removed at `a6a2b8fb` (2026-09-29). Google retired the free-tier quota API
(`UNSUPPORTED_CLIENT`). **Do not re-add** unless Google revives it; the kit
remains in git history for reference.

## Adding a fork page

Do not fork upstream navigation code. Register the page through
`ForkPageRegistry`
(`Packages/QuotioCore/Sources/QuotioPresentation/Settings/ForkPageRegistry.swift`,
a bounded seam edit) and provide the screen from this package, wired in
`CompositionRoot`.
