//
//  ProxyBinarySourceScreen.swift
//  QuotioForkExtras — choose which proxy binary the app runs
//

import SwiftUI

/// Screen model for the binary-source picker: persists the choice (same
/// UserDefaults key the pre-port fork used) and restarts the proxy to
/// apply it.
@MainActor
@Observable
public final class ProxyBinarySourceScreenModel {
    public private(set) var source: ForkProxyBinarySource
    public private(set) var isRestarting = false
    public private(set) var lastError: String?

    private let restartProxy: @MainActor () async throws -> Void

    public init(restartProxy: @escaping @MainActor () async throws -> Void) {
        self.source = ForkProxyBinarySource.stored()
        self.restartProxy = restartProxy
    }

    public func select(_ source: ForkProxyBinarySource) async {
        guard source != self.source else { return }
        ForkProxyBinarySource.set(source)
        self.source = source
        isRestarting = true
        defer { isRestarting = false }
        do {
            try await restartProxy()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }
}

/// Fork settings page: official CLIProxyAPI (GitHub install + updates)
/// vs the bundled sha-pinned plus build. Restores the pre-port
/// binary-source selection.
public struct ProxyBinarySourceScreen: View {
    public init() {}

    @Environment(ProxyBinarySourceScreenModel.self) private var model

    public var body: some View {
        Form {
            Section {
                Picker("proxySource.source".localized(), selection: Binding(
                    get: { model.source },
                    set: { newValue in Task { await model.select(newValue) } }
                )) {
                    Text("proxySource.upstream".localized()).tag(ForkProxyBinarySource.upstream)
                    Text("proxySource.plusLocal".localized()).tag(ForkProxyBinarySource.plusLocal)
                }
                .pickerStyle(.radioGroup)
                .disabled(model.isRestarting)

                if model.isRestarting {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("proxySource.restarting".localized()).font(.caption)
                    }
                }
                if let error = model.lastError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            } footer: {
                Text("proxySource.footer".localized())
            }
        }
        .formStyle(.grouped)
        .navigationTitle("proxySource.title".localized())
    }
}
