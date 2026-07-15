# W5：Android 接入与鸿蒙 PoC 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在不分叉 Flutter UI、Dart 本地模型和同步协议的前提下交付 Android；以可量化 PoC 决定鸿蒙使用 Flutter 适配还是 ArkTS 原生壳。

**Architecture:** Android 复用 `v2/apps/mobile/lib/`，通过 Kotlin Pigeon 实现 Google 登录、Credential Manager、Play Billing、Push、后台同步、媒体与 Widget。鸿蒙先验证 Flutter runtime、SQLite、网络、登录、推送、文件和支付；无论结果如何，均使用同一 OpenAPI、Clovery ID/Vault 和 sync cursor 协议。

**Tech Stack:** Flutter、Dart、Kotlin、Credential Manager、Google Identity、Play Billing、WorkManager、FCM、Android Widget、HarmonyOS/ArkTS、OpenAPI。

---

### Task 1: 完成 Android 原生桥接与账户能力

**Files:**
- Modify: `v2/apps/mobile/pigeons/clovery_platform.dart`
- Create: `v2/apps/mobile/android/app/src/main/kotlin/com/clovery/app/CloveryPlatformApi.kt`
- Create: `v2/apps/mobile/android/app/src/test/kotlin/com/clovery/app/CloveryPlatformApiTest.kt`
- Create: `v2/apps/mobile/android/app/src/androidTest/kotlin/com/clovery/app/AuthenticationFlowTest.kt`
- Modify: `v2/apps/mobile/android/app/build.gradle.kts`

- [ ] **Step 1: 写 Pigeon parity 测试**

测试必须验证 Android 实现提供与 iOS 相同的：安全 refresh token 存储、Passkey/Credential assertion、媒体选择、Widget 快照写入和设备信息。Dart API 不得出现 `Platform.isAndroid` 业务分支。

- [ ] **Step 2: 使用 Android 官方凭证能力**

Kotlin 实现 Credential Manager/Google Identity；获取的授权结果只交给 W2 的后端验证 endpoint。Google 账号 subject 不能在 Android 客户端作为 Vault 主键或本地数据目录名。

- [ ] **Step 3: 执行 Android 登录验收**

在至少一台带 GMS 的 Android 设备和一台不使用 Google 登录的设备上完成：Clovery ID/密码、Passkey、Google 登录、设备撤销和恢复码流程。

### Task 2: 完成 Android 媒体、同步、支付与桌面组件

**Files:**
- Create: `v2/apps/mobile/android/app/src/main/kotlin/com/clovery/app/MediaBridge.kt`
- Create: `v2/apps/mobile/android/app/src/main/kotlin/com/clovery/app/WidgetSnapshotReceiver.kt`
- Create: `v2/apps/mobile/android/app/src/main/kotlin/com/clovery/app/BillingBridge.kt`
- Create: `v2/apps/mobile/android/app/src/main/kotlin/com/clovery/app/SyncWorker.kt`
- Create: `v2/apps/mobile/android/app/src/main/res/xml/widget_info.xml`
- Create: `v2/apps/mobile/integration_test/android_offline_sync_test.dart`

- [ ] **Step 1: 写离线与后台同步测试**

测试创建含照片日记，断网、杀掉 Flutter engine、重启设备网络后，由 WorkManager 唤醒 SyncEngine；验证同一 `operation_id` 只上传一次，图片校验一致。

- [ ] **Step 2: 实现 Android 媒体和文件保护策略**

媒体文件保存到 app-private storage；Dart asset metadata 与 iOS 相同。请求权限被拒绝时 Flutter 显示替代路径，不依赖外部共享目录或可读写公共存储。

- [ ] **Step 3: 实现 Play Billing 桥接**

Kotlin 将购买 token 发送到 W4 服务端验证；Flutter 仅观察 backend entitlement。购买取消、待处理和恢复购买必须与 iOS 的状态模型一致。

- [ ] **Step 4: 生成 Android Widget 快照**

Flutter 经 Pigeon 写入最小快照；Android Widget 只读快照并深链进入 Flutter 编辑器。不得在 Widget 中重建第二套日记同步逻辑。

- [ ] **Step 5: Android 验收**

在离线、弱网、横竖屏、深色模式、动态字体和新旧 Android 版本上运行 integration tests；日记、照片、同步、支付和 Widget 与 iOS 同账户结果一致。

### Task 3: 执行鸿蒙 Flutter 可行性 PoC

**Files:**
- Create: `v2/poc/harmony/README.md`
- Create: `v2/poc/harmony/checklist.md`
- Create: `v2/poc/harmony/results.json`
- Create: `v2/poc/harmony/decision-record.md`

- [ ] **Step 1: 定义不可妥协的 PoC 用例**

`checklist.md` 必须逐项验证：Flutter runtime 启动、Dart/Drift SQLite、HTTPS/OpenAPI、Clovery ID/密码、Passkey或等价安全凭证、图片选择、app-private 文件存储、推送、后台同步、支付、深链和 Widget/服务卡片能力。

- [ ] **Step 2: 在真实鸿蒙设备运行同一 Flutter UI**

PoC 只能引用 `v2/apps/mobile/lib/` 的 Flutter UI、domain 和 sync modules；禁止为了 PoC 修改 iOS/Android 行为或添加只在 Dart 层生效的鸿蒙业务分支。

- [ ] **Step 3: 记录每项结果与阻塞证据**

`results.json` 对每个用例写入 `pass`、`fail` 或 `blocked`，附设备/系统版本、SDK 版本、日志链接和最小复现步骤。`blocked` 不能视为通过。

- [ ] **Step 4: 做出平台决策**

若所有安全、同步、媒体、推送和支付用例通过，交付 Flutter 鸿蒙插件计划；任一关键项失败，创建 ArkTS 原生壳计划，复用 OpenAPI、Clovery ID、Vault、Drift 数据语义和同步测试向量，不复制后端业务规则。

### Task 4: 统一跨端发布与兼容性验收

**Files:**
- Create: `v2/docs/release/android-release-checklist.md`
- Create: `v2/docs/release/harmony-release-checklist.md`
- Create: `v2/apps/mobile/integration_test/cross_platform_account_test.dart`
- Modify: `v2/.github/workflows/verify.yml`

- [ ] **Step 1: 写跨端账户验收测试**

测试固定一套 staging 账户：iOS 用 Passkey 登录、Android 用 Clovery ID/密码登录、已绑定第三方身份登录；三端必须得到同一 `clovery_account_id`、同一 `vault_id`、同一日记/图片/权益状态。

- [ ] **Step 2: 将 Android 验证加入 CI**

CI 构建 Android release candidate，运行 Dart unit tests、Android unit tests 和 emulator integration smoke tests；iOS 与 Android 生成的 OpenAPI client 必须来自同一契约 commit。

- [ ] **Step 3: W5 验收**

Android 在 iOS 生产同步指标稳定后灰度发布。鸿蒙只能在 PoC 决策记录完整、关键能力通过且具备平台发布/支付/隐私资质后进入独立发布流程。
