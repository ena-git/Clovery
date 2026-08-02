# iOS 1.1.0 预发账户继承与权益验收

本文档用于真实 Apple Sandbox、Clovery 预发 API、PostgreSQL 和对象存储环境。脚本只输出场景名称与 `PASS/FAIL`；完整响应、访问令牌、身份认领令牌、日记、哈希和 StoreKit JWS 仅在外部加密证据目录中短暂存在，并在脚本退出时删除。

当前 Git 记录不代表真实预发已执行。没有真实部署、Apple 测试账户和受控交易证据时，所有场景保持 `NOT_RUN`。

## 1. 环境门禁

1. 数据库已按 `ios-1.1.0-database-runbook.md` 升至版本 `17` 并通过基线校验。
2. 部署镜像绑定完整 release SHA，API `/v1/health` 和受保护指标均通过。
3. `IDENTITY_CLAIM_TTL_SECONDS=600`。
4. `MIGRATION_WRITES_ENABLED=true`；数据库迁移窗口内必须先临时改为 `false`。
5. `APPLE_BILLING_BUNDLE_ID=com.clovery.app`。
6. `APPLE_BILLING_PRODUCT_IDS` 包含 `com.clovery.app.board.lifetime`。
7. Apple Sandbox IAP 五项私密凭据完整，`APPLE_IAP_ALLOW_SANDBOX=true`。
8. App Store Connect 的 Server Notifications V2 指向 `https://api.staging.clovery.cn/v1/billing/apple/notifications`。
9. Apple、Google、Huawei OIDC 预发凭据完整，且不使用生产用户账户。

```bash
v2/scripts/staging-preflight.sh /opt/clovery/staging/.env acceptance
```

预检仅证明配置完整，不证明真实身份或交易链路已通过。

## 2. 外部证据目录

```bash
export CLOVERY_API_BASE_URL=https://api.staging.clovery.cn
export SECURE_EVIDENCE_DIR="$HOME/CloveryReleaseEvidence/1.1.0/staging"
install -d -m 700 "$SECURE_EVIDENCE_DIR"
```

所有文件设为 `0600`，目录设为 `0700`。目录不得位于 Clovery Git 仓库中，不得由云盘公开共享。脚本拒绝仓库内路径和符号链接输入。

## 3. 账户继承输入

从测试 iPhone 和预发 Apple OIDC 流程生成一次性请求，保存以下文件路径到环境变量：

| 环境变量 | 外部文件内容 |
| --- | --- |
| `BOUND_APPLE_COMPLETE_REQUEST_FILE` | 已绑定 Apple 用户的 `/complete` JSON |
| `BOUND_APPLE_EXPECTED_ROOT_FILE` | 预发后台确认的原 `account_id`、`vault_id` JSON |
| `UNBOUND_APPLE_COMPLETE_REQUEST_FILE` | 未绑定 Apple 身份的 `/complete` JSON |
| `CLAIM_REGISTRATION_TEMPLATE_FILE` | 不含 claim token、`source_kind=legacy_local/legacy_cloudkit` 的注册 JSON |
| `CLAIM_REPLAY_REGISTRATION_TEMPLATE_FILE` | 不同 Clovery ID、设备 ID、registration request ID 的重放 JSON |
| `PLAIN_REGISTRATION_REQUEST_FILE` | `recovery_method=recovery_codes` 的纯 Clovery 注册 JSON |

`authorization_code`、nonce、密码和预期根账户标识不得写入 Git。Apple code 为一次性值，脚本失败后重新发起登录，不复用过期 code。

## 4. 日记迁移输入

使用当前 iOS exporter 生成三个独立 fixture 目录，并设置：

- `MIGRATION_RETRY_FIXTURE_DIR`
- `MIGRATION_CONTENT_DUPLICATE_FIXTURE_DIR`
- `MIGRATION_ID_CONFLICT_FIXTURE_DIR`

每个目录包含：

```text
create.json       完整迁移创建请求和真实 manifest
entries.ndjson    每行一个受 manifest 约束的 entry 请求
precondition.json 仅 ID 冲突场景需要；先通过 sync push 建立同 ID 不同内容
```

三个 fixture 必须使用不同 migration ID。retry 场景会在 verify 前重复上传同一 entry；content duplicate 包含不同 ID、相同可去重内容；ID conflict 包含与 precondition 同 ID、不同内容的迁移 entry。

## 5. 运行账户与迁移 smoke

```bash
CLOVERY_API_BASE_URL="$CLOVERY_API_BASE_URL" \
SECURE_EVIDENCE_DIR="$SECURE_EVIDENCE_DIR" \
BOUND_APPLE_COMPLETE_REQUEST_FILE="$SECURE_EVIDENCE_DIR/bound-complete.json" \
BOUND_APPLE_EXPECTED_ROOT_FILE="$SECURE_EVIDENCE_DIR/bound-root.json" \
UNBOUND_APPLE_COMPLETE_REQUEST_FILE="$SECURE_EVIDENCE_DIR/unbound-complete.json" \
CLAIM_REGISTRATION_TEMPLATE_FILE="$SECURE_EVIDENCE_DIR/claim-registration.json" \
CLAIM_REPLAY_REGISTRATION_TEMPLATE_FILE="$SECURE_EVIDENCE_DIR/claim-replay.json" \
PLAIN_REGISTRATION_REQUEST_FILE="$SECURE_EVIDENCE_DIR/plain-registration.json" \
MIGRATION_RETRY_FIXTURE_DIR="$SECURE_EVIDENCE_DIR/migration-retry" \
MIGRATION_CONTENT_DUPLICATE_FIXTURE_DIR="$SECURE_EVIDENCE_DIR/migration-content-duplicate" \
MIGRATION_ID_CONFLICT_FIXTURE_DIR="$SECURE_EVIDENCE_DIR/migration-id-conflict" \
v2/scripts/smoke-account-inheritance.sh
```

脚本验证原账户/Vault、一份 Apple binding、一份 bootstrap job、认领幂等与冲突，以及三种日记去重结果。终端不得出现 ID、token、日记 JSON 或响应 body。

## 6. 运行旧权益 smoke

准备同一 Clovery 根账户两台设备的 access token、另一个 Clovery 账户 token，以及未带 app account token 的真实 Sandbox StoreKit 签名交易：

```bash
CLOVERY_API_BASE_URL="$CLOVERY_API_BASE_URL" \
SECURE_EVIDENCE_DIR="$SECURE_EVIDENCE_DIR" \
LEGACY_ENTITLEMENT_PRIMARY_ACCESS_TOKEN_FILE="$SECURE_EVIDENCE_DIR/primary.token" \
LEGACY_ENTITLEMENT_OTHER_ACCESS_TOKEN_FILE="$SECURE_EVIDENCE_DIR/other-account.token" \
LEGACY_ENTITLEMENT_SECOND_DEVICE_ACCESS_TOKEN_FILE="$SECURE_EVIDENCE_DIR/second-device.token" \
LEGACY_APPLE_CLAIM_REQUEST_FILE="$SECURE_EVIDENCE_DIR/legacy-claim.json" \
APPLE_BILLING_PRODUCT_ID=com.clovery.app.board.lifetime \
v2/scripts/smoke-legacy-entitlement.sh
```

脚本验证首次认领激活、同账户重放幂等、其他账户被阻止，以及第二台设备读取相同权益。脚本不会把 JWS 或交易号复制到 Git 证据。

## 7. 故障注入

只在预发逐项执行，每次只阻断一个依赖：

1. 阻断对象存储写入：迁移保持 pending/needs-attention，本地原数据和 bundle 不删除；恢复后 retry 完成。
2. 阻断 Apple 验证：权益不授予错误账户，引导 entitlement stage 可重试；恢复后同一交易只产生一份权益。
3. 阻断数据库写入：不出现半账户、孤立 Vault 或已消费但无账户的 claim；恢复后同一 registration request 回到同一根账户。

禁止在生产环境模拟故障。

## 8. 验收记录

| 场景 | 当前状态 |
| --- | --- |
| bound Apple -> original account/vault | `NOT_RUN` |
| unbound Apple -> 202 claim, no account | `NOT_RUN` |
| claim registration -> one account/vault/binding/job | `NOT_RUN` |
| same request retry -> same account/vault | `NOT_RUN` |
| claim replay with another request -> conflict | `NOT_RUN` |
| plain Clovery registration/login -> bootstrap job | `NOT_RUN` |
| same diary migration twice -> one result | `NOT_RUN` |
| different-ID duplicate -> one result | `NOT_RUN` |
| same-ID conflict -> two preserved entries | `NOT_RUN` |
| legacy transaction first claim -> active entitlement | `NOT_RUN` |
| same-account replay -> same entitlement | `NOT_RUN` |
| other-account claim -> blocked | `NOT_RUN` |
| second device -> same entitlement list | `NOT_RUN` |
| object storage failure/recovery | `NOT_RUN` |
| Apple verification failure/recovery | `NOT_RUN` |
| database write failure/recovery | `NOT_RUN` |

执行后只在 Git 记录 UTC 时间、完整 deployment SHA 的短引用、迁移版本 `17`、操作人和每个场景的聚合状态。测试账户 ID、Vault ID、设备 ID、交易号、JWS、token、日记和图片证据只保存在批准的加密系统中。
