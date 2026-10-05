#!/bin/bash
#
# RAR 助手 —— 一键构建脚本
#
# 用法：bash build.sh
# 产物：build/RarHelper.app
#
# 说明：不需要 Xcode.app，只需要 Xcode Command Line Tools（swiftc）。
#       RAR 的压缩 / 解压由 Resources 下的 RARLAB 官方二进制驱动，脚本会把它们一并打进 App 包。

set -euo pipefail
cd "$(dirname "$0")"

APP_BUNDLE="RarHelper.app"
BUILD_DIR="build"
EXECUTABLE="RarHelper"
APP_PATH="$BUILD_DIR/$APP_BUNDLE"

echo "==> 检查源码与内置二进制"
for file in Sources/main.swift Sources/RarEngine.swift Sources/MainWindowController.swift \
            Info.plist Resources/rar Resources/unrar; do
    if [[ ! -f "$file" ]]; then
        echo "错误：缺少 $file" >&2
        exit 1
    fi
done

echo "==> 清理旧的构建产物"
rm -rf "$BUILD_DIR"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"

echo "==> 编译 Swift 源码（$(swift --version 2>/dev/null | head -1 || echo swiftc)）"
# 先用带部署目标的 target 编译；若本机 SDK 不支持，则退回默认 target。
if ! swiftc -O -target arm64-apple-macos13.0 \
        -o "$APP_PATH/Contents/MacOS/$EXECUTABLE" \
        Sources/main.swift Sources/RarEngine.swift Sources/MainWindowController.swift 2>/tmp/rarhelper_build.log; then
    echo "    （带 -target 编译失败，改用本机默认 target 重试）"
    swiftc -O \
        -o "$APP_PATH/Contents/MacOS/$EXECUTABLE" \
        Sources/main.swift Sources/RarEngine.swift Sources/MainWindowController.swift
fi

# 图标缺失时用 Tools/MakeIcon 现生成一个（橙色底 + 拉链 + RAR 字样）
if [[ ! -f Resources/AppIcon.icns ]]; then
    echo "==> 生成应用图标"
    swiftc -O -o /tmp/rarhelper_makeicon Tools/MakeIcon/main.swift
    rm -rf Resources/AppIcon.iconset
    /tmp/rarhelper_makeicon Resources/AppIcon.iconset > /dev/null
    iconutil -c icns Resources/AppIcon.iconset -o Resources/AppIcon.icns
    rm -rf Resources/AppIcon.iconset
fi

echo "==> 拷贝资源与 Info.plist"
cp Info.plist "$APP_PATH/Contents/Info.plist"
cp Resources/rars Resources/unrar "$APP_PATH/Contents/Resources/"
if [[ -f Resources/rars-COPYING.txt ]]; then
    cp Resources/rars-COPYING.txt "$APP_PATH/Contents/Resources/"
fi
cp Resources/AppIcon.icns "$APP_PATH/Contents/Resources/"
# rar（RARLAB 试用版）不随仓库分发；若使用者自行放了进来则一并打包
if [[ -f Resources/rar ]]; then
    cp Resources/rar "$APP_PATH/Contents/Resources/"
else
    echo "    （未找到 Resources/rar，将只使用开源引擎 rars 压缩）"
fi
if [[ -f Resources/RARLAB-LICENSE.txt ]]; then
    cp Resources/RARLAB-LICENSE.txt "$APP_PATH/Contents/Resources/"
fi

chmod +x "$APP_PATH/Contents/MacOS/$EXECUTABLE" \
         "$APP_PATH/Contents/Resources/rar" \
         "$APP_PATH/Contents/Resources/unrar"

echo "==> 清除下载隔离属性"
xattr -dr com.apple.quarantine "$APP_PATH" 2>/dev/null || true

echo "==> ad-hoc 签名（本地自用，不启用 App Sandbox）"
codesign --force --deep --sign - "$APP_PATH" 2>/dev/null || {
    echo "    签名失败（不影响本机使用，继续）"
}

echo "==> 向 LaunchServices 注册 .rar 文件关联"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
if [[ -x "$LSREGISTER" ]]; then
    "$LSREGISTER" -f "$PWD/$APP_PATH" > /dev/null 2>&1 || true
fi

echo
echo "==> 构建完成：$PWD/$APP_PATH"
echo "    版本信息："
"$APP_PATH/Contents/Resources/rar" 2>&1 | head -2 | sed 's/^/      /'
"$APP_PATH/Contents/Resources/unrar" 2>&1 | head -2 | sed 's/^/      /'
echo
echo "    打开方式：open \"$PWD/$APP_PATH\""
echo "    若提示「无法验证开发者」，去 系统设置 → 隐私与安全性 点「仍要打开」，"
echo "    或在终端执行：xattr -dr com.apple.quarantine \"$PWD/$APP_PATH\""
