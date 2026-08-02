# Clovery V2 平台基础

`v2/` 是 Clovery 面向生产的账户、数据和跨端重构目录。现有 `Clovery/` 与 `CloveryWidget/` 在迁移窗口结束前继续作为已发布 iOS 客户端的升级来源。

| 路径 | 职责 |
| --- | --- |
| `apps/mobile` | Flutter UI 基础、Drift 本地数据库和同步引擎预留 |
| `services/api` | Go API、账户/Vault、迁移、同步、图片和权益服务 |
| `contracts/openapi` | HTTP 接口唯一事实源 |
| `infra` | PostgreSQL、MinIO 与部署配置 |
| `scripts` | 预发、安全和发布验证脚本 |

OpenAPI 是保存在仓库中的版本化接口描述规范，不是 OpenAI 服务，也不会把用户数据发送给 OpenAI。

运行与验证请参阅：

- [`../docs/zh-CN/development.md`](../docs/zh-CN/development.md)
- [`../docs/zh-CN/architecture.md`](../docs/zh-CN/architecture.md)
- [`../docs/zh-CN/release-status.md`](../docs/zh-CN/release-status.md)
