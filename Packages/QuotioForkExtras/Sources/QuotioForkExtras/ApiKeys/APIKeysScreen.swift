//
//  APIKeysScreen.swift
//  QuotioForkExtras — proxy client API key management page (fork)
//

import AppKit
import SwiftUI

/// Fork API Keys page: the client keys CLI agents use to authenticate
/// against the local proxy. Restored from the pre-port fork (upstream
/// retired the page together with the old local-proxy UI).
public struct APIKeysScreen: View {
    public init() {}

    @Environment(APIKeysScreenModel.self) private var model
    @State private var newKey = ""
    @FocusState private var keyFieldFocused: Bool

    public var body: some View {
        Form {
            Section {
                if model.keys.isEmpty && !model.isLoading {
                    Text("apiKeys.empty".localized()).foregroundStyle(.secondary)
                }
                ForEach(model.keys, id: \.self) { key in
                    HStack {
                        Text(Self.masked(key))
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                        Spacer()
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(key, forType: .string)
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.borderless)
                        .help("apiKeys.copy".localized())
                        Button(role: .destructive) {
                            Task { await model.delete(key: key) }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .help("apiKeys.delete".localized())
                    }
                }
            } header: {
                Text("apiKeys.keys".localized())
            } footer: {
                Text("apiKeys.footer".localized())
            }

            Section {
                // Row 1: the input fills the full width.
                TextField("apiKeys.newKeyPlaceholder".localized(), text: $newKey)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .autocorrectionDisabled()
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity)
                    .focused($keyFieldFocused)
                // Row 2: actions right-aligned.
                HStack {
                    Spacer()
                    Button("apiKeys.generate".localized()) {
                        // Draft mode: fill the field for review/editing;
                        // nothing is saved until "Add" is clicked.
                        newKey = APIKeysScreenModel.generateKey()
                        keyFieldFocused = true
                    }
                    Button("apiKeys.add".localized()) {
                        Task {
                            await model.add(key: newKey)
                            newKey = ""
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(newKey.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: {
                Text("apiKeys.addKey".localized())
            } footer: {
                Text("apiKeys.draftHint".localized())
            }

            if let error = model.lastError {
                Section {
                    Text(error).foregroundStyle(.red).font(.caption)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("apiKeys.title".localized())
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await model.refresh() }
                } label: {
                    if model.isLoading {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(model.isLoading)
            }
        }
        .task {
            if model.keys.isEmpty {
                await model.refresh()
            }
        }
    }

    /// Shows head and tail so the row stays readable while remaining copiable.
    static func masked(_ key: String) -> String {
        guard key.count > 14 else { return key }
        return "\(key.prefix(8))…\(key.suffix(4))"
    }
}
