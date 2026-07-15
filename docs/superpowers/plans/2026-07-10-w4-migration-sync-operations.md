# W4：迁移、同步与运营 Beta 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 W1 的旧数据安全导入 W2 Vault，并让 W3 的 Flutter 本地库完成可靠同步、冲突处理、删除传播、权益恢复和运营可观测性。

**Architecture:** 服务端使用 journal revision、全局 `change_cursor` 与删除墓碑维护 Vault 变更流；Dart SyncEngine 将 Drift 的 `sync_operations` 幂等上传、分页拉取并事务性应用。迁移始终复制数据并返回可审计报告；支付权益以服务端账本为准。

**Tech Stack:** Go、PostgreSQL、S3 兼容对象存储、Dart/Drift、Dio、StoreKit 2、WidgetKit、OpenTelemetry、结构化日志。

---

### Task 1: 实现版本化日记与同步 API

**Files:**
- Create: `v2/services/api/migrations/0002_journal_sync.sql`
- Create: `v2/services/api/internal/journal/service.go`
- Create: `v2/services/api/internal/sync/service.go`
- Create: `v2/services/api/internal/http/sync_handler.go`
- Create: `v2/services/api/internal/sync/service_test.go`
- Modify: `v2/contracts/openapi/openapi.yaml`

- [x] **Step 1: 写同步一致性测试**

测试必须覆盖：同一 `operation_id` 重放不重复创建记录；拉取超过一页时返回连续 cursor；删除产生 tombstone；旧 `base_revision` 的修改返回冲突快照而不静默覆盖。

- [x] **Step 2: 创建同步表**

迁移至少创建：

```sql
journal_entries(id uuid, vault_id uuid, revision bigint, payload jsonb,
                deleted_at timestamptz, primary key(id, vault_id));
sync_changes(cursor bigint primary key, vault_id uuid, entity_type text,
             entity_id uuid, revision bigint, operation_id uuid unique, payload jsonb);
journal_conflicts(id uuid primary key, vault_id uuid, entry_id uuid,
                  client_payload jsonb, server_payload jsonb, created_at timestamptz);
```

- [x] **Step 3: 定义 API 契约**

```text
POST /v1/vault/sync/push
GET  /v1/vault/sync/pull?cursor={cursor}&limit={limit}
POST /v1/vault/assets/uploads
POST /v1/vault/assets/{assetId}/complete
GET  /v1/vault/assets/{assetId}/download
```

`push` 请求必须携带 `operation_id`、`base_revision`、实体 payload 和删除标记。服务端从 session 推导 Vault，不接受客户端提供的可任意替换 Vault ID。

- [x] **Step 4: 验证分页与冲突**

使用两个测试账户设备并发创建、编辑和删除；确认分页完整、冲突表有记录、被删除条目不会在另一设备复活。

验收证据：`pagination_conflict_integration_test.go` 在隔离 PostgreSQL 16 中验证跨 Vault cursor 间隔下的两页完整拉取、陈旧 revision 冲突落库、墓碑后普通编辑继续返回冲突，以及另一 Vault 的变更不可见。

### Task 2: 实现 Dart SyncEngine 与冲突 UI

**Files:**
- Create: `v2/apps/mobile/lib/features/sync/data/sync_api_client.dart`
- Create: `v2/apps/mobile/lib/features/sync/domain/sync_engine.dart`
- Create: `v2/apps/mobile/lib/features/sync/domain/conflict_resolver.dart`
- Create: `v2/apps/mobile/lib/features/sync/presentation/conflict_screen.dart`
- Create: `v2/apps/mobile/test/features/sync/sync_engine_test.dart`
- Create: `v2/apps/mobile/integration_test/two_device_sync_test.dart`

- [ ] **Step 1: 写 SyncEngine 测试**

测试固定场景：离线创建后恢复网络；push 超时重试相同 operation ID；pull 两页；远端删除；同一 entry 双设备编辑。每个场景都验证 Drift 最终记录、sync operation 状态和 cursor。

- [ ] **Step 2: 实现有序同步状态机**

状态机顺序固定为：获取 refresh token → push pending operations → pull remote changes 直到无 next cursor → 应用冲突/墓碑 → 刷新 Widget 快照。任一步失败保留可重试 operation，不得删除本地正文或照片。

- [ ] **Step 3: 实现冲突界面**

冲突页展示本地与服务器版本的时间、正文、标签和照片差异。用户只能选择“保留本地副本”“采用云端版本”“另存为新日记”；所有选择产生新的同步 operation。

- [ ] **Step 4: W4 同步验收**

两台真机在飞行模式下修改同一日记后分别上线；验证没有静默覆盖、删除同步、图片完整、冲突可解决且最终两端 cursor 一致。

### Task 3: 导入 V1 Migration Bundle 与旧 CloudKit 数据

**Files:**
- Create: `v2/services/api/internal/migration/service.go`
- Create: `v2/services/api/internal/http/migration_handler.go`
- Create: `v2/services/api/internal/migration/service_test.go`
- Create: `v2/apps/mobile/lib/features/migration/data/migration_repository.dart`
- Create: `v2/apps/mobile/lib/features/migration/presentation/migration_screen.dart`
- Create: `v2/apps/mobile/integration_test/migration_bundle_test.dart`
- Modify: `v2/contracts/openapi/openapi.yaml`

- [x] **Step 1: 写 Bundle 校验失败测试**

测试必须拒绝：未知 `format_version`、条目数不匹配、丢失照片、错误 SHA-256、同一 `migration_id` 内容不同、跨账户导入。测试必须证明失败不会修改目标 Vault。

- [x] **Step 2: 定义迁移 API**

```text
POST /v1/vault/migrations
POST /v1/vault/migrations/{migrationId}/entries
POST /v1/vault/migrations/{migrationId}/assets
POST /v1/vault/migrations/{migrationId}/verify
GET  /v1/vault/migrations/{migrationId}/report
```

每个 API 必须以 `migration_id` 幂等；服务端记录 source、条目数、照片数、字节数、错误和校验摘要。

- [ ] **Step 3: 实现 Flutter 导入向导**

向导顺序固定为：选择 V1 导出 ZIP → 本地验证 manifest → 登录目标 Clovery 账户 → 上传/重试 → 服务端校验 → 显示条目/照片报告 → 用户确认。确认前不得删除 ZIP 或 V1 数据。

- [ ] **Step 4: 处理旧 CloudKit 限制**

在 iOS 迁移页显示：只有同一 Apple 账号、旧容器能力仍可用的设备才能读取旧私有 CloudKit 数据。读取成功后将其作为 Bundle source 上传；读取失败时提供本地 Bundle 导入，不伪造“云端已迁移”。

- [ ] **Step 5: 迁移验收**

使用 W1 导出的真实样本，验证 V2 报告的条目数、照片数、删除状态和随机三条内容与 V1 一致；重复导入只返回已有结果，不重复创建日记。

### Task 4: 建立服务端权益账本与 iOS Widget 快照

**Files:**
- Create: `v2/services/api/migrations/0003_entitlements.sql`
- Create: `v2/services/api/internal/billing/service.go`
- Create: `v2/services/api/internal/http/billing_handler.go`
- Create: `v2/apps/mobile/lib/features/billing/billing_repository.dart`
- Create: `v2/apps/mobile/ios/Runner/CloveryWidgetSnapshotBridge.swift`
- Create: `v2/apps/mobile/test/features/billing/billing_repository_test.dart`

- [x] **Step 1: 写权益归属测试**

测试验证一笔验证通过的 StoreKit transaction 只授予关联 `clovery_account_id`；同 transaction 重放幂等；恢复购买在新设备登录同账户后得到同一 entitlement；取消/失败不授予权益。

- [x] **Step 2: 服务端记录交易与权益**

`store_transactions` 对 `storefront + transaction_id` 建唯一约束，`entitlements` 对 `account_id + product_id` 保存状态和失效时间。客户端购买结果只能触发服务端验证，不直接写本地“已购买”。

- [ ] **Step 3: 生成 Widget 快照**

SyncEngine 每次本地 journal transaction 成功后调用 Pigeon，将最小 Widget JSON 写入 iOS App Group；Swift WidgetKit extension 只读取该 JSON。快写 deep link 使用 Clovery ID/Vault 已认证状态进入 Flutter 编辑器。

- [ ] **Step 4: 验收**

购买、恢复购买、换设备登录和无网络显示均以服务端 entitlement 为准；Widget 在新增/删除日记后刷新，不读取 WebView 或 CloudKit。

### Task 5: 建立 Beta 观测、回滚与发布操作

**Files:**
- Create: `v2/services/api/internal/observability/metrics.go`
- Create: `v2/infra/dashboards/beta-migration.json`
- Create: `v2/docs/runbooks/migration-rollback.md`
- Create: `v2/docs/runbooks/account-recovery.md`
- Create: `v2/docs/runbooks/sync-incident.md`

- [x] **Step 1: 记录无敏感内容的指标**

必须采集：迁移开始/完成/失败、校验差异、同步积压、冲突、认证/绑定失败、设备撤销、支付恢复。指标不得包含日记正文、图片 URL、密码、token、邮箱或 Clovery ID。

- [x] **Step 2: 写可执行回滚手册**

每份手册必须包含触发条件、负责人、停止迁移开关、保护现有 V1 数据、恢复 staging/production 数据库备份、用户沟通模板和事后审计步骤。

- [ ] **Step 3: W4 验收**

完成至少一轮受控 TestFlight Beta：迁移、离线同步冲突、支付恢复、设备撤销和回滚演练均有记录。通过后才允许提交 iOS 正式版。
