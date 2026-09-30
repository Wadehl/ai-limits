import Foundation

public enum LimitsError: Error, CustomStringConvertible {
    case keychainReadFailed(String, String)
    case credentialsMissing(String)
    case credentialsMalformed(String)
    case requestFailed(String)
    case responseRejected(String, Int)
    case responseMalformed(String)

    public var description: String {
        switch self {
        case let .keychainReadFailed(service, detail):
            "钥匙串项目 \(service) 读取失败：\(detail)"
        case let .credentialsMissing(provider):
            "本机没有找到 \(provider) 的登录凭据"
        case let .credentialsMalformed(provider):
            "\(provider) 的凭据文件内容无法识别"
        case let .requestFailed(detail):
            "请求失败：\(detail)"
        case let .responseRejected(url, code):
            "\(url) 返回 HTTP \(code)"
        case let .responseMalformed(url):
            "\(url) 的响应无法解析"
        }
    }
}

public enum LocalPaths {
    public static var home: URL {
        FileManager.default.homeDirectoryForCurrentUser
    }

    public static func directory(_ name: String) -> URL {
        home.appending(path: name, directoryHint: .isDirectory)
    }

    /// 读取环境变量指定的目录，未设置时使用默认目录
    public static func override(_ variable: String, fallback: URL) -> URL {
        guard let value = ProcessInfo.processInfo.environment[variable], !value.isEmpty else {
            return fallback
        }
        return URL(fileURLWithPath: value, isDirectory: true)
    }
}

public enum Keychain {
    /// 通过 /usr/bin/security 读取钥匙串中的通用密码项目
    public static func genericPassword(service: String, account: String) throws -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", service, "-a", account, "-w"]
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        try process.run()

        let deadline = Date().addingTimeInterval(3)
        while process.isRunning && Date() < deadline {
            usleep(50_000)
        }
        if process.isRunning {
            process.terminate()
            throw LimitsError.keychainReadFailed(service, "读取超时")
        }

        let stdout = output.fileHandleForReading.readDataToEndOfFile()
        let stderr = errors.fileHandleForReading.readDataToEndOfFile()
        if process.terminationStatus != 0 {
            let message = String(decoding: stderr, as: UTF8.self)
            if message.contains("could not be found") || process.terminationStatus == 44 {
                return nil
            }
            throw LimitsError.keychainReadFailed(service, message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return String(decoding: stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public enum JSONFile {
    public static func read(at url: URL) throws -> Any {
        let data = try Data(contentsOf: url)
        return try JSONSerialization.jsonObject(with: data)
    }

    public static func readIfPresent(at url: URL) throws -> Any? {
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            return nil
        }
        return try read(at: url)
    }
}

public func clampPercent(_ value: Double) -> Double {
    min(100, max(0, value))
}

public func finiteNumber(_ value: Any?) -> Double? {
    switch value {
    case let number as NSNumber:
        guard CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let double = number.doubleValue
        return double.isFinite ? double : nil
    case let text as String:
        return Double(text.trimmingCharacters(in: .whitespaces))
    default:
        return nil
    }
}

public func nonEmptyString(_ value: Any?) -> String? {
    guard let text = value as? String else { return nil }
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

/// 解析重置时间：秒级与毫秒级时间戳都能接受，也接受 ISO 8601 文本
public func parseResetDate(_ value: Any?) -> Date? {
    if let number = finiteNumber(value) {
        return Date(timeIntervalSince1970: number > 10_000_000_000 ? number / 1000 : number)
    }
    guard let text = nonEmptyString(value) else { return nil }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: text) {
        return date
    }
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: text)
}
