# RAR 助手 1.1

一个本地的 macOS RAR 压缩 / 解压工具，原生 AppKit 界面，支持 **AES-256 密码加密**。所有操作都在本机完成，不联网、不上传任何文件。

## 功能

| 功能 | 说明 |
|------|------|
| 压缩 | 选择多个文件 / 文件夹，或把它们直接拖进窗口，一键打包成 `.rar` |
| 解压 | 选择或拖入 `.rar`，解压到指定目录（默认解压到同名文件夹） |
| 密码加密 | RAR5 格式 + AES-256 加密内容；可勾选「同时加密文件名」（`-hp`） |
| 加密检测 | 选中压缩包后自动检测是否加密，已加密时红字提示 |
| **双击打开** | 在访达里双击 `.rar` 直接唤起本应用，并自动切到解压页、填好路径 |
| **设为默认** | 解压页有「设为 .rar 默认打开方式」按钮，一键接管 `.rar` |
| **移到废纸篓** | 可勾选「解压完成后把原压缩包移到废纸篓」（进废纸篓，可恢复，不是彻底删除） |
| 实时进度 | 解析 rar / unrar 的进度输出，进度条 + 实时日志 |
| 中文报错 | 密码错误、文件不存在、无写入权限等都给中文结论 |

## 安装

已经构建好的应用包在：

```
RarHelper/build/RarHelper.app
```

直接双击即可运行。想放进「应用程序」：

```bash
cp -R RarHelper/build/RarHelper.app /Applications/
```

### 设为 .rar 的默认打开方式

三种方式任选：

1. **应用内一键设置**：打开 RAR 助手 → 切到「解压」页 → 点「设为 .rar 默认打开方式」
2. **命令行**：
   ```bash
   swift -e 'import CoreServices; _ = LSSetDefaultRoleHandlerForContentType("com.rarlab.rar-archive" as CFString, .viewer, "com.local.rarhelper" as CFString)'
   ```
3. **访达手动设置**：右键任意 `.rar` → 显示简介 → 打开方式 → 选「RAR 助手」→ 点「全部更改…」

> 如果之前 `.rar` 被其它程序（例如 WPS Office、The Unarchiver、Keka）占用，设置后即以 RAR 助手为准。

设置好后，在访达双击任意 `.rar` 就会直接打开 RAR 助手，并自动切到解压页、填好该文件和默认解压目录。

> **首次打开提示「无法验证开发者」时**：这是 ad-hoc 签名（本地自签）的正常提示，不是病毒。
> 处理方式任选其一：
> 1. 在访达中 **右键** 点击 RAR 助手 → 「打开」；
> 2. 或执行 `xattr -dr com.apple.quarantine /Applications/RarHelper.app`；
> 3. 或去 系统设置 → 隐私与安全性 → 点「仍要打开」。

## 使用

### 压缩

1. 点「添加文件…」/「添加文件夹…」，或把文件直接拖进窗口上半部分
2. 确认「输出为」的路径（默认与第一个源文件同级、同名 `.rar`）
3. 需要加密就填密码（**两遍要一致**）；不加密就把两个密码框留空
4. 点「开始压缩」

- 勾选「同时加密文件名」后，连文件名都会被加密——**没有密码连目录都列不出来**，安全性更高，但忘记密码就彻底无法恢复
- 多个源一起压缩时，默认输出名为「归档.rar」

### 解压

1. 点「选择…」或把 `.rar` 拖进窗口
2. 「解压到」默认填的是压缩包同目录下的同名文件夹，可以改
3. 如果提示「该压缩包已加密，请输入密码」，填密码后再点「开始解压」

## 构建

不需要 Xcode.app，只要有 Xcode Command Line Tools：

```bash
cd RarHelper
bash build.sh
```

脚本会：编译 Swift 源码 → 组装 `.app` → 拷入 rar / unrar → 清除隔离属性 → ad-hoc 签名。
产物：`build/RarHelper.app`。

## 技术实现

- **界面**：AppKit + Swift 5，纯代码 Auto Layout，无 xib / storyboard，无第三方依赖
- **压缩**：`rar a [-p|-hp] -ep1 -ma5` —— `-ma5` 指定 RAR5 格式，这是 AES-256 的前提
- **解压**：`unrar x [-p] -y -o+`
- **加密检测**：`unrar l`，加密条目的行首带 `*`
- **密码安全**：密码一律通过 **stdin** 写入子进程，不拼进命令行参数，避免被 `ps` 看到
- **输出解析**：rar 用退格符做行内进度覆盖，引擎会先模拟退格、剔除 ANSI 序列，再提取百分比

### 源码结构

```
Sources/main.swift                 应用委托、菜单栏、接收系统传来的 .rar 文件
Sources/RarEngine.swift            子进程封装：定位二进制、清洗输出、进度、错误判定
Sources/MainWindowController.swift 主窗口 UI：压缩 / 解压、拖放、废纸篓、默认打开方式、日志
Resources/rar                      RARLAB 官方 rar 7.23（arm64）
Resources/unrar                    RARLAB 官方 unrar 7.23（arm64）
Resources/AppIcon.icns             应用图标（橙色底 + 拉链 + RAR 字样）
Tools/MakeIcon/main.swift          图标绘制程序（CoreGraphics，改配色/文字后重跑即可）
Tests/EngineSmoke/main.swift       引擎端到端冒烟测试（9 场景 15 断言）
build.sh                           一键构建（含图标生成与 LaunchServices 注册）
Info.plist                         Bundle 配置（含 .rar 文档类型与 UTI 声明）
```

图标是代码画的（不是图片素材）：橙色渐变圆角底 + 白色拉链 + 白色粗体 `RAR`。
改配色或字样后重新生成：

```bash
swiftc -O -o /tmp/makeicon Tools/MakeIcon/main.swift
/tmp/makeicon Resources/AppIcon.iconset && iconutil -c icns Resources/AppIcon.iconset -o Resources/AppIcon.icns
```

## 授权与合规（请务必了解）

- **`unrar`** 是 RARLAB 发布的 **免费软件**（freeware），解压功能可自由使用
- **`rar`** 是 **试用版**（Trial version），功能完整，但**商业用途需要向 RARLAB 购买许可**；个人自用不受影响
- RAR 压缩格式是 RARLAB 的专有格式，这也是为什么必须用它官方的二进制——7-Zip、bsdtar 等开源工具只能解压 RAR，无法打包 RAR
- 二进制来源：RARLAB 官方 `rarmacos-arm-723`（Apple Silicon 原生）

## 已知限制

1. 只支持 **RAR5**（`-ma5`），不提供旧版 RAR4 格式输出
2. 未做分卷压缩、恢复记录、注释等进阶选项
3. 支持「双击打开」和「设为默认打开方式」，但**未做**访达右键菜单里的「快速操作」项
4. 不支持分卷包（`.part1.rar` 多卷）的自动合并解压——需要用解压功能时先手动保证分卷齐全
5. 是 ad-hoc 签名，换一台 Mac 首次打开需要按上面的方式放行一次
6. 「移到废纸篓」只在**解压成功后**才执行；解压失败不会动原压缩包（废纸篓里也能随时恢复）
