# W1：V1 数据保护与迁移导出实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 以最小改动停止现有 iOS V1 的照片/桥接数据损失，并生成可校验、可重复导入的迁移 Bundle。

**Architecture:** V1 继续使用现有 WebView，仅增加受测试的原生照片存储和导出通道。导出操作复制 WebView 日记 JSON、Documents 照片、全量备份和可读取的 CloudKit 数据到版本化 Bundle；不删除、重写或迁移用户原数据。

**Tech Stack:** Swift、WKWebView、XCTest、CloudKit、CryptoKit、现有 React HTML。

## 2026-07-11 执行状态

- 自动化已完成：`PhotoStore`、照片保存/读取/GC 桥接、结构化 JavaScript 回调、CloudKit 日志、版本化迁移 ZIP、SHA-256 校验、设置页导出入口与 XCTest target。
- 已通过：16 项 XCTest、Babel 校验、P0 合同测试、外部系统 `unzip -t`、Debug 模拟器构建、签名 Release/iPhoneOS Archive，以及主 App/Widget 的 App Group 签名校验。
- 发布门禁仍需人工完成：真机照片重启回归、真机导出并随机打开三张照片、Sandbox/TestFlight 内购矩阵、App Store Connect 首个内购商品审核配置。
- 排期确定为：W1 当前完成自动化、迁移包和签名收口；真机照片、迁移抽检与 Sandbox/TestFlight 验收集中安排在 W3/W4 的 Flutter iOS 版本完成后、W5 Android/鸿蒙接入前。门禁通过前不进入 W5，也不把对应 iOS 版本标记为可上线。

---

### Task 1: 将照片存储从 WebView Coordinator 提取为可测试组件

**Files:**
- Create: `Clovery/PhotoStore.swift`
- Create: `CloveryTests/PhotoStoreTests.swift`
- Modify: `Clovery/WebView.swift`
- Modify: `Clovery.xcodeproj/project.pbxproj`

- [x] **Step 1: 添加 XCTest target 与失败测试**

`PhotoStoreTests` 必须覆盖：保存 JPEG Data URL 后能读回同一 base64；保留名单垃圾回收不删除被引用文件；非法文件名和无效 base64 被拒绝。

- [x] **Step 2: 实现 `PhotoStore`**

接口固定为：

```swift
protocol PhotoStoring {
    func save(filename: String, dataURL: String) throws
    func load(filename: String) throws -> String
    func garbageCollect(keeping filenames: Set<String>) throws
}
```

实现要求：文件名只允许匹配 `^[A-Za-z0-9-]+\\.jpg$`；目录固定为 Documents 的 `photos/`；写入使用 `.atomic`；读取返回无 data URL 前缀的 base64；任何错误必须向调用方返回而不是 `try?` 吞掉。

- [x] **Step 3: 运行单元测试确认通过**

Run:

```bash
xcodebuild -project Clovery.xcodeproj -scheme Clovery -destination 'platform=iOS Simulator,name=iPhone 16' test
```

Expected: `PhotoStoreTests` 通过；若本机无 simulator runtime，记录该环境问题并在 CI/真机重新执行。

### Task 2: 补全 WebView 照片桥接与可见错误

**Files:**
- Modify: `Clovery/WebView.swift`
- Modify: `Clovery/Clover Diary.html`
- Create: `CloveryTests/WebBridgeContractTests.swift`

- [x] **Step 1: 写桥接契约测试**

测试读取 `Clover Diary.html` 与 `WebView.swift`，验证每个网页 handler 均被 Swift 注册：`photoSave`、`photoLoad`、`photoGC`、`icloud`、`cloudkit`。测试还要验证 `photoLoad` 的回调调用：

```javascript
window.__cloveryPhotoLoaded(reqId, base64)
```

- [x] **Step 2: 注册并处理 `photoSave`**

在 `makeUIView` 注册 `photoSave`。收到 `{ filename, dataURL }` 后调用 `PhotoStore.save`；失败时只向对应 WebView 回传结构化 `window.__cloveryPhotoSaveFailed(filename, code)`，不得静默成功。

- [x] **Step 3: 注册并处理 `photoLoad`**

在 `makeUIView` 注册 `photoLoad`。收到 `{ reqId, filename }` 后读取 `PhotoStore`，通过 JSON 序列化的参数调用 `window.__cloveryPhotoLoaded(reqId, base64OrNull)`；不得把 filename 或 base64 直接拼入 JavaScript 字符串。

- [x] **Step 4: 修正 HTML 错误处理**

`Clover Diary.html` 必须在 `savePhotoFile` 失败时从 `photos` state 移除对应 filename 并显示“照片未保存，请重试”；`PhotoImg` 超时要显示重试入口，不能将空占位误报为已保存图片。

- [ ] **Step 5: 执行桥接回归**

真机步骤：添加两张照片 → 完成日记 → 杀掉 App → 重新打开 → 日历、详情、分享卡和 CloudKit 上传均能显示相同照片。

### Task 3: 修正 V1 关键回调与日志

**Files:**
- Modify: `Clovery/WebView.swift`
- Modify: `Clovery/CloudKitSync.swift`
- Create: `CloveryTests/JavaScriptCallbackTests.swift`

- [x] **Step 1: 写字符串插值回归测试**

测试必须拒绝 Swift 源码中的 `\\(` 字面量回调，并验证购买状态、价格、解锁状态、分享临时文件名和 CloudKit 错误日志使用真实 Swift 插值。

- [x] **Step 2: 定义付费结果枚举**

在 `BoardStore.swift` 将购买结果改为：

```swift
enum BoardPurchaseOutcome: String {
    case success, cancelled, pending, failed
}
```

网页回调只能接收上述 raw value；不再把 `Bool` 伪装为 JavaScript 状态字符串。

- [x] **Step 3: 安全构造 JavaScript 调用**

新增单一 `evaluateJSONCallback(name:payload:)` helper，使用 `JSONSerialization` 序列化参数；所有购买、价格、照片和 iCloud 回调只能通过该 helper 进入网页。

- [ ] **Step 4: 运行回归**

验收：TestFlight/Sandbox 环境分别检查查询价格、取消购买、成功购买和恢复购买；日志必须包含真实 record ID 与错误说明。

### Task 4: 生成版本化迁移 Bundle

**Files:**
- Create: `Clovery/MigrationBundle.swift`
- Create: `Clovery/MigrationBundleExporter.swift`
- Create: `CloveryTests/MigrationBundleExporterTests.swift`
- Modify: `Clovery/WebView.swift`
- Modify: `Clovery/Clover Diary.html`

- [x] **Step 1: 定义 Bundle 清单**

清单 JSON 固定包含：

```json
{
  "format_version": 1,
  "exported_at": "RFC3339 timestamp",
  "entries_file": "entries.json",
  "entry_count": 0,
  "photos": [{"filename":"photo-0001.jpg","sha256":"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef","bytes":1024}],
  "sources": ["localStorage", "documents", "cloudkit"]
}
```

- [x] **Step 2: 写导出器失败测试**

测试创建临时 entries 和照片，验证 ZIP 含清单、`entries.json` 与所有照片；少一张照片、hash 不一致或 JSON 非数组时导出失败且不覆盖上一份成功 Bundle。

- [x] **Step 3: 实现导出器**

导出目录固定为 `Documents/CloveryMigration/`，每次导出使用新 `migration_id` 子目录；先写临时目录、校验全部 SHA-256、最后原子重命名。原始日记、备份和照片都只能读取，不能清理。

- [x] **Step 4: 暴露用户可触发的导出入口**

网页设置页增加“为迁移导出数据”；通过 `migrationExport` handler 发送 entries JSON。原生完成后使用系统分享面板导出 ZIP，并回传条目数、照片数和失败原因。

- [ ] **Step 5: W1 验收**

在有照片、已删除记录和多条日记的真机上导出；解压后校验清单、条目数、照片数、SHA-256 和随机打开的三张图片。保留原 App 数据后，再启动 App 确认内容未变化。
