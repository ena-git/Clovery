# W1 V1 数据保护与迁移导出验收记录

**版本：** `1.0.2 (13)`
**代码状态：** 自动化与签名 Archive 通过，等待真机与 App Store Sandbox/TestFlight 验收
**测试设备：** Ao-iPhone，iPhone 12，iOS 17.4.1，已配对并启用开发者模式

原生 iOS 1.0.3 (14) 的自动化、升级数据、相册、迁移、StoreKit、TestFlight 和 App Store 发布门禁必须在 Flutter W3 开始前完成。旧文档中 W3/W4 后再完成 W1 真机验收的排期由 2026-07-15 已批准方案 A 替代。

## 自动化验收

| 验收项 | 状态 | 证据 |
| --- | --- | --- |
| PhotoStore JPEG 往返、GC、非法文件名、无效 base64 | PASS | `PhotoStoreTests` 4 项 |
| photoSave/photoLoad/photoGC/iCloud/CloudKit/migrationExport 桥接 | PASS | `WebBridgeContractTests` 4 项 |
| 购买、价格、照片、iCloud JSON 回调与 CloudKit 日志 | PASS | `JavaScriptCallbackTests` 3 项 |
| Bundle 清单、全部照片、缺图、错哈希、非法 JSON、历史导出保留 | PASS | `MigrationBundleExporterTests` 5 项 |
| 标准 ZIP 兼容性 | PASS | 系统 `unzip -t` 验证 `entries.json`、`deleted_ids.json`、`manifest.json`、照片 |
| HTML/Babel 与 P0 合同 | PASS | `validate-v1-html.cjs`、`test-v1-p0-contract.sh` |
| 当前 W1 Release/iPhoneOS 编译 | PASS | 签名 Archive `build/Clovery-W1-1.0.2-13-signed.xcarchive`，成品版本 `1.0.2 (13)` |
| App Group 签名权限 | PASS | 主 App 与 Widget 均签入 `com.apple.security.application-groups = group.com.clovery.app` |

总计：16 项 XCTest 全部通过。

## 数据安全不变量

- 照片只有在 `PhotoStore.save` 原子写入成功后才加入日记状态。
- 旧 base64 照片迁移失败时保留原 base64，不替换为不存在的文件名。
- 导出只读取日记、备份和照片，不删除或重写原 App 数据。
- 每次导出写入 `Documents/CloveryMigration/<migration_id>/migration_bundle.zip`。
- Bundle 包含 `entries.json`、`deleted_ids.json`、全部合法 Documents JPEG、可用备份和 SHA-256 清单。
- 删除墓碑随 Bundle 导出，避免已删除 CloudKit 记录在 V2 迁移后复活。
- 临时目录验证成功后才原子改名；失败不会覆盖之前成功的 Bundle。

## 待完成真机验收

### A. 照片持久化与 CloudKit

- [ ] 真机添加两张照片并完成日记。
- [ ] 强制结束 App 后重新打开。
- [ ] 首页、日历、详情和分享卡显示相同两张照片。
- [ ] 第二台同 iCloud 测试设备拉取后显示相同照片。
- [ ] 拒绝或破坏存储条件时显示“照片未保存，请重试”，日记不引用缺失文件。

### B. 迁移 Bundle

- [ ] 准备多条日记、至少三张照片和至少一条删除墓碑。
- [ ] 设置 → 为迁移导出数据 → 保存 ZIP 到文件。
- [ ] 解压后核对 manifest 的 entry/photo/deleted 计数。
- [ ] 对所有照片重算 SHA-256，并随机打开至少三张。
- [ ] 再次启动 V1，确认原日记、照片和删除状态完全不变。
- [ ] 重复导出，确认两个 migration_id 目录和 ZIP 均保留。

### C. StoreKit Sandbox/TestFlight

- [ ] App Store Connect 存在 `com.clovery.app.board.lifetime`，类型 Non-Consumable。
- [ ] 商品价格、简体中文本地化、中国大陆可用性和审核截图完整。
- [ ] 商品状态为 Ready to Submit，并随首个支持内购的新版本提交审核。
- [ ] TestFlight 查询并显示真实价格。
- [ ] 取消购买不解锁、不显示失败误导。
- [ ] Ask to Buy pending 不解锁，并可在交易更新后自动刷新。
- [ ] Sandbox 成功购买立即解锁。
- [ ] 杀掉 App、重装和换测试设备后“恢复购买”可重新解锁。
- [ ] App Store Connect/Sales 报告能找到对应 Sandbox 或生产交易来源。

## 当前外部阻塞

1. App Group 后台关联正确；项目原先误用了不存在的 `com.apple.developer.app-groups` 键，现已统一改为 Apple 描述文件实际签发的 `com.apple.security.application-groups`，签名 Archive 已通过。
2. Ao-iPhone 已通过 USB 识别并配对，但两次安装时设备均返回 `kAMDMobileImageMounterDeviceLocked`；真机验收前需解锁并保持屏幕点亮。
3. App Store Connect 登录已过期；重新登录后才能确认 `com.clovery.app.board.lifetime` 的创建、价格、本地化和审核状态。

解除第 2、3 项后，安装真机、上传 TestFlight，并逐项勾选本文件即可完成 W1 验收。未完成这些外部步骤前，不得把 W1 标记为可上线。
