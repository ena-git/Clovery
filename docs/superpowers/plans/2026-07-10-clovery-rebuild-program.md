# Clovery 跨端重构计划总控

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement one workflow at a time. Do not start a later workflow before its declared input artifacts are accepted.

**Goal:** 将 Clovery 重构为 Flutter 跨端客户端、Clovery 根账户/Vault 后端和可安全迁移旧用户数据的可运营产品。

**Architecture:** Flutter/Dart 负责统一 UI、本地 SQLite 和同步队列；Go 服务负责账户、Vault、同步、权益和迁移 API；Swift/Kotlin 仅承担平台系统能力。所有客户端通过版本化 OpenAPI 契约访问同一 Clovery 后端，UI 只观察本地数据库。

**Tech Stack:** Flutter/Dart、Drift/SQLite、Riverpod、Go、Chi、pgx、PostgreSQL、MinIO（开发环境）、S3 兼容对象存储（生产环境）、OpenAPI、Pigeon、Swift、Kotlin。

---

## 技术决策

- 新代码放在 `v2/`，保留当前 `Clovery/` 与 `CloveryWidget/` 作为 V1 迁移源，直到迁移窗口关闭。
- 后端已确定采用 Go 模块化单体（Chi + pgx）；Dart 与 Go 不共享运行时代码，只共享 `v2/contracts/openapi/openapi.yaml` 的 HTTP 契约和生成模型。首发不拆分微服务。
- OpenAPI 是供应商中立的接口描述文件，不调用 OpenAI 或其他 AI 服务；它不承载、不转发任何用户日记、图片或账户数据。
- Flutter 使用 Drift 维护本地 SQLite，Riverpod 管理应用状态，Pigeon 定义 Dart 与 Swift/Kotlin 的类型化平台接口。
- PostgreSQL 保存账户、Vault、日记元数据、同步游标与权益；图片保存到私有 S3 兼容对象存储；开发环境使用 MinIO。
- V2 首发支持 iOS 17+；Android 在 iOS Beta 验收后接入；鸿蒙先执行可行性 PoC，不进入 V2 首发承诺。

## 工作流与验收依赖

| ID | 工作流 | 可独立验收产物 | 依赖 |
| --- | --- | --- | --- |
| W0 | 平台基础与契约 | 可启动的 Flutter 壳、Go 健康服务、Postgres/MinIO、CI 与 OpenAPI 校验 | 无 |
| W1 | V1 数据保护与导出 | 修复照片落盘、导出可校验 `migration_bundle` 的 V1 维护版本 | W0 的契约版本号规则 |
| W2 | Clovery 账户与 Vault | 可在 staging 注册自定义 Clovery ID、密码/Passkey、绑定第三方身份、撤销设备 | W0 |
| W3 | Flutter iOS 核心体验 | iOS TestFlight 垂直切片：账户、离线日记、照片、同步状态、原生扩展 | W0、W2 |
| W4 | 迁移、同步与运营 Beta | V1→V2 校验迁移、冲突处理、删除传播、支付权益、监控与回滚演练 | W1、W2、W3 |
| W5 | Android 接入与鸿蒙 PoC | Android Flutter 版本；鸿蒙运行时/原生能力结论与可发布路径 | W0、W2、W4 |
| W6 | 上线后体验扩展 | 锁屏组件、繁体中文、Watch 与新玩法的独立增量版本 | W3、W4 |

## 执行规则

1. 严格按 W0→W1/W2→W3→W4→W5→W6 的工作流边界实施；同步冲突、删除传播和服务端权益属于 W4，不提前塞入 W1 维护版。
2. 原生 iOS 1.0.3 (14) 的自动化、升级数据、相册、迁移、StoreKit、TestFlight 和 App Store 发布门禁必须在 Flutter W3 开始前完成。旧文档中 W3/W4 后再完成 W1 真机验收的排期由 2026-07-15 已批准方案 A 替代。
3. 每个工作流单独建立 Issue、验收清单和发布记录；一个工作流失败不能通过临时绕过影响另一个工作流。
4. 所有身份、同步、支付和迁移变更必须先编写测试，再改实现；协议先变更 OpenAPI，再生成客户端。
5. 不允许 V2 代码写入 V1 `localStorage` 或覆盖 V1 Documents 备份；迁移只复制、校验、可重试。
6. 不允许在客户端硬编码第三方密钥、支付密钥、对象存储密钥或生产 URL。
7. 当前目录无 Git 历史。W0 首先建立受保护的新 Git 仓库与远端备份；计划不要求在此归档副本上直接提交。

## 计划文件

- `2026-07-10-w0-platform-foundation.md`
- `2026-07-10-w1-v1-data-protection.md`
- `2026-07-10-w2-account-vault-backend.md`
- `2026-07-10-w3-flutter-ios-core.md`
- `2026-07-10-w4-migration-sync-operations.md`
- `2026-07-10-w5-android-harmony.md`
- `2026-07-10-w6-post-launch-experience.md`

## 全局上线门槛

- 旧数据迁移后条目数、照片数、删除状态和随机抽样内容均一致。
- 同一 Clovery 账户使用 Clovery ID、Passkey 或任一已绑定第三方身份登录时进入同一 Vault。
- 离线写入、图片上传重试、分页同步、删除墓碑和冲突副本均无静默数据丢失。
- 购买、恢复购买、设备撤销、密码重置、账户删除和数据导出均有审计记录与真机验证。
- iOS 真机体验矩阵通过；Android/Harmony 只在各自工作流验收完成后发布。
