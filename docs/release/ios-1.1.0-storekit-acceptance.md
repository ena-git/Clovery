# Clovery iOS 1.1.0 StoreKit、TestFlight 与 App Store Connect 验收

**执行状态：** `NOT_RUN`

**固定商品：** `com.clovery.app.board.lifetime`（`Non-Consumable`）

本手册需要 App Store Connect 权限、Apple Sandbox 测试账户、签名证书、两台真机和可用预发后端。代码与本地 StoreKit 测试通过不等于真实商品链路通过。

## Apple 官方依据

- 账户创建应用必须允许用户在应用内发起删除：https://developer.apple.com/support/offering-account-deletion-in-your-app/
- App 隐私与隐私政策 URL：https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/
- IAP 状态：https://developer.apple.com/help/app-store-connect/reference/in-app-purchases-and-subscriptions/in-app-purchase-statuses/
- Sandbox 购买测试：https://developer.apple.com/documentation/storekit/testing-in-app-purchases-with-sandbox
- 提交 IAP：https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-in-app-purchase/

## App Store Connect 商品审计

| 检查项 | 要求 | 结果 |
| --- | --- | --- |
| 商品类型 | Non-Consumable | NOT_RUN |
| 所属 App | `com.clovery.app` | NOT_RUN |
| 协议 | Paid Applications 有效 | NOT_RUN |
| 税务与银行 | 无待处理项 | NOT_RUN |
| 中文元数据 | 名称、说明、审核截图完整 | NOT_RUN |
| 定价与地区 | 中国大陆及计划地区可售 | NOT_RUN |
| 商品状态 | 无红色待处理标记 | NOT_RUN |
| 版本关联 | 需要时已加入 `1.1.0` 审核提交 | NOT_RUN |

趋势页面显示 `0` 不能证明用户未付款。单个用户的判断必须来自 Apple 交易查询、StoreKit 验证结果和 Clovery 服务端权益账本。

## 服务端 Apple 配置

在受保护运维环境检查生产和 Sandbox：

| 检查项 | 结果 |
| --- | --- |
| App Store Server API issuer/key 与私钥可用 | NOT_RUN |
| Bundle ID 与商品 allowlist 固定 | NOT_RUN |
| Apple 根证书链与服务器时钟正常 | NOT_RUN |
| Notifications V2 生产/Sandbox URL 正确 | NOT_RUN |
| Apple 测试通知成功且幂等 | NOT_RUN |
| 日志不输出 JWS、收据或完整交易标识 | NOT_RUN |

## Sandbox 真机矩阵

必须使用 App Store Connect 的真实商品数据；`Clovery.storekit` 只能用于自动化单元测试。

| 场景 | 验收点 | 结果 |
| --- | --- | --- |
| 商品加载 | 显示 Apple 返回的本地化价格 | NOT_RUN |
| 用户取消 | 不解锁，中文状态正确 | NOT_RUN |
| interrupted/pending | 不误报失败或成功，后续更新可恢复 | NOT_RUN |
| 购买成功 | 验证交易、携带 `appAccountToken`、服务端激活后解锁 | NOT_RUN |
| 重启 | 当前权益恢复且无需再次购买 | NOT_RUN |
| 恢复购买 | 同一 Clovery 根账户恢复 | NOT_RUN |
| 第二设备 | 同一根账户得到相同权益 | NOT_RUN |
| 其他账户认领 | 被服务端阻止，不串权 | NOT_RUN |
| 退款/撤销 | 服务端撤销并在客户端反映 | NOT_RUN |
| 通知重放 | 幂等，不重复创建权益 | NOT_RUN |

Sandbox 与 TestFlight 都不产生真实扣款。测试账户和敏感交易材料只存放于批准的加密证据系统。

## 受影响用户修复验收

1. 先让用户升级并登录自己的 Clovery 根账户。
2. 用户在应用内执行“恢复购买/旧权益认领”，不得通过聊天索取密码、验证码、完整收据或 JWS。
3. 客服只收集短支持编号、App 版本、iOS 版本和大致购买时间。
4. 授权运营人员在 Apple 工具中核验交易，再从 `/v1/account/entitlements` 查看该 Clovery 账户的聚合权益结果。
5. 不允许手工修改本地付费开关；任何补偿都必须形成可审计的服务端权益来源。

| 场景 | 结果 |
| --- | --- |
| 用户恢复流程可提交验证交易 | NOT_RUN |
| Apple 查询与服务端权益一致 | NOT_RUN |
| 同一账户重启/换机仍已解锁 | NOT_RUN |
| 无交易时给出 Apple 支付查询路径 | NOT_RUN |

## 签名归档

在真机验收通过后创建归档：

```bash
CLOVERY_RELEASE_API_BASE_URL=https://api.clovery.cn \
xcodebuild -project Clovery.xcodeproj -scheme Clovery \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath build/Clovery-1.1.0-15.xcarchive archive

scripts/verify-ios-1.1.0-archive.sh \
  build/Clovery-1.1.0-15.xcarchive
```

验证脚本检查主 App/Widget 标识、`1.1.0 (15)`、Team、App Group、iCloud、生产推送、隐私清单、代码签名，并拒绝归档中出现 `Clovery.storekit`。归档、导出包和签名材料保持忽略，不上传 GitHub。

| 场景 | 结果 |
| --- | --- |
| 签名 archive 创建成功 | NOT_RUN |
| 本地 archive 审计通过 | NOT_RUN |
| Organizer Validate App 通过 | NOT_RUN |
| Organizer 上传且构建可选 | NOT_RUN |

## TestFlight 矩阵

两台真机均使用上传后的同一构建：

- 冷安装注册与登录；
- App Store `1.0.3` 原位升级；
- Apple 认领和已绑定 Apple 登录；
- 旧日记、照片、字体和冲突迁移；
- 旧付费用户认领、新购买、恢复、重装和第二设备；
- Photos 保存/拒绝/设置恢复/分享；
- 账户删除和会话撤销。

| Device A | Device B | 总结果 |
| --- | --- | --- |
| NOT_RUN | NOT_RUN | NOT_RUN |

## App 隐私与审核资料

- 隐私政策：`https://api.clovery.cn/v1/legal/privacy`
- 用户协议：`https://api.clovery.cn/v1/legal/terms`
- App 隐私回答必须覆盖账户标识、设备标识、日记、用户选择上传的照片和购买历史；均不用于跟踪。
- 审核说明使用一次性 CloveryID，解释旧用户公告、迁移、恢复购买和账户删除路径，不放生产凭据或真实用户数据。
- 隐私 URL 和回答变更需在 App Store Connect 中保存并发布，不能只修改代码仓库。

## 验收签字

- App Store Connect 执行人：`待填写`
- Sandbox/TestFlight 执行人：`待填写`
- 构建上传时间：`待填写`
- 结果：`NOT_RUN`

所有行 PASS 且受影响用户修复路径验证后，才可提交 App Review。
