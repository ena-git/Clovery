# W2：Clovery 账户与 Vault 后端实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 staging 提供 Clovery ID/密码、Passkey、联邦身份绑定、设备撤销和私有 Vault 的安全后端，且所有授权均以 `clovery_account_id` 与 `vault_id` 为根。

**Architecture:** Go API 以 PostgreSQL 事务维护账户、登录 ID、身份、Passkey、恢复码、会话、设备和 Vault。认证 endpoint 按 OpenAPI 定义，Dart 只保存短期 access token 和轮换 refresh token；第三方提供方只在服务端验证。

**Tech Stack:** Go、Chi、pgx、PostgreSQL、Argon2id、WebAuthn、OpenAPI、Redis 或 PostgreSQL 限流表、XCTest/Flutter integration test clients。

## 2026-07-12 后端优先执行约束

- W2 只交付后端、数据库、OpenAPI 和自动化 API 验收，不实现 Flutter 登录、注册、重置密码或绑定页面。
- HTTP、领域服务、仓储、密码算法、令牌、Passkey 和 provider adapter 按职责分类分文件；单文件接近 250 行时继续拆分。
- 前端设计完成后只对接冻结接口，不让临时页面反向定义账户或安全模型。

---

### Task 1: 定义账户、身份与 Vault 数据库模型

**Files:**
- Create: `v2/services/api/migrations/000002_accounts.up.sql`
- Create: `v2/services/api/migrations/000002_accounts.down.sql`
- Create: `v2/services/api/internal/account/repository.go`
- Create: `v2/services/api/internal/account/repository_test.go`
- Modify: `v2/contracts/openapi/openapi.yaml`

- [x] **Step 1: 写数据库约束测试**

测试必须证明：规范化后重复 `clovery_login_id` 被拒绝；同一 `(provider, issuer, subject)` 不能关联两个账户；一个账户只有一个 V2 私有 Vault；同一旧 ID 不能被重新注册。

- [x] **Step 2: 创建核心表和唯一索引**

迁移至少创建：

```sql
clovery_accounts(id uuid primary key, created_at timestamptz not null)
account_login_ids(account_id uuid, normalized_id text unique, status text, reserved_until timestamptz)
vaults(id uuid primary key, owner_account_id uuid unique, status text)
external_identities(account_id uuid, provider text, issuer text, subject text,
                    unique(provider, issuer, subject))
devices(id uuid primary key, account_id uuid, revoked_at timestamptz)
sessions(id uuid primary key, device_id uuid, refresh_token_hash bytea, revoked_at timestamptz)
passkeys(id uuid primary key, account_id uuid, credential_id bytea unique, public_key bytea)
recovery_codes(id uuid primary key, account_id uuid, code_hash bytea, used_at timestamptz)
audit_events(id uuid primary key, account_id uuid, event_type text, payload jsonb)
```

- [x] **Step 3: 将 Clovery ID 规则放在数据库前校验与数据库约束两层**

Go validator 固定允许 `^[a-z][a-z0-9_]{3,23}$`；应用层拒绝保留词，数据库使用 lower-case unique index。改名时将旧 ID 标记为 `retired`，永久拒绝新注册。

- [x] **Step 4: 运行迁移与仓储测试**

Run:

```bash
cd v2/services/api
go test ./internal/account/...
DATABASE_URL="$DATABASE_URL" MIGRATIONS_PATH=./migrations go run ./cmd/migrate up
```

Expected: 空数据库可迁移，重复约束测试通过。

### Task 2: 实现 Clovery ID、密码与恢复码认证

**Files:**
- Create: `v2/services/api/internal/auth/password.go`
- Create: `v2/services/api/internal/auth/password_test.go`
- Create: `v2/services/api/internal/auth/login_service.go`
- Create: `v2/services/api/internal/http/auth_handler.go`
- Modify: `v2/contracts/openapi/openapi.yaml`

- [x] **Step 1: 先写密码策略测试**

测试必须覆盖：弱密码黑名单拒绝；12 字符以上密码可以包含空格；相同密码两次哈希不同；错误密码不泄露“账户不存在”；连续失败触发限流。

- [x] **Step 2: 实现密码凭证**

`password.go` 使用 Argon2id 和每个密码独立随机 salt。固定参数、hash encoding 和版本号必须能支持未来重新哈希。日志、API response 和 audit payload 不得出现密码、salt 或 hash。

- [x] **Step 3: 定义认证 API**

OpenAPI 必须包含：

```text
POST /v1/auth/accounts
POST /v1/auth/password/login
POST /v1/auth/password/reset/start
POST /v1/auth/password/reset/complete
POST /v1/auth/recovery-codes
POST /v1/auth/recovery-codes/consume
```

创建账户要求 custom Clovery ID、密码和第二恢复凭证的注册意图；密码重置要求 Passkey、验证恢复邮箱或未使用恢复码，成功后撤销其余 refresh sessions。

- [x] **Step 4: 验证 API 行为**

编写 handler tests，分别验证创建、登录、错误密码、限流、恢复码一次性消费和 reset 后旧 token 被拒绝。

### Task 3: 实现 Passkey 与联邦身份绑定

**Files:**
- Create: `v2/services/api/internal/auth/passkey_service.go`
- Create: `v2/services/api/internal/auth/federation_service.go`
- Create: `v2/services/api/internal/auth/federation_service_test.go`
- Create: `v2/services/api/internal/http/binding_handler.go`
- Modify: `v2/contracts/openapi/openapi.yaml`

- [x] **Step 1: 写绑定安全测试**

测试必须拒绝：仅凭新第三方 token 绑定到现有账户；邮箱相同自动合并；解绑最后一种恢复凭证；同一 provider subject 绑定到两个账户。

- [x] **Step 2: 实现 WebAuthn 挑战**

Passkey 注册和 assertion challenge 必须由服务端随机生成、与 session/intent 绑定、单次使用和过期。服务端只存 credential ID、public key、sign counter 和设备元数据。

- [x] **Step 3: 实现提供方 adapter 接口**

固定接口：

```go
type IdentityProvider interface {
    Name() string
    Verify(ctx context.Context, authorizationCode string, nonce string) (VerifiedIdentity, error)
}
```

先交付 Apple、Google、Huawei adapter；微信和 QQ adapter 使用同一接口但在已取得生产开发者资质、回调 URL 和服务端验签材料后启用。任何 adapter 都必须返回 verified `issuer` 与 `subject`，不得返回邮箱作为主键。

- [x] **Step 4: 实现显式绑定流**

`POST /v1/account/bindings/start` 创建 bind intent；`POST /v1/account/bindings/complete` 要求当前 session 的近期重新认证和新凭证验证都通过。未绑定身份首次登录只允许“创建账户”或“登录已有账户后绑定”。

- [ ] **Step 5: 验收**

在 staging 完成：Clovery ID/密码创建 → 绑定 Passkey → 绑定 Apple/Google test identity → 使用任一已绑定方式进入同一 `vault_id` → 撤销一个设备 → 被撤销设备 refresh 失败。

### Task 4: 建立会话、设备与 Vault 授权边界

**Files:**
- Create: `v2/services/api/internal/auth/session_service.go`
- Create: `v2/services/api/internal/vault/service.go`
- Create: `v2/services/api/internal/http/session_handler.go`
- Create: `v2/services/api/internal/http/vault_handler.go`
- Create: `v2/services/api/internal/http/auth_middleware.go`
- Create: `v2/services/api/internal/http/auth_middleware_test.go`

- [x] **Step 1: 写跨账户访问拒绝测试**

测试创建两个账户和两个 Vault，使用账户 A access token 请求 Vault B；必须返回 `403`，且 audit log 记录拒绝但不泄露 Vault B 数据。

- [x] **Step 2: 实现轮换会话**

refresh token 只保存 hash；每次刷新替换 token，旧 token 即失效。设备撤销、密码重置和账户删除请求都将相关 session 标记 `revoked_at`。

- [x] **Step 3: 定义最小 Vault API**

```text
GET  /v1/account
GET  /v1/account/devices
DELETE /v1/account/devices/{deviceId}
GET  /v1/vault
POST /v1/account/deletion-requests
```

每个 handler 从认证 middleware 注入的 `clovery_account_id` 获取 Vault，禁止接收任意 account ID 作为请求参数。

- [ ] **Step 4: W2 验收**

执行 Go integration tests 和 Flutter/Dart API smoke tests；验证自定义 Clovery ID、密码、Passkey、绑定、解绑、设备撤销、恢复码和跨 Vault 拒绝全部通过。部署到 staging 后才允许 W3/W4 使用真实账户 API。
