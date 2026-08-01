# Clovery iOS 1.1.0 生产发布清单

**执行状态：** `NOT_RUN`

本清单只用于外部验收全部通过后的生产窗口。当前不得创建 `ios-v1.1.0` 标签、公开 GitHub Release 或向 App Store 提交审核。

## 发布前置

| 门禁 | 结果 |
| --- | --- |
| 自动化与四尺寸模拟器矩阵 | PASS |
| 法律文本与客服邮箱人工确认 | NOT_RUN |
| 真实预发数据库、账户、迁移与权益 smoke | NOT_RUN |
| 两台真机升级、Photos 与跨设备继承 | NOT_RUN |
| Sandbox、签名归档与 TestFlight | NOT_RUN |
| App Store Connect 商品和隐私元数据 | NOT_RUN |
| 无开放 P0/P1 | NOT_RUN |

任一 NOT_RUN、FAIL 或开放 P0/P1 都禁止进入生产变更。

## 代码合并

1. 从 `codex/swift-auth-foundation` 创建非草稿 PR。
2. 确认分支与受保护发布分支同步，CI 使用 `scripts/verify-ios-1.1.0.sh` 且通过。
3. 审查 W7–W10 脱敏证据、迁移、法律页面、源代码和脚本；不提交构建产物或凭据。
4. 获得代码审查和发布批准后合并，不重写已发布历史。

## 后端先行

1. 执行生产受保护快照和自定义格式逻辑备份，校验 SHA-256 与恢复元数据。
2. 暂停迁移写入，应用 additive migrations `000016`、`000017`。
3. 运行数据库结构校验，再部署固定镜像 digest 的 Go API。
4. 使用专用运营账户验证健康、认证、空迁移、bootstrap 和权益列表。
5. 确认指标健康后恢复迁移写入；禁止用真实用户 Vault 做 canary。

| 操作 | 结果 |
| --- | --- |
| 最终备份与恢复元数据 | NOT_RUN |
| 迁移版本 17 | NOT_RUN |
| API 固定 digest 部署 | NOT_RUN |
| 生产安全 canary | NOT_RUN |
| 迁移写入恢复 | NOT_RUN |

## App Store 分阶段发布

1. 选择已通过 TestFlight 的 `1.1.0 (15)` 构建和需要关联的非消耗型商品。
2. 填写版本说明、审核说明、隐私回答、截图和联系信息。
3. 提交 App Review；批准后启动分阶段发布，不直接手动放量到 100%。
4. 每个阶段按 `ios-1.1.0-monitoring.md` 观察；无 P0/P1 且核心指标稳定才继续。

| 阶段 | 结果 |
| --- | --- |
| App Review 接受 | NOT_RUN |
| 首批用户可用 | NOT_RUN |
| 首批观察窗口健康 | NOT_RUN |
| 继续分阶段放量 | NOT_RUN |

## P0 回滚

发生数据丢失、串账户、付费用户被锁、升级崩溃或无法保存照片时：

1. 立即暂停 App Store 分阶段发布并关闭迁移写入。
2. 保留客户端本地数据、服务端 staging 数据和所有审计记录。
3. 后端问题可部署上一兼容 API；不要先下迁移生产数据库。
4. 发布用户通知并以短支持编号建立事故，不收集敏感原始数据。
5. 修复版必须增加 build number，重新走真机、Sandbox 和 TestFlight 门禁。

## GitHub 发布

仅在生产验收完成后执行：

```bash
git tag -a ios-v1.1.0 -m "Clovery iOS 1.1.0"
git push origin ios-v1.1.0
gh release create ios-v1.1.0 \
  --title "Clovery iOS 1.1.0" \
  --notes-file docs/release/1.1.0-ios-release.md
```

公开 Release 只包含源代码与发布说明，不附加应用包、归档、数据库备份、交易材料、用户截图或签名文件。

## 完成签字

- 数据库执行人：`待填写`
- 后端执行人：`待填写`
- App Store 执行人：`待填写`
- 发布批准人：`待填写`
- 最终结果：`NOT_RUN`

生产版本面向目标用户可用、监控健康且没有开放 P0/P1 后，才允许将 W10 标记完成并启动 Flutter W3。
