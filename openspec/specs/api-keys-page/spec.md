# api-keys-page Specification

## Purpose

The fork-owned API Keys page (generate and manage API keys for the local
proxy). Implemented in
`Packages/QuotioForkExtras/Sources/QuotioForkExtras/ApiKeys/`
(`APIKeysScreen`, `APIKeysScreenModel`). The UX is **frozen**; upstream syncs
must not restyle or re-gate it.

## Requirements

### Requirement: Two-row entry layout

The key entry area shall be a two-row layout: row 1 is a single full-width
key input (label hidden via `.labelsHidden()`, monospaced font, middle
truncation); row 2 holds the actions, right-aligned: **Generate** followed by
a prominent **Add** (bordered-prominent), with Add disabled while the input is
empty after trimming.

#### Scenario: Layout shape

- **WHEN** the API Keys page is shown
- **THEN** the key input occupies the full available width on its own row
- **AND** Generate and Add sit on a second row, flush right

### Requirement: Generate produces an editable draft

**Generate** shall fill the input with a newly generated key and focus it for
editing. Nothing is saved until **Add** is clicked; Add saves the (possibly
edited) value and clears the field.

#### Scenario: Generate then edit then Add

- **WHEN** the user clicks Generate
- **THEN** the input fills with a generated key and receives keyboard focus
- **WHEN** the user edits the value and clicks Add
- **THEN** the edited value is saved and the input is cleared

#### Scenario: Generate without Add saves nothing

- **WHEN** the user clicks Generate and leaves the page without clicking Add
- **THEN** no key is persisted

### Requirement: Stable geometry

The input row shall never resize based on its content. A Form row does not
grant width to a field sharing it; only a lone full-width field or
`frame(width:) + .fixedSize()` holds — layout changes must preserve this.

#### Scenario: Long key does not widen the box

- **WHEN** the input contains a key longer than the visible width
- **THEN** the input box keeps its width and truncates the middle of the value
