# Clovery 下载、运行与验证

## 1. 获取代码

推荐克隆当前完整开发分支：

```bash
git clone --branch release/ios-1.1.0 --single-branch https://github.com/ena-git/Clovery.git
cd Clovery
```

不使用 Git 时可下载：<https://github.com/ena-git/Clovery/archive/refs/heads/release/ios-1.1.0.zip>

## 2. 开发依赖

| 范围 | 依赖 |
| --- | --- |
| 原生 iOS | macOS、Xcode 26.0.1 推荐、可用 iPhone Simulator；最低运行版本 iOS 16.0 |
| WebView 离线资源 | Node.js 22 |
| 后端 | Go 1.26.5 |
| 本地基础设施 | Docker Desktop、Docker Compose |
| 跨端基础工程 | Flutter 与 Dart；只有运行 `v2/apps/mobile` 时需要 |

Xcode、Swift、Go、Node 或 Flutter 大版本变化后，应重新执行完整门禁，不要直接假设兼容。

## 3. 启动本地后端

### 3.1 启动 PostgreSQL 与 MinIO

```bash
cd v2
docker compose -f infra/compose.yaml up -d
docker compose -f infra/compose.yaml ps
```

Compose 使用仅限本机开发的账户，并自动创建私有 `clovery-dev` 对象桶。不得将这些密码用于预发或生产。

### 3.2 注入开发环境变量并迁移数据库

```bash
cd services/api
set -a
. ./.env.example
set +a
MIGRATIONS_PATH=./migrations go run ./cmd/migrate up
```

API 不会自动读取 `.env`，也不会在启动时自动执行数据库迁移；必须先在当前终端导出环境变量并执行迁移命令。

### 3.3 启动 API

```bash
go run ./cmd/api
```

另开终端检查：

```bash
curl http://127.0.0.1:8080/v1/health
```

Debug iOS 配置默认访问 `http://127.0.0.1:8080`。Release 配置固定读取 `CLOVERY_RELEASE_API_BASE_URL`，不能为了本地调试修改成明文 HTTP。

## 4. 启动原生 iOS

1. 保持本地 API 运行；
2. 执行 `open Clovery.xcodeproj`；
3. 选择 `Clovery` Scheme 和目标 iPhone Simulator；
4. 在 Xcode 中点击 Run；
5. 首次注册使用自定义 Clovery ID 和 8 位以上非弱密码。

如果只检查无后端首页，登录、注册、恢复、同步和权益流程会按设计失败；这不是前端页面故障。

## 5. 运行 Flutter 基础工程

Flutter 目前用于跨端基础和契约验证，不是本次 App Store 升级版入口：

```bash
cd v2/apps/mobile
flutter pub get --enforce-lockfile
flutter analyze
flutter test
```

原生 iOS 外部发布门禁未关闭前，不应把 Flutter 构建替换为线上 iOS 客户端。

## 6. 验证命令

### 原生 iOS 发布候选

```bash
CLOVERY_RELEASE_API_BASE_URL=https://api.clovery.cn scripts/verify-ios-1.1.0.sh
```

覆盖 Go race/build、接口与发布脚本、Swift XCTest、隐私/身份/仓库卫生检查和无签名 Release 构建。

### Go 与 Flutter 平台基础

```bash
cd v2
make verify
```

### 单独验证基础设施

```bash
cd v2
docker compose -f infra/compose.yaml config --quiet
```

## 7. 停止本地服务

```bash
cd v2
docker compose -f infra/compose.yaml down
```

不要执行 `down -v`，除非明确要删除本地 PostgreSQL 和 MinIO 数据卷。

## 8. 常见问题

| 现象 | 检查项 |
| --- | --- |
| 注册或登录失败 | API 是否运行、`/v1/health` 是否成功、数据库迁移是否执行 |
| 图片上传失败 | `minio-init` 是否完成、`clovery-dev` 桶是否存在、S3 环境变量是否一致 |
| 模拟器访问不到 API | 确认使用 Debug 配置且端口 `8080` 未被占用 |
| Release 指向本地地址 | 立即停止发布，检查 `Config/Release.xcconfig` 和构建注入参数 |
| 恢复购买未解锁 | 必须检查 StoreKit 环境、后端交易验证和根账户权益，不得手工改客户端状态 |
| 旧用户出现认领页 | 只有检测到旧数据或已验证旧身份时才应进入；新注册用户应直接进入空 Vault |
