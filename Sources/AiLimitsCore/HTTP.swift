import Foundation

public enum ResetDescription {
    private static let timeOnly: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static let withDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter
    }()

    public static func text(for date: Date?, now: Date = Date()) -> String? {
        guard let date else { return nil }
        let calendar = Calendar.current
        return calendar.isDate(date, inSameDayAs: now)
            ? timeOnly.string(from: date)
            : withDay.string(from: date)
    }
}

public func makeWindow(usedPercent: Double, windowMinutes: Int, resetsAt: Date?) -> RateLimitWindow {
    RateLimitWindow(
        usedPercent: clampPercent(usedPercent),
        windowMinutes: windowMinutes,
        resetsAt: resetsAt,
        resetDescription: ResetDescription.text(for: resetsAt)
    )
}

public struct HTTPPayload: Sendable {
    public let status: Int
    public let body: Data

    public var text: String {
        String(decoding: body, as: UTF8.self)
    }

    public func json() throws -> Any {
        try JSONSerialization.jsonObject(with: body)
    }
}

public enum HTTP {
    public static let timeout: TimeInterval = 10

    public static func get(_ url: URL, headers: [String: String], urlSession: URLSession = .shared) async throws -> HTTPPayload {
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.httpMethod = "GET"
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LimitsError.responseMalformed(url.absoluteString)
        }
        return HTTPPayload(status: httpResponse.statusCode, body: data)
    }

    public static func requireSuccess(_ payload: HTTPPayload, url: URL) throws -> Any {
        guard (200..<300).contains(payload.status) else {
            throw LimitsError.responseRejected(url.absoluteString, payload.status)
        }
        do {
            return try payload.json()
        } catch {
            throw LimitsError.responseMalformed(url.absoluteString)
        }
    }
}
