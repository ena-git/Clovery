# iOS 1.1.0 数据库升级手册

本手册用于把 Clovery 后端从迁移版本 `15` 升级到 `17`。`000016` 增加身份认领和账户引导状态，`000017` 增加日记迁移去重决策字段。所有操作先在隔离恢复库演练，再进入生产变更窗口。

## 发布前提

- 发布提交、API 镜像摘要和迁移二进制来自同一份已审核源码。
- 源数据库的 `schema_migrations` 为 `15|false`，且没有未完成迁移。
- 备份目录、恢复数据库和证据目录位于 Git 仓库之外，权限为 `0700`。
- PostgreSQL、对象存储和 API 已停止结构性变更；发布期间不执行人工数据修复。
- `MIGRATION_WRITES_ENABLED=false`，旧版客户端仍可读取原账户、Vault、日记和权益。
- 操作人员具备快照、`pg_dump`、`pg_restore` 和部署旧 API 镜像的权限。

任何一项不满足时停止发布，不通过删除数据、重建数据库或跳过备份继续。

## 1. 记录不可变发布信息

在受控发布系统中记录完整提交 SHA、镜像 digest、数据库实例、执行人和 UTC 时间。Git 仅保留汇总状态，不记录数据库 URL、账户标识、交易号或日记内容。

```bash
export RELEASE_SHA='<full-commit-sha>'
export SECURE_EVIDENCE_DIR="$HOME/CloveryReleaseEvidence/1.1.0/database"
install -d -m 700 "$SECURE_EVIDENCE_DIR"
```

## 2. 创建升级前备份

先创建云数据库受保护快照，再生成可恢复的 custom-format 逻辑备份：

```bash
v2/scripts/backup-before-account-bootstrap.sh \
  "$STAGING_DATABASE_URL" \
  "$SECURE_EVIDENCE_DIR"
```

脚本会：

- 拒绝 Git 仓库内路径和已有同名证据；
- 要求数据库处于干净的迁移版本 `15`；
- 使用 `pg_dump --format=custom --no-owner --no-privileges`；
- 生成 `clovery-before-1.1.0.dump`、SHA-256 和权限为 `0600` 的元数据；
- 记录 PostgreSQL 服务版本、迁移版本及账户、Vault、权益基线数量；
- 不写入数据库 URL、密码、用户标识或业务内容。

用部署环境批准的 KMS、加密备份服务或离线加密介质加密并上传这三个文件。密钥、上传地址和访问令牌只存在于密钥管理系统，不进入 Git 或终端日志。

## 3. 恢复到第二数据库

恢复目标必须是独立的临时数据库，不能复用源库名称或连接：

```bash
createdb clovery_restore_rehearsal
pg_restore --exit-on-error --clean --if-exists --no-owner --no-privileges \
  --dbname "$RESTORE_DATABASE_URL" \
  "$SECURE_EVIDENCE_DIR/clovery-before-1.1.0.dump"
```

校验 dump SHA-256 与备份元数据一致，并确认恢复库为迁移版本 `15`。恢复失败、关系数量不一致或抽样外键断裂时，备份不合格，禁止进入下一步。

## 4. 在恢复库执行升级

```bash
cd v2/services/api
DATABASE_URL="$RESTORE_DATABASE_URL" \
MIGRATIONS_PATH=./migrations \
go run ./cmd/migrate up

cd ../../..
v2/scripts/verify-account-bootstrap-migrations.sh \
  "$RESTORE_DATABASE_URL" \
  "$SECURE_EVIDENCE_DIR/clovery-before-1.1.0.metadata.env"
```

验证脚本仅在以下条件全部成立时输出 `PASS`：

- schema 精确为版本 `17` 且非 dirty；
- `identity_claims` 仅保存令牌 SHA-256，不存在原始令牌列；
- 一个账户只能对应一个引导作业和一个 Vault；
- 迁移决策约束和日记去重索引完整；
- 账户、Vault、权益数量与版本 `15` 基线一致；
- 不存在孤立的外部身份或 Vault。

## 5. 执行数据库测试

```bash
cd v2/services/api
DATABASE_URL="$RESTORE_DATABASE_URL" \
GOCACHE=/private/tmp/clovery-go-build \
go test -count=1 ./internal/database ./internal/identityclaim ./internal/migration ./internal/billing
```

随后运行 `go test -race ./...` 和 API 构建门禁。任何失败都先修复并重新从备份恢复演练，不能在生产库上试错。

## 6. 演练非破坏回滚

先按照 [iOS 1.1.0 回滚手册](ios-1.1.0-rollback-runbook.md) 部署上一版 API，同时保留数据库版本 `17` 并保持 `MIGRATION_WRITES_ENABLED=false`。确认旧 API 的健康检查、登录读取、Vault 读取和权益读取正常。

只有在可丢弃的恢复库中，才可演练 SQL 降级：

```bash
cd v2/services/api
DATABASE_URL="$RESTORE_DATABASE_URL" MIGRATIONS_PATH=./migrations go run ./cmd/migrate down
DATABASE_URL="$RESTORE_DATABASE_URL" MIGRATIONS_PATH=./migrations go run ./cmd/migrate down
DATABASE_URL="$RESTORE_DATABASE_URL" MIGRATIONS_PATH=./migrations go run ./cmd/migrate up
```

生产回滚的首选方案永远是旧 API + 保留 additive schema，不是执行 down migration。

## 7. 生产升级顺序

1. 冻结写入并设置 `MIGRATION_WRITES_ENABLED=false`。
2. 确认受保护快照、逻辑备份、SHA-256 和恢复演练均为 `PASS`。
3. 对生产库执行一次迁移 `up`。
4. 使用本手册的验证脚本校验生产库与版本 `15` 基线。
5. 部署固定 digest 的新 API，验证健康检查和受保护指标。
6. 完成账户继承、权益和迁移 smoke 后再设置 `MIGRATION_WRITES_ENABLED=true`。
7. 观察错误率、引导作业积压、权益验证失败和数据库延迟；达到阈值立即按回滚手册处理。

## 8. Git 内验收记录

| 项目 | 状态 | 允许记录的证据 |
| --- | --- | --- |
| 本地迁移往返测试 | 自动化测试结果 | `PASS/FAIL`、提交短 SHA |
| 预发备份及恢复 | `NOT_RUN` 直到真实执行 | 时间、操作人、聚合 `PASS/FAIL` |
| 生产受保护快照 | `NOT_RUN` 直到发布窗口 | 快照内部编号的脱敏引用 |
| 生产迁移与校验 | `NOT_RUN` 直到发布窗口 | 版本号 `17`、聚合 `PASS/FAIL` |

完整 dump、元数据、数据库地址和恢复证据仅保存在批准的加密证据库中。
