# 🍀 Clovery — 幸运日记

一款轻量、手绘风格的 iOS 日记应用，记录每天最幸运的小事。

## 功能特性

- **今日记录** — 记录每天的幸运瞬间，支持文字、照片、心情、标签
- **幸运田野** — 每记录 4 天解锁一朵四叶草，在田野中生长
- **日历视图** — 按月查看所有记录，支持标签筛选
- **今日留言板** — 将日记、照片、贴纸组合成手绘风格卡片并分享
- **手绘贴纸** — 12 款手绘艺术贴纸 + 主题 emoji 贴纸
- **多语言** — 支持简体中文、English、日本語、한국어
- **深色模式** — 完整适配，手绘图标自动反色
- **字体主题** — 多种手写字体可选（月亮海、Yomogi、NotoSerifSC 等）
- **WidgetKit 小组件** — 4 种桌面小组件（快写、叶片、日记、田野）
- **iCloud 同步** — 通过 CloudKit 跨设备同步数据

## 技术架构

| 层 | 技术 |
|---|---|
| UI | React + Babel（单页 HTML，运行在 WKWebView 中）|
| 原生层 | Swift / SwiftUI |
| 数据持久化 | localStorage + NSUbiquitousKeyValueStore |
| 云同步 | CloudKit（私有数据库）|
| 小组件 | WidgetKit，App Groups 共享数据 |
| 字体 | Gaegu、Yomogi、YueLiangHai、NotoSerifSC、NaiChaTi |

## 项目结构

```
CloverDiary-iOS/
├── Clovery/
│   ├── Clover Diary.html      # 主应用（React 单页）
│   ├── WebView.swift          # WKWebView 桥接层
│   ├── CloudKitSync.swift     # iCloud 同步
│   ├── BoardStore.swift       # 留言板状态管理
│   ├── fonts/                 # 手写字体资源
│   └── vendor/                # React / Babel 离线包
├── CloveryWidget/
│   ├── CloveryWidget.swift    # 小组件实现
│   └── CloveryWidgetBundle.swift
└── Clovery.xcodeproj/
```

## 开发环境

- Xcode 16+
- iOS 17+ 部署目标
- Bundle ID: `com.clovery.app`

## Bundle ID & 配置

- 主 App: `com.clovery.app`
- Widget: `com.clovery.app.CloveryWidget`
- App Group: `group.com.clovery.app`
- iCloud Container: `iCloud.com.clovery.app`

## Verification

- Native App Store iOS V1: `scripts/verify-ios-v1.sh`
- Go/Flutter V2 platform: `cd v2 && make verify`

Flutter feature development must resume only after the native iOS release gate passes.
