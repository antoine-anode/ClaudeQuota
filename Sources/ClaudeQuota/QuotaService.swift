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

    var estimatedTimeUntilRelief: String {
        guard utilization5h > 0 else { return "5h00m" }
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
    private let tokenURL = URL(string: "https://platform.claude.com/v1/oauth/token")!
    private let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"

    private var isRefreshingToken = false

    private init() {}

    // MARK: - Keychain

    private func readKeychain() throws -> (accessToken: String, refreshToken: String) {
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
              let accessToken = oauth["accessToken"] as? String,
              let refreshToken = oauth["refreshToken"] as? String
        else {
            throw QuotaError.tokenParsingFailed
        }

        return (accessToken, refreshToken)
    }

    private func writeKeychain(accessToken: String, refreshToken: String) throws {
        // Read existing keychain data to preserve other fields
        let readQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var existingResult: AnyObject?
        SecItemCopyMatching(readQuery as CFDictionary, &existingResult)

        var credentials: [String: Any]
        if let existingData = existingResult as? Data,
           let existing = try? JSONSerialization.jsonObject(with: existingData) as? [String: Any]
        {
            credentials = existing
        } else {
            credentials = [:]
        }

        // Update only the OAuth tokens
        credentials["claudeAiOauth"] = [
            "accessToken": accessToken,
            "refreshToken": refreshToken,
        ]

        let data = try JSONSerialization.data(withJSONObject: credentials)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
        ]
        let update: [String: Any] = [
            kSecValueData as String: data,
        ]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)

        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw QuotaError.keychainWriteFailed(addStatus)
            }
        } else if status != errSecSuccess {
            throw QuotaError.keychainWriteFailed(status)
        }
    }

    // MARK: - Token Refresh

    private func refreshAccessToken() async throws -> String {
        let tokens = try readKeychain()
        log("Refreshing expired OAuth token...")

        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        let body = "grant_type=refresh_token&refresh_token=\(tokens.refreshToken)&client_id=\(clientID)"
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw QuotaError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "no body"
            log("Token refresh failed (HTTP \(httpResponse.statusCode)): \(String(errorBody.prefix(300)))")
            throw QuotaError.tokenRefreshFailed
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let newAccessToken = json["access_token"] as? String,
              let newRefreshToken = json["refresh_token"] as? String
        else {
            throw QuotaError.tokenParsingFailed
        }

        // Persist new tokens (rotation: old refresh token is now invalid)
        try writeKeychain(accessToken: newAccessToken, refreshToken: newRefreshToken)
        log("Token refreshed successfully")

        return newAccessToken
    }

    // MARK: - API Probe

    func fetchQuota() async throws -> QuotaInfo {
        let tokens = try readKeychain()
        let result = try await probeAPI(token: tokens.accessToken)

        // If 401, refresh token and retry once
        if case .unauthorized = result {
            guard !isRefreshingToken else {
                throw QuotaError.apiError(401, "Token refresh already in progress")
            }
            isRefreshingToken = true
            defer { isRefreshingToken = false }

            let newToken = try await refreshAccessToken()
            let retryResult = try await probeAPI(token: newToken)
            if case .success(let quota) = retryResult {
                return quota
            }
            throw QuotaError.apiError(401, "Still unauthorized after token refresh")
        }

        if case .success(let quota) = result {
            return quota
        }

        throw QuotaError.invalidResponse
    }

    private enum ProbeResult {
        case success(QuotaInfo)
        case unauthorized
    }

    private func probeAPI(token: String) async throws -> ProbeResult {
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

        if httpResponse.statusCode == 401 {
            return .unauthorized
        }

        if httpResponse.statusCode != 200 {
            let errorBody = String(data: data, encoding: .utf8) ?? "no body"
            log("HTTP \(httpResponse.statusCode): \(String(errorBody.prefix(300)))")
            throw QuotaError.apiError(httpResponse.statusCode, errorBody)
        }

        return .success(parseQuotaHeaders(httpResponse))
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
    case keychainWriteFailed(OSStatus)
    case tokenParsingFailed
    case tokenRefreshFailed
    case invalidResponse
    case apiError(Int, String)

    var errorDescription: String? {
        switch self {
        case .keychainAccessFailed(let status):
            return "Keychain read failed (status: \(status)). Make sure Claude Code is logged in."
        case .keychainWriteFailed(let status):
            return "Keychain write failed (status: \(status))."
        case .tokenParsingFailed:
            return "Failed to parse OAuth token."
        case .tokenRefreshFailed:
            return "Token refresh failed. Try running 'claude auth login' to re-authenticate."
        case .invalidResponse:
            return "Invalid API response."
        case .apiError(let code, _):
            return "API error (HTTP \(code))."
        }
    }
}
