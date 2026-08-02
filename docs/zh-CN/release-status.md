# Clovery 当前完成度与待补充事项

- 候选版本：iOS `1.1.0 (15)`
- 已发布基线：iOS `1.0.3 (14)`
- 候选分支：`codex/swift-auth-foundation`
**结论：** 代码与本地发布候选门禁可供审查；外部发布门禁未全部执行，暂不创建正式 GitHub Release，也不提交 App Store 审核。

## 1. 已完成

- 原生 iOS 中文登录、注册、恢复、旧用户升级公告和账户安全入口；
- 新用户与旧用户数据认领流程分离，新用户不进入旧数据确认页；
- Clovery 根账户、用户自定义 Clovery ID、Vault 和多种登录方式绑定；
- 旧 localStorage/iCloud/CloudKit 数据复制、清单校验、失败保留和重试；
- 日记、图片、同步游标、冲突、墓碑和迁移 Go API；
- App Store 交易验证、服务端权益账本和客户端权益刷新；
- 相册保存权限路径、分享路径与错误恢复实现；
- 中文隐私政策、用户协议、账户删除入口和隐私清单；
- iOS `1.1.0 (15)` 身份、生产 API、权限和 Widget 配置；
- Go 测试、Swift XCTest、模拟器尺寸/字体/深色模式矩阵和无签名 Release 构建。

详细自动化证据以 [`../release/ios-1.1.0-acceptance.md`](../release/ios-1.1.0-acceptance.md) 为准。

## 2. 发布前必须执行

| 优先级 | 工作 | 完成标准 | 记录位置 |
| --- | --- | --- | --- |
| P0 | 法律与运营主体确认 | 隐私政策、协议、留存期限、客服邮箱和主体信息获批准 | `docs/release/ios-1.1.0-acceptance.md` |
| P0 | 真实预发数据库演练 | 加密备份可恢复，迁移前后账户/Vault/权益关系一致 | `docs/release/ios-1.1.0-production-checklist.md` |
| P0 | 两台 iPhone 真机升级 | `1.0.3` 升级、照片、字体、后台恢复和跨设备同步通过 | `docs/release/ios-1.1.0-device-acceptance.md` |
| P0 | 相册保存回归 | 允许、拒绝、受限、设置恢复和截图保存全部通过 | `docs/release/ios-1.1.0-device-acceptance.md` |
| P0 | App Store Connect 商品核对 | 商品、协议、税务、银行、地区和 Bundle 关联完整 | `docs/release/ios-1.1.0-storekit-acceptance.md` |
| P0 | Sandbox 权益验收 | 购买、pending、取消、恢复、退款/撤销和跨设备继承通过 | `docs/release/ios-1.1.0-storekit-acceptance.md` |
| P0 | 受影响付费用户处理 | 找到未解锁用户，核验交易并恢复同一根账户权益 | `docs/release/ios-1.1.0-storekit-acceptance.md` |
| P0 | 签名 Archive | Archive 脚本通过，Organizer Validate/Upload 无阻断警告 | `docs/release/ios-1.1.0-production-checklist.md` |
| P0 | TestFlight 验收 | 旧版升级与全新安装均无开放 P0/P1 | `docs/release/ios-1.1.0-storekit-acceptance.md` |
| P1 | 生产发布与监控 | 分阶段发布、指标、告警、回滚与客服响应就绪 | `docs/release/ios-1.1.0-monitoring.md` |

## 3. 需要人工填写

- 法律/隐私批准人、批准时间和最终文本版本；
- 客服邮箱真实收发测试结果；
- 预发数据库备份位置、恢复演练执行人和校验摘要；
- 两台真机型号、系统版本、升级来源和验收人；
- App Store Connect 商品状态、协议/税务/银行状态和截图证据；
- Sandbox 测试账户的聚合结果，不提交 Apple ID、交易凭证或用户内容；
- Archive/TestFlight 构建号、审核状态和最终发布批准人；
- 生产 API、对象存储、数据库、监控和备份责任人。

## 4. 不得提交到 Git

- `.env`、JWT/Passkey/OIDC/IAP 私钥、证书、描述文件和 API 密钥；
- 用户日记、照片、邮箱、设备 UDID、完整交易凭证和恢复码；
- `DerivedData`、`.xcarchive`、`.ipa`、`.xcresult`、Flutter/Go 构建生成物；
- 数据库生产备份、对象存储导出和包含账户标识的日志。

## 5. 后续阶段

原生 iOS `1.1.0` 完成真机、Sandbox、TestFlight 和正式发布且无开放 P0/P1 后，按以下顺序继续：

1. W3 Flutter iOS 核心体验；
2. W4 Flutter 同步、冲突和运营 Beta；
3. W5 Android 原生桥接与 HarmonyOS PoC；
4. W6 锁屏组件、繁体中文、Watch 和轻量体验扩展。

实施计划位于 `docs/superpowers/plans/`，未勾选项仍是计划，不代表已实现。
