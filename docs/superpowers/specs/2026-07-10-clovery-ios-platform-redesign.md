# Clovery 跨端重构与 iOS 首发运营优先级策略

**状态：** 已确认架构决策
**目标：** 将现有的 WebView + 本地存储 + CloudKit 私有库应用，重构为可长期运营的 Flutter 跨端产品、原生平台扩展与 Clovery 账户平台；优先保证 iOS 首发的日记、照片、同步、账户和付费在真实用户场景中可靠工作。

---

## 1. 结论与边界

### 1.1 目标架构决策

1. **客户端改为 Flutter 主应用。** V2 使用 Flutter/Dart 承载 iOS、Android 与后续鸿蒙的统一 UI、状态管理、离线数据库、同步队列和 API 调用；不再以 React、Babel、`WKWebView` 或字符串 JS/Swift 消息桥承载核心体验。
2. **Clovery 账户是唯一账户根。** Apple、Google、Huawei 是可替换的联邦身份入口，不是数据所有者，也不是订阅权益主体。
3. **Clovery 后端是唯一云端事实源。** 现有 CloudKit 私有数据库仅在迁移期用于读取和导入旧数据；迁移完成后不再承担日常同步。
4. **本地数据库是唯一离线事实源。** Flutter 写入日记、图片、标签和设置时先提交本地 SQLite 数据库，再由 Dart 同步队列上传；网络失败不能阻断记录。
5. **iOS 首发以 iOS 17+ 为基线。** Flutter 主应用在 iOS 17+ 运行，原生扩展使用 Swift；旧 iOS 16 用户停留在 V1 维护版，并获得导出/迁移引导。
6. **原生能力通过类型安全桥接实现。** iOS 使用 Swift，Android 使用 Kotlin；使用 Pigeon 生成的接口替代任意字符串 `MethodChannel` 或 JS 消息，避免现有桥接协议失配问题。
7. **鸿蒙是独立可行性闸门。** Flutter 官方当前支持清单覆盖 iOS 和 Android，未将 HarmonyOS 列为官方支持目标；因此后端和 Dart 领域层必须预留适配边界，但鸿蒙不得在 PoC 验证前进入正式发布日期承诺。[Flutter 支持平台](https://docs.flutter.dev/reference/supported-platforms)
8. **后端固定采用 Go。** V2 首发以 Go 模块化单体交付账户、Vault、同步、权益、迁移和运营 API；使用 Chi 处理 HTTP 路由、pgx 访问 PostgreSQL。服务拆分只在可观测的容量或团队边界出现后进行，不为首发预建微服务。
9. **iOS 作为现有 App Store 应用升级，其他平台首次上架。** iOS V2 继承 `com.clovery.app`、Team `M92TBSSR2R`、`iCloud.com.clovery.app`、`group.com.clovery.app` 和现有 Widget 标识。Android、Huawei AppGallery 及其他尚未上架的平台统一以 `com.clovery.app` 为应用包名起点，并分别生成、离线备份长期发布签名；首次上架后这些标识和签名同样不可更换。
10. **数据库结构只能通过版本化迁移演进。** PostgreSQL 固定主版本；生产环境禁止 ORM 自动建表、应用启动时静默改表和人工直接修改结构。每个迁移必须有确定顺序、事务边界、回滚或前向修复策略，并在空库和已有数据快照上验证。

OpenAPI 是供应商中立的 HTTP 接口描述规范，不是 OpenAI 服务或协议：它不调用任何 AI 模型、不要求 OpenAI 账号或密钥，也不向外发送用户数据。它仅作为 Flutter 客户端、Go 服务和测试之间的版本化接口契约。[OpenAPI Initiative](https://www.openapis.org/what-is-openapi)

### 1.2 不做的事

- 不在 V2 中继续修补或扩展 WebView 主界面。
- 不将用户日记、图片、订阅权益绑定到设备、Apple ID、Google 账号、Huawei ID 或电子邮件。
- 不通过邮箱、昵称或头像自动合并账号。
- 不在数据迁移完成并验收前删除旧 `localStorage`、Documents 备份或 CloudKit 记录。
- 不把锁屏组件、Watch、随机雨雪、每日抽签等新功能放在可运营版本之前。
- 不更换 iOS 已上架应用的 Bundle ID、App Group、iCloud Container 或升级签名；不在其他平台首次发布后更换 Application ID 或发布签名。
- 不通过手工导入 SQL、生产环境自动建表或覆盖式导入迁移用户数据。

### 1.3 跨端职责划分

```text
Flutter/Dart（共享）
├── 统一 UI、设计令牌、多语言、状态管理
├── 日记编辑、日历、搜索、标签、账户与安全、付费页面
├── SQLite 数据库、同步队列、API Client、图片上传编排
└── Vault、账号、权益与同步领域模型

iOS / Swift（原生扩展）
├── Sign in with Apple、Keychain、StoreKit 2、Push
├── Photos/Camera、WidgetKit、锁屏组件、Watch
└── App Group 快照、文件保护和系统分享

Android / Kotlin（原生扩展）
├── Credential Manager、Google 登录、Play Billing、Push
├── Widget、后台任务、媒体权限和系统分享
└── Flutter 插件实现与平台测试

Harmony（后续适配）
└── 复用 Clovery API、Dart 领域/同步层；在 PoC 后确定 Flutter 运行时和 ArkTS 原生扩展边界
```

UI 不直接与服务端保持业务状态。Flutter 界面只观察本地 SQLite 数据库；Dart 同步器将本地变更上传并将服务端变更写回数据库，因此 iOS、Android 和后续鸿蒙看到的是同一 Vault 数据，而不是彼此复制界面状态。

---

## 2. 当前系统为何必须重构

当前实现由 SwiftUI 壳层加载单页 HTML，日记同时散落在 WebKit `localStorage`、Documents 备份、iCloud KVS、App Group 与 CloudKit 私有库。这个模型没有单一事实源，也没有可靠的冲突、删除或账号模型。

已确认的上线阻断包括：

| 风险 | 当前根因 | 重构后的处理 |
| --- | --- | --- |
| 照片重启后丢失 | 网页请求保存/读取照片，但原生桥未注册对应处理器 | 原生图片库、文件保护、资产校验和、离线同步队列 |
| 跨设备数据不一致 | 本地优先合并、删除不上传、CloudKit 查询不分页 | 服务端版本号、变更游标、删除墓碑、冲突副本 |
| 付费留言板失效 | Web/Swift 回调协议不一致且插值被转义为字面量 | 原生 StoreKit 2 + 服务端权益账本 |
| 用户更换平台后无数据 | CloudKit 私有库与 Apple 身份绑定 | Clovery 账户 + `vault_id` 统一数据域 |
| 无法安全恢复账户 | 没有 Clovery 根账户、绑定和恢复机制 | 多身份绑定、Passkey/恢复码、设备会话管理 |

现有代码证据：照片桥接断裂见 `Clovery/Clover Diary.html` 与 `Clovery/WebView.swift`；CloudKit 同步见 `Clovery/CloudKitSync.swift`；Widget 通过 App Group 读取精简 JSON。V2 不继承这些边界，只迁移已有用户数据。

---

## 3. 账户与身份设计

### 3.1 账户模型

```text
Clovery Account（唯一根账户）
├── clovery_account_id：用户、权益、删除和恢复的唯一主体
├── clovery_login_id：用户注册时自定义的 Clovery ID
├── vault_id：日记、图片、同步记录、容量和密钥域
├── Apple Identity：可绑定登录钥匙
├── Google Identity：可绑定登录钥匙
├── Huawei Identity：可绑定登录钥匙
├── Passkey：推荐恢复凭证
└── Recovery Code：一次性离线恢复凭证
```

核心约束：

- `clovery_account_id` 与 `vault_id` 均使用不可推测的 UUID；一个个人账户在 V2 首发时对应一个私有 Vault。
- `clovery_login_id` 是用户注册时自定义的 Clovery ID，用于密码登录和账户识别；它不是数据主键、Vault ID、权益 ID 或公开社交昵称。更改 Clovery ID 不得改变任何数据归属。
- Clovery ID 格式固定为 4–24 个 ASCII 小写字母、数字或下划线，必须以字母开头；登录时统一转换为小写。禁止空格、中文、Emoji、全角字符和易混淆 Unicode 字符，避免跨端输入差异与同形字账号欺骗。
- 服务端对规范化后的 `clovery_login_id` 建立唯一索引；保留 `admin`、`support`、`clovery`、第三方品牌、敏感词和系统路由等保留名单。注册可返回“该 ID 不可用”，但请求必须限流并配置人机验证，防止批量抢注与枚举。
- Clovery ID 注册成功后默认锁定 30 天；后续改名要求近期重新认证、受限频率和审计记录。旧 ID 保留 30 天仅用于提示迁移，之后不再接受登录且永久标记为不可注册，防止他人接管旧登录名。显示昵称独立于 Clovery ID，可随时修改。
- 外部身份唯一键为 `(provider, issuer, subject)`，并建立唯一索引；绝不使用邮箱作为关联键。
- Apple 使用服务端验证后的用户标识；Google 使用经验证 ID Token 的 `sub`；Huawei 使用其授权响应中面向本应用稳定的 subject/open ID。客户端提交的展示名、邮箱、头像都不是可信身份凭据。
- Apple 官方明确要求用用户标识而不是邮箱识别账户，且用户可能选择私密转发邮箱；Google 也明确说明 `sub` 才是唯一且不会复用的用户标识。[Apple 身份验证文档](https://developer.apple.com/documentation/signinwithapple/authenticating-users-with-sign-in-with-apple)；[Google OpenID Connect Claims](https://developers.google.com/identity/openid-connect/reference)。
- Huawei Account Kit 使用 OAuth 2.0 / OpenID Connect；其开发者控制台、回调地址与生产证书属于发布依赖。[Huawei Account Kit](https://developer.huawei.com/consumer/cn/sdk/account-kit)。

### 3.2 登录、绑定与恢复流程

1. 用户可以选择“创建 Clovery 账号”，先检查并注册自定义 Clovery ID，再设置密码并绑定 Passkey、恢复邮箱或恢复码；也可以首次选择 Apple、Google、Huawei、微信或 QQ 后，由客户端取得授权码或 ID Token 并立即交给 Clovery 后端验证。
2. 对第三方登录，后端验证 `issuer`、`audience`、签名、有效期、`nonce`、授权码使用状态和平台回调状态；验证通过后：
   - 已存在 `(provider, issuer, subject)`：创建该 `clovery_account_id` 的设备会话；
   - 不存在该身份：显示“创建新 Clovery 账户”或“绑定到已有 Clovery 账户”。新账户在进入 Vault 前必须创建自定义 Clovery ID，并设置密码或注册 Passkey。
3. **不自动合并。** 未绑定的 Google/Huawei 身份不能进入 Apple 创建的 Clovery 账户。用户必须先登录已有 Clovery 账户，再完成新身份的二次验证绑定。
4. 绑定操作要求“当前账户的近期重新认证 + 新身份的有效验证”同时成立，并以单个服务端事务写入身份关系和审计事件。
5. 每个账户必须拥有两种独立登录/恢复凭证：Clovery 密码加 Passkey、已验证恢复邮箱或恢复码；或两种联邦身份；或一种联邦身份加 Passkey、Clovery 密码或恢复码。未满足时在“账户与安全”持续提示；在删除、解绑和购买恢复前强制补全。
6. 不允许解绑最后一种可用凭证。用户必须先添加新身份、Passkey 或新的恢复码。
7. 恢复码生成一次后只展示一次；服务端仅保存强哈希，使用后立即失效并记录审计事件。

### 3.4 Clovery ID 与密码登录体验

- 登录页的默认入口是“使用 Clovery 账号”：输入 `Clovery ID 或已验证邮箱` 和密码；同页优先展示“使用 Passkey 登录”。
- 没有任何第三方账户的用户，只要记住自定义 Clovery ID 和密码，并保留 Passkey、恢复邮箱或恢复码之一，就可以在三星、OPPO、vivo、Pixel、iPhone 和后续鸿蒙设备登录同一账户。
- 密码只作为凭证记录关联到 `clovery_account_id`；服务端使用 Argon2id 与独立随机盐保存哈希，永不保存、记录或回传明文密码。
- 密码创建/修改必须检查弱密码与已泄露密码黑名单、限流失败尝试、提示强度；无泄露迹象时不强制周期性改密。NIST 推荐将弱密码黑名单与认证限流作为防护重点。[NIST SP 800-63B](https://pages.nist.gov/800-63-4/sp800-63b.html)
- 忘记密码不能只凭昵称、Clovery ID 或设备识别恢复；必须验证已绑定 Passkey、恢复邮箱或恢复码，并在成功后撤销现有会话/要求重新登录。

### 3.3 设备会话与撤销

- 每台设备拥有独立 `device_id`、会话和刷新令牌；刷新令牌轮换、可单设备撤销、可查看最近活动。
- iOS 访问令牌放入 Keychain；应用数据库使用 iOS Data Protection，图片文件使用 `.complete` 文件保护。
- “移除设备”立即拒绝该设备的新 token 刷新和同步请求；设备下次在线时删除本地 Vault 密钥包装与缓存。
- 需要明确产品限制：离线且已解锁的失窃设备无法被服务端即时物理擦除；撤销保护的是后续访问，设备保护和应用锁用于降低离线暴露风险。

---

## 4. 数据、密钥和同步设计

### 4.1 分层存储

| 层 | 技术与职责 | 允许的数据 |
| --- | --- | --- |
| Flutter 本地库 | Dart + Drift/SQLite | 日记、标签、草稿、同步操作、设置、资产元数据 |
| 端侧文件区 | `Application Support/VaultAssets` | 压缩后的原图/缩略图；iOS 由 Swift 设置 Data Protection，Android/Harmony 使用对应平台保护策略 |
| Clovery API | 账户、权限、同步和迁移协议 | 已认证请求、变更游标、签名上传授权 |
| 关系数据库 | PostgreSQL 或等价托管关系库 | 账户、Vault、身份、日记元数据、版本、权益、审计 |
| 对象存储 | 私有对象存储 + 短期预签名 URL | 加密后的图片与附件 |
| 密钥服务 | KMS/HSM | Vault 数据密钥的信封加密与轮换 |

服务端核心表：

- `clovery_accounts`、`vaults`、`external_identities`、`passkeys`、`recovery_codes`
- `devices`、`sessions`、`audit_events`
- `journal_entries`、`entry_assets`、`sync_changes`、`deleted_records`
- `entitlements`、`store_transactions`、`account_deletion_requests`

### 4.2 Vault 密钥边界

- 每个 `vault_id` 拥有独立数据密钥域；服务端使用 KMS 信封加密保存 Vault 数据密钥，不与设备或第三方身份绑定。
- 设备只持有经设备 Keychain 保护、可轮换的本地密钥包装；不在 `UserDefaults`、日志、备份 JSON 或第三方分析工具中保存明文密钥。
- V2 首发承诺“传输加密、静态加密、设备缓存保护”，**不宣传端到端加密**。端到端加密需要独立的多设备密钥分发、恢复、搜索和冲突方案，作为后续安全专项，不能在未完成设计时承诺。
- Vault 所有者删除账户后，服务端执行异步、可审计的元数据与对象删除；保留期限与法务/支付争议留存规则必须在隐私政策中明确。

### 4.3 同步协议

1. Flutter 本地写入先落 Drift/SQLite，并追加不可变 `SyncOperation`；界面立即显示成功状态。
2. 同步器按 `operation_id` 幂等上传，服务端为每条记录分配递增 `revision` 和全局变更游标 `change_cursor`。
3. 图片先创建资产上传会话，分块/断点上传到对象存储；完成后以 SHA-256、尺寸、MIME 类型和资产 ID 提交到日记修订版本。
4. 客户端拉取 `change_cursor` 之后的变更，事务性写入本地库，成功后推进游标；服务端分页必须完整处理。
5. 删除使用墓碑记录并同步到所有设备；物理删除在恢复窗口和后台清理策略满足后执行。
6. 同一日记的并发编辑不能静默覆盖：当客户端 `base_revision` 过期时，服务端保留冲突快照并返回需要处理的冲突；客户端提供“保留两个版本”或“选择一个版本”的明确 UI。
7. 账户设置、标签排序、主题、提醒和小组件设置均纳入 Vault 同步模型；Flutter 经 Pigeon 请求 iOS/Android 原生层生成小组件快照，小组件不能直接读取云端。

### 4.4 数据模型最小集合

`JournalEntry` 至少包括：`id`、`vault_id`、`created_at`、`updated_at`、`revision`、`deleted_at`、`lucky_text`、`body_text`、`mood`、`tags`、`asset_ids` 与迁移来源。任何字段的增加必须同步更新本地模型、API 契约、服务器校验和迁移测试。

---

## 5. 旧数据迁移策略

### 5.1 迁移原则

- 迁移是**复制与校验**，不是移动与删除。
- 旧数据在 V2 服务端确认完整、用户可查看且导出成功前始终保留。
- 迁移必须在用户登录 Clovery 账户后、明确授权上传到其 Vault 后执行。
- 每次迁移生成 `migration_id`、条目计数、照片计数、字节数和校验摘要，可中断重试且幂等。

### 5.2 V1 到 V2 的桥接版本

先发布一个仅负责数据保护的 V1 维护版，再发布 V2：

1. 修复 V1 照片桥接和关键数据回调，防止迁移窗口继续产生损坏数据。
2. V1 将 WebView `localStorage`、Documents 全量备份、`Documents/photos` 与可读取的旧 CloudKit 私有记录导出为版本化 `migration_bundle`。
3. Bundle 逐项包含条目 ID、正文、标签、原始照片文件名、SHA-256、创建/修改时间和来源；导出完成后写入不可变清单。
4. V2 登录后导入 Bundle，按清单上传至新 Vault；服务端返回逐项结果和总校验摘要。
5. 用户在迁移报告中确认“条目数、照片数、最近记录、随机抽样图片”均一致后，V2 才标记迁移完成。
6. V2 在迁移完成后保留本地只读旧数据快照和重新迁移入口；不自动清理 V1 数据。

### 5.3 CloudKit 迁移限制

旧 CloudKit 是用户 iCloud 私有数据库。只有在登录原 Apple 账号且具有旧容器权限的 Apple 设备上，应用才能读取相应记录。因此：

- 必须保留旧 iCloud Container、相关 entitlement 和迁移读取代码直到迁移窗口结束。
- 未持有任何旧 Apple 设备或无法登录原 iCloud 的用户，不能由 Clovery 后端直接读取其旧 CloudKit 私有数据；只能从本地备份或用户导出恢复。
- 产品内必须明确该限制，并在停用 V1 前多次提醒用户执行迁移/导出。

---

## 6. 分阶段优先级与上线闸门

### P0：停止数据损失，建立重构控制面

**目标：** 现有用户的日记和照片不再因当前架构问题继续损坏，团队具备交付与回滚能力。

- 建立 Git 仓库、分支保护、Issue 看板、版本发布记录与崩溃监控。
- 移交 Apple Developer、App Store Connect、CloudKit Dashboard、域名/DNS、支付、证书和生产密钥管理权限。
- 发布 V1 数据保护维护版：照片落盘、关键 Web/Swift 回调、导出 Bundle、原始数据备份。
- 冻结 V1 新功能，仅接受数据安全、迁移和严重体验修复。
- 定义 V2 API 契约、数据库迁移、密钥管理、审计日志和灾难恢复演练。

**P0 验收：** 新增带照片日记重启后仍可读取；V1 可导出完整迁移 Bundle；任一操作失败都有可见错误和可重试路径；生产凭据由团队而非个人设备持有。

### P1：Clovery 账户平台与原生 iOS 数据核心

**目标：** 建立跨设备、跨平台的账户和数据底座。

- 部署账户、Vault、身份绑定、Passkey/恢复码、设备会话、审计和账户删除 API。
- 完成 Apple、Google、Huawei 身份验证服务端适配；iOS 首发界面至少交付 Apple、Google 与 Passkey，Huawei 身份可先通过受控绑定流完成，不能伪装为已支持的原生 iOS 登录。
- 建立 Flutter Monorepo：Dart 领域模型、OpenAPI 生成 Client、Drift/SQLite 数据库、同步队列、变更游标、删除墓碑与冲突副本。
- 建立 Pigeon 平台接口：iOS Swift 和 Android Kotlin 分别实现身份、支付、推送、文件保护、App Group/Widget 快照等能力；不允许业务层直接调用平台通道。
- 完成 StoreKit 2 交易验证、服务端权益归属和恢复购买；权益只写入 `clovery_account_id`。
- 实现 V1 Bundle 与旧 CloudKit 的导入器。

**P1 验收：** 使用任一已绑定身份登录同一账户均得到同一 Vault；新身份不会自动串入既有账户；移除设备后不能刷新会话；两设备离线编辑、删除、恢复、照片上传和冲突处理均无静默丢失。

### P2：Flutter iOS 首发体验与原生 iOS 扩展

**目标：** 完成可替代 V1 的主日记体验。

- Flutter 实现首页、快速记录、编辑/多图、日历、搜索、标签、四叶草田、设置和账户与安全；全部页面复用同一 Dart UI 代码与设计令牌。
- 用 Flutter 的安全区、键盘可见区、动态布局和 Cupertino 交互规范处理底部按钮/键盘冲突、刘海屏、不同 iPhone 尺寸与横竖屏策略。
- 支持深色模式、Dynamic Type、VoiceOver、Reduce Motion、中文/英语/日语/韩语；繁体中文作为独立本地化包，不与简体中文混用。
- 重建 Swift WidgetKit 扩展：小组件从 Flutter 写入的 App Group 快照读取；快速记录使用深链直达 Flutter 编辑器；不交付未完成的 Timer 模板控件。
- 通过 Swift 原生扩展完成图片选择、拍照、压缩、照片权限、后台上传与失败恢复；Flutter 只消费类型化结果。
- 通过 Swift 原生扩展完成 Sign in with Apple、StoreKit 2、Keychain、Push、系统分享与 iOS 文件保护。

**P2 验收：** 在最小支持设备、主流小/大屏 iPhone、深色模式、放大字体和无网络场景下，记录、编辑、删除、搜索、照片查看与同步状态均可完成；没有文本截断、按钮被键盘遮挡或不可点击的阻断问题。

### P3：迁移 Beta、Android 接入与运营就绪

**目标：** 让真实 V1 用户安全迁移并验证生产运营链路。

- 邀请真实 V1 数据样本进入 TestFlight；覆盖空数据、小数据、大量照片、长期未同步、重复 ID 和删除记录。
- 建立迁移仪表盘：开始/完成/失败率、条目与照片校验差异、同步积压、冲突率、登录/绑定失败率与支付恢复率。
- 配置 CloudKit 旧数据迁移期观察、Clovery 后端备份、对象存储生命周期、告警和值班手册。
- 在 iOS Beta 指标达标后，接入 Android Kotlin 原生扩展：Google 登录、Credential Manager、Play Billing、后台同步、Push 与桌面组件；Flutter UI 与 Dart 同步层不分叉。
- 完成鸿蒙 Flutter 运行时、登录、Push、文件权限和支付的 PoC。PoC 未通过时，鸿蒙进入独立 ArkTS 客户端方案，但仍复用 Clovery API 契约与数据模型。
- 完成隐私政策、账户删除入口、数据导出、客服恢复流程、付费条款与 App Store 素材。

**P3 验收：** Beta 用户迁移后条目/照片校验一致；账户绑定、恢复码、移除设备、删除账户与购买恢复均有可审计结果；P0/P1 级事故有可执行回滚手册。

### P4：正式上线与功能扩展

**目标：** 在 V2 稳定后扩展体验，不牺牲数据可靠性。

- 首发正式发布：Flutter 日记体验、Clovery 账户、同步、照片、付费权益、iOS 桌面小组件与数据迁移；Android 在 P3 验收后以同一 Flutter 版本发布。
- 正式版稳定后按用户价值排序交付：锁屏组件 → 繁体中文 → Watch → 每日抽签 → 四叶草田雨雪动画。
- 每个新增端或新登录入口必须复用同一 Clovery 账户、Vault、同步 API、权益账本和设备撤销模型。

---

## 7. iOS 体验验收矩阵

发布候选版本必须覆盖以下真实设备/系统组合：

| 场景 | 必测行为 |
| --- | --- |
| 小屏与大屏 iPhone | 首页、搜索、编辑器、键盘弹出、底部操作、照片预览不截断/遮挡 |
| 深色模式与动态字体 | 文字可读、信封/图标不反白、布局不溢出 |
| 离线与弱网 | 新建、编辑、删除立即本地可见；同步队列可恢复 |
| 两台 iPhone | 同账户、不同登录钥匙、编辑冲突、删除同步、图片同步、设备撤销 |
| 重装与换机 | 登录、恢复 Vault、迁移 Bundle、购买恢复 |
| 权限拒绝 | 相册、相机、通知拒绝后功能给出替代路径且不崩溃 |
| 辅助功能 | VoiceOver 焦点、Dynamic Type、Reduce Motion、键盘可达性 |
| 支付 | 首购、取消、待批准、失败重试、恢复购买、权益跨设备生效 |
| Android 发布前 | Flutter UI、Drift 本地库、Google 登录、Play Billing、后台同步与 Android Widget 不产生 Dart 分叉 |
| 鸿蒙发布前 | Flutter 运行时和原生能力 PoC 通过；若未通过，ArkTS 客户端复用同一 API 契约并完成独立验收 |

---

## 8. 发布前不可妥协的闸门

以下任一项未通过，不提交正式版本：

1. V1 → V2 的条目、照片和删除状态迁移校验通过，并可生成用户可读报告。
2. 账户绑定、解绑、恢复、设备撤销和删除账户均有自动化 API 测试和人工演练。
3. 所有联邦登录均在服务端完成 token 验证；客户端不能凭邮箱或本地标识获得他人 Vault。
4. 日记、图片、订阅和容量只由 `clovery_account_id` / `vault_id` 授权。
5. 同步支持分页、幂等、重试、墓碑、冲突副本和可观测指标；不存在“本地优先静默覆盖”。
6. StoreKit 交易与服务端权益账本一致，购买恢复可跨设备验证。
7. 生产环境密钥、数据库备份、对象存储、KMS、日志脱敏、告警和事故响应已演练。
8. P2 真机矩阵、迁移 Beta 和隐私/商店审核材料全部完成。

---

## 9. 交付物与责任面

| 责任面 | 必须交付 |
| --- | --- |
| Flutter/Dart | 统一 UI、设计令牌、多语言、Drift 本地库、同步器、API Client、迁移编排、领域测试与端到端测试 |
| iOS / Swift | Sign in with Apple、Keychain、StoreKit 2、Photos/Camera、Push、WidgetKit、锁屏/Watch、App Group、文件保护与真机测试 |
| Android / Kotlin | Google 登录、Credential Manager、Play Billing、Push、后台任务、Widget、媒体权限、Flutter 插件与真机测试 |
| Harmony 适配 | Flutter 运行时与原生扩展 PoC；通过后交付平台插件，未通过则交付 ArkTS 客户端并复用 API 契约 |
| 后端 | 身份验证、账户/Vault API、同步 API、关系库、对象存储、KMS、权益、审计、删除与导出 |
| 平台运维 | CI/CD、密钥托管、监控告警、备份恢复、生产配置、事故手册 |
| 产品/设计 | 登录绑定文案、迁移报告、冲突解决 UI、账户安全、删除和导出体验、支付说明 |
| 运营/客服 | 账户恢复 SOP、迁移失败分流、支付恢复、隐私请求、发布公告 |

---

## 10. 下一步

本策略确认后，实施计划按独立可验收工作流拆分：

1. P0 V1 数据保护与迁移 Bundle；
2. P1 Clovery 账户/Vault 后端、Flutter 数据核心与类型化原生桥接；
3. P2 Flutter iOS 首发体验与 Swift 原生能力；
4. P3 iOS Beta 迁移、Android 接入、鸿蒙 PoC、运营和发布；
5. P4 锁屏、Watch 与新玩法。

每个工作流都必须先写测试、定义 API/数据迁移回滚方案，并在完成后进行安全与真机复核；不得以视觉完成替代数据和账户验收。
