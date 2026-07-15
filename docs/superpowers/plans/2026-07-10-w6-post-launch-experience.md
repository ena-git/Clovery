# W6：上线后体验扩展实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 V2 数据、账户和同步稳定后，交付锁屏组件、繁体中文、Watch 和轻量玩法，且不创建新的账户、同步或支付事实源。

**Architecture:** Flutter 保持主 App UI 和本地 Vault；iOS Widget/Watch 使用 Swift 原生扩展读取 Flutter 生成的最小 App Group 快照。新增功能只通过现有 SyncEngine 写入日记或偏好，不得绕过 Repository 直连后端。

**Tech Stack:** Flutter、Dart、Pigeon、SwiftUI、WidgetKit、App Intents、WatchConnectivity、ARB 本地化、XCTest、Flutter integration_test。

---

### Task 1: 增加锁屏组件与可靠快写深链

**Files:**
- Modify: `v2/apps/mobile/pigeons/clovery_platform.dart`
- Modify: `v2/apps/mobile/ios/Runner/CloveryWidgetSnapshotBridge.swift`
- Create: `v2/apps/mobile/ios/CloveryWidgets/LockScreenWidgets.swift`
- Create: `v2/apps/mobile/ios/CloveryWidgets/LockScreenWidgetsTests.swift`
- Modify: `v2/apps/mobile/lib/core/routing/app_router.dart`

- [ ] **Step 1: 写快照兼容测试**

测试必须验证旧 Widget JSON 版本仍能解码，新字段缺失时使用安全默认值；Widget 不得因单条损坏日记崩溃。

- [ ] **Step 2: 实现 accessory families**

实现 `.accessoryInline`、`.accessoryCircular` 和 `.accessoryRectangular`；仅显示今日记录/连续天数等最小数据。所有组件通过 `widgetURL` 深链到 Flutter 的快速记录或日历路由。

- [ ] **Step 3: 真机验收**

锁屏、待机模式和深色模式下验证文字可读、深链正确、App Group 无数据时安全降级。

### Task 2: 完成繁体中文与字体/深色回归

**Files:**
- Create: `v2/apps/mobile/lib/l10n/app_zh_TW.arb`
- Modify: `v2/apps/mobile/lib/l10n/app_localizations.dart`
- Create: `v2/apps/mobile/test/l10n/zh_tw_test.dart`
- Create: `v2/apps/mobile/integration_test/dark_mode_typography_test.dart`

- [ ] **Step 1: 写本地化完整性测试**

测试比较 `app_zh_TW.arb` 与基准英文 ARB 的 key 集合；缺失、重复或带简体硬编码的文案均失败。

- [ ] **Step 2: 实现繁体中文选择**

语言代码固定为 `zh_TW`；用户设置通过现有 Repository/SyncEngine 同步。日记原文永不自动转简体或繁体。

- [ ] **Step 3: 执行视觉回归**

在深色模式、最大 Dynamic Type、中文手写字体和系统字体下截图对比首页、编辑器、日历、标签、账户与安全页面。

### Task 3: 交付 Watch 伴侣应用

**Files:**
- Create: `v2/apps/mobile/ios/CloveryWatch/CloveryWatchApp.swift`
- Create: `v2/apps/mobile/ios/CloveryWatch/WatchSnapshotStore.swift`
- Create: `v2/apps/mobile/ios/Runner/WatchSnapshotBridge.swift`
- Create: `v2/apps/mobile/ios/CloveryWatchTests/WatchSnapshotStoreTests.swift`

- [ ] **Step 1: 约束 Watch 数据边界**

Watch 只接收最小只读快照和“新建快速记录”意图；不保存独立账户、refresh token 或完整照片库。

- [ ] **Step 2: 实现 WatchConnectivity 快照刷新**

iPhone SyncEngine 完成后经 Swift bridge 将加密/最小化快照发送至 Watch；Watch 不可达时保留上次有效快照并显示更新时间。

- [ ] **Step 3: 实现快速记录回传**

Watch 新建文本生成待同步意图，传回 iPhone 后通过 Flutter JournalRepository 创建日记；未连接时显示待发送状态，不能伪造成功。

- [ ] **Step 4: Watch 验收**

验证换 iPhone、移除设备、离线 Watch、账户注销和重新登录后，Watch 快照与主 Vault 权限一致。

### Task 4: 增加每日抽签与雨雪动画但隔离数据风险

**Files:**
- Create: `v2/apps/mobile/lib/features/daily_draw/`
- Create: `v2/apps/mobile/lib/features/field_weather/`
- Create: `v2/apps/mobile/test/features/daily_draw/daily_draw_test.dart`
- Create: `v2/apps/mobile/test/features/field_weather/reduce_motion_test.dart`

- [ ] **Step 1: 定义纯本地、可复现的每日抽签**

抽签以 `vault_id + local calendar date + content version` 计算稳定 seed；结果可选择同步为偏好，但不得改变日记、权益或容量。

- [ ] **Step 2: 实现可关闭的雨雪动画**

动画只能使用 Flutter 合成层，遵守 `Reduce Motion`；低电量/后台时停止；不得创建持续计时器、网络请求或影响滚动帧率。

- [ ] **Step 3: W6 验收**

所有扩展功能在账户注销、设备撤销、离线、深色模式和辅助功能下安全退化；W4 同步、迁移和支付回归测试仍通过。
