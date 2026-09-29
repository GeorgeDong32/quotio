//
//  GeminiQuotaScreenModel.swift
//  QuotioForkExtras — Gemini quota screen backing model
//

import Foundation
import Observation
import QuotioApplication

/// Backing model for the fork's Gemini quota page: refreshes quota through
/// the management relay (local proxy first, then a saved remote connection)
/// plus the native `~/.gemini` login.
@MainActor
@Observable
public final class GeminiQuotaScreenModel {
    public private(set) var snapshots: [GeminiQuotaSnapshot] = []
    public private(set) var diagnostics: GeminiDiagnostics?
    public private(set) var lastRefresh: Date?
    public private(set) var isRefreshing = false
    public private(set) var lastError: String?

    private let apiClientProvider: @MainActor () -> (any ProxyManagementAPI)?
    private let fetcher = GeminiCLIQuotaFetcher.shared

    public init(apiClientProvider: @escaping @MainActor () -> (any ProxyManagementAPI)?) {
        self.apiClientProvider = apiClientProvider
    }

    public func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        lastError = nil
        diagnostics = nil
        defer { isRefreshing = false }

        do {
            let results = await fetcher.fetchAll(apiClient: apiClientProvider())
            snapshots = results
            lastRefresh = Date()
            if snapshots.isEmpty {
                // Explain an empty result instead of showing a bare
                // placeholder (e.g. Google retired the free-tier quota API).
                diagnostics = await fetcher.nativeDiagnostics()
            }
        } catch {
            lastError = error.localizedDescription
        }
    }
}
