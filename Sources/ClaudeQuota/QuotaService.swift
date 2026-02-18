import Foundation
import Security

func log(_ message: String) {
    let ts = ISO8601DateFormatter().string(from: Date())
    FileHandle.standardError.write(Data("[\(ts)] \(message)\n".utf8))
}

struct QuotaInfo {
    let utilization5h: Double    // 0.0 to 1.0+ (5-hour window)
    let utilization7d: Double    // 0.0 to 1.0+ (7-day window)
    let status: String?          // "allowed", "allowed_warning", "rejected"
    let representativeClaim: String?
    let fallbackPercentage: Double?

    var percentUsed: Int {
        min(Int(utilization5h * 100), 100)
    }

    /// The 5h window is rolling, so we estimate time until utilization drops.
    /// If utilization is X%, the oldest usage that pushed us to this level
    /// will expire sometime in the next 5h. We estimate linearly.
    var estimatedTimeUntilRelief: String {
        guard utilization5h > 0 else { return "5h00m" }
        // Rolling window: if we stop using now, utilization decreases over time
        // as old usage falls off the 5h window. Rough estimate: if at X%,
        // the earliest relief comes as the oldest contributing usage expires.
        // Without exact usage timestamps, we estimate proportionally.
        let remainingSeconds = 5.0 * 3600.0 * (1.0 - utilization5h)
        let clamped = max(remainingSeconds, 0)
        let hours = Int(clamped) / 3600
        let minutes = (Int(clamped) % 3600) / 60
        return "\(hours)h\(String(format: "%02d", minutes))m"
    }
}

final class QuotaService {
    static let shared = QuotaService()

    private let keychainService = "Claude Code-credentials"
    private let apiURL = URL(string: "https://api.anthropic.com/v1/messages")!

    private init() {}

    // MARK: - Keychain

    func getAccessToken() throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            throw QuotaError.keychainAccessFailed(status)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String
        else {
            throw QuotaError.tokenParsingFailed
        }

        return token
    }

    // MARK: - API Probe

    func fetchQuota() async throws -> QuotaInfo {
        let token = try getAccessToken()

        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.timeoutInterval = 15

        let body: [String: Any] = [
            "model": "claude-sonnet-4-5-20250929",
            "max_tokens": 1,
            "messages": [["role": "user", "content": "hi"]],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw QuotaError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            let errorBody = String(data: data, encoding: .utf8) ?? "no body"
            log("HTTP \(httpResponse.statusCode): \(String(errorBody.prefix(300)))")
            throw QuotaError.apiError(httpResponse.statusCode, errorBody)
        }

        return parseQuotaHeaders(httpResponse)
    }

    // MARK: - Header Parsing

    private func parseQuotaHeaders(_ response: HTTPURLResponse) -> QuotaInfo {
        let headers = response.allHeaderFields

        let util5h = doubleHeader(headers, key: "anthropic-ratelimit-unified-5h-utilization") ?? 0
        let util7d = doubleHeader(headers, key: "anthropic-ratelimit-unified-7d-utilization") ?? 0
        let status = stringHeader(headers, key: "anthropic-ratelimit-unified-status")
        let claim = stringHeader(headers, key: "anthropic-ratelimit-unified-representative-claim")
        let fallback = doubleHeader(headers, key: "anthropic-ratelimit-unified-fallback-percentage")

        log("Quota: 5h=\(String(format: "%.1f", util5h * 100))% 7d=\(String(format: "%.1f", util7d * 100))% status=\(status ?? "?") claim=\(claim ?? "?")")

        return QuotaInfo(
            utilization5h: util5h,
            utilization7d: util7d,
            status: status,
            representativeClaim: claim,
            fallbackPercentage: fallback
        )
    }

    private func stringHeader(_ headers: [AnyHashable: Any], key: String) -> String? {
        for (rawKey, rawValue) in headers {
            if "\(rawKey)".lowercased() == key.lowercased() {
                return "\(rawValue)"
            }
        }
        return nil
    }

    private func doubleHeader(_ headers: [AnyHashable: Any], key: String) -> Double? {
        guard let str = stringHeader(headers, key: key) else { return nil }
        return Double(str)
    }
}

enum QuotaError: LocalizedError {
    case keychainAccessFailed(OSStatus)
    case tokenParsingFailed
    case invalidResponse
    case apiError(Int, String)

    var errorDescription: String? {
        switch self {
        case .keychainAccessFailed(let status):
            return "Keychain access failed (status: \(status)). Make sure Claude Code is logged in."
        case .tokenParsingFailed:
            return "Failed to parse OAuth token from Keychain."
        case .invalidResponse:
            return "Invalid API response."
        case .apiError(let code, _):
            return "API error (HTTP \(code))."
        }
    }
}
