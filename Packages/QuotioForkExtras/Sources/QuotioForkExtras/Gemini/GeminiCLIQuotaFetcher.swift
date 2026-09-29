//
//  GeminiCLIQuotaFetcher.swift
//  QuotioForkExtras — Gemini CLI quota (native + management-relay paths)
//
//  Ported from the fork. Two credential paths survive the port:
//  1. native `~/.gemini` files with direct Google token refresh;
//  2. the CLIProxyAPI management-api relay (`apiCall` with `$TOKEN$`
//     substitution — a CLIProxyAPI-plus capability) over a local or remote
//  connection. The pre-port "monitor vault" path is gone: those accounts
//  migrate into the Rust host, which has no Gemini collection.
//

import Foundation
import QuotioApplication
import QuotioDomain

// MARK: - Output types

public struct GeminiSeriesQuota: Identifiable, Equatable, Sendable {
    public let name: String
    public let percentage: Double
    public let resetTime: String

    public var id: String { name }

    public init(name: String, percentage: Double, resetTime: String) {
        self.name = name
        self.percentage = percentage
        self.resetTime = resetTime
    }
}

public struct GeminiQuotaSnapshot: Equatable, Identifiable, Sendable {
    public let accountKey: String
    public let series: [GeminiSeriesQuota]
    public let lastUpdated: Date
    public let planType: String?

    public var id: String { accountKey }

    public init(accountKey: String, series: [GeminiSeriesQuota], lastUpdated: Date, planType: String?) {
        self.accountKey = accountKey
        self.series = series
        self.lastUpdated = lastUpdated
        self.planType = planType
    }
}

/// Tier/eligibility explanation when quota cannot be fetched (e.g. Google
/// retired the free-tier quota API — UNSUPPORTED_CLIENT, migrate to
/// Antigravity).
public struct GeminiDiagnostics: Equatable, Sendable {
    public let account: String
    public let tierName: String?
    public let message: String

    public init(account: String, tierName: String?, message: String) {
        self.account = account
        self.tierName = tierName
        self.message = message
    }
}

// MARK: - Support types

private extension String {
    var geminiFormEncoded: String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return addingPercentEncoding(withAllowedCharacters: allowed) ?? self
    }
}

nonisolated struct GeminiAccountsFile: Codable, Sendable {
    let active: String?
    let old: [String]?
}

nonisolated struct GeminiJWTClaims: Sendable {
    let email: String?
    let emailVerified: Bool
    let name: String?
    let givenName: String?
    let familyName: String?
    let subject: String?
}

nonisolated struct GeminiCLIAccountInfo: Sendable {
    let email: String
    let name: String?
    let isActive: Bool
    let expiryDate: Date?
}

nonisolated struct GeminiCLIAuthFile: Codable, Sendable {
    let idToken: String?
    let accessToken: String?
    let scope: String?
    let refreshToken: String?
    let tokenType: String?
    let expiryDate: Double?

    enum CodingKeys: String, CodingKey {
        case idToken = "id_token"
        case accessToken = "access_token"
        case scope
        case refreshToken = "refresh_token"
        case tokenType = "token_type"
        case expiryDate = "expiry_date"
    }
}

// MARK: - Fetcher

public actor GeminiCLIQuotaFetcher {
    public static let shared = GeminiCLIQuotaFetcher()

    private let authFilePath = "~/.gemini/oauth_creds.json"
    private let accountsFilePath = "~/.gemini/google_accounts.json"
    private let quotaURL = "https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota"
    private let codeAssistURL = "https://cloudcode-pa.googleapis.com/v1internal:loadCodeAssist"
    private let tokenURL = "https://oauth2.googleapis.com/token"
    private let oauthClientID = "681255809395-oo8ft2oprdrnp9e3aqf6av3hmdib135j.apps.googleusercontent.com"
    private let oauthClientSecret = "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"
    private var session: URLSession
    private let requestHeaders = [
        "Authorization": "Bearer $TOKEN$",
        "Content-Type": "application/json",
    ]

    private struct ParsedBucket: Sendable {
        let modelId: String
        let tokenType: String?
        let remainingFraction: Double?
        let remainingAmount: Double?
        let resetTime: String?
    }

    private struct BucketGroupDefinition: Sendable {
        let id: String
        let label: String
        let preferredModelId: String?
        let modelIds: [String]
    }

    private struct BucketGroupState: Sendable {
        var id: String
        var label: String
        var tokenType: String?
        var modelIds: [String]
        var preferredModelId: String?
        var preferredBucket: ParsedBucket?
        var fallbackRemainingFraction: Double?
        var fallbackRemainingAmount: Double?
        var fallbackResetTime: String?
    }

    private let quotaGroups: [BucketGroupDefinition] = [
        BucketGroupDefinition(
            id: "gemini-flash-lite-series",
            label: "Gemini Flash Lite Series",
            preferredModelId: "gemini-2.5-flash-lite",
            modelIds: ["gemini-2.5-flash-lite"]
        ),
        BucketGroupDefinition(
            id: "gemini-flash-series",
            label: "Gemini Flash Series",
            preferredModelId: "gemini-3-flash-preview",
            modelIds: ["gemini-3-flash-preview", "gemini-2.5-flash"]
        ),
        BucketGroupDefinition(
            id: "gemini-pro-series",
            label: "Gemini Pro Series",
            preferredModelId: "gemini-3.1-pro-preview",
            modelIds: ["gemini-3.1-pro-preview", "gemini-3-pro-preview", "gemini-2.5-pro"]
        ),
    ]

    public init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        session = URLSession(configuration: configuration)
    }

    // MARK: - Public entry points

    /// Fetches quota for every discoverable Gemini account: relay results for
    /// proxy-hosted auth files, plus the native `~/.gemini` login.
    public func fetchAll(apiClient: (any ProxyManagementAPI)?) async -> [GeminiQuotaSnapshot] {
        var results: [String: GeminiQuotaSnapshot] = [:]
        if let apiClient {
            for snapshot in await fetchRelayQuotas(apiClient: apiClient) where results[snapshot.accountKey] == nil {
                results[snapshot.accountKey] = snapshot
            }
        }
        if let native = await fetchNativeQuota(), results[native.accountKey] == nil {
            results[native.accountKey] = native
        }
        return Array(results.values)
    }

    /// Quota via the proxy management relay (`apiCall`, plus-binary feature).
    public func fetchRelayQuotas(apiClient: any ProxyManagementAPI) async -> [GeminiQuotaSnapshot] {
        guard let authFiles = try? await apiClient.fetchAuthFiles() else { return [] }
        let files = authFiles.filter {
            $0.provider.lowercased().contains("gemini") &&
                !$0.disabled &&
                !$0.unavailable &&
                $0.runtimeOnly != true
        }
        var results: [GeminiQuotaSnapshot] = []
        for file in files {
            guard let authIndex = file.authIndex?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !authIndex.isEmpty,
                  let projectId = resolveProjectId(account: file.account, name: file.name) else {
                continue
            }
            if let snapshot = try? await fetchRelayQuota(authIndex: authIndex, projectId: projectId, apiClient: apiClient, accountKey: file.name) {
                results.append(snapshot)
            }
        }
        return results
    }

    /// Quota from the native Gemini CLI credential with token refresh.
    public func fetchNativeQuota() async -> GeminiQuotaSnapshot? {
        guard var auth = readAuthFile(), var accessToken = auth.accessToken else { return nil }
        let path = NSString(string: authFilePath).expandingTildeInPath
        if shouldRefresh(auth), let refreshToken = auth.refreshToken,
           let refreshed = try? await refresh(refreshToken: refreshToken) {
            accessToken = refreshed.accessToken
            auth = applying(refreshed, to: auth)
            try? persist(auth, expectedRefreshToken: refreshToken, path: path)
        }
        do {
            return try await fetchDirectQuota(accessToken: accessToken)
        } catch DirectGeminiError.authenticationRequired {
            let latest = readAuthFile() ?? auth
            guard let refreshToken = latest.refreshToken,
                  let refreshed = try? await refresh(refreshToken: refreshToken) else { return nil }
            let updated = applying(refreshed, to: latest)
            try? persist(updated, expectedRefreshToken: refreshToken, path: path)
            return try? await fetchDirectQuota(accessToken: refreshed.accessToken)
        } catch {
            return nil
        }
    }

    /// Whether the native Gemini CLI login exists.
    public func hasNativeCredential() -> Bool {
        readAuthFile() != nil
    }

    /// Tier/eligibility diagnostics for the native login. Google retired
    /// the free-tier quota API (UNSUPPORTED_CLIENT → migrate to Antigravity);
    /// when that happens `loadCodeAssist` returns no project and quota
    /// fetching is impossible — surface why instead of showing nothing.
    public func nativeDiagnostics() async -> GeminiDiagnostics? {
        guard let auth = readAuthFile() else { return nil }
        var accessToken = auth.accessToken
        if shouldRefresh(auth), let refreshToken = auth.refreshToken,
           let refreshed = try? await refresh(refreshToken: refreshToken) {
            accessToken = refreshed.accessToken
        }
        guard let accessToken,
              let payload = try? await postJSON(url: codeAssistURL, accessToken: accessToken, body: [
                  "metadata": [
                      "ideType": "IDE_UNSPECIFIED",
                      "platform": "PLATFORM_UNSPECIFIED",
                      "pluginType": "GEMINI",
                  ],
              ]) else {
            return nil
        }
        let account = getAccountInfo()?.email ?? "gemini-cli"
        if let ineligible = payload["ineligibleTiers"] as? [[String: Any]],
           let reason = stringValue(ineligible.first?["reasonMessage"]) {
            return GeminiDiagnostics(
                account: account,
                tierName: stringValue(ineligible.first?["tierName"]),
                message: reason
            )
        }
        guard stringValue(payload["cloudaicompanionProject"] ?? payload["projectId"] ?? payload["project"]) == nil else {
            return nil // quota should have worked; not a diagnostics case
        }
        return GeminiDiagnostics(
            account: account,
            tierName: stringValue((payload["allowedTiers"] as? [[String: Any]])?.first?["name"]),
            message: "Google did not return a quota project for this account, so quota cannot be fetched."
        )
    }

    // MARK: - Relay path

    private func fetchRelayQuota(
        authIndex: String,
        projectId: String,
        apiClient: any ProxyManagementAPI,
        accountKey: String
    ) async throws -> GeminiQuotaSnapshot? {
        let requestBody = try jsonString(["project": projectId])
        let response = try await apiClient.apiCall(ProxyAPICall(
            authIndex: authIndex,
            method: "POST",
            url: quotaURL,
            header: requestHeaders,
            data: requestBody
        ))

        guard 200..<300 ~= response.statusCode,
              let body = response.body,
              let payload = parseJSON(body) else {
            return nil
        }

        let buckets = parseBuckets(from: payload)
        let series = buildSeries(from: buckets)
        guard !series.isEmpty else { return nil }

        let planType = await fetchPlanType(authIndex: authIndex, projectId: projectId, apiClient: apiClient)
        return GeminiQuotaSnapshot(
            accountKey: accountKey,
            series: series,
            lastUpdated: Date(),
            planType: planType
        )
    }

    private func fetchPlanType(authIndex: String, projectId: String, apiClient: any ProxyManagementAPI) async -> String? {
        do {
            let body: [String: Any] = [
                "cloudaicompanionProject": projectId,
                "metadata": [
                    "ideType": "IDE_UNSPECIFIED",
                    "platform": "PLATFORM_UNSPECIFIED",
                    "pluginType": "GEMINI",
                    "duetProject": projectId,
                ],
            ]
            let response = try await apiClient.apiCall(ProxyAPICall(
                authIndex: authIndex,
                method: "POST",
                url: codeAssistURL,
                header: requestHeaders,
                data: try jsonString(body)
            ))
            guard 200..<300 ~= response.statusCode,
                  let responseBody = response.body,
                  let payload = parseJSON(responseBody) else {
                return nil
            }
            return resolveTierLabel(from: payload)
        } catch {
            return nil
        }
    }

    // MARK: - Native path

    private struct DirectTokenResponse: Decodable {
        let accessToken: String
        let refreshToken: String?
        let idToken: String?
        let expiresIn: Int?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case idToken = "id_token"
            case expiresIn = "expires_in"
        }
    }

    private enum DirectGeminiError: LocalizedError {
        case authenticationRequired
        case http(Int)
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .authenticationRequired: "Gemini CLI login expired."
            case .http(let status): "Gemini quota request failed with HTTP \(status)."
            case .invalidResponse: "Gemini quota returned an invalid response."
            }
        }
    }

    private func shouldRefresh(_ auth: GeminiCLIAuthFile) -> Bool {
        guard let expiry = auth.expiryDate else { return false }
        return Date(timeIntervalSince1970: expiry / 1000).timeIntervalSinceNow < 300
    }

    private func refresh(refreshToken: String) async throws -> DirectTokenResponse {
        var request = URLRequest(url: URL(string: tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let values = [
            "client_id=\(oauthClientID.geminiFormEncoded)",
            "client_secret=\(oauthClientSecret.geminiFormEncoded)",
            "grant_type=refresh_token",
            "refresh_token=\(refreshToken.geminiFormEncoded)",
        ].joined(separator: "&")
        request.httpBody = Data(values.utf8)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw DirectGeminiError.authenticationRequired
        }
        return try JSONDecoder().decode(DirectTokenResponse.self, from: data)
    }

    private func applying(_ response: DirectTokenResponse, to auth: GeminiCLIAuthFile) -> GeminiCLIAuthFile {
        GeminiCLIAuthFile(
            idToken: response.idToken ?? auth.idToken,
            accessToken: response.accessToken,
            scope: auth.scope,
            refreshToken: response.refreshToken ?? auth.refreshToken,
            tokenType: auth.tokenType,
            expiryDate: response.expiresIn.map { Date().addingTimeInterval(TimeInterval($0)).timeIntervalSince1970 * 1000 } ?? auth.expiryDate
        )
    }

    /// Atomic write guarded by a refresh-token compare-and-swap, mirroring
    /// the fork's SecureAtomicFileWriter semantics (0600, no clobber).
    private func persist(_ auth: GeminiCLIAuthFile, expectedRefreshToken: String, path: String) throws {
        guard let current = readAuthFile(), current.refreshToken == expectedRefreshToken else { return }
        let data = try JSONEncoder().encode(auth)
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
    }

    private func fetchDirectQuota(accessToken: String) async throws -> GeminiQuotaSnapshot {
        let projectPayload = try await postJSON(
            url: codeAssistURL,
            accessToken: accessToken,
            body: [
                "metadata": [
                    "ideType": "IDE_UNSPECIFIED",
                    "platform": "PLATFORM_UNSPECIFIED",
                    "pluginType": "GEMINI",
                ],
            ]
        )
        guard let projectID = stringValue(projectPayload["cloudaicompanionProject"] ?? projectPayload["projectId"] ?? projectPayload["project"]) else {
            throw DirectGeminiError.invalidResponse
        }
        let quotaPayload = try await postJSON(url: quotaURL, accessToken: accessToken, body: ["project": projectID])
        let series = buildSeries(from: parseBuckets(from: quotaPayload))
        guard !series.isEmpty else { throw DirectGeminiError.invalidResponse }
        let accountKey = getAccountInfo()?.email ?? "gemini-cli"
        return GeminiQuotaSnapshot(
            accountKey: accountKey,
            series: series,
            lastUpdated: Date(),
            planType: resolveTierLabel(from: projectPayload)
        )
    }

    private func postJSON(url: String, accessToken: String, body: [String: Any]) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("GeminiCLI", forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw DirectGeminiError.invalidResponse }
        if http.statusCode == 401 || http.statusCode == 403 { throw DirectGeminiError.authenticationRequired }
        guard 200..<300 ~= http.statusCode else { throw DirectGeminiError.http(http.statusCode) }
        guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw DirectGeminiError.invalidResponse }
        return value
    }

    // MARK: - Native credential reading

    func readAuthFile() -> GeminiCLIAuthFile? {
        let expandedPath = NSString(string: authFilePath).expandingTildeInPath
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: expandedPath)) else { return nil }
        return try? JSONDecoder().decode(GeminiCLIAuthFile.self, from: data)
    }

    func readAccountsFile() -> GeminiAccountsFile? {
        let expandedPath = NSString(string: accountsFilePath).expandingTildeInPath
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: expandedPath)) else { return nil }
        return try? JSONDecoder().decode(GeminiAccountsFile.self, from: data)
    }

    func decodeJWT(token: String) -> GeminiJWTClaims? {
        let segments = token.split(separator: ".")
        guard segments.count >= 2 else { return nil }

        var base64 = String(segments[1])
        let padLength = (4 - base64.count % 4) % 4
        base64 += String(repeating: "=", count: padLength)
        base64 = base64.replacingOccurrences(of: "-", with: "+")
        base64 = base64.replacingOccurrences(of: "_", with: "/")

        guard let data = Data(base64Encoded: base64) else { return nil }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return GeminiJWTClaims(
            email: json["email"] as? String,
            emailVerified: json["email_verified"] as? Bool ?? false,
            name: json["name"] as? String,
            givenName: json["given_name"] as? String,
            familyName: json["family_name"] as? String,
            subject: json["sub"] as? String
        )
    }

    func getAccountInfo() -> GeminiCLIAccountInfo? {
        guard let authFile = readAuthFile() else { return nil }
        var email: String? = readAccountsFile()?.active
        var name: String?
        if email == nil, let idToken = authFile.idToken, let claims = decodeJWT(token: idToken) {
            email = claims.email
            name = claims.name
        }
        guard let accountEmail = email else { return nil }
        let expiryDate = authFile.expiryDate.map { Date(timeIntervalSince1970: $0 / 1000) }
        return GeminiCLIAccountInfo(email: accountEmail, name: name, isActive: true, expiryDate: expiryDate)
    }

    // MARK: - Bucket parsing and grouping

    private func parseBuckets(from payload: [String: Any]) -> [ParsedBucket] {
        guard let buckets = payload["buckets"] as? [[String: Any]] else { return [] }

        return buckets.compactMap { bucket in
            guard var modelId = stringValue(bucket["modelId"] ?? bucket["model_id"]) else { return nil }
            if modelId.hasSuffix("_vertex") {
                modelId = String(modelId.dropLast("_vertex".count))
            }

            let remainingFraction = numberValue(bucket["remainingFraction"] ?? bucket["remaining_fraction"])
            let remainingAmount = numberValue(bucket["remainingAmount"] ?? bucket["remaining_amount"])
            let resetTime = stringValue(bucket["resetTime"] ?? bucket["reset_time"])
            let fallbackFraction: Double?
            if remainingFraction == nil {
                if let remainingAmount {
                    fallbackFraction = remainingAmount <= 0 ? 0 : nil
                } else if resetTime != nil {
                    fallbackFraction = 0
                } else {
                    fallbackFraction = nil
                }
            } else {
                fallbackFraction = remainingFraction
            }

            return ParsedBucket(
                modelId: modelId,
                tokenType: stringValue(bucket["tokenType"] ?? bucket["token_type"]),
                remainingFraction: fallbackFraction,
                remainingAmount: remainingAmount,
                resetTime: resetTime
            )
        }
    }

    private func buildSeries(from buckets: [ParsedBucket]) -> [GeminiSeriesQuota] {
        guard !buckets.isEmpty else { return [] }

        let groupLookup = Dictionary(uniqueKeysWithValues: quotaGroups.flatMap { group in
            group.modelIds.map { ($0, group) }
        })
        let groupOrder = Dictionary(uniqueKeysWithValues: quotaGroups.enumerated().map { ($0.element.id, $0.offset) })
        var grouped: [String: BucketGroupState] = [:]

        for bucket in buckets {
            guard !isIgnoredGeminiModel(bucket.modelId) else { continue }

            let definition = groupLookup[bucket.modelId]
            let groupId = definition?.id ?? bucket.modelId
            let label = definition?.label ?? bucket.modelId
            let tokenType = bucket.tokenType ?? ""
            let mapKey = "\(groupId)::\(tokenType)"

            if grouped[mapKey] == nil {
                grouped[mapKey] = BucketGroupState(
                    id: tokenType.isEmpty ? groupId : "\(groupId)-\(tokenType)",
                    label: label,
                    tokenType: bucket.tokenType,
                    modelIds: [bucket.modelId],
                    preferredModelId: definition?.preferredModelId,
                    preferredBucket: definition?.preferredModelId == bucket.modelId ? bucket : nil,
                    fallbackRemainingFraction: bucket.remainingFraction,
                    fallbackRemainingAmount: bucket.remainingAmount,
                    fallbackResetTime: bucket.resetTime
                )
                continue
            }

            var existing = grouped[mapKey]!
            existing.fallbackRemainingFraction = minNullable(existing.fallbackRemainingFraction, bucket.remainingFraction)
            existing.fallbackRemainingAmount = minNullable(existing.fallbackRemainingAmount, bucket.remainingAmount)
            existing.fallbackResetTime = pickEarlierResetTime(existing.fallbackResetTime, bucket.resetTime)
            if !existing.modelIds.contains(bucket.modelId) {
                existing.modelIds.append(bucket.modelId)
            }
            if existing.preferredModelId == bucket.modelId {
                existing.preferredBucket = bucket
            }
            grouped[mapKey] = existing
        }

        return grouped.values.sorted { lhs, rhs in
            let lhsGroupId = groupId(from: lhs.id, tokenType: lhs.tokenType)
            let rhsGroupId = groupId(from: rhs.id, tokenType: rhs.tokenType)
            let orderDiff = (groupOrder[lhsGroupId] ?? Int.max) - (groupOrder[rhsGroupId] ?? Int.max)
            if orderDiff != 0 { return orderDiff < 0 }
            return (lhs.tokenType ?? "").localizedCaseInsensitiveCompare(rhs.tokenType ?? "") == .orderedAscending
        }.compactMap { group in
            let source = group.preferredBucket
            let remainingFraction = source?.remainingFraction ?? group.fallbackRemainingFraction
            guard let remainingFraction else { return nil }
            let percent = max(0, min(100, remainingFraction * 100))
            let resetTime = source?.resetTime ?? group.fallbackResetTime ?? ""
            return GeminiSeriesQuota(name: group.label, percentage: percent, resetTime: resetTime)
        }
    }

    private func resolveProjectId(account: String?, name: String) -> String? {
        if let account, let projectId = extractProjectId(from: account) {
            return projectId
        }
        return extractProjectId(from: name)
    }

    private func extractProjectId(from value: String) -> String? {
        let pattern = #"\(([^()]+)\)"#
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let range = NSRange(value.startIndex..<value.endIndex, in: value)
            let matches = regex.matches(in: value, range: range)
            if let match = matches.last,
               let swiftRange = Range(match.range(at: 1), in: value) {
                let candidate = String(value[swiftRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !candidate.isEmpty { return candidate }
            }
        }

        let filenamePattern = #"project-[A-Za-z0-9-]+"#
        if let regex = try? NSRegularExpression(pattern: filenamePattern) {
            let range = NSRange(value.startIndex..<value.endIndex, in: value)
            if let match = regex.firstMatch(in: value, range: range),
               let swiftRange = Range(match.range, in: value) {
                return String(value[swiftRange])
            }
        }

        return nil
    }

    private func resolveTierLabel(from payload: [String: Any]) -> String? {
        let currentTier = payload["currentTier"] as? [String: Any] ?? payload["current_tier"] as? [String: Any]
        let paidTier = payload["paidTier"] as? [String: Any] ?? payload["paid_tier"] as? [String: Any]
        guard let rawId = stringValue(paidTier?["id"] ?? currentTier?["id"]) else { return nil }

        switch rawId.lowercased() {
        case "free-tier": return "Free"
        case "legacy-tier": return "Legacy"
        case "standard-tier": return "Standard"
        case "g1-pro-tier": return "Pro"
        case "g1-ultra-tier": return "Ultra"
        default: return rawId
        }
    }

    // MARK: - Small helpers

    private func parseJSON(_ body: String) -> [String: Any]? {
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json
    }

    private func jsonString(_ value: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: value)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private func stringValue(_ value: Any?) -> String? {
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        return nil
    }

    private func numberValue(_ value: Any?) -> Double? {
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasSuffix("%"), let parsed = Double(trimmed.dropLast()) {
                return parsed / 100
            }
            return Double(trimmed)
        }
        return nil
    }

    private func isIgnoredGeminiModel(_ modelId: String) -> Bool {
        modelId == "gemini-2.0-flash" || modelId.hasPrefix("gemini-2.0-flash-")
    }

    private func minNullable(_ lhs: Double?, _ rhs: Double?) -> Double? {
        guard let lhs else { return rhs }
        guard let rhs else { return lhs }
        return min(lhs, rhs)
    }

    private func pickEarlierResetTime(_ lhs: String?, _ rhs: String?) -> String? {
        guard let lhs else { return rhs }
        guard let rhs else { return lhs }

        let formatter = ISO8601DateFormatter()
        let lhsDate = formatter.date(from: lhs)
        let rhsDate = formatter.date(from: rhs)

        switch (lhsDate, rhsDate) {
        case let (lhsDate?, rhsDate?):
            return lhsDate <= rhsDate ? lhs : rhs
        case (nil, _?):
            return rhs
        default:
            return lhs
        }
    }

    private func groupId(from id: String, tokenType: String?) -> String {
        guard let tokenType, !tokenType.isEmpty else { return id }
        let suffix = "-\(tokenType)"
        return id.hasSuffix(suffix) ? String(id.dropLast(suffix.count)) : id
    }
}
