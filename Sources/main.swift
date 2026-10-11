import Cocoa

let fm = FileManager.default
let support = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
let defaultBackupRoot = support.appendingPathComponent("DaveSaveImporter/Backups")
let backupPreference = "backupDirectoryPath"
func backupRoot() -> URL {
    if let path = UserDefaults.standard.string(forKey: backupPreference) { return URL(fileURLWithPath: path, isDirectory: true) }
    return defaultBackupRoot
}
func validateBackupRoot(_ root: URL, targets: [URL]) throws {
    let path = root.resolvingSymlinksInPath().standardizedFileURL.path
    for target in targets {
        let save = target.resolvingSymlinksInPath().standardizedFileURL.path
        if path == save || path.hasPrefix(save + "/") { throw ImportError(message: "备份位置不能放在游戏存档目录内部，请选择其他文件夹。") }
    }
    try fm.createDirectory(at: root, withIntermediateDirectories: true)
    let probe = root.appendingPathComponent(".write-check-" + UUID().uuidString)
    try Data("test".utf8).write(to: probe, options: .atomic); try fm.removeItem(at: probe)
}
func createSnapshot(_ targets: [URL], at root: URL) throws -> URL {
    try validateBackupRoot(root, targets: targets)
    let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "Asia/Shanghai"); formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
    let backup = root.appendingPathComponent(formatter.string(from: Date()) + "_" + UUID().uuidString.prefix(8))
    try fm.createDirectory(at: backup, withIntermediateDirectories: false)
    for (index, target) in targets.enumerated() {
        let copy = backup.appendingPathComponent("\(index)-\(target.lastPathComponent)")
        try fm.copyItem(at: target, to: copy)
        if let enumerator = fm.enumerator(atPath: target.path) {
            for case let relative as String in enumerator {
                let original = target.appendingPathComponent(relative)
                if try original.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
                    guard try Data(contentsOf: original) == Data(contentsOf: copy.appendingPathComponent(relative)) else { throw ImportError(message: "备份校验失败，未替换游戏存档。") }
                }
            }
        }
    }
    try targets.map(\.path).joined(separator: "\n").write(to: backup.appendingPathComponent("原始路径.txt"), atomically: true, encoding: .utf8)
    let note = "备份时间（北京时间）：\(formatter.string(from: Date()))\n保存内容：本次导入前的完整存档。\n"
    try note.write(to: backup.appendingPathComponent("备份说明.txt"), atomically: true, encoding: .utf8)
    return backup
}
struct ImportError: LocalizedError { let message: String; var errorDescription: String? { message } }
func run(_ executable: String, _ args: [String]) throws -> Data {
    let p = Process(); p.executableURL = URL(fileURLWithPath: executable); p.arguments = args
    let out = Pipe(); let err = Pipe(); p.standardOutput = out; p.standardError = err
    try p.run(); let data = out.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
    if p.terminationStatus != 0 { throw ImportError(message: "操作失败：\(executable)（\(p.terminationStatus)）") }; return data
}
func targets() -> [URL] {
    var result: [URL] = []
    for root in [support.appendingPathComponent("com.nexon.dave/SteamSData"), support.appendingPathComponent("nexon/DAVE THE DIVER/SteamSData")] {
        for u in (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [] {
            if fm.fileExists(atPath: u.appendingPathComponent("GameSave_00_GD.sav").path) { result.append(u) }
        }
    }
    for path in ["com.nexon.dave/SData", "nexon/DAVE THE DIVER/SData"] {
        let u = support.appendingPathComponent(path)
        if fm.fileExists(atPath: u.appendingPathComponent("GameSave_00_GD.sav").path) { result.append(u) }
    }
    return result
}
func mirrors() -> [URL] {
    let root = support.appendingPathComponent("NemirtingasSteamEmu")
    return ((try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []).map { $0.appendingPathComponent("1868140/remote") }.filter { fm.fileExists(atPath: $0.appendingPathComponent("gamesave_00_gd.sav").path) }
}
func performImport(_ archive: URL, _ destination: URL) throws -> String {
    let running = NSWorkspace.shared.runningApplications.contains { app in
        let name = (app.localizedName ?? "").lowercased(); let path = (app.executableURL?.path ?? "").lowercased()
        return app.processIdentifier != ProcessInfo.processInfo.processIdentifier && (app.bundleIdentifier == "com.nexon.dave" || path.contains("davethediver.app") || name == "dave the diver")
    }
    if running { throw ImportError(message: "请先完全退出潜水员戴夫，再点击导入。") }
    guard archive.pathExtension.lowercased() == "zip" else { throw ImportError(message: "请选择 SData 的 ZIP 压缩包。") }
    let listing = try run("/usr/bin/unzip", ["-Z1", archive.path])
    guard let names = String(data: listing, encoding: .utf8)?.components(separatedBy: .newlines) else { throw ImportError(message: "ZIP 文件名编码无法识别。") }
    let pattern = "^GameSave_[0-9]{2}_(GD|PZ|UO)\\.sav$"
    let entries = names.filter { URL(fileURLWithPath: $0).lastPathComponent.range(of: pattern, options: .regularExpression) != nil && !$0.components(separatedBy: "/").contains("_BackUp") && !$0.contains("__MACOSX/") }
    let parents = Set(entries.map { ($0 as NSString).deletingLastPathComponent })
    guard parents.count == 1, !entries.isEmpty else { throw ImportError(message: "压缩包中必须包含一组主存档（可放在 SData 文件夹内），不能有多个存档目录。") }
    var files: [String: Data] = [:]
    for entry in entries {
        let name = URL(fileURLWithPath: entry).lastPathComponent
        guard files[name] == nil else { throw ImportError(message: "压缩包包含重名存档。") }
        let data = try run("/usr/bin/unzip", ["-p", archive.path, entry])
        guard !data.isEmpty, data.count < 50_000_000 else { throw ImportError(message: "存档为空或过大：\(name)") }
        files[name] = data
    }
    for name in files.keys where name.hasSuffix("_GD.sav") || name.hasSuffix("_PZ.sav") {
        let partner = name.hasSuffix("_GD.sav") ? name.replacingOccurrences(of: "_GD.sav", with: "_PZ.sav") : name.replacingOccurrences(of: "_PZ.sav", with: "_GD.sav")
        guard files[partner] != nil else { throw ImportError(message: "槽位文件不完整，缺少 \(partner)。") }
    }
    guard files.keys.contains(where: { $0.hasSuffix("_GD.sav") }) else { throw ImportError(message: "没有找到完整的 GD/PZ 存档。") }
    let all = [destination] + mirrors()
    let backup = try createSnapshot(all, at: backupRoot())
    var prepared: [(URL, URL, URL)] = []
    defer { for (_, _, stage) in prepared { try? fm.removeItem(at: stage) } }
    for (index, target) in all.enumerated() {
        let old = backup.appendingPathComponent("\(index)-\(target.lastPathComponent)")
        let stage = target.deletingLastPathComponent().appendingPathComponent(".dave-import-\(UUID().uuidString)")
        try fm.copyItem(at: target, to: stage)
        prepared.append((target, old, stage))
        for existing in try fm.contentsOfDirectory(at: stage, includingPropertiesForKeys: nil) {
            if existing.lastPathComponent.lowercased().hasSuffix(".sav") || existing.lastPathComponent == "_BackUp" { try fm.removeItem(at: existing) }
        }
        for (name, data) in files { try data.write(to: stage.appendingPathComponent(index == 0 ? name : name.lowercased()), options: .atomic) }
    }
    var changed: [(URL, URL)] = []
    do {
        for (target, old, stage) in prepared {
            changed.append((target, old)); try fm.removeItem(at: target); try fm.moveItem(at: stage, to: target)
            for (name, data) in files {
                let actual = try Data(contentsOf: target.appendingPathComponent(target == destination ? name : name.lowercased()))
                guard actual == data else { throw ImportError(message: "写入校验失败。") }
            }
        }
    } catch {
        var failures: [String] = []
        for (target, old) in changed.reversed() {
            do { if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }; try fm.copyItem(at: old, to: target) } catch { failures.append(target.path) }
        }
        throw ImportError(message: "导入失败：\(error.localizedDescription)\n备份：\(backup.path)\n" + (failures.isEmpty ? "已恢复原存档。" : "以下目录恢复失败：\(failures.joined(separator: ", "))"))
    }
    return "已导入 \(files.count) 个主存档文件，更新 \(all.count) 个存档目录。\n\n备份位置：\n\(backup.path)\n\n请启动游戏，在载入游戏中检查进度。"
}

class DropView: NSView {
    var onDrop: ((URL) -> Void)?
    override init(frame: NSRect) { super.init(frame: frame); registerForDraggedTypes([.fileURL]) }
    required init?(coder: NSCoder) { fatalError() }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as? [URL], urls.count == 1 else { return false }; onDrop?(urls[0]); return true
    }
}
class Delegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!; var selected: URL?; var choices = targets()
    let fileLabel = NSTextField(labelWithString: "将 SData.zip 拖入此窗口，或点击选择压缩包")
    let status = NSTextField(wrappingLabelWithString: "导入前自动备份。请先退出游戏。支持 ZIP；只导入主槽位，不导入旧备份。")
    let backupLabel = NSTextField(wrappingLabelWithString: "")
    var importing = false
    let picker = NSPopUpButton(); let button = NSButton(title: "导入并替换存档", target: nil, action: nil)
    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 500), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "潜水员戴夫 · 存档导入工具"; window.center()
        let drop = DropView(frame: window.contentView!.bounds); window.contentView = drop; drop.onDrop = { [weak self] in self?.select($0) }
        let title = NSTextField(labelWithString: "潜水员戴夫  存档迁移"); title.font = .boldSystemFont(ofSize: 25)
        let choose = NSButton(title: "选择 ZIP 压缩包…", target: self, action: #selector(browse))
        fileLabel.lineBreakMode = .byTruncatingMiddle
        picker.addItems(withTitles: choices.map { $0.path.replacingOccurrences(of: fm.homeDirectoryForCurrentUser.path, with: "~") })
        if choices.isEmpty { picker.addItem(withTitle: "未找到存档，请先启动游戏并保存一次") }
        button.target = self; button.action = #selector(importNow); button.bezelStyle = .rounded; button.isEnabled = false
        let backups = NSButton(title: "打开备份文件夹", target: self, action: #selector(showBackups))
        let settings = NSButton(title: "设置备份位置…", target: self, action: #selector(configureBackup))
        let backupActions = NSStackView(views: [backups, settings]); backupActions.spacing = 12
        updateBackupLabel()
        let stack = NSStackView(views: [title, fileLabel, choose, NSTextField(labelWithString: "目标存档目录"), picker, button, status, backupLabel, backupActions]); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false; drop.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: drop.leadingAnchor, constant: 28), stack.trailingAnchor.constraint(equalTo: drop.trailingAnchor, constant: -28), stack.topAnchor.constraint(equalTo: drop.topAnchor, constant: 26)])
        window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        if UserDefaults.standard.string(forKey: backupPreference) == nil { DispatchQueue.main.async { _ = self.chooseBackupLocation() } }
    }
    func select(_ url: URL) { selected = url; fileLabel.stringValue = url.lastPathComponent; button.isEnabled = !importing && url.pathExtension.lowercased() == "zip" && !choices.isEmpty; status.stringValue = button.isEnabled ? "已选择压缩包。点击导入将自动备份并替换目标存档。" : "请选择 ZIP 文件，并确保游戏已有存档。" }
    @objc func browse() { let p = NSOpenPanel(); p.allowedFileTypes = ["zip"]; p.allowsMultipleSelection = false; if p.runModal() == .OK, let u = p.url { select(u) } }
    func updateBackupLabel() { backupLabel.stringValue = "自动备份位置：\(backupRoot().path)\n每次导入保留一份替换前的存档，按北京时间命名，历史备份不会自动删除。" }
    @discardableResult func chooseBackupLocation() -> Bool {
        guard !importing else { return false }
        let alert = NSAlert(); alert.messageText = "设置自动备份位置"
        alert.informativeText = "每次导入前，都会把当前存档完整备份到这里。选择会被记住，之后可随时更改。\n\n默认位置：\(defaultBackupRoot.path)\n\n更改位置后，已有备份仍保留在原位置。"
        alert.addButton(withTitle: "使用默认位置"); alert.addButton(withTitle: "选择自定义位置…"); alert.addButton(withTitle: "取消")
        let response = alert.runModal(); var root = defaultBackupRoot
        if response == .alertSecondButtonReturn {
            let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true; panel.allowsMultipleSelection = false
            panel.prompt = "设为备份位置"; panel.directoryURL = backupRoot()
            guard panel.runModal() == .OK, let selected = panel.url else { return false }; root = selected
        } else if response != .alertFirstButtonReturn { return false }
        do {
            try validateBackupRoot(root, targets: choices + mirrors())
            UserDefaults.standard.set(root.path, forKey: backupPreference); updateBackupLabel(); return true
        } catch { let failure = NSAlert(); failure.messageText = "无法使用此备份位置"; failure.informativeText = error.localizedDescription; failure.runModal(); return false }
    }
    @objc func configureBackup() { chooseBackupLocation() }
    @objc func showBackups() {
        do { let root = backupRoot(); try fm.createDirectory(at: root, withIntermediateDirectories: true); NSWorkspace.shared.open(root) }
        catch { let alert = NSAlert(); alert.messageText = "无法打开备份目录"; alert.informativeText = error.localizedDescription; alert.runModal() }
    }
    @objc func importNow() {
        guard !importing else { return }
        if UserDefaults.standard.string(forKey: backupPreference) == nil && !chooseBackupLocation() { return }
        guard let url = selected, choices.indices.contains(picker.indexOfSelectedItem) else { return }
        importing = true
        let dest = choices[picker.indexOfSelectedItem]; button.isEnabled = false; status.stringValue = "正在验证、备份和导入…"
        DispatchQueue.global(qos: .userInitiated).async {
            let result: Result<String, Error> = Result { try performImport(url, dest) }
            DispatchQueue.main.async {
                self.importing = false; self.button.isEnabled = true
                let alert = NSAlert()
                switch result { case .success(let message): alert.messageText = "导入完成"; alert.informativeText = message; self.status.stringValue = "导入成功，原存档已备份。"
                case .failure(let error): alert.messageText = "未能导入"; alert.informativeText = error.localizedDescription; self.status.stringValue = "导入失败，请查看提示。" }
                alert.runModal()
            }
        }
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply { importing ? .terminateCancel : .terminateNow }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
if CommandLine.arguments.count == 3 && CommandLine.arguments[1] == "--import" {
    do { let options = targets(); guard options.count == 1, let dest = options.first else { throw ImportError(message: "需在界面选择目标目录。") }; print(try performImport(URL(fileURLWithPath: CommandLine.arguments[2]), dest)) } catch { fputs("\(error.localizedDescription)\n", stderr); exit(1) }
} else {
    let app = NSApplication.shared; let delegate = Delegate(); app.delegate = delegate; app.setActivationPolicy(.regular); app.run()
}
