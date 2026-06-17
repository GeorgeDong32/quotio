## 1. Remove UpdaterService.swift

- [x] 1.1 Delete `Quotio/Services/UpdaterService.swift`

## 2. Remove Sparkle dependency from Xcode project

- [x] 2.1 Remove Sparkle SPM dependency from `Quotio.xcodeproj/project.pbxproj`

## 3. Clean up Info.plist

- [x] 3.1 Remove `SUFeedURL`, `SUPublicEDKey`, `SUEnableAutomaticChecks`, `SUScheduledCheckInterval` from `Quotio/Info.plist`

## 4. Update QuotioApp.swift

- [x] 4.1 Remove `#if canImport(Sparkle)` / `import Sparkle` at top of file
- [x] 4.2 Remove `#if canImport(Sparkle)` block in `performFullInitialization()` (background update check)
- [x] 4.3 Remove `#if canImport(Sparkle)` CommandGroup block for "Check for Updates..." menu item

## 5. Update AtomFeedUpdateService.swift

- [x] 5.1 Remove `checkForQuotioUpdate(currentVersion:)` method
- [x] 5.2 Remove `quotioFeedURL` and `quotioCacheKey` static properties

## 6. Update SettingsScreen.swift — About screen

- [x] 6.1 Remove `@State private var updaterService = UpdaterService.shared` from `AboutScreen`
- [x] 6.2 Replace `UpdaterService.shared.currentAppIcon` with `NSImage(named: "AppIconImage")`
- [x] 6.3 Remove `#if canImport(Sparkle)` block in `onAppear`
- [x] 6.4 Replace `AboutUpdateCard()` with version-only display in `updatesSection`
- [x] 6.5 Remove entire `AboutUpdateCard` struct definition

## 7. Update SettingsScreen.swift — Settings section

- [x] 7.1 Remove entire `UpdateSettingsSection` struct definition

## 8. Remove update scripts

- [x] 8.1 Delete `scripts/generate-appcast.sh`
- [x] 8.2 Delete `scripts/generate-appcast-ci.sh`

## 9. Clean up release scripts

- [x] 9.1 Remove appcast generation step from `scripts/release.sh`
- [x] 9.2 Remove Sparkle config from `scripts/config.sh`
- [x] 9.3 Update `scripts/package.sh` spinner text
- [x] 9.4 Update `scripts/quick-release.sh` step description

## 10. Verification

- [x] 10.1 Build the project: `xcodebuild -project Quotio.xcodeproj -scheme Quotio -configuration Debug build` — **BUILD SUCCEEDED**
