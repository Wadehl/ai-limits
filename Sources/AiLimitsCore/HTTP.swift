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
        // GET is safe to retry. Authentication failures and rate limits need their
        // own handling; retry only brief connectivity/server failures here.
        for attempt in 0..<3 {
            do {
                let payload = try await send(request, urlSession: urlSession)
                if ![408, 500, 502, 503, 504].contains(payload.status) || attempt == 2 {
                    return payload
                }
            } catch {
                guard attempt < 2, isTransient(error) else { throw error }
            }
            try await Task.sleep(for: .seconds(attempt + 1))
        }
        throw LimitsError.requestFailed("重试次数已用尽")
    }

    static func isTransient(_ error: Error) -> Bool {
        guard let error = error as? URLError else { return false }
        return [.timedOut, .cannotFindHost, .cannotConnectToHost, .networkConnectionLost,
                .dnsLookupFailed, .notConnectedToInternet].contains(error.code)
    }

    /// POST 不保证幂等，传输中断时不自动重发
    static func postJSON(_ url: URL, body: Data, headers: [String: String],
                         urlSession: URLSession = .shared) async throws -> HTTPPayload {
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        return try await send(request, urlSession: urlSession)
    }

    /// Token exchanges can rotate credentials. Do not automatically replay POST
    /// after an ambiguous transport failure, or forward its body on a redirect.
    static func postForm(_ url: URL, fields: [String: String], urlSession: URLSession) async throws -> HTTPPayload {
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        request.httpBody = Data(fields.sorted(by: { $0.key < $1.key }).map {
            "\($0.key.addingPercentEncoding(withAllowedCharacters: allowed)!)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed)!)"
        }.joined(separator: "&").utf8)
        return try await send(request, urlSession: urlSession)
    }

    private static func send(_ request: URLRequest, urlSession: URLSession) async throws -> HTTPPayload {
        try Task.checkCancellation()
        let (data, response) = try await urlSession.data(for: request, delegate: NoRedirect())
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LimitsError.responseMalformed(request.url!.absoluteString)
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

private final class NoRedirect: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
