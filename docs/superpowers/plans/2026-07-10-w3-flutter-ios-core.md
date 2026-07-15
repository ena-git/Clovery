# W3：Flutter iOS 核心体验实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 交付 iOS 17+ TestFlight 垂直切片：Clovery 登录、离线日记、照片、账户安全入口、原生系统能力和可理解的同步状态。

**Architecture:** Flutter UI 通过 Riverpod 观察 Drift 数据库；Repository 先写本地再通知 Dart SyncEngine。Swift 原生代码只通过 Pigeon 实现 Keychain、Passkey、相册/相机、文件保护、StoreKit/Widget 预留接口。W3 不实现跨设备冲突协议本身，W4 接入已定义 SyncEngine。

**Tech Stack:** Flutter、Dart、Riverpod、Drift、go_router、Pigeon、Swift、AuthenticationServices、PhotosUI、Keychain、XCTest、Flutter integration_test。

---

### Task 1: 建立 Flutter 分层与 Drift 本地模型

**Files:**
- Create: `v2/apps/mobile/lib/core/database/app_database.dart`
- Create: `v2/apps/mobile/lib/features/journal/data/journal_entries.dart`
- Create: `v2/apps/mobile/lib/features/journal/data/journal_repository.dart`
- Create: `v2/apps/mobile/lib/features/journal/domain/journal_entry.dart`
- Create: `v2/apps/mobile/test/features/journal/journal_repository_test.dart`

- [ ] **Step 1: 先写 Repository 测试**

测试必须在内存 SQLite 验证：创建日记立即可查询；编辑递增本地 `dirty_revision`；删除写入墓碑而不是立即物理删除；离线时读写不依赖 Dio/API client。

- [ ] **Step 2: 定义本地表**

Drift `journal_entries` 至少包含：

```text
id, vault_id, lucky_text, body_text, mood, created_at, updated_at,
server_revision nullable, dirty_revision, deleted_at nullable, sync_state
```

另建 `journal_assets`、`sync_operations`、`account_snapshot`、`app_settings`。所有日期存 UTC；UI 格式化在 presentation 层完成。

- [ ] **Step 3: 实现事务性 Repository**

`createEntry`、`updateEntry`、`deleteEntry` 必须在同一 SQLite transaction 内写业务记录和 `sync_operations`。禁止 UI 层直接操作 Drift DAO。

- [ ] **Step 4: 验证本地优先行为**

Run:

```bash
cd v2/apps/mobile
flutter test test/features/journal/journal_repository_test.dart
flutter analyze
```

Expected: 在无网络模拟下所有测试通过。

### Task 2: 实现认证状态与 iOS 安全凭证桥接

**Files:**
- Create: `v2/apps/mobile/lib/features/auth/data/auth_repository.dart`
- Create: `v2/apps/mobile/lib/features/auth/presentation/auth_gate.dart`
- Create: `v2/apps/mobile/lib/features/auth/presentation/login_screen.dart`
- Modify: `v2/apps/mobile/pigeons/clovery_platform.dart`
- Modify: `v2/apps/mobile/ios/Runner/` generated Pigeon files
- Create: `v2/apps/mobile/ios/Runner/CloveryCredentialStore.swift`
- Create: `v2/apps/mobile/test/features/auth/auth_repository_test.dart`

- [ ] **Step 1: 写认证状态测试**

测试覆盖：无 token 显示登录；有效 session 显示 Vault；refresh 失败清除本地 token 但不删除离线日记；设备被撤销显示“此设备已被移除”并锁定本地 Vault。

- [ ] **Step 2: 定义 Pigeon 凭证接口**

接口仅允许：

```dart
storeRefreshToken(String token)
readRefreshToken() -> String?
clearRefreshToken()
createPasskeyAssertion(PasskeyRequest request) -> PasskeyAssertion
```

Swift 实现将 refresh token 写入 Keychain，Passkey 调用 AuthenticationServices。不得把 token 写入 Drift、SharedPreferences、日志或 Widget App Group。

- [ ] **Step 3: 实现 Clovery ID/密码与 Passkey 页面**

登录页包含“使用 Passkey 登录”“Clovery ID/邮箱 + 密码”“恢复账户”与已绑定第三方入口。表单错误使用服务端通用文案，不能区分账户不存在与密码错误。

- [ ] **Step 4: 验收**

在 iPhone 真机创建自定义 Clovery ID，完成密码登录、Passkey 登录、强制 token 失效和设备撤销场景；确认离线日记在锁定前不被删除。

### Task 3: 实现日记编辑、照片与文件保护

**Files:**
- Create: `v2/apps/mobile/lib/features/journal/presentation/editor/entry_editor_screen.dart`
- Create: `v2/apps/mobile/lib/features/journal/presentation/editor/photo_picker_controller.dart`
- Create: `v2/apps/mobile/lib/features/media/data/asset_repository.dart`
- Create: `v2/apps/mobile/lib/features/media/domain/local_asset.dart`
- Create: `v2/apps/mobile/ios/Runner/CloveryMediaBridge.swift`
- Create: `v2/apps/mobile/test/features/media/asset_repository_test.dart`
- Create: `v2/apps/mobile/integration_test/create_entry_with_photo_test.dart`

- [ ] **Step 1: 写资产失败测试**

测试必须覆盖：选择两张照片产生两个独立 asset ID；压缩失败不创建日记引用；应用重启后能从受保护目录读取图片；删除日记只标记资产待清理，不立即误删其他条目共用资产。

- [ ] **Step 2: 定义媒体 Pigeon API**

Swift API 返回临时选择结果后，Dart `AssetRepository` 将图片复制至 `Application Support/VaultAssets/{assetId}.jpg`。Swift 负责设置 `NSFileProtectionComplete`；Dart 负责 SHA-256、尺寸、MIME 和缩略图元数据。

- [ ] **Step 3: 实现编辑器 UI**

编辑器使用 Flutter safe-area 与键盘 inset；保存按钮必须保持可点击；最多照片数、标签、日期和文字限制由 domain validator 统一判断。保存成功只表示本地落库，界面另显示“等待同步”或“已同步”。

- [ ] **Step 4: 执行 iOS 集成测试**

Run:

```bash
cd v2/apps/mobile
flutter devices
flutter test integration_test/create_entry_with_photo_test.dart -d "$CLOVERY_IOS_DEVICE_ID"
```

在运行前将 `CLOVERY_IOS_DEVICE_ID` 设置为 `flutter devices` 输出的真实 iPhone device ID；脚本必须拒绝 simulator 和空值。

Expected: 新建含照片日记、强制终止 App、重新启动后仍显示原图和缩略图。

### Task 4: 建立 iOS 首发导航、可访问性与同步状态

**Files:**
- Create: `v2/apps/mobile/lib/features/home/presentation/home_screen.dart`
- Create: `v2/apps/mobile/lib/features/calendar/presentation/calendar_screen.dart`
- Create: `v2/apps/mobile/lib/features/search/presentation/search_screen.dart`
- Create: `v2/apps/mobile/lib/features/settings/presentation/settings_screen.dart`
- Create: `v2/apps/mobile/lib/features/sync/presentation/sync_status_banner.dart`
- Modify: `v2/apps/mobile/lib/app.dart`
- Create: `v2/apps/mobile/integration_test/ios_layout_matrix_test.dart`

- [ ] **Step 1: 写导航与语义测试**

Widget tests 必须验证首页、日历、搜索、设置可通过语义标签访问；动态字体下按钮仍可获得焦点；深色模式下核心文本对比度满足设计令牌规则。

- [ ] **Step 2: 实现可离线的核心界面**

首页、日历、搜索均从 Drift stream 读取。搜索按 `lucky_text`、`body_text`、标签和日期本地执行；网络状态只能影响同步 banner，不能影响浏览历史日记。

- [ ] **Step 3: 显示同步状态而不伪造成功**

`SyncStatusBanner` 只基于 `sync_operations` 统计展示：`Offline`、`Syncing`、`Needs attention`、`Up to date`。每个失败操作提供重试入口和可复制的错误 ID。

- [ ] **Step 4: W3 验收**

在小屏/大屏 iPhone、深色模式、最大 Dynamic Type、离线模式和键盘弹出状态下执行集成测试。验收要求：没有按钮遮挡、文本截断、照片丢失或将本地保存误报为云端同步成功的情况。
