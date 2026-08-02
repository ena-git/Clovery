# Clovery iOS 1.1.0 发布验收主表

**发布类型：** 已上架 iOS 应用升级  
**生产基线：** `1.0.3 (14)`  
**候选版本：** `1.1.0 (15)`  
**候选分支：** `codex/swift-auth-foundation`  
**外部验收准备节点：** `2b85ea9`
**模拟器验收节点：** `57b830e`
**总体状态：** `BLOCKED — 自动化与模拟器已通过，等待真实预发、真机、Sandbox、TestFlight 与 App Store Connect 验收`

本文件只记录不含用户内容、账户标识、设备 UDID、交易凭证或完整提交 SHA 的聚合结果。任何 `NOT_RUN`、`FAIL` 或未关闭的 P0/P1 都阻止提交审核和 GitHub Release。

## 执行手册

- 模拟器证据：`docs/release/ios-1.1.0-simulator-matrix.md`
- 真机升级：`docs/release/ios-1.1.0-device-acceptance.md`
- StoreKit/TestFlight：`docs/release/ios-1.1.0-storekit-acceptance.md`
- 生产发布：`docs/release/ios-1.1.0-production-checklist.md`
- 发布监控：`docs/release/ios-1.1.0-monitoring.md`

## 固定发布身份

| 项目 | 固定值 | 状态 |
| --- | --- | --- |
| 主应用 Bundle ID | `com.clovery.app` | PASS |
| Widget Bundle ID | `com.clovery.app.CloveryWidget` | PASS |
| Team ID | `M92TBSSR2R` | PASS |
| App Group | `group.com.clovery.app` | PASS |
| iCloud 容器 | `iCloud.com.clovery.app` | PASS |
| StoreKit 商品 | `com.clovery.app.board.lifetime` | 待 App Store Connect 复核 |
| 最低系统 | iOS 16.0 | PASS |

## 已完成代码门禁

- [x] 新用户与旧用户 bootstrap 分流 — PASS
- [x] Clovery 根账户、Vault、迁移与服务端权益接口 — PASS
- [x] 中文隐私政策与用户协议公开路由 — PASS
- [x] 注册前主动勾选协议，应用内打开法律页面 — PASS
- [x] “账户与安全”入口、双重确认和账户删除请求 — PASS
- [x] 删除成功立即退出并清理账户权益状态，失败保持登录 — PASS
- [x] App 与 Widget 同步锁定 `1.1.0 (15)` — PASS
- [x] Release 使用生产 API、分发签名和生产推送环境 — PASS
- [x] 隐私清单申报账户 ID、设备 ID、日记、照片和购买历史 — PASS
- [x] `UserDefaults` 与 App Group required-reason API 声明 — PASS
- [x] 仓库密钥、用户证据、大文件和生成物负向门禁 — PASS
- [x] Go race、全量 XCTest 与无签名 Release 构建 — PASS（`234/234`）
- [x] iPhone SE/mini/Pro/Pro Max 模拟器矩阵 — PASS（iOS 26.0.1）
- [x] 最大辅助字号、四种字体、深色系统外观与 Reduce Motion — PASS
- [x] 认领/迁移/权益/日记重启、后台恢复和离线重试 UI — PASS

## 隐私与 App Store Connect 答案

App Store Connect 中必须与 `Clovery/PrivacyInfo.xcprivacy` 和线上隐私政策保持一致：

| 数据类型 | 是否关联用户 | 是否跟踪 | 用途 |
| --- | --- | --- | --- |
| 用户 ID | 是 | 否 | 账户认证、Vault 与跨设备同步 |
| 设备 ID | 是 | 否 | 会话、设备管理与安全 |
| 其他用户内容 | 是 | 否 | 用户主动保存和同步日记 |
| 照片或视频 | 是 | 否 | 仅用户主动添加并选择同步的照片 |
| 购买历史 | 是 | 否 | 验证、恢复和跨设备继承权益 |
| 开发者诊断数据 | 按实际实现选择；当前客户端不上传崩溃日志 | 否 | 不得虚报分析或广告用途 |

- 隐私政策 URL：`https://api.clovery.cn/v1/legal/privacy`
- 用户协议 URL：`https://api.clovery.cn/v1/legal/terms`
- Apple 官方账户删除要求：`https://developer.apple.com/support/offering-account-deletion-in-your-app/`
- Apple App 隐私管理：`https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy`

## 待执行发布门禁

| 工作流 | 状态 | 阻断条件 |
| --- | --- | --- |
| 法律文本负责人确认 | NOT_RUN | 负责人确认运营主体、留存期限与联系方式 |
| 客服邮箱收发测试 | NOT_RUN | 必须能接收并回复测试邮件 |
| 本地 PostgreSQL 迁移往返演练 | PASS | 自动化覆盖升级、回滚和重新应用；不替代真实预发备份恢复 |
| 预发 PostgreSQL 备份/恢复/升级 | NOT_RUN | 必须从加密备份恢复且数据关系一致 |
| 预发账户继承与权益 smoke | NOT_RUN | 所有命名场景必须 PASS |
| Go race/full build | PASS | 提交 `57b830e` 权威脚本退出 `0` |
| 完整 XCTest 与 Release 模拟器 build | PASS | `234` 通过、`0` 失败、`0` 跳过 |
| 小屏/Dynamic Type/字体/中断模拟器矩阵 | PASS | 四尺寸均通过；详见模拟器矩阵文档 |
| iOS 16 运行时/旧款真机 | NOT_RUN | 当前未安装 iOS 16 模拟器运行时，必须由 Task 7 真机补齐 |
| 两台真机升级与跨设备同步 | NOT_RUN | 数据、照片、字体或权益不一致阻断 |
| 真机 Photos 保存/拒绝/设置恢复 | NOT_RUN | 任一保存失败阻断 |
| 签名 archive 身份与权限审计 | NOT_RUN | `scripts/verify-ios-1.1.0-archive.sh` 必须 PASS |
| App Store Connect 商品配置 | NOT_RUN | 商品、协议、税务、银行或地区不完整阻断 |
| Sandbox 购买/取消/pending/恢复/撤销 | NOT_RUN | 付费用户未解锁或跨账户串权阻断 |
| TestFlight 升级与冷安装 | NOT_RUN | P0/P1 阻断 |
| Archive Validate/Upload | NOT_RUN | 签名、隐私或 entitlement 警告阻断 |
| App Store 审核与分阶段发布 | NOT_RUN | 审核未接受或监控异常阻断 |

## 外部人工确认

- 法律/隐私批准人：`待填写`
- 数据库演练执行人：`待填写`
- 真机验收执行人：`待填写`
- App Store Connect 执行人：`待填写`
- 最终发布批准人：`待填写`

Flutter W3 只能在本表所有发布阻断项通过、iOS `1.1.0` 已面向目标用户可用且没有开放 P0/P1 后开始。
