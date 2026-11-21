import Foundation
import Darwin

// A fixed-operation executable. Production paths cannot be supplied by callers.
struct EnvironmentError: LocalizedError {
    let errorDescription: String?
    init(_ text: String) { errorDescription = text }
}

let arguments = Array(CommandLine.arguments.dropFirst())
let operation = arguments.first ?? "status"
let testing = arguments.count == 3 && arguments[1] == "--test-root" && geteuid() != 0
let root = testing ? URL(fileURLWithPath: arguments[2]) : URL(fileURLWithPath: "/")
let preferences = root.appendingPathComponent("Library/Preferences/com.apple.MobileBluetooth.debug.plist")
let directory = root.appendingPathComponent("Library/Application Support/Rimo/VoiceEnvironment")
let backup = directory.appendingPathComponent("original.plist")
// File logging is explicitly disabled while Rimo owns these settings.
let applied: [String: Bool] = ["StackDebugEnabled": true, "HCILiveTraces": true,
    "HCIFileTraces": false, "RawAudioTrace": true, "HIDTrace": true, "HCISkipAuth": true]
let manager = FileManager.default

@MainActor
func read(_ url: URL) throws -> [String: Any] {
    guard manager.fileExists(atPath: url.path) else { return [:] }
    let data = try Data(contentsOf: url)
    guard let value = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
        throw EnvironmentError("配置文件格式无法识别，已停止操作。")
    }
    return value
}

@MainActor
func write(_ dictionary: [String: Any], to url: URL) throws {
    let data = try PropertyListSerialization.data(fromPropertyList: dictionary, format: .xml, options: 0)
    try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    if manager.fileExists(atPath: url.path),
       (try manager.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType) != .typeRegular {
        throw EnvironmentError("配置路径不是普通文件，已停止操作。")
    }
    try data.write(to: url, options: .atomic)
    try manager.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
}

@MainActor
func equal(_ left: Any?, _ right: Any?) -> Bool {
    switch (left, right) {
    case (nil, nil): return true
    case (let left?, let right?): return NSDictionary(dictionary: ["value": left]).isEqual(to: ["value": right])
    default: return false
    }
}

@MainActor
func reload() throws {
    guard !testing else { return }
    // Match the reference applications' SIGUSR1 reload, retaining Bluetooth pairing.
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
    process.arguments = ["-30", "bluetoothd"]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw EnvironmentError("设置已写入，但蓝牙日志重载失败。可重试配置或还原。")
    }
}

@MainActor
func settings(_ document: [String: Any]) throws -> [String: Any] {
    guard let value = document["HCITraces"] else { return [:] }
    guard let value = value as? [String: Any] else {
        throw EnvironmentError("现有 HCITraces 格式不受支持。")
    }
    return value
}

@MainActor
func run() throws -> [String: Any] {
    guard ["status", "configure", "restore"].contains(operation),
          arguments.count == 1 || testing else { throw EnvironmentError("无效的语音环境操作。") }
    if operation != "status", !testing, geteuid() != 0 {
        throw EnvironmentError("此操作需要管理员授权。")
    }
    var descriptor: Int32 = -1
    if operation != "status" {
        try manager.createDirectory(at: directory, withIntermediateDirectories: true,
                                    attributes: [.posixPermissions: 0o755])
        let attributes = try manager.attributesOfItem(atPath: directory.path)
        guard attributes[.type] as? FileAttributeType == .typeDirectory,
              testing || (attributes[.ownerAccountID] as? UInt32 == 0 &&
                          ((attributes[.posixPermissions] as? Int ?? 0o777) & 0o022) == 0) else {
            throw EnvironmentError("语音环境目录的所有者或类型异常。")
        }
        descriptor = open(directory.appendingPathComponent("operation.lock").path, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
        guard descriptor >= 0, flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            if descriptor >= 0 { close(descriptor) }
            throw EnvironmentError("已有语音环境操作正在运行，请稍后重试。")
        }
    }
    defer { if descriptor >= 0 { flock(descriptor, LOCK_UN); close(descriptor) } }
    var document = try read(preferences)
    var current = try settings(document)
    if operation == "status" {
        return ["configured": applied.allSatisfy { equal(current[$0.key], $0.value) },
                "canRestore": manager.fileExists(atPath: backup.path)]
    }
    if operation == "configure" {
        if !manager.fileExists(atPath: backup.path) {
            let original = current.filter { applied[$0.key] != nil }
            try write(["schema": 1, "original": original,
                       "hadDictionary": document["HCITraces"] != nil], to: backup)
        }
        let saved = try read(backup)
        guard saved["schema"] as? Int == 1, let original = saved["original"] as? [String: Any] else {
            throw EnvironmentError("原配置备份无效，已停止操作。")
        }
        for (key, value) in applied {
            guard equal(current[key], original[key]) || equal(current[key], value) else {
                throw EnvironmentError("蓝牙诊断设置已被其他程序修改，请先检查后再配置。")
            }
            current[key] = value
        }
        document["HCITraces"] = current
        do {
            try write(document, to: preferences)
            let actual = try settings(read(preferences))
            guard applied.allSatisfy({ equal(actual[$0.key], $0.value) }) else {
                throw EnvironmentError("蓝牙日志设置校验失败。")
            }
        } catch {
            // Restore only owned keys. Keep the backup if rollback also fails.
            var rollback = try read(preferences)
            var values = try settings(rollback)
            for key in applied.keys { values[key] = original[key] }
            if values.isEmpty && saved["hadDictionary"] as? Bool == false { rollback.removeValue(forKey: "HCITraces") }
            else { rollback["HCITraces"] = values }
            try write(rollback, to: preferences)
            throw error
        }
        try reload()
        return ["configured": true, "canRestore": true]
    }
    guard manager.fileExists(atPath: backup.path) else { throw EnvironmentError("没有 Rimo 保存的原配置。") }
    let saved = try read(backup)
    guard saved["schema"] as? Int == 1, let original = saved["original"] as? [String: Any] else {
        throw EnvironmentError("原配置备份无效，已停止还原。")
    }
    for (key, value) in applied {
        guard equal(current[key], value) || equal(current[key], original[key]) else {
            throw EnvironmentError("蓝牙诊断设置已被其他程序修改，原备份已保留。")
        }
        current[key] = original[key]
    }
    if current.isEmpty && saved["hadDictionary"] as? Bool == false { document.removeValue(forKey: "HCITraces") }
    else { document["HCITraces"] = current }
    try write(document, to: preferences)
    let actual = try settings(read(preferences))
    guard applied.keys.allSatisfy({ equal(actual[$0], original[$0]) }) else {
        throw EnvironmentError("还原校验失败，原备份已保留。")
    }
    try reload()
    try manager.removeItem(at: backup)
    return ["configured": false, "canRestore": false]
}

do {
    let result = try run()
    let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
    FileHandle.standardOutput.write(data)
} catch {
    FileHandle.standardError.write(Data(error.localizedDescription.utf8))
    exit(1)
}
