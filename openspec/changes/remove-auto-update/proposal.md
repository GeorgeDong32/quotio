## Why

Quotio 的 fork 版本（GeorgeDong32/quotio）是自用魔改版，不需要上游的自动更新推送。保留自动更新会导致：用户收到不兼容的上游更新通知、意外覆盖魔改版本、Sparkle 框架占用不必要的依赖空间。

## What Changes

- 移除 Sparkle 框架依赖及其所有引用（`#if canImport(Sparkle)` 代码块、SPM 依赖）
- 移除 `UpdaterService` 服务类
- 移除 `AtomFeedUpdateService` 中的 Quotio 应用更新检查逻辑（保留 CLI Proxy 更新检查，因为 CLI Proxy 仍需独立更新）
- 移除 Info.plist 中的 Sparkle 配置项（`SUFeedURL`、`SUPublicEDKey`、`SUEnableAutomaticChecks`、`SUScheduledCheckInterval`）
- 移除 App 菜单中的 "Check for Updates..." 菜单项
- 移除设置页面中的 UpdateSettingsSection
- 移除关于页面中的 AboutUpdateCard 更新卡片
- 移除 appcast 生成脚本和 Sparkle 相关打包逻辑
- 移除动态 App Icon 功能（随更新通道一起移除，改为固定使用默认图标）

## Capabilities

### New Capabilities
<!-- No new capabilities introduced -->

### Modified Capabilities
<!-- No existing specs to modify -->

## Impact

- `Quotio/Services/UpdaterService.swift` — 整个文件删除
- `Quotio/Services/AtomFeedUpdateService.swift` — 移除 Quotio 应用更新检查相关方法
- `Quotio/QuotioApp.swift` — 移除 Sparkle 引用、菜单项、AppDelegate 中的更新轮询
- `Quotio/Views/Screens/SettingsScreen.swift` — 移除 UpdateSettingsSection 和 AboutUpdateCard
- `Quotio/Info.plist` — 移除 Sparkle 配置键值
- `Quotio.xcodeproj/project.pbxproj` — 移除 Sparkle SPM 依赖
- `scripts/generate-appcast.sh` — 删除
- `scripts/package.sh` — 移除 Sparkle 相关打包逻辑
