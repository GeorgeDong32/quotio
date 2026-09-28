# Host REST API

The Rust host owns account identity, names, native discovery, provider requests,
refresh scheduling and quota interpretation. CLI JSON output and HTTP snapshots
use the same resolved schema. Clients display that data and submit commands.

## Start a host

```sh
cargo run -- serve --provider codex --provider amp
```

A fixture-only host needs no saved accounts or provider credentials:

```sh
cargo run -- serve --provider mock --no-saved-accounts
curl http://127.0.0.1:6767/health
curl http://127.0.0.1:6767/v2/providers
curl http://127.0.0.1:6767/v2/snapshot
```

The foreground process prints its listening address to stderr. Use
`--listen 127.0.0.1:0` for an available port or `--listen '[::1]:6767'` for IPv6
loopback. Ctrl-C or SIGTERM stops the host on Unix.

| Option | Default | Meaning |
| --- | --- | --- |
| `--listen` | `127.0.0.1:6767` | Loopback address; non-loopback listeners are rejected |
| `--provider` | Config selection | Repeat to override configured providers |
| `--config` | Platform config path | Host settings in TOML |
| `--refresh-interval` | Config, then `60` | Seconds after a completed cycle; `0` means manual quota refresh |
| `--timeout` | Config, then `10` | Per-provider collection deadline |
| `--no-saved-accounts` | Off | Bypass the account vault and collect explicit environment/local sources |
| `--manage` | Off | Enable mutations; requires authentication |
| `--public-url` | None | Exact external HTTPS origin behind a reverse proxy; requires authentication |
| `--allow-origin` | None | Exact allowed browser origin; repeat for multiple origins |

Without overrides, the host uses `enabled_providers` minus `disabled_providers`.
`automatically_discover_logins` controls native discovery at startup and before
scheduled refreshes. Manual quota cadence still permits startup discovery.
Native quota collection uses registered sources; it cannot bypass discovery by
silently reading another local login. Explicit environment credentials remain
independent sources. Borrowed credentials are read-only.

## Default contract and routes

API version 2 is the only supported HTTP contract. There is no version-selection
flag or v1 fallback. [openapi.json](openapi.json) defines request fields and response
schemas.

| Request | Purpose |
| --- | --- |
| `GET /health` | Listener and refresh readiness |
| `GET /v2/status` | Scheduler state, API version, client ID, access mode and settings revision |
| `GET/POST /v2/clients` | Owner-only list or issuance of client credentials |
| `DELETE /v2/clients/{id}` | Owner-only credential revocation |
| `GET /v2/snapshot` | Resolved accounts, source health, quota, issues and revision |
| `GET /v2/providers` or `/v2/providers/{id}` | Provider names, available actions and input metadata |
| `GET /v2/accounts` or `/v2/accounts/{id}` | Resolved logical account metadata |
| `POST /v2/accounts` | Create an owned account |
| `PATCH /v2/accounts/{id}` | Rename/reset, enable/disable or select a logical account |
| `DELETE /v2/accounts/{id}` | Remove the account's registered sources |
| `POST /v2/sources` | Register an explicit supported source reference |
| `PATCH /v2/sources/{id}` | Enable/disable a source or replace its owned API key |
| `DELETE /v2/sources/{id}` | Unlink that source |
| `GET /v2/discovery` | Host scan status and pending permissions |
| `POST /v2/discovery` | Scan selected providers; `restore_removed: true` explicitly restores removed sources |
| `POST /v2/sources/discover` | Bounded metadata inspection with opaque discovery references |
| `POST /v2/sources/authorize` | Explicit OS authorization for a supported source |
| `POST /v2/account-vault/authorize` | Explicit OS authorization for Quotio's vault |
| `POST /v2/migrations/accounts` | Idempotent import of existing native-app account data |
| `POST /v2/auth/sessions` | Begin the provider-declared OAuth workflow |
| `GET/DELETE /v2/auth/sessions/{id}` | Poll/cancel a session |
| `POST /v2/auth/sessions/{id}/callback` | Submit manual code or an explicitly selected relay callback |
| `GET/PATCH /v2/settings` | Read or change host settings |
| `POST /v2/refresh` | Request a refresh operation |
| `GET /v2/operations/{id}` | Read operation status |
| `GET /openapi.json` | OpenAPI 3.1 document |

Reads remain available without management mode. Mutations require `--manage`.
Account and source writes require an `Idempotency-Key` containing 1–128 visible
ASCII characters. Query parameters are not supported. `HEAD` returns no body;
allowed CORS preflights use `OPTIONS`.

## Accounts and quota

Snapshots use `schema_version: 2`, a host ID, a revision, `generated_at`, `accounts`
and `usage`. Logical account IDs differ from physical source IDs. Clients follow
only explicit `account_redirects`; they do not match accounts by email, labels,
token fingerprints or identical quota. Only authenticated provider identity
allows the host to group sources.

Use the host's `display_name`, source selection, connection state, quota state,
metric units and recovery actions. Unknown quota stays unknown. A stale result
retains its original fetch timestamp; `generated_at` is not proof of freshness.
Supplemental profile, subscription and reset-credit observations remain attached
to the selected source. Expired reset credits are omitted even between refreshes.
There is no reset-credit redemption route.

Actions and host capabilities reflect the running server's access mode and
account-storage availability. Read-only hosts advertise no mutation or refresh
actions. Clients must honor `available` and retain the supplied reason code.

`usage.summary` supplies session-only and combined totals (lowest and average),
plus an optional two-metric display pair. Clients choose a display preference and
format these values; they must not regroup provider metrics or recompute totals.
A null percentage means unknown, not zero or unlimited.

A restarted host restores cached observations for matching credential identities,
including when automatic refresh is disabled. Restoration performs no provider
fetch and preserves observation timestamps, so expired quota remains `stale`.
A new host can publish registered accounts with `not_loaded` quota before its
first refresh. Provider failures do not hide healthy accounts. Invalid snapshots
and unavailable protected storage return errors rather than an empty account list.
The explicit `--no-saved-accounts` mode uses a session-scoped host ID and never opens
the protected vault.

`PATCH /v2/accounts/{id}` accepts `user_label`; `null` restores provider naming.
Source enablement and unlinking use the source route. Unlinking a borrowed source
never edits its native login. Persisted suppression prevents automatic scans and
implicit CLI collection from immediately restoring it. An explicit restore scan
can register it again; already disabled sources remain disabled.

Available provider/account/source actions come from Rust. Render supported actions
and input fields rather than maintaining a provider switch. API-key input metadata
uses top-level `region`/`organization` or `settings.<name>` paths. Omitted settings
are preserved during key rotation; explicit null values follow the schema's reset
rules. A rejected mutation does not apply a partial name or credential change.

## Refresh and settings

HTTP reads do not fetch provider quota. The scheduler and manual operations share
collection, cache locking and generation fences. Collection runs one cycle at a
time. Only missing/expired cache entries are fetched unless `force` is true.
`cache_ttl_seconds` and `refresh_interval` have separate purposes.

`POST /v2/refresh` returns 202 with an operation. Its completed result contains
provider/failure counts, not an alternate raw quota report. Read `/v2/snapshot`
for the authoritative resolved view. An account-scoped refresh names exactly one
provider and its logical account ID. Unscoped refreshes use tracked providers.

Settings patches include the current `revision`. A stale revision returns 409
`revision_conflict`; read current settings before retrying. Startup overrides are
listed in `overridden` and cannot be changed through the API. Reading settings
also detects external configuration edits and wakes the scheduler safely.

Successful account writes store retry receipts in the protected vault. Retrying
the same intent after restart does not repeat a credential exchange. A changed
body with the same key is a conflict. `credential_commit_uncertain` means a write
may already be visible: inspect current accounts or retry the same intent rather
than starting another login. Operation IDs themselves are process-local.

## OAuth and native authorization

The host chooses the OAuth workflow and owns its deadline. Clients open the supplied
HTTPS URL, display a supplied device code or manual-code field, and poll the session.
`processing` means exchange or persistence has been claimed. Terminal states are
`completed`, `failed`, `cancelled` and `expired`. Completion supplies an account ID;
read that account instead of constructing a client-side name or identity.

Native inspection does not grant OS access or open background permission dialogs.
An explicit authorization request can require interaction on the host. Scan status
and pending permissions persist in the protected vault across restart; reads recheck
registered and removed sources. Native references remain bounded and read-only; access/refresh tokens and private source
paths are never returned in discovery results.

## Authentication and HTTPS deployment

Set `QUOTIO_SERVER_TOKEN` to require bearer authentication on every route, including
health checks. Tokens contain 32–4096 visible ASCII characters and travel in the
Authorization header. The host never accepts a token in a URL or command argument.
Management mode and `--public-url` require a token.

The listener stays on loopback. An HTTPS reverse proxy may expose the exact origin
configured by `--public-url`. Host headers must match the listener or that configured
origin; forwarded headers do not establish trust. Browser origins must be explicitly
listed with `--allow-origin`. Responses use `Cache-Control: no-store` and do not
expose credentials in logs or errors.

## Client credentials

Keep the owner token (`QUOTIO_SERVER_TOKEN` or the native bootstrap token) on the
host. On a management-enabled host, use it to issue a separate credential with
`POST /v2/clients`:

```json
{"label":"Phone","scope":"read","expires_in_seconds":2592000}
```

The response includes `host_id`, client metadata and a `token`. Save that token
securely: the host returns it only once. If the response is lost, list the clients,
revoke the lost credential, and issue a new one. Do not automatically retry issuance.

A `read` client can read snapshots, provider/account metadata, settings, discovery
status and health. It cannot change settings or accounts, request a refresh, issue
credentials, or inspect OAuth sessions and operations. Returned capabilities reflect
those limits. `GET /v2/status` reports the caller's `client_id` and access mode.

Credentials expire after 30 days by default. The owner can choose 1 second through
365 days when issuing one. Each vault supports up to 64 unexpired clients. The
protected vault stores only a hash bound to its host ID. Expired, revoked, altered,
or wrong-host credentials receive `401`. An unavailable credential store returns
`503`, allowing the client to retry without discarding its credential.

Revoke with `DELETE /v2/clients/{id}`. This blocks later requests and is safe to
repeat. Client listing never returns tokens or hashes. Client management requires
the saved-account vault and is unavailable with `--no-saved-accounts`.

## Local approval

A host exposed with `--public-url` does not accept OS approval requests or Codex
browser sign-in through HTTP. Complete those actions on the host itself. The API
returns `host_interaction_required`, and provider actions reflect that restriction.
Device-code and manual-code workflows remain available where the provider supports
them. Delegated clients never receive OS approval authority.

OAuth sessions, operation IDs, retry keys and opaque discovery references belong
to the requesting client. The owner may inspect client operations and sessions.
Revocation cancels pending client OAuth sessions. Before committing account,
settings or OAuth changes, the host checks that the client still has permission.
Already-started reads may finish.

## Native parent bootstrap

`serve --manage --parent-pipe --listen 127.0.0.1:0` uses an inherited Unix stdin pipe.
Within five seconds the parent sends one JSON object followed by LF, at most 16 KiB:
`token` holds the bearer token; optional `preferences` carries
`disabled_providers`, `automatically_discover_logins` and `refresh_interval`.
Do not also set `QUOTIO_SERVER_TOKEN`.

Rust imports only configuration fields that are absent before starting work.
Later launches preserve persisted host choices. The parent retains its old
preferences solely as migration input.

After initialization the helper emits one stdout record:

```json
{"bootstrap_version":2,"api_version":2,"server_version":"0.2.12","pid":123,"host":"127.0.0.1","port":49152}
```

Validate the version, owned child PID and loopback address, then authenticate
`/v2/status`. The record means the listener is bound, not that quota has loaded.
Keep stdin open: EOF, read failure or unexpected extra input ends the session.
