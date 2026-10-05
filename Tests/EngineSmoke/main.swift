import Foundation

// RarEngine 端到端冒烟测试（命令行版，用于验证引擎逻辑，不涉及界面）

let engine = RarEngine.shared
let fm = FileManager.default
let base = "/tmp/rartest"
let src = base + "/src"

var failures: [String] = []
var done = false

func waitDone() {
    let deadline = Date().addingTimeInterval(180)
    while !done, Date() < deadline {
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.2))
    }
    done = false
}

func check(_ ok: Bool, _ name: String) {
    print((ok ? "  [PASS] " : "  [FAIL] ") + name)
    if !ok { failures.append(name) }
}

func contents(_ path: String) -> String? {
    return try? String(contentsOfFile: path, encoding: .utf8)
}

// ---------- 场景 1：明文压缩 ----------
print("场景 1：明文压缩")
let plainRar = base + "/明文包.rar"
try? fm.removeItem(atPath: plainRar)
var maxProgress: Double = 0
engine.compress(sources: [src], output: plainRar, password: "",
                encryptNames: false,
                progress: { v in if v > maxProgress { maxProgress = v } },
                log: { _ in },
                completion: { result in
                    if case .failure(let e) = result { print("     错误：\(e.title) / \(e.detail)") }
                    check(fm.fileExists(atPath: plainRar), "生成明文压缩包")
                    check(maxProgress >= 90, "进度回调到达 \(Int(maxProgress))%")
                    done = true
                })
waitDone()

// ---------- 场景 2：明文包加密检测 ----------
print("场景 2：明文包加密检测")
check(engine.isEncrypted(archive: plainRar) == false, "明文包判定为未加密")

// ---------- 场景 3：明文解压 + 中文/空格/嵌套目录完整性 ----------
print("场景 3：明文解压")
let plainOut = base + "/明文解压"
try? fm.removeItem(atPath: plainOut)
engine.extract(archive: plainRar, to: plainOut, password: "",
               progress: { _ in }, log: { _ in },
               completion: { result in
                   if case .failure(let e) = result { print("     错误：\(e.title)") }
                   check(fm.fileExists(atPath: plainOut + "/src/中文文件.txt"), "中文文件名还原")
                   check(fm.fileExists(atPath: plainOut + "/src/带 空格 的名字.md"), "带空格文件名还原")
                   check(fm.fileExists(atPath: plainOut + "/src/子目录/深层目录/深层.txt"), "三层嵌套目录还原")
                   check(contents(plainOut + "/src/中文文件.txt") == "顶层中文内容\n", "中文文件内容一致")
                   let bin = plainOut + "/src/随机数据.bin"
                   let srcBin = src + "/随机数据.bin"
                   let a = fm.contents(atPath: bin)?.count ?? 0
                   let b = fm.contents(atPath: srcBin)?.count ?? 0
                   check(a == b && a == 3000000, "3MB 二进制文件字节数一致（\(a)）")
                   done = true
               })
waitDone()

// ---------- 场景 4：AES-256 加密压缩 ----------
print("场景 4：AES-256 加密压缩")
let encRar = base + "/加密包.rar"
try? fm.removeItem(atPath: encRar)
let password = "密 码-中文123"
engine.compress(sources: [src], output: encRar, password: password,
                encryptNames: false,
                progress: { _ in }, log: { _ in },
                completion: { result in
                    if case .failure(let e) = result { print("     错误：\(e.title)") }
                    check(fm.fileExists(atPath: encRar), "生成加密压缩包")
                    done = true
                })
waitDone()

// ---------- 场景 5：加密包检测 ----------
print("场景 5：加密包检测")
check(engine.isEncrypted(archive: encRar) == true, "加密包判定为已加密")

// ---------- 场景 6：正确密码解压 ----------
print("场景 6：正确密码解压")
let encOut = base + "/加密解压"
try? fm.removeItem(atPath: encOut)
engine.extract(archive: encRar, to: encOut, password: password,
               progress: { _ in }, log: { _ in },
               completion: { result in
                   switch result {
                   case .success:
                       check(fm.fileExists(atPath: encOut + "/src/中文文件.txt"), "解密后中文文件名还原")
                       check(contents(encOut + "/src/中文文件.txt") == "顶层中文内容\n", "解密后内容一致")
                   case .failure(let e):
                       check(false, "正确密码解压失败：\(e.title) \(e.detail)")
                   }
                   done = true
               })
waitDone()

// ---------- 场景 7：错误密码 ----------
print("场景 7：错误密码应报错")
let wrongOut = base + "/错密码解压"
try? fm.removeItem(atPath: wrongOut)
engine.extract(archive: encRar, to: wrongOut, password: "完全不对的密码",
               progress: { _ in }, log: { _ in },
               completion: { result in
                   switch result {
                   case .success:
                       check(false, "错误密码竟然解压成功（严重问题）")
                   case .failure(let e):
                       if case .wrongPassword = e {
                           check(true, "错误密码被正确识别为「密码错误」")
                       } else {
                           check(false, "错误密码被识别成其它错误：\(e.title)")
                       }
                   }
                   done = true
               })
waitDone()

// ---------- 场景 8：加密文件名（-hp） ----------
print("场景 8：加密文件名（-hp）")
let hpRar = base + "/隐藏文件名.rar"
try? fm.removeItem(atPath: hpRar)
engine.compress(sources: [src], output: hpRar, password: "hp123456",
                encryptNames: true,
                progress: { _ in }, log: { _ in },
                completion: { result in
                    if case .failure(let e) = result { print("     错误：\(e.title)") }
                    check(fm.fileExists(atPath: hpRar), "生成 -hp 压缩包")
                    done = true
                })
waitDone()
check(engine.isEncrypted(archive: hpRar) == true, "-hp 包判定为已加密")
let hpOut = base + "/hp解压"
try? fm.removeItem(atPath: hpOut)
engine.extract(archive: hpRar, to: hpOut, password: "hp123456",
               progress: { _ in }, log: { _ in },
               completion: { result in
                   switch result {
                   case .success:
                       check(fm.fileExists(atPath: hpOut + "/src/中文文件.txt"), "-hp 包用密码解压成功")
                   case .failure(let e):
                       check(false, "-hp 包解压失败：\(e.title)")
                   }
                   done = true
               })
waitDone()

// ---------- 场景 9：不存在的压缩包 ----------
print("场景 9：异常路径")
engine.extract(archive: base + "/不存在的包.rar", to: base + "/x", password: "",
               progress: { _ in }, log: { _ in },
               completion: { result in
                   if case .failure = result {
                       check(true, "不存在的压缩包被正确拦截")
                   } else {
                       check(false, "不存在的压缩包竟然返回成功")
                   }
                   done = true
               })
waitDone()

// ---------- 场景 10：多源混合（跨目录）结构不能丢 ----------
print("场景 10：多源混合压缩")
let extraDir = base + "/extra"
try? fm.createDirectory(atPath: extraDir, withIntermediateDirectories: true)
try? "另一个目录里的文件\n".write(toFile: extraDir + "/单文件.txt", atomically: true, encoding: .utf8)
let multiRar = base + "/多源包.rar"
let multiOut = base + "/多源解压"
try? fm.removeItem(atPath: multiRar)
try? fm.removeItem(atPath: multiOut)
engine.compress(sources: [src, extraDir + "/单文件.txt"], output: multiRar, password: "",
                encryptNames: false,
                progress: { _ in }, log: { _ in },
                completion: { result in
                    if case .failure(let e) = result { print("     错误：\(e.title)") }
                    done = true
                })
waitDone()
engine.extract(archive: multiRar, to: multiOut, password: "",
               progress: { _ in }, log: { _ in },
               completion: { _ in done = true })
waitDone()
check(fm.fileExists(atPath: multiOut + "/src/子目录/深层目录/深层.txt"),
      "多源：第一个目录的三层子目录结构保留")
check(fm.fileExists(atPath: multiOut + "/extra/单文件.txt"),
      "多源：第二个目录的路径结构保留")
check(contents(multiOut + "/extra/单文件.txt") == "另一个目录里的文件\n",
      "多源：第二个文件内容一致")

print()
if failures.isEmpty {
    print("=== 全部通过 ===")
} else {
    print("=== 失败 \(failures.count) 项 ===")
    for f in failures { print(" - \(f)") }
    exit(1)
}
