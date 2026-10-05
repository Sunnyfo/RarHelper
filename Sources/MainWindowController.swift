import AppKit
import UniformTypeIdentifiers

// MARK: - 支持拖放的容器视图

/// 可以接收文件拖放的容器视图。
///
/// - `onDrop`：拖入文件后回调（已在主线程）。
/// - `filter`：可选的过滤器，用来限定只接受某种类型（例如解压区只接受 .rar）。
/// - `hint`：底部的灰字提示。
final class DropZoneView: NSView {

    var onDrop: (([URL]) -> Void)?
    var filter: ((URL) -> Bool)?

    var hint: String = "" {
        didSet { hintLabel.stringValue = hint }
    }

    private let hintLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([NSPasteboard.PasteboardType.fileURL])
        hintLabel.alignment = .center
        hintLabel.textColor = .tertiaryLabelColor
        hintLabel.font = NSFont.systemFont(ofSize: 11)
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hintLabel)
        NSLayoutConstraint.activate([
            hintLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            hintLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            hintLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("不支持从 xib 加载")
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        return droppedURLs(from: sender).isEmpty ? [] : .copy
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        return !droppedURLs(from: sender).isEmpty
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = droppedURLs(from: sender)
        guard !urls.isEmpty else { return false }
        onDrop?(urls)
        return true
    }

    private func droppedURLs(from sender: NSDraggingInfo) -> [URL] {
        let objects = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: nil) ?? []
        let urls = objects.compactMap { $0 as? URL }
        if let filter = filter { return urls.filter(filter) }
        return urls
    }
}

// MARK: - 主窗口

/// 主窗口控制器：上半部分是「压缩 / 解压」切换区，下半部分是共享的进度条与日志。
final class MainWindowController: NSWindowController {

    private enum Mode: Int {
        case compress = 0
        case extract = 1
    }

    // MARK: 压缩区

    private var sources: [String] = []
    private let compressZone = DropZoneView(frame: .zero)
    private let sourceTable = NSTableView(frame: .zero)
    private let outputField = NSTextField(frame: .zero)
    private let passwordField = NSSecureTextField(frame: .zero)
    private let confirmField = NSSecureTextField(frame: .zero)
    private let encryptNamesCheck = NSButton(checkboxWithTitle: "同时加密文件名（更安全，但忘记密码将无法恢复）",
                                             target: nil, action: nil)
    private let compressButton = NSButton(title: "开始压缩", target: nil, action: nil)
    private let engineStatusLabel = NSTextField(labelWithString: "")
    private let installRarButton = NSButton(title: "安装 rar…", target: nil, action: nil)

    // MARK: 解压区

    private let extractZone = DropZoneView(frame: .zero)
    private let archiveField = NSTextField(frame: .zero)
    private let destField = NSTextField(frame: .zero)
    private let extractPasswordField = NSSecureTextField(frame: .zero)
    private let encryptionHint = NSTextField(labelWithString: "选择压缩包后会自动检测是否需要密码")
    private let extractButton = NSButton(title: "开始解压", target: nil, action: nil)
    private let trashAfterExtractCheck =
        NSButton(checkboxWithTitle: "解压完成后把原压缩包移到废纸篓", target: nil, action: nil)
    private let setDefaultButton = NSButton(title: "设为 .rar 默认打开方式", target: nil, action: nil)
    private let defaultStatusLabel = NSTextField(labelWithString: "")

    // MARK: 共享区

    private let segmented = NSSegmentedControl(labels: ["压缩", "解压"],
                                               trackingMode: .selectOne,
                                               target: nil, action: nil)
    private let container = NSView(frame: .zero)
    private let progress = NSProgressIndicator(frame: .zero)
    private let statusLabel = NSTextField(labelWithString: "就绪")
    private var logView: NSTextView!
    private var busy = false

    private var mode: Mode = .compress

    // MARK: 生命周期

    convenience init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 660, height: 640),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered,
                              defer: false)
        window.title = "RAR 助手"
        window.minSize = NSSize(width: 620, height: 560)
        window.center()
        self.init(window: window)
        buildUI()
    }

    // MARK: 界面搭建

    private func buildUI() {
        guard let contentView = window?.contentView else { return }

        segmented.target = self
        segmented.action = #selector(switchMode(_:))
        segmented.selectedSegment = 0
        segmented.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(segmented)

        container.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(container)

        buildCompressZone()
        buildExtractZone()

        progress.translatesAutoresizingMaskIntoConstraints = false
        progress.style = .bar
        progress.isIndeterminate = false
        progress.minValue = 0
        progress.maxValue = 100
        progress.doubleValue = 0
        contentView.addSubview(progress)

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = NSFont.systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        contentView.addSubview(statusLabel)

        let scrollView = NSScrollView(frame: .zero)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        let textView = NSTextView(frame: .zero)
        textView.isEditable = false
        textView.isRichText = false
        textView.font = NSFont.userFixedPitchFont(ofSize: 11) ?? NSFont.systemFont(ofSize: 11)
        textView.autoresizingMask = [.width]
        scrollView.documentView = textView
        logView = textView
        contentView.addSubview(scrollView)

        NSLayoutConstraint.activate([
            segmented.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 14),
            segmented.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),

            container.topAnchor.constraint(equalTo: segmented.bottomAnchor, constant: 12),
            container.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            container.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

            statusLabel.topAnchor.constraint(equalTo: container.bottomAnchor, constant: 10),
            statusLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 18),
            statusLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -18),

            progress.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 6),
            progress.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 18),
            progress.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -18),

            scrollView.topAnchor.constraint(equalTo: progress.bottomAnchor, constant: 10),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 18),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -18),
            scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
            scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 140)
        ])

        extractZone.isHidden = true
        refreshCompressionEngineStatus()
    }

    /// 检查压缩引擎（rars / rar）是否就绪，并更新压缩页底部的状态提示。
    private func refreshCompressionEngineStatus() {
        if RarEngine.shared.isCompressionAvailable() {
            engineStatusLabel.stringValue = "压缩引擎：\(RarEngine.shared.compressionEngineName)"
                + "　解压引擎：\(RarEngine.shared.extractionEngineName)"
            engineStatusLabel.textColor = .secondaryLabelColor
            installRarButton.isHidden = true
        } else {
            engineStatusLabel.stringValue = "未找到可用的压缩引擎，压缩不可用（解压不受影响）"
            engineStatusLabel.textColor = .systemOrange
            installRarButton.isHidden = false
        }
    }

    /// 引导用户自行下载安装 RARLAB 官方 rar。
    ///
    /// 本仓库不附带、也不代为分发该二进制——RARLAB EULA 第 3b 条禁止把未注册试用版
    /// 打包进其它软件分发。解压用的 unrar 是 freeware，允许自由分发，故已在仓库内。
    @objc private func showInstallRarGuide(_ sender: NSButton) {
        #if arch(arm64)
        let packageName = "rarmacos-arm-723.tar.gz"
        let archName = "Apple Silicon"
        #else
        let packageName = "rarmacos-x64-723.tar.gz"
        let archName = "Intel"
        #endif
        let resourcesPath = (Bundle.main.bundlePath as NSString)
            .appendingPathComponent("Contents/Resources")
        let command = """
        cd "\(resourcesPath)"
        curl -L -o rar.tar.gz https://www.rarlab.com/rar/\(packageName)
        tar -xzf rar.tar.gz && mv rar/rar . && chmod +x rar && rm -rf rar rar.tar.gz
        """
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "安装 rar（\(archName)）"
        alert.informativeText = """
        rar 是 RARLAB 的试用版，按其许可不能随本应用一起分发，需要你自行下载一次。

        在终端粘贴执行下面三行，执行完重新打开本应用即可压缩：
        \(command)

        商业用途请向 RARLAB 购买许可：https://www.rarlab.com
        """
        alert.addButton(withTitle: "复制命令")
        alert.addButton(withTitle: "打开下载页")
        alert.addButton(withTitle: "关闭")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(command, forType: .string)
        case .alertSecondButtonReturn:
            if let url = URL(string: "https://www.rarlab.com/download.htm") {
                NSWorkspace.shared.open(url)
            }
        default:
            break
        }
    }

    private func buildCompressZone() {
        compressZone.translatesAutoresizingMaskIntoConstraints = false
        compressZone.hint = "把文件或文件夹拖到这里即可加入列表"
        compressZone.onDrop = { [weak self] urls in
            self?.addSources(urls.map { $0.path })
        }
        container.addSubview(compressZone)
        NSLayoutConstraint.activate([
            compressZone.topAnchor.constraint(equalTo: container.topAnchor),
            compressZone.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            compressZone.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            compressZone.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        let title = NSTextField(labelWithString: "要压缩的文件 / 文件夹")
        title.font = NSFont.boldSystemFont(ofSize: 12)
        title.translatesAutoresizingMaskIntoConstraints = false
        compressZone.addSubview(title)

        let addFiles = NSButton(title: "添加文件…", target: self, action: #selector(addFiles(_:)))
        let addFolder = NSButton(title: "添加文件夹…", target: self, action: #selector(addFolder(_:)))
        let clear = NSButton(title: "清空", target: self, action: #selector(clearSources(_:)))
        for button in [addFiles, addFolder, clear] {
            button.translatesAutoresizingMaskIntoConstraints = false
            button.bezelStyle = .rounded
            compressZone.addSubview(button)
        }

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("path"))
        column.title = "路径"
        sourceTable.addTableColumn(column)
        sourceTable.headerView = nil
        sourceTable.dataSource = self
        sourceTable.delegate = self
        sourceTable.rowHeight = 22
        let tableScroll = NSScrollView(frame: .zero)
        tableScroll.translatesAutoresizingMaskIntoConstraints = false
        tableScroll.hasVerticalScroller = true
        tableScroll.borderType = .bezelBorder
        tableScroll.documentView = sourceTable
        compressZone.addSubview(tableScroll)

        let outputLabel = NSTextField(labelWithString: "输出为：")
        let pwdLabel = NSTextField(labelWithString: "密码：")
        let confirmLabel = NSTextField(labelWithString: "确认密码：")
        for label in [outputLabel, pwdLabel, confirmLabel] {
            label.translatesAutoresizingMaskIntoConstraints = false
            label.alignment = .right
            compressZone.addSubview(label)
        }

        outputField.translatesAutoresizingMaskIntoConstraints = false
        outputField.placeholderString = "选择 .rar 的保存位置"
        compressZone.addSubview(outputField)

        let chooseOutput = NSButton(title: "选择…", target: self, action: #selector(chooseOutput(_:)))
        chooseOutput.translatesAutoresizingMaskIntoConstraints = false
        chooseOutput.bezelStyle = .rounded
        compressZone.addSubview(chooseOutput)

        passwordField.translatesAutoresizingMaskIntoConstraints = false
        passwordField.placeholderString = "留空表示不加密"
        compressZone.addSubview(passwordField)

        confirmField.translatesAutoresizingMaskIntoConstraints = false
        confirmField.placeholderString = "再输入一次"
        compressZone.addSubview(confirmField)

        encryptNamesCheck.translatesAutoresizingMaskIntoConstraints = false
        compressZone.addSubview(encryptNamesCheck)

        compressButton.translatesAutoresizingMaskIntoConstraints = false
        compressButton.bezelStyle = .rounded
        compressButton.target = self
        compressButton.action = #selector(runCompress(_:))
        compressButton.font = NSFont.boldSystemFont(ofSize: 13)
        compressZone.addSubview(compressButton)

        engineStatusLabel.translatesAutoresizingMaskIntoConstraints = false
        engineStatusLabel.font = NSFont.systemFont(ofSize: 11)
        engineStatusLabel.lineBreakMode = .byWordWrapping
        compressZone.addSubview(engineStatusLabel)

        installRarButton.translatesAutoresizingMaskIntoConstraints = false
        installRarButton.bezelStyle = .rounded
        installRarButton.font = NSFont.systemFont(ofSize: 11)
        installRarButton.target = self
        installRarButton.action = #selector(showInstallRarGuide(_:))
        compressZone.addSubview(installRarButton)

        let passwordNote = NSTextField(labelWithString: "使用 RAR5 格式，加密强度 AES-256")
        passwordNote.translatesAutoresizingMaskIntoConstraints = false
        passwordNote.font = NSFont.systemFont(ofSize: 11)
        passwordNote.textColor = .secondaryLabelColor
        compressZone.addSubview(passwordNote)

        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: compressZone.topAnchor, constant: 4),
            title.leadingAnchor.constraint(equalTo: compressZone.leadingAnchor, constant: 2),

            addFiles.topAnchor.constraint(equalTo: compressZone.topAnchor, constant: 0),
            addFiles.trailingAnchor.constraint(equalTo: addFolder.leadingAnchor, constant: -8),
            addFolder.topAnchor.constraint(equalTo: addFiles.topAnchor),
            addFolder.trailingAnchor.constraint(equalTo: clear.leadingAnchor, constant: -8),
            clear.topAnchor.constraint(equalTo: addFiles.topAnchor),
            clear.trailingAnchor.constraint(equalTo: compressZone.trailingAnchor, constant: 0),

            tableScroll.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 8),
            tableScroll.leadingAnchor.constraint(equalTo: compressZone.leadingAnchor),
            tableScroll.trailingAnchor.constraint(equalTo: compressZone.trailingAnchor),
            tableScroll.heightAnchor.constraint(equalToConstant: 130),

            outputLabel.topAnchor.constraint(equalTo: tableScroll.bottomAnchor, constant: 14),
            outputLabel.leadingAnchor.constraint(equalTo: compressZone.leadingAnchor),
            outputLabel.widthAnchor.constraint(equalToConstant: 78),

            outputField.centerYAnchor.constraint(equalTo: outputLabel.centerYAnchor),
            outputField.leadingAnchor.constraint(equalTo: outputLabel.trailingAnchor, constant: 8),
            outputField.trailingAnchor.constraint(equalTo: chooseOutput.leadingAnchor, constant: -8),

            chooseOutput.centerYAnchor.constraint(equalTo: outputLabel.centerYAnchor),
            chooseOutput.trailingAnchor.constraint(equalTo: compressZone.trailingAnchor),
            chooseOutput.widthAnchor.constraint(equalToConstant: 70),

            pwdLabel.topAnchor.constraint(equalTo: outputLabel.bottomAnchor, constant: 14),
            pwdLabel.leadingAnchor.constraint(equalTo: compressZone.leadingAnchor),
            pwdLabel.widthAnchor.constraint(equalToConstant: 78),

            passwordField.centerYAnchor.constraint(equalTo: pwdLabel.centerYAnchor),
            passwordField.leadingAnchor.constraint(equalTo: pwdLabel.trailingAnchor, constant: 8),
            passwordField.trailingAnchor.constraint(equalTo: compressZone.trailingAnchor),

            confirmLabel.topAnchor.constraint(equalTo: pwdLabel.bottomAnchor, constant: 12),
            confirmLabel.leadingAnchor.constraint(equalTo: compressZone.leadingAnchor),
            confirmLabel.widthAnchor.constraint(equalToConstant: 78),

            confirmField.centerYAnchor.constraint(equalTo: confirmLabel.centerYAnchor),
            confirmField.leadingAnchor.constraint(equalTo: confirmLabel.trailingAnchor, constant: 8),
            confirmField.trailingAnchor.constraint(equalTo: compressZone.trailingAnchor),

            encryptNamesCheck.topAnchor.constraint(equalTo: confirmLabel.bottomAnchor, constant: 12),
            encryptNamesCheck.leadingAnchor.constraint(equalTo: confirmField.leadingAnchor),

            passwordNote.topAnchor.constraint(equalTo: encryptNamesCheck.bottomAnchor, constant: 4),
            passwordNote.leadingAnchor.constraint(equalTo: confirmField.leadingAnchor),

            compressButton.topAnchor.constraint(equalTo: passwordNote.bottomAnchor, constant: 14),
            compressButton.centerXAnchor.constraint(equalTo: compressZone.centerXAnchor),
            compressButton.widthAnchor.constraint(equalToConstant: 160),

            engineStatusLabel.topAnchor.constraint(equalTo: compressButton.bottomAnchor, constant: 14),
            engineStatusLabel.leadingAnchor.constraint(equalTo: compressZone.leadingAnchor, constant: 2),
            engineStatusLabel.trailingAnchor.constraint(equalTo: installRarButton.leadingAnchor, constant: -8),

            installRarButton.centerYAnchor.constraint(equalTo: engineStatusLabel.centerYAnchor),
            installRarButton.trailingAnchor.constraint(equalTo: compressZone.trailingAnchor),

            engineStatusLabel.bottomAnchor.constraint(lessThanOrEqualTo: compressZone.bottomAnchor, constant: -20)
        ])
    }

    private func buildExtractZone() {
        extractZone.translatesAutoresizingMaskIntoConstraints = false
        extractZone.hint = "把 .rar 文件拖到这里"
        extractZone.filter = { $0.pathExtension.lowercased() == "rar" }
        extractZone.onDrop = { [weak self] urls in
            guard let url = urls.first else { return }
            self?.selectArchive(url.path)
        }
        container.addSubview(extractZone)
        NSLayoutConstraint.activate([
            extractZone.topAnchor.constraint(equalTo: container.topAnchor),
            extractZone.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            extractZone.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            extractZone.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        let archiveLabel = NSTextField(labelWithString: "压缩包：")
        let destTitleLabel = NSTextField(labelWithString: "解压到：")
        let pwdTitleLabel = NSTextField(labelWithString: "密码：")
        for label in [archiveLabel, destTitleLabel, pwdTitleLabel] {
            label.translatesAutoresizingMaskIntoConstraints = false
            label.alignment = .right
            extractZone.addSubview(label)
        }

        archiveField.translatesAutoresizingMaskIntoConstraints = false
        archiveField.placeholderString = "选择 .rar 文件"
        extractZone.addSubview(archiveField)

        destField.translatesAutoresizingMaskIntoConstraints = false
        destField.placeholderString = "选择解压到的文件夹"
        extractZone.addSubview(destField)

        extractPasswordField.translatesAutoresizingMaskIntoConstraints = false
        extractPasswordField.placeholderString = "压缩包未加密时留空"
        extractZone.addSubview(extractPasswordField)

        chooseArchiveButton.translatesAutoresizingMaskIntoConstraints = false
        chooseArchiveButton.title = "选择…"
        chooseArchiveButton.bezelStyle = .rounded
        chooseArchiveButton.target = self
        chooseArchiveButton.action = #selector(chooseArchive(_:))
        extractZone.addSubview(chooseArchiveButton)

        chooseDestButton.translatesAutoresizingMaskIntoConstraints = false
        chooseDestButton.title = "选择…"
        chooseDestButton.bezelStyle = .rounded
        chooseDestButton.target = self
        chooseDestButton.action = #selector(chooseDestination(_:))
        extractZone.addSubview(chooseDestButton)

        encryptionHint.translatesAutoresizingMaskIntoConstraints = false
        encryptionHint.font = NSFont.systemFont(ofSize: 11)
        encryptionHint.textColor = .secondaryLabelColor
        extractZone.addSubview(encryptionHint)

        extractButton.translatesAutoresizingMaskIntoConstraints = false
        extractButton.bezelStyle = .rounded
        extractButton.target = self
        extractButton.action = #selector(runExtract(_:))
        extractButton.font = NSFont.boldSystemFont(ofSize: 13)
        extractZone.addSubview(extractButton)

        trashAfterExtractCheck.translatesAutoresizingMaskIntoConstraints = false
        extractZone.addSubview(trashAfterExtractCheck)

        setDefaultButton.translatesAutoresizingMaskIntoConstraints = false
        setDefaultButton.bezelStyle = .rounded
        setDefaultButton.target = self
        setDefaultButton.action = #selector(setAsDefaultApp(_:))
        setDefaultButton.font = NSFont.systemFont(ofSize: 11)
        extractZone.addSubview(setDefaultButton)

        defaultStatusLabel.translatesAutoresizingMaskIntoConstraints = false
        defaultStatusLabel.font = NSFont.systemFont(ofSize: 11)
        defaultStatusLabel.textColor = .secondaryLabelColor
        defaultStatusLabel.alignment = .center
        extractZone.addSubview(defaultStatusLabel)

        NSLayoutConstraint.activate([
            archiveLabel.topAnchor.constraint(equalTo: extractZone.topAnchor, constant: 12),
            archiveLabel.leadingAnchor.constraint(equalTo: extractZone.leadingAnchor),
            archiveLabel.widthAnchor.constraint(equalToConstant: 78),

            archiveField.centerYAnchor.constraint(equalTo: archiveLabel.centerYAnchor),
            archiveField.leadingAnchor.constraint(equalTo: archiveLabel.trailingAnchor, constant: 8),
            archiveField.trailingAnchor.constraint(equalTo: chooseArchiveButton.leadingAnchor, constant: -8),

            chooseArchiveButton.centerYAnchor.constraint(equalTo: archiveLabel.centerYAnchor),
            chooseArchiveButton.trailingAnchor.constraint(equalTo: extractZone.trailingAnchor),
            chooseArchiveButton.widthAnchor.constraint(equalToConstant: 70),

            destTitleLabel.topAnchor.constraint(equalTo: archiveLabel.bottomAnchor, constant: 14),
            destTitleLabel.leadingAnchor.constraint(equalTo: extractZone.leadingAnchor),
            destTitleLabel.widthAnchor.constraint(equalToConstant: 78),

            destField.centerYAnchor.constraint(equalTo: destTitleLabel.centerYAnchor),
            destField.leadingAnchor.constraint(equalTo: destTitleLabel.trailingAnchor, constant: 8),
            destField.trailingAnchor.constraint(equalTo: chooseDestButton.leadingAnchor, constant: -8),

            chooseDestButton.centerYAnchor.constraint(equalTo: destTitleLabel.centerYAnchor),
            chooseDestButton.trailingAnchor.constraint(equalTo: extractZone.trailingAnchor),
            chooseDestButton.widthAnchor.constraint(equalToConstant: 70),

            pwdTitleLabel.topAnchor.constraint(equalTo: destTitleLabel.bottomAnchor, constant: 14),
            pwdTitleLabel.leadingAnchor.constraint(equalTo: extractZone.leadingAnchor),
            pwdTitleLabel.widthAnchor.constraint(equalToConstant: 78),

            extractPasswordField.centerYAnchor.constraint(equalTo: pwdTitleLabel.centerYAnchor),
            extractPasswordField.leadingAnchor.constraint(equalTo: pwdTitleLabel.trailingAnchor, constant: 8),
            extractPasswordField.widthAnchor.constraint(equalToConstant: 260),

            encryptionHint.centerYAnchor.constraint(equalTo: pwdTitleLabel.centerYAnchor),
            encryptionHint.leadingAnchor.constraint(equalTo: extractPasswordField.trailingAnchor, constant: 10),
            encryptionHint.trailingAnchor.constraint(equalTo: extractZone.trailingAnchor),

            trashAfterExtractCheck.topAnchor.constraint(equalTo: pwdTitleLabel.bottomAnchor, constant: 22),
            trashAfterExtractCheck.leadingAnchor.constraint(equalTo: extractPasswordField.leadingAnchor),

            extractButton.topAnchor.constraint(equalTo: trashAfterExtractCheck.bottomAnchor, constant: 18),
            extractButton.centerXAnchor.constraint(equalTo: extractZone.centerXAnchor),
            extractButton.widthAnchor.constraint(equalToConstant: 160),

            setDefaultButton.topAnchor.constraint(equalTo: extractButton.bottomAnchor, constant: 16),
            setDefaultButton.centerXAnchor.constraint(equalTo: extractZone.centerXAnchor),

            defaultStatusLabel.topAnchor.constraint(equalTo: setDefaultButton.bottomAnchor, constant: 6),
            defaultStatusLabel.leadingAnchor.constraint(equalTo: extractZone.leadingAnchor, constant: 8),
            defaultStatusLabel.trailingAnchor.constraint(equalTo: extractZone.trailingAnchor, constant: -8),
            defaultStatusLabel.bottomAnchor.constraint(lessThanOrEqualTo: extractZone.bottomAnchor, constant: -20)
        ])
    }

    private let chooseArchiveButton = NSButton(title: "选择…", target: nil, action: nil)
    private let chooseDestButton = NSButton(title: "选择…", target: nil, action: nil)

    // MARK: 模式切换

    @objc private func switchMode(_ sender: NSSegmentedControl) {
        mode = Mode(rawValue: sender.selectedSegment) ?? .compress
        let isCompress = mode == .compress
        compressZone.isHidden = !isCompress
        extractZone.isHidden = isCompress
    }

    // MARK: 压缩区交互

    @objc private func addFiles(_ sender: NSButton) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.prompt = "添加"
        guard panel.runModal() == .OK else { return }
        addSources(panel.urls.map { $0.path })
    }

    @objc private func addFolder(_ sender: NSButton) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "添加"
        guard panel.runModal() == .OK else { return }
        addSources(panel.urls.map { $0.path })
    }

    @objc private func clearSources(_ sender: NSButton) {
        sources.removeAll()
        sourceTable.reloadData()
        outputField.stringValue = ""
    }

    @objc private func chooseOutput(_ sender: NSButton) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = defaultArchiveName()
        if let rarType = UTType(filenameExtension: "rar") {
            panel.allowedContentTypes = [rarType]
        }
        if !outputField.stringValue.isEmpty {
            let ns = outputField.stringValue as NSString
            panel.directoryURL = URL(fileURLWithPath: ns.deletingLastPathComponent)
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        outputField.stringValue = url.path
    }

    @objc private func runCompress(_ sender: NSButton) {
        guard !busy else { return }
        guard !sources.isEmpty else {
            showAlert(title: "还没有选择内容", message: "请先添加要压缩的文件或文件夹。")
            return
        }

        let output = outputField.stringValue.isEmpty ? suggestedOutputPath() : outputField.stringValue
        let password = passwordField.stringValue

        if !password.isEmpty && password != confirmField.stringValue {
            showAlert(title: "两次密码不一致", message: "请重新输入，或把两个密码框都留空表示不加密。")
            return
        }

        let encryptNames = encryptNamesCheck.state == .on && !password.isEmpty
        setBusy(true, status: "正在压缩…")
        logView.string = ""
        progress.doubleValue = 0

        RarEngine.shared.compress(sources: sources,
                                 output: output,
                                 password: password,
                                 encryptNames: encryptNames,
                                 progress: { [weak self] value in
                                     self?.progress.doubleValue = value
                                 },
                                 log: { [weak self] line in
                                     self?.appendLog(line)
                                 },
                                 completion: { [weak self] result in
                                     self?.setBusy(false, status: "就绪")
                                     switch result {
                                     case .success:
                                         self?.progress.doubleValue = 100
                                         self?.showAlert(title: "压缩完成",
                                                         message: "已生成：\n\(output)")
                                     case .failure(let error):
                                         self?.showAlert(title: error.title, message: error.detail, style: .warning)
                                     }
                                 })
    }

    // MARK: 解压区交互

    @objc private func chooseArchive(_ sender: NSButton) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "选择"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        selectArchive(url.path)
    }

    @objc private func chooseDestination(_ sender: NSButton) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "选择"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        destField.stringValue = url.path
    }

    @objc private func runExtract(_ sender: NSButton) {
        guard !busy else { return }
        let archive = archiveField.stringValue
        guard !archive.isEmpty else {
            showAlert(title: "还没有选择压缩包", message: "请先选择或拖入一个 .rar 文件。")
            return
        }
        let destination = destField.stringValue.isEmpty ? suggestedExtractPath(for: archive) : destField.stringValue
        let password = extractPasswordField.stringValue

        setBusy(true, status: "正在解压…")
        logView.string = ""
        progress.doubleValue = 0

        RarEngine.shared.extract(archive: archive,
                                to: destination,
                                password: password,
                                progress: { [weak self] value in
                                    self?.progress.doubleValue = value
                                },
                                log: { [weak self] line in
                                    self?.appendLog(line)
                                },
                                completion: { [weak self] result in
                                    self?.setBusy(false, status: "就绪")
                                    switch result {
                                    case .success:
                                        self?.progress.doubleValue = 100
                                        self?.trashArchiveIfNeeded(archive)
                                        var message = "已解压到：\n\(destination)"
                                        if self?.trashAfterExtractCheck.state == .on {
                                            message += "\n\n原压缩包已移到废纸篓。"
                                        }
                                        self?.showAlert(title: "解压完成", message: message)
                                    case .failure(let error):
                                        self?.showAlert(title: error.title, message: error.detail, style: .warning)
                                    }
                                })
    }

    // MARK: 从系统打开（双击 .rar / 打开方式 / 拖到 Dock 图标）

    /// 处理系统传进来的文件路径：切到解压页并预填信息。
    ///
    /// - Parameter path: .rar 文件的绝对路径。
    func handleOpenedFile(_ path: String) {
        guard (path as NSString).pathExtension.lowercased() == "rar" else { return }
        segmented.selectedSegment = 1
        mode = .extract
        compressZone.isHidden = true
        extractZone.isHidden = false
        selectArchive(path)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func setAsDefaultApp(_ sender: NSButton) {
        defaultStatusLabel.textColor = .secondaryLabelColor
        defaultStatusLabel.stringValue = "正在向系统申请…"
        guard let rarType = UTType(filenameExtension: "rar") else {
            defaultStatusLabel.stringValue = "系统未识别 .rar 类型，无法设置"
            return
        }
        NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL,
                                                 toOpen: rarType) { [weak self] error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let error = error {
                    self.defaultStatusLabel.stringValue = "设置未生效，可在访达中手动设置"
                    self.showAlert(
                        title: "设置未生效",
                        message: "系统返回：\(error.localizedDescription)\n\n"
                            + "手动设置：在访达中右键任意 .rar → 显示简介 → 打开方式 → 选「RAR 助手」→ 点「全部更改…」。")
                } else {
                    self.defaultStatusLabel.stringValue = "已把 RAR 助手设为 .rar 的默认打开方式"
                    self.defaultStatusLabel.textColor = .systemGreen
                }
            }
        }
    }

    // MARK: 辅助方法

    private func addSources(_ paths: [String]) {
        for path in paths where !sources.contains(path) {
            sources.append(path)
        }
        sourceTable.reloadData()
        if outputField.stringValue.isEmpty || !sources.isEmpty {
            outputField.stringValue = suggestedOutputPath()
        }
    }

    private func selectArchive(_ path: String) {
        archiveField.stringValue = path
        destField.stringValue = suggestedExtractPath(for: path)
        encryptionHint.stringValue = "正在检测…"
        // isEncrypted 会同步拉起子进程，放到后台队列避免卡住界面
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let encrypted = RarEngine.shared.isEncrypted(archive: path)
            DispatchQueue.main.async {
                guard let self = self, self.archiveField.stringValue == path else { return }
                if encrypted {
                    self.encryptionHint.stringValue = "该压缩包已加密，请输入密码"
                    self.encryptionHint.textColor = .systemRed
                    self.extractPasswordField.isEnabled = true
                } else {
                    self.encryptionHint.stringValue = "该压缩包未加密，密码可留空"
                    self.encryptionHint.textColor = .secondaryLabelColor
                    self.extractPasswordField.isEnabled = true
                }
            }
        }
    }

    private func defaultArchiveName() -> String {
        guard let first = sources.first else { return "归档.rar" }
        let ns = first as NSString
        if sources.count == 1 {
            return (ns.lastPathComponent as NSString).deletingPathExtension + ".rar"
        }
        return "归档.rar"
    }

    private func suggestedOutputPath() -> String {
        guard let first = sources.first else { return "" }
        let ns = first as NSString
        return ns.deletingLastPathComponent + "/" + defaultArchiveName()
    }

    private func suggestedExtractPath(for archive: String) -> String {
        let ns = archive as NSString
        let directory = ns.deletingLastPathComponent
        let name = (ns.lastPathComponent as NSString).deletingPathExtension
        return directory + "/" + name
    }

    private func setBusy(_ value: Bool, status: String) {
        busy = value
        statusLabel.stringValue = status
        compressButton.isEnabled = !value
        extractButton.isEnabled = !value
        if value {
            progress.startAnimation(nil)
        } else {
            progress.stopAnimation(nil)
        }
    }

    /// 解压成功后，按勾选情况把原压缩包移到废纸篓（可恢复，不是彻底删除）。
    ///
    /// - Parameter archive: 原压缩包路径。
    private func trashArchiveIfNeeded(_ archive: String) {
        guard trashAfterExtractCheck.state == .on else { return }
        var resultingURL: NSURL?
        do {
            try FileManager.default.trashItem(at: URL(fileURLWithPath: archive),
                                              resultingItemURL: &resultingURL)
            appendLog("已把原压缩包移到废纸篓：\(archive)")
        } catch {
            appendLog("移到废纸篓失败：\(error.localizedDescription)")
        }
    }

    private func appendLog(_ line: String) {
        logView.textStorage?.append(NSAttributedString(string: line + "\n"))
        logView.scrollToEndOfDocument(nil)
    }

    private func showAlert(title: String, message: String, style: NSAlert.Style = .informational) {
        let alert = NSAlert()
        alert.alertStyle = style
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "好")
        if let window = window {
            alert.beginSheetModal(for: window, completionHandler: nil)
        } else {
            alert.runModal()
        }
    }
}

// MARK: - 源列表数据源

extension MainWindowController: NSTableViewDataSource, NSTableViewDelegate {

    func numberOfRows(in tableView: NSTableView) -> Int {
        return sources.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("pathCell")
        let cell: NSTableCellView
        if let reused = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView {
            cell = reused
        } else {
            let created = NSTableCellView()
            created.identifier = identifier
            let textField = NSTextField(labelWithString: "")
            textField.translatesAutoresizingMaskIntoConstraints = false
            textField.lineBreakMode = .byTruncatingMiddle
            textField.font = NSFont.systemFont(ofSize: 12)
            created.addSubview(textField)
            created.textField = textField
            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: created.leadingAnchor, constant: 4),
                textField.trailingAnchor.constraint(equalTo: created.trailingAnchor, constant: -4),
                textField.centerYAnchor.constraint(equalTo: created.centerYAnchor)
            ])
            cell = created
        }
        cell.textField?.stringValue = sources[row]
        return cell
    }
}
