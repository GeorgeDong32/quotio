# proxy-config-ownership Specification

## Purpose

Fork-owned ownership switch for the provider/model sections of the proxy
`config.yaml`: while manual provider config mode is enabled, Quotio keeps
managing the proxy process and still writes back the port and management
key, but never rewrites the provider sections — hand edits survive every
proxy (re)start, including silent health-recovery restarts. Implemented in
`Packages/QuotioForkExtras/Sources/QuotioForkExtras/ManualConfig/`
(`ManualProviderConfigStore`, `ManualModeConfigurationSynchronizer`,
`ProviderConfigScreen`), wired in `CompositionRoot.swift`.

## Requirements

### Requirement: Mode storage

Manual provider config mode shall be persisted in UserDefaults under
`manualProviderConfig` (Bool), defaulting to disabled. Disabled preserves
upstream behavior exactly: provider sections are re-rendered from the
app's custom providers before every proxy start.

#### Scenario: Fresh install / default

- **WHEN** no `manualProviderConfig` value is stored
- **THEN** provider sections are synchronized (upstream behavior unchanged)

#### Scenario: Choice survives restarts and upgrades

- **WHEN** the user enables the mode and later restarts or upgrades the app
- **THEN** the stored value is honored without re-prompting

### Requirement: Synchronization gating

While enabled, `ManualModeConfigurationSynchronizer` shall suppress the
managed-sections rewrite for both write paths — the lifecycle
`configurationSupplement` invoked before every proxy start and the
Providers screen's explicit synchronize — without throwing. Port and
management-key write-backs (and all other configuration-repository
mutations) shall remain active in both modes.

#### Scenario: Hand edits survive proxy restarts

- **WHEN** the mode is enabled and the user hand-edits the
  `openai-compatibility`, `claude-api-key`, `gemini-api-key`,
  `codex-api-key`, or `glm-api-key` sections
- **THEN** a proxy start (manual restart, app launch, crash recovery, or
  health-recovery restart) leaves those sections byte-identical
- **AND** the port and management key are still written back

#### Scenario: In-app provider edits while enabled

- **WHEN** the mode is enabled and the user saves or deletes a custom
  provider in the app
- **THEN** the change is stored in the app's UserDefaults only and is not
  written to `config.yaml`

#### Scenario: Turning the mode off

- **WHEN** the mode is disabled again
- **THEN** the next proxy start re-renders the managed sections from the
  app's custom providers, replacing manual edits to those sections

### Requirement: Settings page

The mode toggle shall live on a fork settings page (Settings → Proxy
Config, registered through `ForkPageRegistry`/`NavigationPage` seams) that
also shows the config.yaml path and a Show-in-Finder action, with footer
copy documenting the semantics above.
