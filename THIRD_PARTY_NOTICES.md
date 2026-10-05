# 第三方组件与许可声明

本项目源码以 **MIT** 许可开源（见 `LICENSE`）。以下是其内置 / 依赖的第三方组件。

## 1. rars —— 默认压缩 / 解压引擎

- 文件：`Resources/rars`
- 版本：0.10.0
- 作者：Gareth Davidson（bitplane）
- 许可：**Apache License 2.0**
- 源码：<https://github.com/bitplane/rars>
- 许可全文：随二进制分发于 `Resources/rars-COPYING.txt`
- 说明：纯 Rust 实现的 RAR 读写库，支持 RAR 1.3 ~ RAR 7，能读也能写。
  它**独立实现，未使用 RARLAB 的 unrar 源码**（后者许可禁止用其代码重建 RAR 压缩算法）。
  本项目用 `cargo install rars-cli` 编译生成，仅在 macOS arm64 上使用。

## 2. unrar —— 仅用于检测压缩包是否加密

- 文件：`Resources/unrar`
- 版本：7.23（freeware）
- 作者：Alexander Roshal / win.rar GmbH
- 许可：RARLAB 发布的 freeware，非开源
- 分发依据：RARLAB EULA 第 3a 条明确允许 **UnRAR 组件自由分发**
- 用途：本项目仅用 `unrar l` 读取目录信息，判断条目行首是否带 `*`（加密标记）。
  **不用于**创建压缩包（创建由 rars 完成）。

## 3. rar —— RARLAB 官方命令行（**未随本仓库分发**）

- 状态：**不在仓库中**，本项目也不代为下载
- 原因：RARLAB EULA 第 3b 条规定，未注册试用版不得打包进其它软件包分发
- 许可：试用版，免费使用 40 天；**商业用途必须购买许可**
  <https://www.rarlab.com>
- 如需使用官方引擎，请自行下载并放入 `Resources/rar`，
  具体命令见 README「可选：安装官方 rar」。App 检测到后会显示当前引擎，但**优先级低于 rars**。

## 4. 应用图标

- 生成方式：由 `Tools/MakeIcon/main.swift` 以 CoreGraphics 代码绘制
- 许可：与本项目相同（MIT）

## 关于 RAR 格式本身

RAR 格式是 RARLAB 的专有格式。本项目通过使用独立开源实现（rars）来读写该格式，
源码中不包含 RARLAB 的专有代码。若你在商业场景中使用本工具产生或消费 RAR 文件，
请自行评估相关合规要求；官方 rar 的商业许可可直接向 RARLAB 购买。
