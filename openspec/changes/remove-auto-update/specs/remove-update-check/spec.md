## REMOVED Requirements

### Requirement: Automatic application update checking
**Reason**: Fork version does not need upstream auto-update. Sparkle framework and all update checking removed.
**Migration**: No migration needed. Users manage updates manually.

### Requirement: Manual update checking via menu and UI
**Reason**: Update UI elements (menu item, settings section, about card) removed along with the update service.
**Migration**: No migration needed.

### Requirement: Update channel switching (beta/stable)
**Reason**: Tied to Sparkle's feed system. No longer applicable without update framework.
**Migration**: No migration needed. App uses a fixed configuration.
