# Port the fork onto the upstream monorepo architecture

## Why

Upstream `nguyenphutrong/quotio` restructured into a monorepo (macOS app at
`apps/macos`, Rust `quotio` CLI host at `apps/cli`, Swift packages under
`Packages/`) and moved accounts/discovery/quota ownership into the Rust host.
Since that restructure, every file path the fork customizes has moved, so the
cherry-pick sync model is dead: as of 2026-09-29 there are ~477 unpicked
upstream commits and no three-way merge baseline exists between the fork line
and upstream master.

Fallback routing (ProxyBridge) is a hard requirement for this fork and was
deleted upstream, so it cannot be regained by syncing. The goal of this change
is to pay the migration cost **once**: rebuild the fork on top of current
upstream master so that the two lines share git ancestry again, and isolate
fork-owned code so future syncs are ordinary `git merge upstream/master`
operations with a small, known conflict surface.

## What Changes

- New integration branch based on **upstream master tip** (not the v0.33.0
  tag — the host migration finished *after* that tag; see design D0). All fork
  customizations are re-committed as new commits; no old history is grafted.
- New fork-only Swift package `Packages/QuotioForkExtras` hosting the ported
  fallback subsystem (ProxyBridge, fallback settings, request logging), remote
  proxy mode, and the Gemini quota kit, with edits to upstream files limited
  to a bounded seam list (~10 files).
- Identity hygiene: keep bundle id `dev.quotio.desktop`, remove Sparkle and
  PostHog via no-op adapters, re-apply GLM endpoint and agent-config tweaks.
- Release pipeline rebuilt for the monorepo layout, including the Rust helper
  build (`cargo`) and signing/notarization of the app plus embedded helper and
  the bundled `cli-proxy-api-plus` binary.
- Upgrade path from fork v0.22.0 validated against upstream's legacy account
  migration (which already consumes the fork's `Monitor/accounts-v1.json` +
  `<bundle>.monitor-auth` keychain format).

## Impact

- ~16–28 focused dev-days across 10 phases (see tasks.md); every phase ends
  buildable and committable.
- Accepted drops: YubiKey secret vault (upstream retired it and ships a
  credential migration), the old settings TabView layout, fork-specific
  manual-model-entry implementation (upstream now ships `manualModelEntry`
  with no save gating).
- Invariants preserved: ProxyBridge targets localhost only;
  `ProxyStorageManager` never deletes the current proxy version; agent config
  backups are never overwritten; no tokens in logs.
