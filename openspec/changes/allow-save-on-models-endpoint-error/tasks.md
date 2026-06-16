## 1. Add localization key

- [x] 1.1 Add `action.saveAnyway` key to `Quotio/Localizable.xcstrings` with translations in `en` (`Save Anyway`), `fr` (`Enregistrer quand même`), `vi` (`Vẫn lưu`), `zh-Hans` (`仍要保存`), following the alphabetical order between `action.ok` and `action.openApp`

## 2. Modify alert to support "Save Anyway" path

- [x] 2.1 Add a `@State` variable to store the provider ready for forced save (`pendingSaveProvider: CustomProvider?`)
- [x] 2.2 Update the `.alert` modifier in `CustomProviderSheet.swift` to show two buttons ("action.cancel".localized() + "action.saveAnyway".localized()) when `testError` is non-nil, and a single "action.ok".localized() button otherwise
- [x] 2.3 Wire the "Save Anyway" button action to call `onSave(pendingSaveProvider!)` and `dismiss()`, then clear `testError` and `pendingSaveProvider`

## 3. Wire save flow to use the new path

- [x] 3.1 In the save action handler, set `pendingSaveProvider = newProvider` before launching the test-connection Task
- [x] 3.2 Ensure basic validation errors still block with a single-button alert (no `pendingSaveProvider` set in that codepath)

## 4. Verify

- [x] 4.1 Build and test: configure a provider with a non-existent `/models` endpoint, confirm "Save Anyway" appears with correct localized label and successfully saves
- [x] 4.2 Build and test: configure a provider with a working `/models` endpoint, confirm auto-save still works without alert
- [x] 4.3 Build and test: submit with empty name/key, confirm single-button "OK" alert still appears
- [x] 4.4 Build and test: switch system language to 中文, confirm "仍要保存" label appears correctly
