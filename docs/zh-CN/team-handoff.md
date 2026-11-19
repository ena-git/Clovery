# 组员交接说明：多端、Apple Watch 与小组件

本文说明本次新增/修改的内容、构建要求和已知限制。

## 1. 构建环境

- Xcode 26.4 及以上。
- **必须安装 watchOS 26.4 模拟器运行时**（Xcode → Settings → Components，或 `xcodebuild -downloadPlatform watchOS`）。
  `Clovery` scheme 会嵌入 Apple Watch App，没有该运行时 Xcode 会报：
  `This scheme builds an embedded Apple Watch app. watchOS 26.4 must be installed`。
- 暂时不想装运行时：在 `Clovery` target 的 Build Phases 里移除 `Embed Watch Content`，并在 Dependencies 里移除 `CloveryWatch`，即可只构建 iOS / iPad / Mac Catalyst。
- Mac Catalyst 不嵌入小组件和手表 App（`platformFilter = ios`）。

## 2. 本次改动

| 模块 | 位置 | 内容 |
| --- | --- | --- |
| 桌面小组件 | `CloveryWidget/CloveryWidget.swift` | 按设计稿重做 4 款；颜色、字体、深浅色与 App 内用户设置一致（App Group 键：`widget_palette` / `widget_font` / `widget_lang` / `widget_dark`）；四叶草数量/叶子数与 App 口径一致：每 4 个不同日期一株，且排除补记条目（`createdAt` 的日期晚于条目日期），连续天数仍包含补记 |
| Apple Watch | `CloveryWatch/` | 首页大四叶草点击记录（系统输入，含听写）；向左滑动进入日记回顾；主题、字体、语言、深浅色与 iPhone 同步 |
| 手表桥接 | `Clovery/WatchBridge.swift` | iPhone→手表：`updateApplicationContext`；手表→iPhone：`transferUserInfo`，写入 WebView 前先入队 |
| 网页桥接 | `Clovery/Clover Diary.html`、`WebView.swift`、`BridgeJavaScript.swift` | 新增 `window.__clovery_addExternalEntry` 钩子与 `watchReady` 就绪信号；同步 `widget_dark` |
| 工程文件 | `Clovery.xcodeproj` | 新增 `CloveryWatch` target；手表与小组件的嵌入均加了 iOS 平台过滤，Mac Catalyst 可构建 |

设计预览图：`docs/widgets-preview.png`、`docs/widgets-palettes-preview.png`、`docs/watch-preview.png`。

## 3. 验证状态（以实际执行为准）

| 平台 | 状态 |
| --- | --- |
| iPhone 模拟器 | 已构建并运行；小组件已在模拟器验证 |
| iPad 模拟器 | 已构建并运行；小组件已在模拟器验证 |
| Mac Catalyst | 完整工程构建成功并启动运行 |
| Apple Watch | **仅通过 watchOS SDK 类型检查和 macOS 预览渲染，未在手表模拟器或真机运行**（本机无 watchOS 运行时） |
| 手表 → iPhone 日记写入 | 在 iPhone 模拟器中用模拟数据验证；真实 WatchConnectivity 配对传输需真机 |
| 跨设备云同步 | 未验证，见下 |
| Swift 单元测试（`CloveryTests`，iPhone 模拟器） | 222 个中 217 个通过，5 个失败（见下）；`StoreKitIntegrationTests` 在无签名环境下会卡住，未运行，需在带 StoreKit 配置的 Xcode 里单独跑 |

## 4. 已知问题与风险

1. **生产后端可能未上线**：`api.clovery.cn` 在检查时解析到域名停放页，HTTPS 证书主机名不匹配。正式版必须先登录账号才能进入日记，后端不可用时无法使用。发布前请先确认 `https://api.clovery.cn/v1/health`。
2. **同步验收全部 `NOT_RUN`**：见 `docs/release/ios-1.1.0-device-acceptance.md`。
3. **旧 iCloud 同步缺陷（1.0.3 用户反馈来源，1.1.0 账号方案不依赖）**：
   - 没有注册远程通知，静默推送链路是断的（`CloudKitSync.setupSubscriptionIfNeeded()` 无人调用）；
   - 回到前台不拉取 CloudKit；
   - `NSUbiquitousKeyValueStore` 总上限 1MB，超限静默失败；
   - 删除不会同步（设计如此）。
4. 手表的连续天数按手表上已有的日记计算（手表只缓存最近 60 条），长期连续记录可能少于 iPhone 上的数字。
5. 手表没有表盘复杂功能。

## 5. 单元测试的 5 个失败（均在账号体系，与小组件/手表/桥接改动无关）

测试文件修改于 8 月，`Config/Debug.xcconfig` 修改于 9 月，均早于本次改动。没有对照基线，因此只能说"看起来是既有问题"，请负责账号模块的同学确认。

- `AuthenticationReleaseConfigurationTests.testDebugBuildEmbedsCompleteAPIURL`：测试期望 Debug 的 API 为 `http://127.0.0.1:8080`，`Debug.xcconfig` 现在是 `https://api.clovery.cn`；
- `AuthenticationReleaseConfigurationTests.testReleaseEnvironmentProvidesVerifiedAPIURL`：缺少 `CLOVERY_RELEASE_API_BASE_URL` 环境变量；
- `AuthenticationAPIClientTests.testRegisterSendsRecoveryCodesAndDevice`：请求体缺少 `recovery_method`；
- `IOSVerificationFixtureTests.testFixtureMatrixAndFontArgumentsAreStable`：fixture 枚举与测试期望集合不一致；
- `ProviderVisibilityPolicyTests.testCrossPlatformQuickProviderMatrix`：各平台快捷登录方式与测试期望不一致。
