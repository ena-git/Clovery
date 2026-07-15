# W0：平台基础与契约实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 建立可重复运行的 V2 Flutter、Go、PostgreSQL、MinIO、OpenAPI、商店升级身份和数据库迁移基础，使后续工作流在稳定契约上独立交付。

**Architecture:** 在 `v2/` 内建立移动端、服务端、契约和基础设施目录。Go 服务以模块化单体启动，先只提供健康检查和受版本控制的 API 文档；移动端先只验证 Flutter 启动、依赖注入和 generated API client，不实现业务功能。`openapi.yaml` 仅为本地版本控制的接口契约，不依赖 OpenAI 或其他外部 AI 服务。

**Tech Stack:** Flutter、Dart、Go、Chi、PostgreSQL、MinIO、Docker Compose、OpenAPI、Pigeon、GitHub Actions 或等价 CI。

---

### Task 1: 建立独立 V2 仓库结构

**Files:**
- Create: `v2/README.md`
- Create: `v2/apps/mobile/`
- Create: `v2/services/api/`
- Create: `v2/contracts/openapi/`
- Create: `v2/infra/compose.yaml`
- Create: `v2/.env.example`

- [x] **Step 1: 初始化 Flutter 与 Go 项目**

Run:

```bash
mkdir -p v2/apps v2/services v2/contracts/openapi v2/infra
flutter create --org com.clovery --platforms ios,android v2/apps/mobile
mkdir -p v2/services/api/cmd/api v2/services/api/internal/http
cd v2/services/api && go mod init github.com/clovery/clovery/services/api
```

Expected: Flutter 项目含 `ios/`、`android/`、`lib/`；Go 模块含 `go.mod`。

- [x] **Step 2: 写入目录职责文档**

`v2/README.md` 必须列出：

```text
apps/mobile       Flutter UI、Drift 本地库、同步器
services/api      Clovery 后端 API 与迁移任务
contracts/openapi HTTP 契约的唯一来源
infra             本地依赖和部署配置
```

- [x] **Step 3: 验证空项目可编译**

Run:

```bash
cd v2/apps/mobile && flutter analyze
cd ../../services/api && go test ./...
```

Expected: 两个命令成功，且没有业务代码。

### Task 2: 启动本地基础设施

**Files:**
- Create: `v2/infra/compose.yaml`
- Create: `v2/services/api/.env.example`
- Create: `v2/services/api/internal/config/config.go`

- [x] **Step 1: 定义开发服务**

`v2/infra/compose.yaml` 必须启动：

```yaml
services:
  postgres:
    image: postgres:17
    environment:
      POSTGRES_DB: clovery
      POSTGRES_USER: clovery
      POSTGRES_PASSWORD: clovery_dev_only
  minio:
    image: minio/minio
    command: server /data --console-address ":9001"
    environment:
      MINIO_ROOT_USER: clovery_minio
      MINIO_ROOT_PASSWORD: clovery_dev_only
```

- [x] **Step 2: 实现显式配置加载**

`config.go` 只从环境变量读取 `DATABASE_URL`、`S3_ENDPOINT`、`S3_BUCKET`、`JWT_ISSUER` 和 `PORT`；缺少任何生产必需变量时进程拒绝启动。不得提供生产默认密钥。

- [x] **Step 3: 验证依赖可用**

Run:

```bash
cd v2/infra
docker compose up -d
docker compose ps
```

Expected: `postgres` 与 `minio` 为 running；使用临时开发凭据不能用于生产。

### Task 3: 建立 API 契约与健康检查

**Files:**
- Create: `v2/contracts/openapi/openapi.yaml`
- Create: `v2/services/api/cmd/api/main.go`
- Create: `v2/services/api/internal/http/router.go`
- Create: `v2/services/api/internal/http/health_handler.go`
- Create: `v2/services/api/internal/http/health_handler_test.go`

- [x] **Step 1: 写健康检查失败测试**

测试必须验证 `GET /v1/health` 返回 `200` 和：

```json
{"status":"ok","service":"clovery-api"}
```

- [x] **Step 2: 在 OpenAPI 定义健康检查**

`openapi.yaml` 必须声明 `/v1/health`、JSON response schema 和 `info.version: 0.1.0`。后续公开 endpoint 只能先加到此文件。

- [x] **Step 3: 实现最小 Chi 路由**

`router.go` 仅注册 `/v1/health`；`main.go` 从配置读取端口后启动 HTTP server，并在 shutdown 时处理 `SIGTERM`。

- [x] **Step 4: 验证契约与服务**

Run:

```bash
cd v2/services/api && go test ./...
go run ./cmd/api &
curl -s http://localhost:8080/v1/health
```

Expected: 测试通过，curl 输出指定 JSON。

### Task 4: 建立 Flutter 应用壳与生成接口边界

**Files:**
- Modify: `v2/apps/mobile/pubspec.yaml`
- Create: `v2/apps/mobile/lib/main.dart`
- Create: `v2/apps/mobile/lib/app.dart`
- Create: `v2/apps/mobile/lib/core/config/app_config.dart`
- Create: `v2/apps/mobile/lib/core/platform/clovery_platform.dart`
- Create: `v2/apps/mobile/pigeons/clovery_platform.dart`
- Create: `v2/apps/mobile/test/app_test.dart`

- [x] **Step 1: 写 Flutter 壳测试**

测试必须 pump `CloveryApp` 并验证应用展示 `Clovery` 与 `Initializing secure vault…`，且不进行网络请求。

- [x] **Step 2: 添加运行时依赖**

`pubspec.yaml` 固定加入 `flutter_riverpod`、`drift`、`sqlite3` 3.x 原生资产、`dio`、`go_router`、`pigeon`、`freezed_annotation` 和各自兼容的开发依赖。依赖版本写入 lockfile，不使用浮动版本范围；不再引入已停止维护的 `sqlite3_flutter_libs`。

- [x] **Step 3: 定义 Pigeon 接口而非任意通道**

`pigeons/clovery_platform.dart` 初始只声明 `getPlatformVersion()` 和 `writeWidgetSnapshot(String json)`；Dart 不得直接创建 `MethodChannel`。

- [x] **Step 4: 验证 Flutter 壳**

Run:

```bash
cd v2/apps/mobile
dart run pigeon --input pigeons/clovery_platform.dart
flutter test
flutter analyze
```

Expected: 生成 Swift/Kotlin/Dart bindings，测试和静态分析通过。

### Task 5: 建立 CI 与交付门槛

**Files:**
- Create: `.github/workflows/verify.yml`
- Create: `v2/services/api/Dockerfile`
- Create: `v2/Makefile`

- [x] **Step 1: 统一验证命令**

`Makefile` 提供 `verify-api`、`verify-mobile`、`verify-contract` 和 `verify`；分别运行 Go 测试、Flutter 分析与测试、OpenAPI 校验。

- [x] **Step 2: 配置 CI**

CI 在每个 pull request 运行验证，并将 Flutter、Go/OpenAPI/迁移、发布身份验证作为独立必需检查。Workflow 必须位于 Git 根目录 `.github/workflows/`，否则 GitHub 不会加载。

### Task 6: 锁定商店升级身份与数据库迁移纪律

**Files:**
- Create: `docs/release/store-identifiers.md`
- Create: `v2/scripts/verify-release-identities.sh`
- Create: `v2/apps/mobile/ios/Runner/Runner.entitlements`
- Modify: `v2/apps/mobile/ios/Runner.xcodeproj/project.pbxproj`
- Create: `v2/services/api/migrations/000001_system_metadata.up.sql`
- Create: `v2/services/api/migrations/000001_system_metadata.down.sql`
- Create: `v2/services/api/cmd/migrate/main.go`
- Create: `v2/services/api/internal/database/migrate.go`
- Create: `v2/services/api/internal/database/migrate_test.go`

- [x] **Step 1: 记录商店身份策略**

记录 iOS 主应用 `com.clovery.app`、Widget `com.clovery.app.CloveryWidget`、Team `M92TBSSR2R`、iCloud Container `iCloud.com.clovery.app` 和 App Group `group.com.clovery.app`。Android、Huawei AppGallery 及其他平台尚未上架，首次发布统一使用 `com.clovery.app` 包名，并要求在上架前生成、离线备份各平台长期发布签名和恢复材料。

- [x] **Step 2: 让 Flutter iOS 工程继承旧应用身份**

Runner 的 Debug/Profile/Release 全部使用 `com.clovery.app` 和 Team `M92TBSSR2R`；entitlements 保留 Push、CloudKit、iCloud KVS、Sign in with Apple 与 App Group，使 V2 能作为现有应用升级并读取迁移期旧数据。

- [x] **Step 3: 添加发布身份检查**

`verify-release-identities.sh` 检查 iOS 工程、entitlements 和 Android 工程的全部已确认值，并拒绝 `com.clovery.mobile`。W5 接入 Harmony 时扩展同一脚本检查其 `com.clovery.app` 应用标识；各平台 release 流程必须检查发布签名证书摘要。

- [x] **Step 4: 写数据库迁移失败测试**

集成测试必须验证空 PostgreSQL 数据库可执行 `up`，重复执行不破坏数据，`down` 后可再次 `up`。缺少 `DATABASE_URL` 时测试明确 skip，本地和 CI 验收必须传入测试数据库 URL。

- [x] **Step 5: 实现显式迁移命令**

使用固定在 `go.mod`/`go.sum` 的迁移库实现独立 `cmd/migrate`；API 进程不自动执行迁移。SQL 文件按递增编号执行，生产部署先运行迁移 Job，成功后才启动新 API 版本。

- [x] **Step 6: 验证身份和迁移**

Run:

```bash
cd v2 && ./scripts/verify-release-identities.sh
cd services/api && DATABASE_URL='postgres://clovery:clovery_dev_only@localhost:5432/clovery?sslmode=disable' go test ./internal/database
```

Expected: iOS 升级身份全部匹配；迁移完成 up/down/up 验证且不会依赖手工导入。

### Task 7: W0 总体验收

- [x] **Step 1: 运行完整验收**

Run:

```bash
cd v2/infra && docker compose up -d
cd .. && make verify
```

Expected: 基础服务、Go 健康 API、Flutter 壳和全部验证均通过；W1/W2/W3 才可开始。
