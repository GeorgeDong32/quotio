//
//  RequestLogsScreen.swift
//  QuotioForkExtras — request log viewer (fork)
//

import QuotioPresentation
import SwiftUI

/// Fork request-log screen: proxy request history with stats, provider
/// filter, and expandable fallback-attempt traces. Ported from the fork's
/// LogsScreen requests tab (the system-log tab was tied to upstream UI
/// that no longer exists).
public struct RequestLogsScreen: View {
    public init() {}

    @Environment(FallbackScreenModel.self) private var screenModel
    @State private var searchText = ""
    @State private var requestFilterProvider: String?
    @State private var expandedTraces: Set<UUID> = []

    private var tracker: RequestTracker { screenModel.tracker }

    private var filteredRequests: [RequestLog] {
        var requests = tracker.requestHistory
        if let provider = requestFilterProvider {
            requests = requests.filter { $0.effectiveProvider == provider }
        }
        if !searchText.isEmpty {
            requests = requests.filter {
                ($0.effectiveProvider?.localizedCaseInsensitiveContains(searchText) ?? false) ||
                    ($0.model?.localizedCaseInsensitiveContains(searchText) ?? false) ||
                    $0.endpoint.localizedCaseInsensitiveContains(searchText)
            }
        }
        return requests
    }

    public var body: some View {
        Group {
            if tracker.requestHistory.isEmpty {
                ContentUnavailableView {
                    Label("logs.noRequests".localized(), systemImage: "arrow.up.arrow.down")
                } description: {
                    Text("logs.requestsWillAppear".localized())
                }
            } else {
                VStack(spacing: 0) {
                    statsHeader
                    Divider()
                    List(filteredRequests) { request in
                        RequestRow(
                            request: request,
                            isTraceExpanded: expandedTraces.contains(request.id),
                            onToggleTrace: {
                                if expandedTraces.contains(request.id) {
                                    expandedTraces.remove(request.id)
                                } else {
                                    expandedTraces.insert(request.id)
                                }
                            }
                        )
                    }
                }
            }
        }
        .navigationTitle("settings.requestLogs".localized())
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(role: .destructive) {
                    tracker.clearHistory()
                } label: {
                    Image(systemName: "trash")
                }
                .help("logs.clearHistory".localized())
                .disabled(tracker.requestHistory.isEmpty)
            }
        }
        .searchable(text: $searchText, prompt: "logs.searchPrompt".localized())
        .task { tracker.start() }
        .onDisappear { tracker.stop() }
    }

    private var statsHeader: some View {
        let stats = tracker.stats

        return HStack(spacing: 24) {
            StatItem(title: "logs.stats.totalRequests".localized(), value: "\(stats.totalRequests)")
            StatItem(title: "logs.stats.successRate".localized(), value: String(format: "%.0f%%", stats.successRate))
            StatItem(title: "logs.stats.totalTokens".localized(), value: stats.totalTokens.formattedTokenCount)
            StatItem(title: "logs.stats.avgDuration".localized(), value: "\(stats.averageDurationMs)ms")

            Spacer()

            Picker("Provider", selection: $requestFilterProvider) {
                Text("logs.filter.allProviders".localized()).tag(nil as String?)
                Divider()
                ForEach(Array(stats.byProvider.keys.sorted()), id: \.self) { provider in
                    Text(RequestLog.displayName(forProvider: provider)).tag(provider as String?)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 140)
        }
        .padding()
        .background(.regularMaterial)
    }
}

// MARK: - Stat Item

private struct StatItem: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.title3, design: .monospaced, weight: .semibold))
                .monospacedDigit()
        }
    }
}

// MARK: - Request Row

private struct RequestRow: View {
    let request: RequestLog
    let isTraceExpanded: Bool
    let onToggleTrace: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 12) {
                Text(request.formattedTimestamp)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 70, alignment: .leading)

                statusBadge
                providerBadge
                    .frame(width: 104, alignment: .leading)

                VStack(alignment: .leading, spacing: 2) {
                    if request.hasFallbackRoute {
                        Text(request.model ?? "unknown")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.orange)
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.right")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(request.resolvedModel ?? "")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    } else if let model = request.model {
                        Text(model)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(width: 180, alignment: .leading)

                if let tokens = request.formattedTokens {
                    HStack(spacing: 4) {
                        Image(systemName: "text.word.spacing")
                            .font(.caption2)
                        Text(tokens)
                            .font(.system(.caption, design: .monospaced))
                    }
                    .foregroundStyle(.secondary)
                    .frame(width: 70, alignment: .trailing)
                } else {
                    Text("-")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .frame(width: 70, alignment: .trailing)
                }

                Text(request.formattedDuration)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 60, alignment: .trailing)

                Spacer()

                HStack(spacing: 4) {
                    Text("\(request.requestSize.formatted())B")
                        .foregroundStyle(.secondary)
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text("\(request.responseSize.formatted())B")
                        .foregroundStyle(.secondary)
                }
                .font(.system(.caption2, design: .monospaced))
            }

            if let attempts = request.fallbackAttempts, !attempts.isEmpty {
                Button(action: onToggleTrace) {
                    HStack(spacing: 6) {
                        Image(systemName: isTraceExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption2)
                        Text("logs.fallbackTrace".localized())
                            .font(.caption2)
                        Spacer()
                    }
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if isTraceExpanded {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(attempts.enumerated()), id: \.offset) { index, attempt in
                            HStack(spacing: 6) {
                                Text("\(index + 1).")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 18, alignment: .trailing)
                                Text("\(attempt.provider) → \(attempt.modelId)")
                                    .font(.caption2)
                                    .lineLimit(1)
                                Text(attemptOutcomeLabel(attempt.outcome))
                                    .font(.caption2)
                                    .foregroundStyle(attemptOutcomeColor(attempt.outcome))
                                if let reason = attempt.reason {
                                    Text(reason.displayValue)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }

                        if let errorMessage = request.errorMessage, !errorMessage.isEmpty {
                            HStack(spacing: 6) {
                                Text("logs.fallbackBackendResponse".localized())
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(errorMessage)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(3)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                    .padding(.leading, 24)
                    .padding(.top, 4)
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var providerBadge: some View {
        if let provider = request.effectiveProvider {
            Text(RequestLog.displayName(forProvider: provider))
                .font(.system(.caption2, weight: .semibold))
                .foregroundStyle(providerColor(provider))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(providerColor(provider).opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .lineLimit(1)
        } else {
            Text("logs.provider.unknown".localized())
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private func providerColor(_ provider: String) -> Color {
        let id = RequestLog.canonicalProviderID(provider)
        if let known = AIProvider(rawValue: id) {
            return providerTint(known)
        }
        switch id {
        case "openai": return .green
        case "gemini": return .blue
        case "deepseek": return .indigo
        default: return .gray
        }
    }

    private func providerTint(_ provider: AIProvider) -> Color {
        switch provider {
        case .gemini: return .blue
        case .claude: return .orange
        case .codex: return .green
        case .glm: return .blue
        case .kiro: return .teal
        case .copilot: return .gray
        case .antigravity: return .indigo
        default: return .gray
        }
    }

    private var statusBadge: some View {
        Text(request.statusBadge)
            .font(.system(.caption2, design: .monospaced, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(statusColor)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private var statusColor: Color {
        guard let code = request.statusCode else { return .gray }
        switch code {
        case 200..<300: return .green
        case 400..<500: return .orange
        case 500..<600: return .red
        default: return .gray
        }
    }

    private func attemptOutcomeLabel(_ outcome: FallbackAttemptOutcome) -> String {
        switch outcome {
        case .failed: "logs.fallbackAttempt.failed".localized()
        case .success: "logs.fallbackAttempt.success".localized()
        case .skipped: "logs.fallbackAttempt.skipped".localized()
        }
    }

    private func attemptOutcomeColor(_ outcome: FallbackAttemptOutcome) -> Color {
        switch outcome {
        case .failed: .orange
        case .success: .green
        case .skipped: .secondary
        }
    }
}
