# Clovery 后端优先 API 设计约束

## 决策

当前阶段只完成 Go 后端、PostgreSQL 数据模型、OpenAPI 契约和自动化验收，不实现登录、注册、密码重置、Passkey、身份绑定或设备管理的 Flutter 页面。前端设计交付后，移动端只对接已经冻结并通过测试的接口。

## 模块边界

- `internal/account`：Clovery ID、根账户、外部身份归属和账户仓储。
- `internal/auth`：密码、恢复码、Passkey、联邦身份、会话和令牌。
- `internal/vault`：Vault 所有权与授权判断，不接收客户端提供的任意账户 ID。
- `internal/http`：请求解析、认证中间件、状态码和 DTO；不编写业务事务。
- `migrations`：只做可重复、可回滚的数据库结构变更。
- `contracts/openapi`：移动端和后端共同使用的 HTTP 契约唯一来源。

## 文件纪律

每个文件只承担一个明确职责。Handler 按账户、密码、恢复、绑定、会话、设备和 Vault 分类；数据库事务、密码算法、令牌编码和 HTTP 映射不得堆在同一文件。单个文件接近 250 行或出现第二个独立职责时必须拆分。

## 接口交付

每个后端工作流必须依次完成：OpenAPI 定义、失败测试、领域服务、仓储事务、HTTP Handler、集成测试。没有页面时使用 `httptest`、Go 集成测试和 curl smoke test 验收，不创建临时前端。

## 外部身份

Apple、Google、Huawei、微信和 QQ 通过统一 `IdentityProvider` 接口接入。生产 adapter 未配置开发者凭据时必须拒绝启动或保持禁用，不能使用测试 verifier 冒充生产验签。邮箱只作为资料或已验证恢复渠道，不能用于自动合并根账户。

## 完成标准

后端阶段完成时，账户创建、密码登录、恢复、Passkey、显式第三方绑定、令牌轮换、设备撤销、跨 Vault 拒绝和账户删除请求均可在没有前端页面的情况下通过自动化 API 验收。
