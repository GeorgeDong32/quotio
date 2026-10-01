# QuotioHostClient

Swift client library for the **Quotio host API v2** — the contract implemented
by the Rust host in [`apps/cli`](../../apps/cli/README.md) (the bundled Quotio
helper). The macOS app reaches this package through the
`QuotioCore/QuotioInfrastructure/QuotioCLI` layer to read host snapshots and
submit commands.

- Platforms: macOS 14+, iOS 15+ · Swift 6 language mode
- Decode-only client: all types are `Decodable` value models; no UI, no storage.

## Contents

| Source | Models |
| --- | --- |
| `QuotioHostHTTPClient.swift` | `QuotioHostConnection` (base URL + token), `QuotioHostClientError`, the HTTP client with no-redirect handling. |
| `QuotioHostSnapshot.swift` | `QuotioHostSnapshot` — availability, host identity, accounts, quotas, consumption metrics, summaries. |
| `QuotioHostDiscovery.swift` | `QuotioHostDiscovery` — native credential-source scans, permissions, failures. |
| `QuotioHostProviders.swift` | Provider catalog types. |
| `QuotioHostSettings.swift` | Monitoring/cache settings types. |
| `QuotioHostSupplemental.swift` | Supplemental data: Codex profile + daily usage, reset credits, subscription tiers. |

## Contract

The source of truth for the v2 contract is **not** this package:

- [`apps/cli/docs/host-contract-v2.md`](../../apps/cli/docs/host-contract-v2.md) — the resolved contract document
- `apps/cli/docs/openapi.json` and `apps/cli/src/contract.rs` — machine-readable definitions

Contract rules that matter to this client: `schema_version` is exactly `2`
and incompatible majors must be rejected before mutating client state; Rust
owns account resolution — clients must not merge accounts or invent display
names client-side; clients store selections by `(host.id, account.id)`, never
by display name; clients tolerate unknown compatibly-added fields but must
not infer meaning for them.

## Tests

`swift test --package-path Packages/QuotioHostClient`
