# 🍀 Clovery — 幸运日记

Clovery 是一款记录日常幸运瞬间的日记应用。仓库包含已上架 iOS 应用的 `1.1.0` 升级候选版本、Go 账户与 Vault 后端，以及后续 Flutter 跨端重构基础。

## 公开查看与下载

- GitHub 仓库：<https://github.com/ena-git/Clovery>
- 当前完整开发分支：<https://github.com/ena-git/Clovery/tree/codex/swift-auth-foundation>
- 当前分支 ZIP：<https://github.com/ena-git/Clovery/archive/refs/heads/codex/swift-auth-foundation.zip>
- Git 克隆：`git clone --branch codex/swift-auth-foundation --single-branch https://github.com/ena-git/Clovery.git`

> 当前默认分支 `main` 保留已发布基线。完整升级代码位于 `codex/swift-auth-foundation`，在真机、Sandbox、TestFlight 和 App Store Connect 门禁全部通过前不会误标为正式 Release。

## 当前状态

| 范围 | 状态 | 说明 |
| --- | --- | --- |
| 原生 iOS `1.1.0 (15)` | 发布候选 | 自动化、模拟器和无签名 Release 构建已通过 |
| Clovery 根账户与 Vault | 已实现 | 数据与权益归属 Clovery 账户，第三方身份仅作为登录方式 |
| Go API 与 PostgreSQL | 已实现 | 包含认证、迁移、同步、图片、权益和账户安全接口 |
| iOS 外部发布门禁 | 待执行 | 真机、Sandbox、TestFlight、签名 Archive 和生产演练 |
| Flutter 跨端客户端 | 基础工程 | 按计划等待原生 iOS 发布门禁完成后继续 |
| Android / HarmonyOS | 未开始交付 | 复用同一 OpenAPI、账户、Vault 和同步协议 |

因此，本仓库当前适合代码审查、协作开发和外部验收，**尚不能仅凭本地结果直接提交 App Store 审核**。

## 产品能力

- 文字、照片、心情和标签日记
- 幸运田野、日历、留言板和小组件
- 简体中文、English、日本語、한국어
- 深色模式、动态字体和应用内字体选择
- Clovery ID、密码、恢复码、Passkey 与第三方联合登录
- 旧版本本地/iCloud 数据认领、复制、校验和云端继承
- App Store 购买验证、恢复购买与服务端权益账本
- Vault 级日记、图片、变更游标和跨设备同步

## 技术组成

| 模块 | 技术 |
| --- | --- |
| 当前 iOS 客户端 | Swift、SwiftUI、WKWebView、离线 React 页面、WidgetKit、StoreKit 2、CloudKit 迁移源 |
| 账户与业务 API | Go 1.26.5、Chi、JWT、OIDC、WebAuthn/Passkey |
| 结构化数据 | PostgreSQL、版本化 SQL Migration |
| 图片对象 | S3 兼容私有对象存储；本地开发使用 MinIO |
| 接口契约 | OpenAPI；这里的 OpenAPI 是接口描述规范，不是 OpenAI 服务 |
| 跨端基础 | Flutter、Riverpod、Drift、Dio、go_router、Pigeon |

详细设计见 [`docs/zh-CN/architecture.md`](docs/zh-CN/architecture.md)。

## 目录说明

```text
Clovery/                 当前原生 iOS 主应用
CloveryWidget/           iOS 桌面小组件
CloveryTests/            Swift 单元与集成测试
CloveryUITests/          iOS UI 测试
Config/                  Debug/Release 编译配置
Tests/                   发布、隐私、仓库卫生等脚本门禁
docs/release/            iOS 1.1.0 发布验收记录
docs/superpowers/plans/  W0–W6 独立可验收实施计划
docs/zh-CN/              中文架构、开发和交付说明
scripts/                 iOS 与发布验证脚本
v2/apps/mobile/          Flutter 跨端基础工程
v2/services/api/         Go API、数据库迁移和测试
v2/contracts/openapi/    HTTP 接口事实源
v2/infra/                PostgreSQL 与 MinIO 本地环境
```

## 开始使用

- 本地运行与验证：[`docs/zh-CN/development.md`](docs/zh-CN/development.md)
- 账户、数据和同步架构：[`docs/zh-CN/architecture.md`](docs/zh-CN/architecture.md)
- 已完成与待补充事项：[`docs/zh-CN/release-status.md`](docs/zh-CN/release-status.md)
- iOS 发布验收主表：[`docs/release/ios-1.1.0-acceptance.md`](docs/release/ios-1.1.0-acceptance.md)

最完整的本地发布验证命令：

```bash
CLOVERY_RELEASE_API_BASE_URL=https://api.clovery.cn scripts/verify-ios-1.1.0.sh
```

该命令不能替代真机、Sandbox、TestFlight、App Store Connect 或生产环境人工验收。

## 数据与隐私边界

- 日记、图片、同步状态、配额和权益绑定 `clovery_account_id` 对应的 `vault_id`，不绑定设备或第三方账号。
- Apple、Google、Huawei 身份使用平台稳定标识绑定，不按邮箱自动合并账户。
- 密码和令牌不得写入日志、Git、Flutter 数据库、WebView localStorage 或 Widget App Group。
- `.env.example` 仅含本地开发示例；生产密钥必须由部署平台的 Secret 管理器注入。

## 版权与使用

仓库公开用于项目审查与协作下载，不代表自动授予开源许可。未经项目所有者书面授权，不得将代码用于再发布、商业分发或衍生产品。
