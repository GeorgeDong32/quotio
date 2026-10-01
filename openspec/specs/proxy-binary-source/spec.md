# proxy-binary-source Specification

## Purpose

Fork-owned selection of which CLIProxyAPI binary the app runs: the official
upstream binary (installed and auto-updated by the upstream lifecycle
machinery) or the fork's bundled, sha-pinned plus build. Implemented in
`Packages/QuotioForkExtras/Sources/QuotioForkExtras/ProxyIntegration/`
(`ForkProxyBinarySource`, `ForkProxyVersionRepository`,
`FallbackProxyLifecycleCoordinator`, `PlusBinaryStore`).

## Requirements

### Requirement: Source selection storage

The selected source shall be persisted in UserDefaults under
`selectedProxyBinarySource` with raw values `upstream` and `plusLocal`,
defaulting to `upstream`. Upgraded installs that stored an explicit choice
shall keep it.

#### Scenario: Fresh install

- **WHEN** no `selectedProxyBinarySource` value is stored
- **THEN** the app runs the official upstream binary

#### Scenario: Explicit choice survives upgrades

- **WHEN** the user previously selected `plusLocal` and the app is upgraded
- **THEN** the stored raw value is honored and the plus binary runs

### Requirement: No dedicated picker page

Binary-source selection is a functional layer only. The fork shall not add a
dedicated settings page for it (explicitly rejected as redundant); version
list, install, rollback, and delete live in the existing
Settings → CLIProxyAPI manage-versions sheet.

#### Scenario: Managing binary versions

- **WHEN** the user opens Settings → CLIProxyAPI and manages versions
- **THEN** the existing manage-versions sheet offers install, rollback, and
  delete for the active source's versions
- **AND** no separate "Proxy Binary" page appears in navigation

### Requirement: Source-aware version lifecycle

`ForkProxyVersionRepository` shall delegate to `FileProxyVersionRepository`
for the official GitHub flow and `PlusProxyVersionRepository` for the bundled
binary, and the coordinator shall launch the binary selected by the stored
source.

#### Scenario: Switching source changes the launched binary

- **WHEN** the stored source changes from `upstream` to `plusLocal` (or back)
- **THEN** the coordinator starts the binary matching the new source on the
  next lifecycle run

### Requirement: Active version is never deleted

Version management shall refuse to delete the currently active version, and
the bundled plus binary shall remain pinned by version + SHA in
`PlusBinaryStore`.

#### Scenario: Deleting the active version

- **WHEN** a delete is requested for the active version
- **THEN** the operation is refused

#### Scenario: Verifying the bundled binary

- **WHEN** `apps/macos/scripts/verify-bundled-proxy.sh` runs
- **THEN** the bundled plus binary matches the pinned version and SHA
