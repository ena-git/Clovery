# Clovery iOS 1.1.0 模拟器 UX 与崩溃矩阵

**验收日期：** 2026-08-01 CST
**验收提交：** `57b830ee5a23`
**候选版本：** `1.1.0 (15)`
**结果：** `PASS — 模拟器范围内无失败、无跳过`

本文件只记录聚合结果，不包含账户、Vault、设备 UDID、日记、照片、交易或完整日志。模拟器证据不能替代真机 Photos、StoreKit Sandbox、TestFlight 或 App Store Connect 验收。

## 权威命令

```bash
CLOVERY_RELEASE_API_BASE_URL=https://api.clovery.cn \
  scripts/verify-ios-1.1.0.sh

CLOVERY_RELEASE_API_BASE_URL=https://api.clovery.cn \
  scripts/verify-ios-1.1.0-simulator-matrix.sh
```

两个命令均在干净提交 `57b830ee5a23` 上退出 `0`。脚本将 DerivedData、XCResult、日志和临时模拟器放在 `/private/tmp`，结束后自动删除。

## 自动化总结果

| 门禁 | 结果 |
| --- | --- |
| Go race 测试与 API 构建 | PASS |
| 预发操作与数据安全契约 | PASS |
| HTML、Bridge、照片与迁移契约 | PASS |
| 发布身份、隐私与仓库卫生 | PASS |
| 全量 XCTest | PASS — `234` 通过、`0` 失败、`0` 跳过 |
| 无签名 Release 模拟器构建 | PASS |

## 屏幕尺寸矩阵

当前开发机只安装 iOS `26.0.1 (23A8464)` 模拟器运行时；未安装 iOS 16 模拟器运行时，因此 iOS 16 兼容性仍需 Task 7 的旧款真机验收。最低部署版本 `16.0` 已由项目身份契约和 Release 构建验证。

| 设备 | 运行时 | 自动 UI 场景 | 结果 |
| --- | --- | ---: | --- |
| iPhone SE（第 3 代） | iOS 26.0.1 | 3 | PASS |
| iPhone 13 mini | iOS 26.0.1 | 3 | PASS |
| iPhone 16 Pro | iOS 26.0.1 | 3 | PASS |
| iPhone 16 Pro Max | iOS 26.0.1 | 3 | PASS |

每台设备都验证全部发布路由无崩溃、最大辅助字号下关键操作可滚动到达，以及账户删除必须输入完整 CloveryID 才能提交。

## 路由与可访问性

在 iPhone 17 Pro、iOS 26.0.1 上，`CloveryUITests` 的 `11/11` 场景通过：

- 中文登录入口、升级公告、Apple/Google 登录、Apple 身份认领、迁移、权益恢复、需要协助、日记、账户安全和删除确认均可渲染且应用保持前台运行。
- 系统辅助功能审计覆盖元素检测、点击区域、元素说明和控件语义；对比度由确定性 WCAG 单元测试验证。
- 默认字号与 `accessibility5` 实际产生不同输入框高度；四种用户可选字体在最大辅助字号和深色系统外观下均可到达主操作。
- `AuthInk` 在认证背景/卡片上达到至少 `7:1`，`AuthPlaceholder` 达到至少 `4.5:1`。
- Reduce Motion 通过真实视图注入点验证，生产环境仍默认读取系统 `accessibilityReduceMotion`。

## 中断与恢复

| 场景 | 结果 |
| --- | --- |
| 身份认领终止后重启 | PASS |
| 迁移、权益、需要协助终止后重启 | PASS |
| 已认证日记终止后重启 | PASS |
| 迁移页后台后回前台 | PASS |
| 离线错误展示后点击重试恢复工作态 | PASS |

Vault 拉取检查点、迁移检查点、离线上传和 API 重试另由 XCTest 单元/集成覆盖。真实断网、低内存终止和跨设备恢复保留给 Task 7 真机门禁。

## P0 照片范围

模拟器自动化保留照片保存成功、权限拒绝、跳转设置恢复、无效图片、重复保存、分享独立性和 JavaScript 回调契约。真实照片权限弹窗、add-only 授权和相册落盘结果必须在 Task 7 真机验证；在此之前不得宣称照片 P0 已完成发布验收。

## 自审结论

- Debug 验收夹具由 `#if DEBUG` 包围，Release 构建不包含用户可选择的测试路由。
- UI 测试目标使用 `com.clovery.app.UITests`，宿主为 `Clovery`，未声明生产 entitlements。
- 最大字号下允许滚动，不以压缩正文或缩小文字规避可访问性要求。
- 所有自动化脚本拒绝非生产发布 API 覆盖，并在退出时清理临时设备和构建产物。
- 未发现开放的模拟器范围 P0/P1；外部真机和商店门禁仍为发布阻断项。
