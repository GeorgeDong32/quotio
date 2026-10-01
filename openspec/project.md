# Quotio (fork) — Project Context

## Mission

Quotio is a native macOS menu bar and window app for operating CLIProxyAPI —
provider OAuth accounts, quota monitoring, CLI agent configuration, and the
local proxy lifecycle — plus a Rust CLI (`apps/cli`) for scripts, headless
systems, and automation.

This repository is the **GeorgeDong32 fork**. It tracks
[`nguyenphutrong/quotio`](https://github.com/nguyenphutrong/quotio) (upstream)
and adds fork-only features that live in
[`Packages/QuotioForkExtras`](../Packages/QuotioForkExtras/README.md).
The fork contract (five sync invariants, module map) is documented in that
package's README; living specifications live under
[`openspec/specs/`](specs/).

## Repository layout

| Path | Contents |
| --- | --- |
| `apps/macos/` | Native macOS app (Swift 6 / SwiftUI, macOS 14+). See `apps/macos/AGENTS.md`. |
| `apps/cli/` | Rust CLI + host. See `apps/cli/README.md` and `apps/cli/docs/`. |
| `Packages/QuotioCore/` | Shared Swift package (Domain, Presentation, Infrastructure, Application layers). |
| `Packages/QuotioForkExtras/` | Fork-owned features (fallback engine, binary-source layer, API Keys, request logs, remote mode, no-op adapters). |
| `Packages/QuotioHostClient/` | Swift client for the host API v2 contract. |
| `openspec/specs/` | Living specifications for fork-owned capabilities. |
| `openspec/changes/archive/` | Archived change proposals/designs (including the port-to-upstream-monorepo decision record). |
| `.github/workflows/` | Repository-level CI and release automation. |

Do not add empty iOS or Windows projects, a root Cargo workspace, or a task
runner until a real consumer requires one.

## Tech stack

- **macOS app:** Swift 6, SwiftUI with targeted AppKit integration; Xcode
  project `apps/macos/Quotio.xcodeproj`, shared scheme `Quotio`.
- **CLI:** Rust (`apps/cli/Cargo.toml`), published to npm as `quotio`.
- **Proxy:** the app operates CLIProxyAPI — the official upstream binary
  (default) or the fork's bundled, sha-pinned `cli-proxy-api-plus`.

## Commands

Run from the repository root:

```bash
swift test --package-path Packages/QuotioCore
./apps/macos/scripts/check_architecture.sh
xcodebuild -project apps/macos/Quotio.xcodeproj -scheme Quotio -configuration Debug -destination 'platform=macOS' test
cargo test --manifest-path apps/cli/Cargo.toml --locked --all-features
```

Release scripts live in `apps/macos/scripts/` (build, package, release,
notarize, verify, verify-bundled-proxy, qa-port); call them by absolute path.

## Conventions

- **Tags:** `v*` for macOS releases, `cli-v*` for CLI releases. Never reuse
  one product's tag namespace for the other; never rewrite shared history.
- **Commits:** conventional commits (`feat:`, `fix:`, `docs:`, …).
- **Upstream sync model:** `git fetch upstream && git merge upstream/master`
  on `master`. Expect conflicts only in the seam files listed in
  `openspec/changes/archive/port-to-upstream-monorepo/design.md`; fork-contract
  conflicts always resolve fork-side (see the QuotioForkExtras README).
- **Identity:** bundle id `dev.quotio.desktop` counts as production
  (AppIdentity). Sparkle and PostHog are intentionally absent (no-op adapters).
- **Bridge topology:** ProxyBridge listens on the user port; the proxy binary
  binds `userPort + 10000` on 127.0.0.1 only.

## Key documents

- `AGENTS.md` — repository rules + fork addendum
- `apps/macos/AGENTS.md`, `apps/macos/README.md`, `apps/macos/RELEASE.md`, `apps/macos/CHANGELOG.md`
- `apps/cli/README.md` and `apps/cli/docs/*` (incl. `host-contract-v2.md`)
- `Packages/QuotioForkExtras/README.md` — the fork contract
- `openspec/specs/*/spec.md` — living specs
- `openspec/changes/archive/port-to-upstream-monorepo/` — port decision record

## Known baseline quirks

- Two upstream tests fail on any dev machine (AgentDetection with a Homebrew
  `claude` on PATH; LocalizationBundle count metrics under some system
  locales). Not fork bugs.
- Agent-session processes cannot bind `NWListener` (POSIX `EINVAL`); E2E
  socket tests auto-skip in agent contexts — run them in Xcode/CI.
