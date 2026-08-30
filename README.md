<div align="right">
  <strong>简体中文</strong> | <a href="./README.en.md">English</a>
</div>

<div align="center">
  <img src="assets/icon/app-icon-1024-rounded.png" alt="Echo Loop" width="128" />
  <h1>Echo Loop — 把一段英语真正练会</h1>
  <p><strong>盲听 · 精听 · 跟读 · 复述 · 间隔复习</strong></p>
  <p>一款围绕真实音频材料打造的英语听说训练 App，自动安排训练步骤，让听懂变成会说。</p>
  <p><sub><em>本项目由中央民族大学外国语学院 <a href="https://sfs.muc.edu.cn/info/1063/3729.htm">杨艳老师</a> 指导设计。</em></sub></p>
  <p>
    <a href="./LICENSE"><img src="https://img.shields.io/badge/License-AGPL--3.0-blue.svg" alt="License: AGPL-3.0" /></a>
    <img src="https://img.shields.io/badge/Platform-iOS%20%C2%B7%20Android%20%C2%B7%20macOS-brightgreen.svg" alt="Platform" />
    <a href="https://github.com/echo-loop/Echo-Loop/releases/latest"><img src="https://img.shields.io/github/v/release/echo-loop/Echo-Loop?label=release&color=orange" alt="Latest release" /></a>
    <a href="https://github.com/echo-loop/Echo-Loop/commits/main"><img src="https://img.shields.io/github/last-commit/echo-loop/Echo-Loop" alt="Last commit" /></a>
  </p>
  <p>
    <a href="https://apps.apple.com/app/id6760324074"><img src="https://developer.apple.com/assets/elements/badges/download-on-the-app-store.svg" alt="Download on the App Store" height="48" /></a>
    <a href="https://play.google.com/store/apps/details?id=app.echoloop"><img src="assets/badges/google-play-en.png" alt="Get it on Google Play" height="40" /></a>
  </p>
</div>

> 🇨🇳 **中国区用户请注意**：中国区 App Store 正在申请 ICP 备案，应用暂时下架。中国大陆用户可切换到非中国区 Apple 账号下载安装 Echo Loop。

## Echo Loop 是什么

Echo Loop 把一段音频拆成可执行的学习任务：先完整盲听，再逐句精听、跟读和复述，最后按照记忆调度安排复习。你可以导入自己喜欢的播客、课程或视频，也可以直接使用官方合集；应用会保存学习进度、难句和收藏内容，帮助你把“听过”变成“听懂、说出、记住”。

主学习闭环免费，AI 能力和订阅只用于增强体验，不会阻断核心的播放与学习流程。

## 截图

<table>
  <tr>
    <td align="center"><img src="assets/screenshots/01-import.png" alt="导入音频" width="180" /><br/><sub>导入音频</sub></td>
    <td align="center"><img src="assets/screenshots/04-intensive.png" alt="逐句精听" width="180" /><br/><sub>逐句精听</sub></td>
    <td align="center"><img src="assets/screenshots/05-analysis.png" alt="句子解析" width="180" /><br/><sub>句子解析</sub></td>
    <td align="center"><img src="assets/screenshots/06-retell.png" alt="段落复述" width="180" /><br/><sub>段落复述</sub></td>
    <td align="center"><img src="assets/screenshots/08-flashcard.png" alt="收藏复习" width="180" /><br/><sub>收藏复习</sub></td>
  </tr>
</table>

## 当前功能

### 学习与播放

- 支持本地音频和视频导入，批量导入字幕（SRT / VTT / LRC），也可使用 AI 转录生成字幕。
- 全文盲听、逐句精听、难句跟读、段落复述、难句补练和自由练习。
- 音频/视频播放、字幕同步、波形、单句/全文/收藏范围播放，以及后台播放和定时停止。
- 支持字幕编辑、句子级时间轴、意群标注和学习材料整理。
- 可浏览官方合集、Podcast 内容，也支持从百度网盘导入材料。

### 收藏与间隔复习

- 收藏句子、单词和意群，并在原句语境中复习。
- 基于 FSRS 的收藏句复习和收藏词汇复习，支持评分、播放偏好和下次复习时间。
- 复习统计包括今日复习、保持率、评分分布、30 天趋势、未来安排和连续复习。
- 学习过程自动保存，支持断点续学、提醒和学习日历。

### 词典、发音与 AI

- 本地词典、离线发音、AI 词典和网页词典，可在不同来源之间切换。
- AI 翻译、句子解析、单词深度解析和语境化词汇讲解。
- 句子级多轮 AI 助手，支持流式回复、追问、引用当前句子和重新生成。
- 平台 TTS 与 Kokoro / Piper 本地 TTS；支持离线 ASR 跟读评测和转录。

### 数据与订阅

- 学习材料可导出为可打印 PDF。
- 支持本地备份与恢复，采用磁盘流式处理并保留失败回滚；备份不包含登录会话和可重新下载的资源。
- 支持邮箱、Google 和 Apple 登录。
- iOS / Android 使用原生应用内订阅；支持的其他渠道使用 Paddle。AI 使用量由后端统一裁决。

## 学习流程

```mermaid
flowchart LR
  A[盲听] --> B[逐句精听]
  B --> C[难句跟读]
  C --> D[段落复述]
  D --> E[间隔复习]
  E --> F[掌握]
```

首次学习完成后，系统会按 6 小时、1 天、2 天、4 天、7 天、14 天、28 天的节奏安排后续复习。实际复习内容由学习状态和收藏内容决定。

## 下载

- [App Store](https://apps.apple.com/app/id6760324074)
- [Google Play](https://play.google.com/store/apps/details?id=app.echoloop)
- [Android APK / Releases](https://github.com/echo-loop/Echo-Loop/releases)

桌面端：macOS 持续开发；Windows 尚未正式发布；暂无 Web 版本。

## Roadmap

已完成的核心能力包括：学习闭环、收藏复习、官方合集、AI 翻译与解析、句子级 AI 助手、PDF 导出、订阅与 AI 配额、数据备份恢复，以及多平台播放和语音能力。

当前重点：

- 修复部分 Android 设备结束离线 ASR 录音后的 native 闪退。
- 继续完善段落复述的统一录音识别模块和跨平台发布验证。
- 持续打磨启动性能、播放、词典、PDF、字幕编辑和订阅生产链路。

详细计划见 [PLAN.md](./PLAN.md) 和 [TASKS.md](./TASKS.md)。

## 社群

- [加入 QQ 群](https://qm.qq.com/q/qmyXIv341q)
- [微信联系我们](https://i.postimg.cc/P5tVpPTV/echo-loop-wecom.jpg)
- [关注 B 站](https://space.bilibili.com/509449049/upload/video)
- [关注小红书](https://xhslink.cn/m/4zOdGUcDH4N)

## 给开发者

```bash
git clone git@github.com:echo-loop/Echo-Loop.git
cd Echo-Loop
cp .dev.env.template .dev.env
flutter pub get
dart run build_runner build
flutter run -d <ios|android|macos> --dart-define-from-file=.dev.env
```

编译期变量（`SUPABASE_URL`、`SUPABASE_PUBLISHABLE_KEY`、`GOOGLE_WEB_CLIENT_ID`、`API_BASE_URL`）放在 `.dev.env` 或 `.prod.env` 中，通过 `--dart-define-from-file` 注入。环境文件已被 `.gitignore`，不要提交密钥。

提交前建议运行：

```bash
flutter analyze
flutter test
```

## 技术栈

Flutter · Dart · Riverpod · Drift / SQLite · just_audio · media_kit · sherpa_onnx · Flutter TTS · Supabase · Firebase · PostHog · Material 3

## 许可证与致谢

本项目使用 [AGPL-3.0](./LICENSE) 许可证。感谢 [杨艳老师](https://sfs.muc.edu.cn/info/1063/3729.htm) 对项目学习方法论的指导。
