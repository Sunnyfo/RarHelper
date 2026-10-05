# RAR 助手 1.2

一个本地的 macOS RAR 压缩 / 解压工具，原生 AppKit 界面，支持 **AES-256 密码加密**。
**完全开源（MIT）**，压缩与解压由开源引擎 [rars](https://github.com/bitplane/rars)（Apache-2.0）驱动，
**不依赖 RARLAB 的任何收费软件**。所有操作都在本机完成，不联网、不上传任何文件。

## 功能

| 功能 | 说明 |
|------|------|
| 压缩 | 选择多个文件 / 文件夹，或把它们直接拖进窗口，一键打包成 `.rar` |
| 解压 | 选择或拖入 `.rar`，解压到指定目录（默认解压到同名文件夹） |
| 密码加密 | RAR5 格式 + AES-256 加密内容；可勾选「同时加密文件名」 |
| 加密检测 | 选中压缩包后自动检测是否加密，已加密时红字提示 |
| **双击打开** | 在访达里双击 `.rar` 直接唤起本应用，并自动切到解压页、填好路径 |
| **设为默认** | 解压页有「设为 .rar 默认打开方式」按钮，一键接管 `.rar` |
| **移到废纸篓** | 可勾选「解压完成后把原压缩包移到废纸篓」（进废纸篓，可恢复，不是彻底删除） |
| 实时进度 | 解析引擎的进度输出，进度条 + 实时日志 |
| 中文报错 | 密码错误、文件不存在、无写入权限等都给中文结论 |

## 为什么不用官方 rar

RAR 的**写入格式是专有的**：7-Zip、bsdtar 等开源工具都只能解压、不能打包 RAR。
本项目的做法是：

- **默认引擎 `rars`** —— 纯 Rust 实现的 RAR 读写库（**Apache-2.0**），支持 RAR 1.3 ~ RAR 7，
  能读也能写，**独立实现、未使用 RARLAB 的 unrar 源码**。经实测，它生成的 RAR5 加密包
  可被官方 `unrar` 正常解开，内容逐字节一致；官方 rar 生成的包它也能正常解开。
- **`unrar`（freeware）** —— 仅用于「检测压缩包是否加密」（读目录里的 `*` 标记）。
  RARLAB EULA 第 3a 条明确允许 UnRAR 组件自由分发，所以可以随仓库提供。
- **官方 `rar`（试用版）不随仓库分发** —— EULA 第 3b 条禁止把未注册试用版打包进其它软件分发。
  如果你希望改用官方引擎，可自行下载（见下方「可选：安装官方 rar」），App 会自动优先使用它。

## 安装

已经构建好的应用包在：

```
RarHelper/build/RarHelper.app
```

直接双击即可运行。想放进「应用程序」：

```bash
cp -R RarHelper/build/RarHelper.app /Applications/
```

> **首次打开提示「无法验证开发者」时**：这是 ad-hoc 签名（本地自签）的正常提示，不是病毒。
> 处理方式任选其一：右键点击 →「打开」；或执行
> `xattr -dr com.apple.quarantine /Applications/RarHelper.app`；
> 或去 系统设置 → 隐私与安全性 → 点「仍要打开」。

### 可选：安装官方 rar

默认不需要装任何东西。若你想用 RARLAB 官方引擎（压缩率略优于开源引擎），可自行下载：

```bash
cd /Applications/RarHelper.app/Contents/Resources
curl -L -o rar.tar.gz https://www.rarlab.com/rar/rarmacos-arm-723.tar.gz   # Intel 芯片用 rarmacos-x64-723
tar -xzf rar.tar.gz && mv rar/rar . && chmod +x rar && rm -rf rar rar.tar.gz
```

放好后重启 App，压缩页底部会显示当前引擎。App 检测到 `rars` 与 `rar` 时**优先使用 rars**。
商业用途请向 RARLAB 购买许可：<https://www.rarlab.com>

### 设为 .rar 的默认打开方式

三种方式任选：

1. **应用内一键设置**：打开 RAR 助手 → 切到「解压」页 → 点「设为 .rar 默认打开方式」
2. **命令行**：
   ```bash
   swift -e 'import CoreServices; _ = LSSetDefaultRoleHandlerForContentType("com.rarlab.rar-archive" as CFString, .viewer, "com.local.rarhelper" as CFString)'
   ```
3. **访达手动设置**：右键任意 `.rar` → 显示简介 → 打开方式 → 选「RAR 助手」→ 点「全部更改…」

设置好后，在访达双击任意 `.rar` 就会直接打开 RAR 助手，并自动切到解压页、填好该文件和默认解压目录。

## 使用

### 压缩

1. 点「添加文件…」/「添加文件夹…」，或把文件直接拖进窗口上半部分
2. 确认「输出为」的路径（默认与第一个源文件同级、同名 `.rar`）
3. 需要加密就填密码（**两遍要一致**）；不加密就把两个密码框留空
4. 点「开始压缩」

- 勾选「同时加密文件名」后，连文件名都会被加密——**没有密码连目录都列不出来**，安全性更高，但忘记密码就彻底无法恢复
- 多个源一起压缩时，默认输出名为「归档.rar」；目录结构会完整保留

### 解压

1. 点「选择…」或把 `.rar` 拖进窗口
2. 「解压到」默认填的是压缩包同目录下的同名文件夹，可以改
3. 如果提示「该压缩包已加密，请输入密码」，填密码后再点「开始解压」

## 从源码构建

不需要 Xcode.app，只要有 Xcode Command Line Tools：

```bash
cd RarHelper
bash build.sh
```

脚本会：生成图标 → 编译 Swift 源码 → 组装 `.app` → 拷入引擎 → ad-hoc 签名 → 注册 `.rar` 文件关联。
产物：`build/RarHelper.app`。

### 想自己编译 rars 引擎（可选）

仓库已带预编译的 `Resources/rars`。若想自行构建：

```bash
cargo install rars-cli
cp "$(~/.cargo/bin/rars)" Resources/rars && chmod +x Resources/rars
```

## 技术实现

- **界面**：AppKit + Swift 5，纯代码 Auto Layout，无 xib / storyboard，无第三方依赖
- **默认引擎**：`rars a --format rar50`（压缩）、`rars x`（解压），均为 Apache-2.0 开源
- **回退引擎**：`rar a -ep1 -ma5` / `unrar x -y -o+`
- **路径处理**：rars 在多源混合时会按各源自己的父目录剥离前缀，导致子目录被压平；
  因此引擎会先算出所有源的**公共父目录**、`cd` 进去再传相对路径，保证目录结构不丢
- **加密检测**：`unrar l`，加密条目的行首带 `*`；整包加密文件名时不带密码会直接失败
- **密码安全**：密码一律通过 **stdin** 写入子进程（rars 用 `--password-file -`），不拼进命令行参数，避免被 `ps` 看到
- **输出解析**：rar 用退格符做行内进度覆盖、rars 把进度打到 stderr，引擎分别做清洗与百分比提取

### 源码结构

```
Sources/main.swift                 应用委托、菜单栏、接收系统传来的 .rar 文件
Sources/RarEngine.swift            子进程封装：引擎选择、路径处理、输出清洗、进度、错误判定
Sources/MainWindowController.swift 主窗口 UI：压缩 / 解压、拖放、废纸篓、默认打开方式、日志
Resources/rars                     开源 RAR 引擎（Apache-2.0）
Resources/unrar                    RARLAB unrar（freeware，仅用于加密检测）
Resources/AppIcon.icns             应用图标
Resources/rars-COPYING.txt         rars 的 Apache-2.0 许可证全文
Tools/MakeIcon/main.swift          图标绘制程序（CoreGraphics，改配色/文字后重跑即可）
Tests/EngineSmoke/main.swift       引擎端到端冒烟测试（10 场景 18 断言）
build.sh                           一键构建
Info.plist                         Bundle 配置（含 .rar 文档类型与 UTI 声明）
LICENSE                            MIT 许可 + 第三方组件声明
```

图标是代码画的（不是图片素材）：橙色渐变圆角底 + 白色拉链 + 白色粗体 `RAR`：

```bash
swiftc -O -o /tmp/makeicon Tools/MakeIcon/main.swift
/tmp/makeicon Resources/AppIcon.iconset && iconutil -c icns Resources/AppIcon.iconset -o Resources/AppIcon.icns
```

## 测试

```bash
swiftc -O -o /tmp/smoke Tests/EngineSmoke/main.swift Sources/RarEngine.swift
/tmp/smoke     # 需在本项目目录下运行，引擎从 Resources/ 定位
```

覆盖：明文压缩解压、加密压缩解压、错误密码、加密文件名、中文/空格文件名、
三层嵌套目录、3MB 二进制完整性、多源混合结构、异常路径拦截。

## 授权与合规

- 本项目源码以 **MIT** 许可开源（见 `LICENSE`）
- 默认引擎 **rars** 为 **Apache License 2.0**，可自由使用与再分发
- **unrar** 为 RARLAB 提供的 freeware，EULA 第 3a 条允许自由分发
- **RAR 格式本身是专有的**；本项目使用独立开源实现，未使用 RARLAB 的 unrar 源码
- 官方 `rar` 为试用版，未随本仓库分发；商业用途请直接向 RARLAB 购买许可

## 已知限制

1. 只支持 **RAR5**（`--format rar50`），不提供旧版 RAR4 格式输出
2. 未做分卷压缩、恢复记录、注释等进阶选项
3. 支持「双击打开」和「设为默认打开方式」，但**未做**访达右键菜单里的「快速操作」项
4. 不支持分卷包（`.part1.rar` 多卷）的自动合并解压
5. 是 ad-hoc 签名，换一台 Mac 首次打开需要按上面的方式放行一次
6. 「移到废纸篓」只在**解压成功后**才执行；解压失败不会动原压缩包
7. 开源引擎 rars 相比官方 rar **速度略慢、内存占用略高、压缩率略低**（作者自述）；
   它很新（2026 年中发布），极端场景下的兼容性建议先用重要文件实测
