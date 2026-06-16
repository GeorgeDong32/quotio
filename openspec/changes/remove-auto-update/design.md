## Context

Quotio 使用 Sparkle 框架实现 macOS 应用的自动更新，同时通过自定义 `AtomFeedUpdateService` 检查 CLI Proxy 组件的更新。fork 版本（GeorgeDong32/quotio）是自用魔改版，不需要上游的应用更新推送。

当前更新系统组成：
- **Sparkle 框架**：通过 SPM 集成，处理应用本身的自动更新
- **UpdaterService**：Sparkle 的封装服务，管理自动/手动检查、beta/stable 通道、动态图标
- **AtomFeedUpdateService**：轮询 GitHub Atom Feed，检查 CLI Proxy 和 Quotio 应用的更新
- **UI 层**：设置页面的 UpdateSettingsSection、关于页面的 AboutUpdateCard、菜单栏 "Check for Updates..."

## Goals / Non-Goals

**Goals:**
- 完全移除 Sparkle 框架依赖
- 移除所有 Quotio 应用更新检查功能
- 移除所有更新相关的 UI 元素
- CLI Proxy 更新检查保持不变（独立于 Sparkle，仍有实用价值）
- 应用编译通过，无残留编译错误

**Non-Goals:**
- 不修改 CLI Proxy 的更新逻辑
- 不修改底层网络请求或 Atom Feed 解析代码
- 不改变应用的其他功能（代理、虚拟模型、fallback 等）
- 不重新设计设置页面的布局

## Decisions

### 1. 完全移除 UpdaterService.swift

**Decision**: 删除整个 `Quotio/Services/UpdaterService.swift` 文件。

**Rationale**: 该文件是 Sparkle 的唯一消费者，所有功能（自动检查、手动检查、通道切换、动态图标）都依赖 Sparkle。移除后无其他代码需要此服务。

### 2. 保留 AtomFeedUpdateService，仅移除 Quotio 应用更新检查

**Decision**: 在 `AtomFeedUpdateService` 中，移除 `checkForQuotioUpdate()` 方法和相关调用，保留 CLI Proxy 更新检查。

**Rationale**: CLI Proxy 独立于应用本身更新，Atom Feed 轮询对 CLI Proxy 仍有意义。只移除应用更新相关逻辑。

### 3. 移除动态 App Icon 功能

**Decision**: 移除 `UpdaterService` 中的 `updateAppIcon()` 和所有图标切换逻辑，应用固定使用默认图标。

**Rationale**: 动态图标是更新通道（beta/stable）的视觉指示器，移除更新通道后此功能无意义。

### 4. 移除 Sparkle SPM 依赖

**Decision**: 从 Xcode project 的 SPM 依赖中移除 Sparkle。

**Rationale**: 不再需要自动更新框架。移除后可减小应用体积。

### 5. 清理 Info.plist 中的 Sparkle 配置

**Decision**: 移除 `SUFeedURL`、`SUPublicEDKey`、`SUEnableAutomaticChecks`、`SUScheduledCheckInterval` 四个键值。

**Rationale**: 这些键值是 Sparkle 运行时配置，移除 Sparkle 后不再有意义，且避免系统查找更新。

### 6. 移除更新脚本

**Decision**: 删除 `scripts/generate-appcast.sh`，从 `scripts/package.sh` 中移除 Sparkle 相关逻辑。

**Rationale**: appcast 是 Sparkle 更新的分发机制，不再需要。

## Risks / Trade-offs

- [Sparkle API 散布在编译条件中] → 所有 `#if canImport(Sparkle)` 代码块都需要移除或替换。遗漏会导致编译错误（不是静默失败，容易发现）。
- [AtomFeedUpdateService 中 Quotio 更新逻辑可能与其他功能耦合] → 需要仔细检查 `startPolling()` 方法中的调用链，确保只移除 Quotio 应用更新部分。
- [设置页面移除更新区域后可能留下空白] → 需要检查布局，确保移除 UpdateSettingsSection 后页面仍然合理。
