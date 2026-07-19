# Clovery 旧用户账户、数据与权益继承设计

## 1. 目标

本设计定义 iOS 升级版本的强制账户接入流程，确保旧用户创建或登录 Clovery 账户后：

- 原有本地日记、照片和设置不会丢失；
- 已绑定的 Apple 身份只成为 Clovery 账户的一种登录方式；
- 已购买内容不会要求重复购买；
- 同一 Clovery 账户在其他设备登录后获得同一 Vault 数据和权益；
- 断网、杀进程或部分失败不会产生第二个账户、第二个 Vault 或不可恢复的半迁移状态。

核心不变量：

```text
Clovery Account（唯一账户根）
├── vault_id（唯一数据根）
├── entitlements（唯一权益根）
├── password credential
├── Apple identity（可替换登录方式）
├── Google identity（可替换登录方式）
└── Huawei identity（可替换登录方式）
```

外部身份、设备、邮箱和 App Store 账户都不得成为数据根。

## 2. 当前实现差距

现有 iOS 升级流程允许旧用户关闭公告后直接进入旧日记页面，没有强制完成账户接入。Apple 未绑定时，联邦登录只返回 `identity_not_bound`，客户端没有“Apple 验证后创建 CloveryID 并原子绑定”的流程。

后端已经具备 Vault migration 与 Apple billing 基础接口，但当前 iOS 客户端尚未调用这些服务：旧数据只可导出，购买解锁仍主要读取本机 StoreKit entitlement。因此，现状不能保证换设备后的账户级数据和权益继承。

## 3. 启动状态机

应用启动统一由 `AccountBootstrapCoordinator` 决定路由：

```text
loading
├── 旧版本升级且公告未确认 → upgradeNotice
├── 无有效 Clovery 会话 → authentication
└── 有有效 Clovery 会话 → reconcilingAccount

upgradeNotice
└── 我已知晓 → authentication

authentication
├── CloveryID 登录成功 → reconcilingAccount
├── CloveryID 注册成功 → reconcilingAccount
├── 已绑定外部身份登录成功 → reconcilingAccount
└── 未绑定外部身份验证成功 → identityClaimRegistration

identityClaimRegistration
└── 创建 CloveryID + 密码并原子绑定 → reconcilingAccount

reconcilingAccount
└── 全部校验完成 → ready → 默认首页
```

### 3.1 旧版本升级用户

- 原加载页上显示不可跳过的更新公告；
- 公告仅提供“我已知晓”；
- 确认后进入登录/注册页，不允许直接进入旧首页；
- 公告确认按升级流程版本持久化，杀进程后不重复显示同一公告；
- 未完成账户接入时，每次启动仍回到认证或继承流程。

### 3.2 新安装用户

- 加载页初始化完成后直接进入登录/注册页；
- 不显示旧版本公告；
- 认证及账户校验完成后进入默认首页。

### 3.3 已有有效 Clovery 会话

- 恢复会话后不重复登录；
- 必须继续未完成的账户继承任务；
- Vault、权益和设备状态校验完成后进入首页。

## 4. 登录入口适配

登录页始终以 CloveryID + 密码为默认表单和主操作。快捷入口按平台显示：

| 设备类型 | 默认入口 | 快捷入口 |
| --- | --- | --- |
| iOS / iPadOS | CloveryID | Apple、Google |
| 华为 / HarmonyOS | CloveryID | Huawei |
| 其他 Android 设备 | CloveryID | Google |

规则：

- 不显示当前发行渠道未配置或无法完成授权的按钮；
- Apple 不在 Android/HarmonyOS 登录页显示；
- Huawei 不在 iOS 或非华为 Android 登录页显示；
- Passkey 保留为账户安全与恢复能力，本阶段不占用首屏快捷登录位置；
- UI 只决定入口可见性，后端仍必须验证 provider、issuer、subject 和 intent。

## 5. 外部身份认领

### 5.1 未绑定 Apple 首次验证

Apple 授权完成后，后端验证 authorization code、nonce、issuer 和稳定 subject。若 subject 未绑定任何 Clovery 账户，后端不创建独立 Apple 账户，而是签发一次性 `identity_claim_token`。

`identity_claim_token` 必须：

- 短期有效；
- 仅可使用一次；
- 绑定 provider、issuer、subject 和原 intent；
- 服务端只保存 token 摘要；
- 不包含邮箱自动合并逻辑；
- 不授予 Vault 或数据访问权限。

客户端持有 claim token 进入 CloveryID 创建页。用户提交自定义 CloveryID 和至少 8 位密码后，后端在单个数据库事务内：

1. 锁定并消费 identity claim；
2. 创建 `clovery_account_id`；
3. 创建唯一 `vault_id`；
4. 创建密码凭证；
5. 绑定 Apple `provider + issuer + subject`；
6. 创建账户继承任务；
7. 签发会话。

任一步失败时事务整体回滚。相同 Apple subject 的并发请求只能有一个成功。

### 5.2 已绑定 Apple 登录

若 Apple subject 已绑定，后端直接签发该 Clovery 账户与 Vault 的会话。不能创建第二个账户，也不能迁移到另一个 Vault。

### 5.3 已有 Clovery 账户后绑定外部身份

用户先登录现有 Clovery 账户，再通过账户安全页面完成 Apple、Google 或 Huawei 绑定。绑定接口要求当前会话、近期重新认证和新 provider 凭证同时有效。

## 6. 可恢复账户继承任务

账户创建或登录成功后，服务端维护 `account_bootstrap_job`。任务至少包含：

- `account_id`、`vault_id`、`device_id`；
- `source_kind`：legacy local、legacy CloudKit、new install；
- 稳定 `migration_id`；
- identity、migration、entitlement、vault pull 各阶段状态；
- 最后错误码、重试次数和更新时间；
- 整体状态：pending、running、needs_attention、complete。

客户端只能根据服务端任务状态推进。杀进程、断网和换设备后继续同一任务，不重新创建账户。

## 7. 旧数据迁移与去重

### 7.1 数据来源

迁移输入优先从现有完整本地备份、Web localStorage、照片文件和旧 CloudKit 标记构建。导出包必须包含 manifest、日记 payload、照片摘要和稳定 source entry ID。

### 7.2 暂存与原子提交

- 所有内容先上传至目标 Vault 的迁移暂存区；
- 每个请求使用同一 `migration_id` 幂等；
- 服务端完成条目数、照片数、字节数和 SHA-256 校验后才提交；
- 校验失败不得修改正式 Vault；
- 本地旧数据不自动删除，只写入“已安全迁移”标记。

### 7.3 去重规则

服务端为每条日记计算规范化内容摘要，摘要覆盖正文、日期、标签、附件引用和附件内容摘要，但排除设备特有字段与迁移元数据。

合并规则：

1. source entry ID 相同且内容摘要相同：只保留一份；
2. source entry ID 不同但内容摘要相同：只保留一份，并记录来源别名；
3. source entry ID 相同但内容摘要不同：两份都保留，冲突副本获得新内部 ID；
4. 无法确定相同：两份都保留；
5. 已删除记录只在明确匹配同一源记录时应用，不得误删云端独立内容。

当目标 Vault 已有其他设备数据时，仍使用同一规则合并，不执行整库覆盖。

## 8. Apple 购买权益继承

Sign in with Apple 的 subject 与 App Store 购买交易是两个独立身份域，不能因为用户看起来使用同一个 Apple ID 就直接关联。权益继承必须在 Clovery 会话建立后，通过 StoreKit 交易证明单独验证。

流程：

1. 客户端读取当前有效 StoreKit transaction 与 legacy signed transaction proof；
2. 将 transaction ID、环境和签名证明提交后端；
3. 后端通过 Apple 服务验证 product、bundle、environment、transaction chain 和状态；
4. 未认领 purchase chain 原子绑定当前 `clovery_account_id`；
5. 已绑定当前账户时幂等成功；
6. 已绑定其他账户时拒绝自动转移并生成支持编号；
7. 客户端重新拉取 `/v1/account/entitlements`；
8. 页面与 Widget 以服务端 entitlement 为最终状态。

离线时可以读取最近一次服务端签名缓存，但不得由本地布尔值永久授予权益。购买成功、恢复购买、换设备登录和续期通知都必须汇聚到同一账户级 entitlement。

## 9. API 契约

### 9.1 联邦身份完成结果

现有联邦登录完成接口扩展为两种成功结果：

```text
POST /v1/auth/federated/{provider}/complete
200 authenticated_session
202 identity_claim_required
```

`identity_claim_required` 返回 provider、过期时间和一次性 claim token，不返回账户或 Vault。

### 9.2 使用 claim 创建账户

```text
POST /v1/auth/accounts
{
  login_id,
  password,
  recovery_method,
  device,
  identity_claim_token?
}
```

带 claim token 时执行账户、Vault、密码凭证、外部身份与 bootstrap job 的原子创建。

### 9.3 账户继承状态

```text
GET  /v1/account/bootstrap
POST /v1/account/bootstrap/resume
```

迁移继续复用现有 `/v1/vault/migrations` 系列接口；购买继续复用 `/v1/billing/apple/legacy-claims`、`/restore` 和 `/v1/account/entitlements`。

## 10. iOS 模块边界

新增模块必须结构化拆分：

- `Application/Bootstrap/AccountBootstrapCoordinator.swift`：启动状态机；
- `Application/Bootstrap/BootstrapRoute.swift`：纯路由模型；
- `Features/Upgrade/UpgradeNoticeView.swift`：公告 UI；
- `Features/Authentication/Data/IdentityClaimAPI.swift`：claim 契约；
- `Features/Authentication/Domain/ProviderVisibilityPolicy.swift`：设备入口矩阵；
- `Features/Migration/Data/LegacyMigrationAPI.swift`：上传与报告；
- `Features/Migration/Domain/LegacyMigrationCoordinator.swift`：本地导出、重试和状态；
- `Features/Entitlements/Data/AccountEntitlementAPI.swift`：服务端权益；
- `Features/Entitlements/Domain/EntitlementReconciler.swift`：StoreKit 证明与账户权益协调；
- `Features/Bootstrap/Presentation/AccountReconciliationView.swift`：进度、重试和支持编号。

不得把认证、迁移、StoreKit 和路由逻辑集中到单个 View 或单个 API 文件中。

## 11. 错误处理

- claim 过期：重新执行外部授权，不创建账户；
- claim 重放：返回固定冲突错误并记录审计；
- CloveryID 被占用：保留 claim，允许在有效期内修改 ID；
- 迁移上传失败：保留本地数据和服务端暂存，使用同一 migration ID 重试；
- 迁移校验失败：正式 Vault 不变；
- 购买验证暂不可用：任务保持 pending，不清除本地已购交易证明；
- purchase chain 已属于其他账户：进入 needs_attention，不自动抢占；
- Vault 拉取失败：不进入首页，允许重试；
- 所有错误日志不得记录密码、refresh token、authorization code、identity claim token、完整日记或购买签名。

## 12. 测试与发布门禁

### 12.1 Go 后端

- claim token 单次消费、过期和防重放；
- 账户、Vault、密码和 Apple identity 原子创建；
- 相同 provider subject 并发只能绑定一个账户；
- 已绑定 Apple 登录返回原 account ID 与 vault ID；
- migration 相同内容去重、不同内容冲突保留；
- migration 校验失败不修改 Vault；
- legacy transaction 首次认领、同账户重放、跨账户拒绝；
- 换设备拉取相同 entitlement。

### 12.2 iOS

- 旧版本公告确认后必须进入认证；
- 新安装直接进入认证；
- 有效会话继续 bootstrap；
- iOS、华为和其他 Android provider matrix 契约；
- Apple claim 创建 CloveryID 后使用同一会话和 Vault；
- 断网、杀进程和重启继续同一 bootstrap job；
- 重复日记只保留一份；
- 已购用户升级后无需再次购买；
- 未完成继承时不能进入默认首页。

### 12.3 发布门禁

- 数据库迁移先在 staging 演练并验证回滚；
- 使用脱敏旧数据样本完成至少两次幂等迁移；
- Sandbox 与 TestFlight 验证购买认领和换设备恢复；
- 真机验证安排在 iOS 功能完成后、Flutter 跨端重构开始前；
- 任何数据丢失、重复扣费、跨账户权益或 Vault 串号均为 P0，阻止发布。

## 13. 不在本阶段范围

- 自动合并两个已经独立存在的 Clovery 账户；
- 使用邮箱判断两个账户属于同一用户；
- 将 Apple、Google、Huawei 或设备 ID 作为账户根；
- 在迁移成功后自动删除旧本地备份；
- Flutter、Android 和 HarmonyOS 页面实现；本阶段仅固化共享契约与 iOS 行为，跨端在后续工作流接入。
