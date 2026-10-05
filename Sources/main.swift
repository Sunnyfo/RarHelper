import AppKit

/// 应用委托：负责创建菜单、拉起主窗口。
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var mainWindow: MainWindowController?
    /// 双击 .rar 打开本应用时，窗口还没创建完，先把路径存下来
    private var pendingFile: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        buildMainMenu()

        let controller = MainWindowController()
        controller.showWindow(nil)
        mainWindow = controller

        // 启动时就带着文件（例如双击某个 .rar、或在访达里“打开方式”选择本应用）
        if let file = pendingFile {
            pendingFile = nil
            controller.handleOpenedFile(file)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    /// 双击 .rar 或把 .rar 拖到 Dock 图标上时，系统会回调这里。
    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        if let window = mainWindow {
            window.handleOpenedFile(filename)
        } else {
            pendingFile = filename
        }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

    /// 纯代码构建菜单栏。
    ///
    /// 没有 xib / storyboard，菜单必须手写，否则 ⌘Q、⌘W、⌘C 等系统快捷键全部失效。
    private func buildMainMenu() {
        let mainMenu = NSMenu()

        // 应用菜单（关于 / 退出）
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        let aboutItem = NSMenuItem(title: "关于 RAR 助手",
                                   action: #selector(showAbout(_:)),
                                   keyEquivalent: "")
        aboutItem.target = self
        appMenu.addItem(aboutItem)
        appMenu.addItem(NSMenuItem.separator())
        let quitItem = NSMenuItem(title: "退出 RAR 助手",
                                  action: #selector(NSApplication.terminate(_:)),
                                  keyEquivalent: "q")
        appMenu.addItem(quitItem)
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // 编辑菜单：让文本框的撤销 / 复制 / 粘贴 / 全选快捷键可用
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "编辑")
        let editItems: [(String, String)] = [
            ("撤销", "z"), ("重做", "Z"), ("剪切", "x"), ("拷贝", "c"),
            ("粘贴", "v"), ("全选", "a")
        ]
        for (title, key) in editItems {
            let selector = NSSelectorFromString(editorSelectorMap[title] ?? "")
            let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
            editMenu.addItem(item)
        }
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        // 窗口菜单：⌘W 关闭窗口、最小化
        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "窗口")
        let closeItem = NSMenuItem(title: "关闭",
                                   action: #selector(NSWindow.performClose(_:)),
                                   keyEquivalent: "w")
        windowMenu.addItem(closeItem)
        let miniItem = NSMenuItem(title: "最小化",
                                  action: #selector(NSWindow.performMiniaturize(_:)),
                                  keyEquivalent: "m")
        windowMenu.addItem(miniItem)
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        NSApp.mainMenu = mainMenu
    }

    /// 编辑菜单标题到标准 responder selector 的映射。
    private let editorSelectorMap: [String: String] = [
        "撤销": "undo:",
        "重做": "redo:",
        "剪切": "cut:",
        "拷贝": "copy:",
        "粘贴": "paste:",
        "全选": "selectAll:"
    ]

    @objc private func showAbout(_ sender: Any?) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "RAR 助手 1.0"
        alert.informativeText = """
        一个本地的 RAR 压缩 / 解压工具，支持 AES-256 密码加密。

        压缩与解压由 RARLAB 官方命令行工具驱动：
        • rar 7.23（试用版，商业用途需向 RARLAB 购买许可）
        • unrar 7.23（免费软件）

        所有操作均在本机完成，不会上传任何文件。
        """
        alert.addButton(withTitle: "好")
        alert.runModal()
    }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()
