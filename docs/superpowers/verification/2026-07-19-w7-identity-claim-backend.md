# W7 Identity Claim Backend 验收记录

- 验收分支：`codex/swift-auth-foundation`
- 验收提交：`9b45ccd` (`feat(account): add resumable bootstrap state`)
- 远程备份：`origin/codex/swift-auth-foundation` 已推送
- 数据库环境：本机 PostgreSQL 16，使用测试临时 schema；Docker PostgreSQL 不作为本次前置条件

## 迁移与回滚

命令：

```bash
DATABASE_URL='postgres://huao@localhost:5432/postgres?sslmode=disable' \
GOCACHE=/private/tmp/clovery-go-build \
go test -v ./internal/database -run \
'TestMigrationsSupportRepeatableDeploymentAndRollback|TestIdentityClaimBootstrapMigrationEnforcesDatabaseContract' -count=1
```

结果：`PASS`。

- 临时 schema 创建并应用全部迁移成功；重复执行 `up` 保留探针数据。
- 最新迁移 `down` 成功，探针数据保持；随后重新 `up` 成功，表恢复。
- `identity_claims`、`account_bootstrap_jobs`、Vault 所有权、迁移归属及状态约束测试全部通过。

## 身份声明

命令：

```bash
DATABASE_URL='postgres://huao@localhost:5432/postgres?sslmode=disable' \
GOCACHE=/private/tmp/clovery-go-build \
go test -v ./internal/identityclaim -run TestPostgresIdentityClaims -count=1
```

结果：`PASS`。

- 已绑定身份：`TestFederatedLoginCompleteReturnsRootAccountSession` 返回 200 会话。
- 未绑定身份：`TestFederatedLoginCompleteReturnsAcceptedIdentityClaim` 返回 202 声明响应。
- 数据库只存 SHA-256 摘要，`stores_digest_without_raw_token` 通过；未知 token 错误不包含原 token。
- 同一请求重放和不同请求重放的行锁测试均通过；不同请求被稳定拒绝。
- 令牌跨 HTTP、应用和账户参数的格式化、JSON、日志值均为 `<redacted>`，没有新增日志记录原始声明令牌。

## 声明账户注册

命令：

```bash
TEST_DATABASE_URL='postgres://huao@localhost:5432/postgres?sslmode=disable' \
GOCACHE=/private/tmp/clovery-go-build \
go test -v ./internal/account -run \
'TestCreateClaimedAccount(CommitsEveryRequiredRow|ReplaysSameRegistrationRequest|ConcurrentDuplicateIdentityCommitsOneGraph)' -count=1
```

结果：`PASS`。

- 成功注册行数各为 1：账户、Vault、Clovery ID、密码凭证、外部身份、bootstrap job、已消费 claim。
- 同 token + 同 request ID 返回原账户/Vault，不新增账户图。
- 同 token + 不同 request ID 返回 `ErrConsumedClaim`。
- 相同外部身份并发注册只有一个账户图成功，另一请求回滚且 claim 保持未消费。
- Clovery ID 冲突保留通用 `login_id_unavailable` 语义。

## Bootstrap 状态

命令：

```bash
TEST_DATABASE_URL='postgres://huao@localhost:5432/postgres?sslmode=disable' \
GOCACHE=/private/tmp/clovery-go-build \
go test -race ./internal/bootstrapjob ./internal/http ./cmd/api ./internal/contract
```

结果：`PASS`。

- `pending -> running -> complete` 只在四阶段全部完成时结束。
- 阶段失败进入 `needs_attention`，错误码满足稳定格式；resume 清理错误、增加 retry_count，并保留已完成阶段和 migration_id。
- 旧账户无 job 时按 `source_kind` 创建兼容 job；`new_install` 的 migration 已完成，旧数据来源保持 pending。
- 已有 job 忽略冲突 source kind，但拒绝冲突 Vault；同一账户并发 resume 只创建一个 job。
- GET/POST 均使用认证上下文的账户和 Vault，不接受客户端 account/vault 字段；跨账户读取或修改返回安全错误。
- 未认证访问两个 bootstrap 路由均返回 401。
- OpenAPI 已覆盖 GET 404、resume 400/401/409 和嵌套四阶段状态结构。

## 全量质量门禁

命令：

```bash
TEST_DATABASE_URL='postgres://huao@localhost:5432/postgres?sslmode=disable' \
GOCACHE=/private/tmp/clovery-go-build \
go test ./...

GOCACHE=/private/tmp/clovery-go-build go build ./cmd/api
git diff --check
```

结果：

- `go test ./...`：`PASS`，所有 Go 包通过。
- `go build ./cmd/api`：退出码 0。
- `git diff --check`：无输出。
- 构建生成的本地二进制已清理，工作树保持干净。
