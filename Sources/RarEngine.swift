import Foundation

// MARK: - 错误类型

/// RAR 引擎的错误类型，所有文案均为中文，可直接展示给用户。
///
/// 设计原则：
/// - `title` 是给用户的简短结论；
/// - `detail` 是可选的补充说明（含原始输出尾部，便于排查）。
enum RarError: Error {

    /// 找不到 rar / unrar 二进制
    case binaryMissing(name: String)
    /// 待压缩的源文件或文件夹不存在
    case sourceMissing(path: String)
    /// 压缩包不存在
    case archiveMissing(path: String)
    /// 输出目录不可写
    case notWritable(path: String)
    /// 密码错误
    case wrongPassword
    /// 压缩包里没有可解压的内容
    case noFilesToExtract
    /// 压缩包已加密但用户没有输入密码
    case encryptedButNoPassword
    /// 其它未知错误
    case unknown(detail: String)

    /// 简短结论（用于 NSAlert 标题）
    var title: String {
        switch self {
        case .binaryMissing(let name):
            return "缺少内置工具 \(name)"
        case .sourceMissing:
            return "源文件或文件夹不存在"
        case .archiveMissing:
            return "压缩包不存在"
        case .notWritable:
            return "目标位置没有写入权限"
        case .wrongPassword:
            return "密码错误"
        case .noFilesToExtract:
            return "压缩包中没有可解压的内容"
        case .encryptedButNoPassword:
            return "该压缩包已加密，请先输入密码"
        case .unknown:
            return "操作失败"
        }
    }

    /// 补充说明（用于 NSAlert 副标题）
    var detail: String {
        switch self {
        case .binaryMissing(let name):
            return "应用包内缺少 \(name) 可执行文件，请重新构建或重新安装 RAR 助手。"
        case .sourceMissing(let path):
            return "路径：\(path)\n该路径已不存在，请重新选择后再试。"
        case .archiveMissing(let path):
            return "路径：\(path)\n该文件不存在或不是有效的 RAR 压缩包。"
        case .notWritable(let path):
            return "路径：\(path)\n请换一个有写入权限的位置（例如“下载”或桌面）。"
        case .wrongPassword:
            return "rar / unrar 报告密码不正确。请确认密码后重试；如果压缩包是用“同时加密文件名”创建的，密码输错将无法读取任何内容。"
        case .noFilesToExtract:
            return "这个压缩包可能是空的，或者其中所有条目都被过滤掉了。"
        case .encryptedButNoPassword:
            return "检测到该压缩包带有密码保护，请在密码框中填写解压密码后再开始。"
        case .unknown(let detail):
            return detail
        }
    }
}

// MARK: - 输出清洗

/// 子进程输出收集器。
///
/// `rar` / `unrar` 会用 `\b`（退格）在同一行内反复覆盖进度输出，因此：
/// - 以 `\r` 或 `\n` 作为“一行结束”的标志；
/// - 行内出现的 `\b` 需要模拟退格（连同前一个字符一起删除）；
/// - 行尾未闭合的片段（当前进度行）单独回调给 `onPartial`，用来驱动进度条。
private final class OutputSink {

    /// 一整行结束时的回调（已清洗）
    var onLine: ((String) -> Void)?
    /// 当前未闭合片段的回调（已清洗），用于实时进度
    var onPartial: ((String) -> Void)?
    /// 是否解析进度百分比（stderr 不需要）
    var parsesProgress: Bool = true

    /// 累积的完整文本（清洗后，按行拼接）
    private(set) var text: String = ""

    private let lock: NSLock = NSLock()
    private var pending: String = ""

    /// 追加一段原始输出数据。
    ///
    /// - Parameter data: 子进程写入的原始字节。
    func append(_ data: Data) {
        guard !data.isEmpty else { return }
        let chunk = String(decoding: data, as: UTF8.self)
        lock.lock()
        pending += chunk
        lock.unlock()
        drain(final: false)
    }

    /// 子进程结束后调用，冲刷最后一段没有换行结尾的内容。
    func finish() {
        drain(final: true)
    }

    private func drain(final: Bool) {
        lock.lock()
        defer { lock.unlock() }

        // 按 \r / \n 切分出完整行
        while let index = pending.firstIndex(where: { $0 == "\n" || $0 == "\r" }) {
            let raw = String(pending[pending.startIndex..<index])
            pending = String(pending[pending.index(after: index)...])
            emit(RarEngine.clean(raw))
        }

        if final {
            if !pending.isEmpty {
                emit(RarEngine.clean(pending))
                pending = ""
            }
        } else if !pending.isEmpty {
            let cleanedLine = RarEngine.clean(pending)
            if !cleanedLine.isEmpty {
                if parsesProgress {
                    onPartial?(cleanedLine)
                }
            }
        }
    }

    private func emit(_ line: String) {
        guard !line.isEmpty else { return }
        if !text.isEmpty { text += "\n" }
        text += line
        onLine?(line)
    }
}

// MARK: - 引擎

/// RAR 压缩 / 解压引擎。
///
/// 内部封装 RARLAB 官方的 `rar` / `unrar` 命令行二进制：
/// - 压缩：`rar a [-p|-hp] -ep1 -ma5 <输出.rar> <源...>`
/// - 解压：`unrar x [-p] -y -o+ <文件.rar> <目标目录/>`
/// - 列目录：`unrar l <文件.rar>`（加密条目的行首带 `*`）
///
/// **安全约束**：密码一律通过 stdin 写入，**绝不**拼进命令行参数，避免被 `ps` 看到。
final class RarEngine {

    /// 进度回调，参数为 0...100 的百分比
    typealias ProgressHandler = (Double) -> Void
    /// 日志回调，参数为一整行已清洗的输出
    typealias LogHandler = (String) -> Void
    /// 完成回调，已经在主线程执行
    typealias Completion = (Result<String, RarError>) -> Void

    /// 全局共享实例
    static let shared: RarEngine = RarEngine()

    /// 后台工作队列，所有子进程都在该队列上执行
    private let workQueue: DispatchQueue = DispatchQueue(label: "com.local.rarhelper.engine", qos: .userInitiated)
    /// 用于从输出中抽取百分比的正则
    private let percentRegex: NSRegularExpression? =
        try? NSRegularExpression(pattern: "([0-9]{1,3})[ ]?%", options: [])
    /// 用于剔除 ANSI 转义序列的正则
    private let ansiRegex: NSRegularExpression? =
        try? NSRegularExpression(pattern: "\u{1B}\\[[0-9;?]*[A-Za-z]", options: [])

    private init() {}

    // MARK: 公开接口 —— 压缩

    /// 把一批文件 / 文件夹压缩成一个 RAR5 压缩包。
    ///
    /// - Parameters:
    ///   - sources: 源文件 / 文件夹的绝对路径列表。
    ///   - output: 输出的 .rar 绝对路径。
    ///   - password: 解压密码；空字符串表示不加密。
    ///   - encryptNames: 是否同时加密文件名（`-hp`）。仅当 `password` 非空时生效。
    ///   - progress: 进度回调（主线程）。
    ///   - log: 日志回调（主线程）。
    ///   - completion: 完成回调（主线程）。
    func compress(sources: [String],
                  output: String,
                  password: String,
                  encryptNames: Bool,
                  progress: ProgressHandler?,
                  log: LogHandler?,
                  completion: @escaping Completion) {
        guard let rarPath = locate("rar") else {
            completion(.failure(.binaryMissing(name: "rar")))
            return
        }

        workQueue.async {
            for source in sources where !FileManager.default.fileExists(atPath: source) {
                self.fail(.sourceMissing(path: source), completion: completion)
                return
            }
            let outputDir = (output as NSString).deletingLastPathComponent
            if !outputDir.isEmpty && !FileManager.default.isWritableFile(atPath: outputDir) {
                self.fail(.notWritable(path: outputDir), completion: completion)
                return
            }

            var arguments: [String] = ["a", "-y"]
            if !password.isEmpty {
                arguments.append(encryptNames ? "-hp" : "-p")
            }
            arguments += ["-ep1", "-ma5", output]
            arguments += sources

            let run = self.launch(executable: rarPath,
                                  arguments: arguments,
                                  password: password.isEmpty ? nil : password,
                                  progress: progress,
                                  log: log)
            let result = self.evaluate(status: run.status, output: run.output)
            DispatchQueue.main.async { completion(result) }
        }
    }

    // MARK: 公开接口 —— 解压

    /// 把一个 RAR 压缩包解压到指定目录。
    ///
    /// - Parameters:
    ///   - archive: .rar 压缩包绝对路径。
    ///   - destination: 目标目录绝对路径（结尾会自动补 `/`）。
    ///   - password: 解压密码；空字符串表示明文解压。
    ///   - progress: 进度回调（主线程）。
    ///   - log: 日志回调（主线程）。
    ///   - completion: 完成回调（主线程）。
    func extract(archive: String,
                 to destination: String,
                 password: String,
                 progress: ProgressHandler?,
                 log: LogHandler?,
                 completion: @escaping Completion) {
        guard let unrarPath = locate("unrar") else {
            completion(.failure(.binaryMissing(name: "unrar")))
            return
        }

        workQueue.async {
            guard FileManager.default.fileExists(atPath: archive) else {
                self.fail(.archiveMissing(path: archive), completion: completion)
                return
            }
            let run = self.launch(executable: unrarPath,
                                  arguments: ["x", password.isEmpty ? "-p-" : "-p", "-y", "-o+", archive,
                                              destination.hasSuffix("/") ? destination : destination + "/"],
                                  password: password.isEmpty ? nil : password,
                                  progress: progress,
                                  log: log)
            let result = self.evaluate(status: run.status, output: run.output)
            DispatchQueue.main.async { completion(result) }
        }
    }

    // MARK: 公开接口 —— 加密检测

    /// 判断压缩包是否包含加密条目。
    ///
    /// 判定规则：
    /// 1. 无密码执行 `unrar l`，如果直接失败，说明整包用了 `-hp`（文件名也被加密），视为已加密；
    /// 2. 成功时解析列表，只要有一行以 `*` 开头（形如 `*-rw-r--r--  6 ... src/b.txt`），即视为已加密。
    ///
    /// - Parameter archive: .rar 压缩包绝对路径。
    /// - Returns: 是否加密。
    func isEncrypted(archive: String) -> Bool {
        guard let unrarPath = locate("unrar") else { return false }
        guard FileManager.default.fileExists(atPath: archive) else { return false }
        let run = launch(executable: unrarPath,
                         arguments: ["l", "-y", archive],
                         password: nil,
                         progress: nil,
                         log: nil)
        if run.status != 0 {
            // 不带密码连目录都列不出来 —— 文件名被加密，或者文件损坏
            return true
        }
        for rawLine in run.output.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("*") else { continue }
            guard line.count > 1 else { continue }
            return true
        }
        return false
    }

    // MARK: 二进制定位

    /// 定位内置的 rar / unrar 二进制。
    ///
    /// 依次尝试：Bundle 资源目录 → `<app>/Contents/Resources` → 可执行文件同级目录 →
    /// 可执行文件上一级的 `Resources` → 项目 `Sources/../Resources`（开发期直跑可执行文件）。
    ///
    /// - Parameter name: `rar` 或 `unrar`。
    /// - Returns: 可执行文件路径，找不到时返回 nil。
    private func locate(_ name: String) -> String? {
        let fileManager = FileManager.default
        var candidates: [String] = []

        if let bundled = Bundle.main.path(forResource: name, ofType: nil) {
            candidates.append(bundled)
        }
        candidates.append(Bundle.main.bundlePath + "/Contents/Resources/" + name)

        if let executablePath = Bundle.main.executablePath {
            let executableDir = (executablePath as NSString).deletingLastPathComponent
            candidates.append(executableDir + "/" + name)
            candidates.append(executableDir + "/Resources/" + name)
            candidates.append(((executableDir as NSString).deletingLastPathComponent as NSString)
                .appendingPathComponent("Resources/" + name))
            candidates.append(((executableDir as NSString).deletingLastPathComponent as NSString)
                .deletingLastPathComponent + "/Resources/" + name)
        }
        candidates.append(fileManager.currentDirectoryPath + "/Resources/" + name)

        for candidate in candidates where fileManager.isExecutableFile(atPath: candidate) {
            return candidate
        }
        return nil
    }

    // MARK: 子进程执行

    /// 启动子进程并持续收集输出。
    ///
    /// - Parameters:
    ///   - executable: 二进制绝对路径。
    ///   - arguments: 参数列表。
    ///   - password: 需要写入 stdin 的密码（只写一次，写完立即关闭写端）。
    ///   - progress: 进度回调。
    ///   - log: 日志回调。
    /// - Returns: 退出码 + 清洗后的完整输出。
    private func launch(executable: String,
                        arguments: [String],
                        password: String?,
                        progress: ProgressHandler?,
                        log: LogHandler?) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let stdinPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.standardInput = stdinPipe

        let sink = OutputSink()
        sink.onLine = { line in
            DispatchQueue.main.async { log?(line) }
            if let percent = self.lastPercent(in: line), let progress = progress {
                DispatchQueue.main.async { progress(percent) }
            }
        }
        sink.onPartial = { partial in
            guard let percent = self.lastPercent(in: partial), let progress = progress else { return }
            DispatchQueue.main.async { progress(percent) }
        }

        let stderrSink = OutputSink()
        stderrSink.parsesProgress = false
        stderrSink.onLine = { line in
            DispatchQueue.main.async { log?(line) }
        }

        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty { sink.append(data) }
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty { stderrSink.append(data) }
        }

        do {
            try process.run()
        } catch {
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            return (status: -1,
                    output: "无法启动 \(executable)：\(error.localizedDescription)")
        }

        // 密码经 stdin 传入：写完立刻关闭写端，避免子进程一直等待输入
        let writeHandle = stdinPipe.fileHandleForWriting
        if let password = password {
            writeHandle.write(Data((password + "\n").utf8))
        }
        try? writeHandle.close()

        process.waitUntilExit()

        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil
        if let tail = try? stdoutPipe.fileHandleForReading.readToEnd(), !tail.isEmpty {
            sink.append(tail)
        }
        if let tail = try? stderrPipe.fileHandleForReading.readToEnd(), !tail.isEmpty {
            stderrSink.append(tail)
        }
        sink.finish()
        stderrSink.finish()

        var combined = sink.text
        if !stderrSink.text.isEmpty {
            combined = combined.isEmpty ? stderrSink.text : combined + "\n" + stderrSink.text
        }
        return (status: process.terminationStatus, output: combined)
    }

    // MARK: 结果判定

    /// 根据退出码与输出判定最终结果。
    ///
    /// - Parameters:
    ///   - status: 子进程退出码。
    ///   - output: 清洗后的完整输出。
    /// - Returns: 成功或具体错误。
    private func evaluate(status: Int32, output: String) -> Result<String, RarError> {
        let lowercased = output.lowercased()

        if lowercased.contains("incorrect password") || lowercased.contains("wrong password") {
            return .failure(.wrongPassword)
        }
        if lowercased.contains("no files to extract") || lowercased.contains("no files to add") {
            return .failure(.noFilesToExtract)
        }
        if lowercased.contains("cannot open") || lowercased.contains("no such file") {
            return .failure(.unknown(detail: "无法打开文件，请检查路径是否存在、以及是否拥有访问权限。\n\n原始输出尾部：\n"
                + outputTail(output)))
        }
        if lowercased.contains("access denied") || lowercased.contains("permission denied") {
            return .failure(.unknown(detail: "没有访问权限，请换一个可写入的目标位置。\n\n原始输出尾部：\n"
                + outputTail(output)))
        }
        if status == 0 {
            return .success(output)
        }
        if lowercased.contains("total errors") {
            return .failure(.unknown(detail: "rar / unrar 执行过程中报错（Total errors）。\n\n原始输出尾部：\n"
                + outputTail(output)))
        }
        return .failure(.unknown(detail: "rar / unrar 以退出码 \(status) 结束。\n\n原始输出尾部：\n"
            + outputTail(output)))
    }

    /// 取输出的最后若干行，避免把几百行进度刷给用户。
    ///
    /// - Parameters:
    ///   - text: 完整输出。
    ///   - limit: 保留行数，默认 12 行。
    /// - Returns: 尾部若干非空行拼成的文本。
    private func outputTail(_ text: String, limit: Int = 12) -> String {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return lines.suffix(limit).joined(separator: "\n")
    }

    /// 统一在主线程回调失败结果。
    ///
    /// - Parameters:
    ///   - error: 错误。
    ///   - completion: 完成回调。
    private func fail(_ error: RarError, completion: @escaping Completion) {
        DispatchQueue.main.async { completion(.failure(error)) }
    }

    // MARK: 输出清洗工具

    /// 模拟退格、剔除 ANSI 转义序列，并压缩多余空白。
    ///
    /// - Parameter raw: 原始的一行文本（不含换行符）。
    /// - Returns: 清洗后的文本。
    fileprivate static func clean(_ raw: String) -> String {
        var characters: [Character] = []
        for character in raw {
            if character == "\u{8}" {
                if !characters.isEmpty { characters.removeLast() }
                continue
            }
            characters.append(character)
        }
        var result = String(characters)
        result = result.replacingOccurrences(of: "\t", with: " ")
        result = stripANSI(result)
        // 折叠连续空格，让进度行更易读
        while result.contains("  ") {
            result = result.replacingOccurrences(of: "  ", with: " ")
        }
        return result.trimmingCharacters(in: .whitespaces)
    }

    /// 剔除 ANSI 颜色 / 光标控制序列。
    ///
    /// - Parameter text: 输入文本。
    /// - Returns: 剔除后的文本。
    private static func stripANSI(_ text: String) -> String {
        guard text.unicodeScalars.contains(where: { $0 == "\u{1B}" }) else { return text }
        guard let regex = try? NSRegularExpression(pattern: "\u{1B}\\[[0-9;?]*[A-Za-z]", options: []) else {
            return text
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
    }

    /// 从一行输出中取出最后一个百分比数字。
    ///
    /// - Parameter line: 已清洗的一行文本。
    /// - Returns: 0...100 的百分比；没有百分比时返回 nil。
    private func lastPercent(in line: String) -> Double? {
        guard let regex = percentRegex else { return nil }
        let range = NSRange(line.startIndex..., in: line)
        let matches = regex.matches(in: line, options: [], range: range)
        guard let last = matches.last, last.numberOfRanges > 1 else { return nil }
        guard let numberRange = Range(last.range(at: 1), in: line) else { return nil }
        guard let value = Double(line[numberRange]) else { return nil }
        return min(max(value, 0), 100)
    }
}
