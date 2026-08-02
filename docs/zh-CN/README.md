# Clovery 中文文档

本目录提供接手项目、运行代码、理解架构和执行发布验收所需的中文入口。

| 文档 | 用途 |
| --- | --- |
| [`architecture.md`](architecture.md) | 账户、数据、同步、支付和跨端架构 |
| [`development.md`](development.md) | 下载、依赖、启动、测试与常见问题 |
| [`release-status.md`](release-status.md) | 当前完成度、阻断项和待填写内容 |

## 事实源优先级

发生描述冲突时按以下顺序判断：

1. `v2/contracts/openapi/openapi.yaml`：HTTP 接口事实源；
2. `v2/services/api/migrations/`：数据库结构事实源；
3. `Config/*.xcconfig` 与 Xcode 工程配置：iOS 构建事实源；
4. `docs/release/ios-1.1.0-acceptance.md`：当前发布状态事实源；
5. `docs/superpowers/plans/`：尚未完成阶段的实施计划。

任何标记为 `NOT_RUN` 的门禁都不得在提交审核、Release 或对外说明中写成已通过。
