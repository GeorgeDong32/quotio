//
//  GeminiQuotaScreen.swift
//  QuotioForkExtras — Gemini CLI quota display (fork)
//

import SwiftUI

/// Fork Gemini quota page: per-account series with remaining percentage,
/// reset windows, and plan tier. Refresh pulls the management relay (local
/// or saved remote connection) plus the native `~/.gemini` login.
public struct GeminiQuotaScreen: View {
    public init() {}

    @Environment(GeminiQuotaScreenModel.self) private var model

    public var body: some View {
        Form {
            if model.snapshots.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("gemini.noAccounts".localized(), systemImage: "sparkles")
                    } description: {
                        Text("gemini.noAccountsHint".localized())
                    }
                }
            }
            ForEach(model.snapshots) { snapshot in
                Section {
                    ForEach(snapshot.series, id: \.id) { series in
                        let percentText = "\(Int(series.percentage.rounded()))%"
                        let percentColor: Color = series.percentage > 20 ? .primary : .orange
                        HStack {
                            Text(series.name)
                                .font(.callout)
                            Spacer()
                            Text(percentText)
                                .font(.system(.callout, design: .monospaced))
                                .monospacedDigit()
                                .foregroundStyle(percentColor)
                        }
                        if !series.resetTime.isEmpty {
                            HStack {
                                Text("gemini.resets".localized())
                                Spacer()
                                Text(series.resetTime)
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    HStack {
                        Text(snapshot.accountKey)
                        if let tier = snapshot.planType {
                            Text(tier)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.blue.opacity(0.12))
                                .foregroundStyle(.blue)
                                .clipShape(Capsule())
                        }
                    }
                } footer: {
                    Text(String(
                        format: "gemini.lastUpdated".localized(),
                        snapshot.lastUpdated.formatted(date: .omitted, time: .shortened)
                    ))
                }
            }
            if let error = model.lastError {
                Section {
                    Text(error).foregroundStyle(.red).font(.caption)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("gemini.title".localized())
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await model.refresh() }
                } label: {
                    if model.isRefreshing {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(model.isRefreshing)
                .help("gemini.refresh".localized())
            }
        }
        .task {
            if model.snapshots.isEmpty {
                await model.refresh()
            }
        }
    }
}
