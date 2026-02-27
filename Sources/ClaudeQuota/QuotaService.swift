import Foundation
import Security

func log(_ message: String) {
    let ts = ISO8601DateFormatter().string(from: Date())
    FileHandle.standardError.write(Data("[\(ts)] \(message)\n".utf8))
}

struct QuotaInfo {
    let utilization5h: Double    // 0.0 to 1.0+ (5-hour window)
    let utilization7d: Double    // 0.0 to 1.0+ (7-day window)
    let reset5h: Date?           // server-provided reset timestamp
    let status: String?          // "allowed", "allowed_warning", "rejected"
    let representativeClaim: String?
    let fallbackPercentage: Double?

    var percentUsed: Int {
        min(Int(utilization5h * 100), 100)
    }

    var timeUntilReset: String {
        guard let reset = reset5h else { return "--" }
        let remaining = reset.timeIntervalSinceNow
        guard remaining > 0 else { return "0m" }
        let hours = Int(remaining) / 3600
        let minutes = (Int(remaining) % 3600) / 60
        if hours > 0 {
            return "\(hours)h\(String(format: "%02d", minutes))m"
        } else {
            return "\(minutes)m"
        }
    }

    var minutesUntilReset: Double? {
        guard let reset = reset5h else { return nil }
        return reset.timeIntervalSinceNow / 60
    }
}

final class QuotaService {
    static let shared = QuotaService()

    private let keychainService = "Claude Code-credentials"
    private let apiURL = URL(string: "https://api.anthropic.com/v1/messages")!
    private init() {}

    // MARK: - Keychain (read-only)

    private func readAccessToken() throws -> String {
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
              let accessToken = oauth["accessToken"] as? String
        else {
            throw QuotaError.tokenParsingFailed
        }

        return accessToken
    }

    // MARK: - API Probe

    func fetchQuota() async throws -> QuotaInfo {
        let token = try readAccessToken()
        let result = try await probeAPI(token: token)

        if case .unauthorized = result {
            throw QuotaError.tokenExpired
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
            "model": "claude-3-haiku-20240307",
            "max_tokens": 1,
            "messages": [["role": "user", "content": "."]],
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

        // Parse reset timestamp
        var reset5h: Date?
        if let resetTs = doubleHeader(headers, key: "anthropic-ratelimit-unified-5h-reset") {
            reset5h = Date(timeIntervalSince1970: resetTs)
        }

        let resetStr: String
        if let r = reset5h {
            let fmt = DateFormatter()
            fmt.dateFormat = "HH:mm"
            resetStr = fmt.string(from: r)
        } else {
            resetStr = "?"
        }

        log("Quota: 5h=\(String(format: "%.1f", util5h * 100))% 7d=\(String(format: "%.1f", util7d * 100))% reset=\(resetStr) status=\(status ?? "?")")

        return QuotaInfo(
            utilization5h: util5h,
            utilization7d: util7d,
            reset5h: reset5h,
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
    case tokenExpired
    case invalidResponse
    case apiError(Int, String)

    var errorDescription: String? {
        switch self {
        case .keychainAccessFailed(let status):
            if status == errSecItemNotFound {
                return "Token Claude Code introuvable. Lance 'claude auth login' d'abord."
            }
            return "Acces Keychain refuse (code \(status)). Relance l'app et clique 'Toujours autoriser'."
        case .tokenParsingFailed:
            return "Token OAuth invalide. Lance 'claude auth login' pour te reconnecter."
        case .tokenExpired:
            return "Token expire. Utilise Claude Code pour le rafraichir automatiquement."
        case .invalidResponse:
            return "Reponse API invalide. Verifie ta connexion internet."
        case .apiError(let code, _):
            if code == 429 {
                return "Rate limit API atteint. Reessai dans quelques minutes."
            }
            return "Erreur API (HTTP \(code)). Voir les logs pour plus de details."
        }
    }
}
