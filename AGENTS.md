# AGENTS.md

## Repository

Quotio is a monorepo with independent product entry points:

- `apps/macos/`: native macOS app. Follow `apps/macos/AGENTS.md`.
- `apps/cli/`: Rust CLI. Follow its README and existing Cargo conventions.
- `Packages/QuotioCore/`: Swift package shared by the Apple app.
- `Packages/QuotioForkExtras/`: fork-owned features — see its README for the fork contract.
- `Packages/QuotioHostClient/`: Swift client for the host API v2 contract.
- `.github/workflows/`: repository-level CI and release automation.

Do not add empty iOS or Windows projects, a root Cargo workspace, or a task runner
until a real consumer requires one. Keep product-specific code and release assets
inside the owning app directory.

## Commands

Run commands from the repository root unless a project document says otherwise.

```bash
swift test --package-path Packages/QuotioCore
./apps/macos/scripts/check_architecture.sh
xcodebuild -project apps/macos/Quotio.xcodeproj -scheme Quotio -configuration Debug -destination 'platform=macOS' test
cargo test --manifest-path apps/cli/Cargo.toml --locked --all-features
```

Use `v*` tags for macOS releases and `cli-v*` tags for CLI releases. Preserve
both imported histories; never rewrite shared history or reuse one product's tag
namespace for the other.

## Fork addendum (port/upstream-monorepo)

This fork (GeorgeDong32/quotio) tracks upstream and adds fork-only features
that live in `Packages/QuotioForkExtras/` — model-fallback routing
(ProxyBridge + coordinator wrapping the upstream lifecycle controller),
request logging, remote CLIProxyAPI connection, API Keys management, and
proxy binary-source selection (official or bundled plus). Gemini CLI quota
was removed (Google retired the free-tier quota API) and must not be re-added.
Rules that keep future upstream merges cheap:

- Fork-owned code goes in `Packages/QuotioForkExtras` (or app-target wiring
  in `apps/macos/Quotio/App/CompositionRoot.swift`); avoid scattering fork
  logic into upstream files. Fork page registration goes through
  `ForkPageRegistry` (Presentation seam).
- Upstream-file edits are bounded to the seam list documented in
  `openspec/changes/archive/port-to-upstream-monorepo/design.md`.
- Identity: bundle id is `dev.quotio.desktop` and counts as production
  (AppIdentity); Sparkle/PostHog are intentionally absent (no-op adapters).
- The app runs a CLIProxyAPI binary chosen by source (`ForkProxyBinarySource`,
  default: the official upstream binary; alternative: the bundled
  `cli-proxy-api-plus`, version+sha pinned in `PlusBinaryStore`); never delete
  the active version; verify with
  `./apps/macos/scripts/verify-bundled-proxy.sh`.
- Bridge topology: ProxyBridge listens on the user port, the proxy binary
  binds user+10000 on 127.0.0.1 only.
- Sync model: `git fetch upstream && git merge upstream/master` on this
  branch; expect conflicts only in the seam files.
- The fork contract (module map and the five sync invariants) is documented
  in `Packages/QuotioForkExtras/README.md`; living specs live in
  `openspec/specs/`.
