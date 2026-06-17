//
//  CustomProviderSheet.swift
//  Quotio - Custom AI provider add/edit modal
//

import SwiftUI

struct CustomProviderSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    let provider: CustomProvider?
    let onSave: (CustomProvider) -> Void
    
    // MARK: - Form State
    
    @State private var name: String = ""
    @State private var providerType: CustomProviderType = .openaiCompatibility
    @State private var baseURL: String = ""
    @State private var prefix: String = ""
    @State private var apiKeys: [CustomAPIKeyEntry] = [CustomAPIKeyEntry(apiKey: "")]
    @State private var models: [ModelMapping] = []
    @State private var headers: [CustomHeader] = []
    @State private var isEnabled: Bool = true
    
    @State private var validationErrors: [String] = []
    @State private var showValidationAlert = false
    @State private var isTestingConnection = false
    @State private var testError: String?
    // Provider data ready for forced save after test failure
    @State private var pendingSaveProvider: CustomProvider?
    
    // Model fetching state
    @State private var availableModels: [AvailableModel] = []
    @State private var selectedModelIds: Set<String> = []
    @State private var modelSearchText: String = ""
    @State private var isLoadingModels: Bool = false
    @State private var modelFetchError: String?
    @State private var limitToSelectedModels: Bool = true
    
    private var isEditing: Bool {
        provider != nil
    }
    
    var body: some View {
        VStack(spacing: 0) {
            headerView
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Step 1: Provider name and type
                    basicInfoSection
                    
                    // Step 2: API Keys (needed before fetching models)
                    apiKeysSection
                    
                    // Step 3: Model selection (requires API key to fetch)
                    if providerType.supportsModelMapping {
                        modelMappingSection
                    }
                    
                    // Step 4: Custom headers (optional)
                    if providerType.supportsCustomHeaders {
                        customHeadersSection
                    }
                    
                    // Step 5: Enable toggle
                    enabledSection
                }
                .padding(20)
            }
            
            Divider()
            
            footerView
        }
        .frame(width: 600, height: 700)
        .onAppear {
            loadProviderData()
        }
        .alert("customProviders.validationError".localized(), isPresented: $showValidationAlert) {
            if testError != nil {
                // Test connection failed — offer forced save option
                Button("action.cancel".localized(), role: .cancel) {
                    testError = nil
                    pendingSaveProvider = nil
                }
                Button("action.saveAnyway".localized()) {
                    saveAndDismiss()
                }
            } else {
                Button("action.ok".localized(), role: .cancel) {
                    testError = nil
                }
            }
        } message: {
            if let error = testError {
                Text(error)
            } else {
                Text(validationErrors.joined(separator: "\n"))
            }
        }
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        HStack(spacing: 16) {
            Image(providerType.menuBarIconName)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 24, height: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(isEditing ? "customProviders.edit".localized() : "customProviders.add".localized())
                    .font(.headline)
                
                Text(providerType.localizedDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            
            Spacer()
            
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(20)
    }
    
    // MARK: - Basic Info Section
    
    private var basicInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("customProviders.basicInfo".localized())
                    .font(.headline)
                Text("• Step 1")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("customProviders.providerName".localized())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                TextField("e.g., OpenRouter, Ollama Local", text: $name)
                    .textFieldStyle(.roundedBorder)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("customProviders.providerType".localized())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                Picker("Type", selection: $providerType) {
                    ForEach(CustomProviderType.allCases) { type in
                        HStack {
                            Image(type.menuBarIconName)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 16, height: 16)
                            Text(type.localizedDisplayName)
                        }
                        .tag(type)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: providerType) { _, newType in
                    // Update base URL to default if empty
                    if baseURL.isEmpty, let defaultURL = newType.defaultBaseURL {
                        baseURL = defaultURL
                    }
                }
            }
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("customProviders.baseURL".localized())
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    if !providerType.requiresBaseURL, let defaultURL = providerType.defaultBaseURL {
                        Text("(default: \(defaultURL))")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                
                TextField(providerType.defaultBaseURL ?? "https://api.example.com", text: $baseURL)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("customProviders.prefix".localized())
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text("(\("customProviders.optional".localized()))")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                TextField("customProviders.prefixHint".localized(), text: $prefix)
                    .textFieldStyle(.roundedBorder)
            }
        }
        .padding(16)
        .background(Color(.controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
    }
    
    // MARK: - API Keys Section
    
    private var apiKeysSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("customProviders.apiKeys".localized())
                    .font(.headline)
                Text("• Step 2")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                
                Spacer()
                
                Button {
                    apiKeys.append(CustomAPIKeyEntry(apiKey: ""))
                } label: {
                    Label("customProviders.addKey".localized(), systemImage: "plus.circle")
                        .font(.caption)
                }
                .buttonStyle(.sectionHeader)
            }
            
            ForEach(Array(apiKeys.enumerated()), id: \.offset) { index, _ in
                apiKeyRow(index: index)
            }
        }
        .padding(16)
        .background(Color(.controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
    }
    
    private func apiKeyRow(index: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("API Key #\(index + 1)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                if apiKeys.count > 1 {
                    Button {
                        apiKeys.remove(at: index)
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.rowActionDestructive)
                }
            }
            
            SecureField("customProviders.apiKeys".localized(), text: Binding(
                get: { apiKeys[safe: index]?.apiKey ?? "" },
                set: { if index < apiKeys.count { apiKeys[index].apiKey = $0 } }
            ))
            .textFieldStyle(.roundedBorder)
            
            TextField("customProviders.proxyURL".localized(), text: Binding(
                get: { apiKeys[safe: index]?.proxyURL ?? "" },
                set: { if index < apiKeys.count { apiKeys[index].proxyURL = $0.isEmpty ? nil : $0 } }
            ))
            .textFieldStyle(.roundedBorder)
            .font(.caption)
        }
        .padding(12)
        .background(Color(.windowBackgroundColor))
        .cornerRadius(6)
    }
    
    // MARK: - Model Mapping Section
    
    private var filteredModels: [AvailableModel] {
        if modelSearchText.isEmpty {
            return availableModels
        }
        return availableModels.filter { 
            $0.name.localizedCaseInsensitiveContains(modelSearchText) ||
            $0.id.localizedCaseInsensitiveContains(modelSearchText)
        }
    }
    
    private var topModels: [AvailableModel] {
        // Return top 5 most popular models
        let popularModelIds = [
            "gpt-4o", "gpt-4-turbo", "gpt-3.5-turbo", "claude-3-opus", "claude-3-sonnet",
            "claude-3-haiku", "claude-3-5-sonnet", "gemini-pro", "gemini-1.5-pro", "llama-3"
        ]
        return availableModels.filter { model in
            popularModelIds.contains { popularId in
                model.name.lowercased().contains(popularId.lowercased()) || 
                model.id.lowercased().contains(popularId.lowercased())
            }
        }
    }
    
    private var modelMappingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("customProviders.modelMapping".localized())
                            .font(.headline)
                        Text("• Step 3")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    
                    Text("customProviders.modelMappingDesc".localized())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                if isLoadingModels {
                    ProgressView()
                        .scaleEffect(0.6)
                } else {
                    Button {
                        fetchModelsFromAPI()
                    } label: {
                        Label("customProviders.fetchModels".localized(), systemImage: "arrow.clockwise")
                            .font(.caption)
                    }
                    .buttonStyle(.sectionHeader)
                    .disabled(apiKeys.first?.apiKey.trimmingCharacters(in: .whitespaces).isEmpty ?? true)
                }
            }
            
            // Limit models toggle
            if !availableModels.isEmpty {
                Toggle(isOn: $limitToSelectedModels) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("customProviders.limitModels".localized())
                            .font(.subheadline)
                        Text("customProviders.limitModelsDesc".localized())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox)
                
                if limitToSelectedModels && selectedModelIds.isEmpty {
                    HStack {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.blue)
                        Text("customProviders.selectModelsHint".localized())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            // Show fetch error if any
            if let error = modelFetchError {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            // Model selection interface
            if !availableModels.isEmpty {
                modelSelectionList
            } else if !isLoadingModels {
                // Manual entry fallback
                manualModelEntry
            }
        }
        .padding(16)
        .background(Color(.controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
    }
    
    private var modelSelectionList: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Search box
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("customProviders.searchModels".localized(), text: $modelSearchText)
                    .textFieldStyle(.plain)
                if !modelSearchText.isEmpty {
                    Button {
                        modelSearchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(6)
            .background(Color(.windowBackgroundColor))
            .cornerRadius(6)
            
            // Top 5 popular models
            if modelSearchText.isEmpty && !topModels.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("customProviders.popularModels".localized())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    ForEach(topModels.prefix(5)) { model in
                        modelSelectionRow(model: model)
                    }
                }
            }
            
            // All models (searchable)
            if !modelSearchText.isEmpty || topModels.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    if modelSearchText.isEmpty {
                        Text("customProviders.allModels".localized())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(filteredModels) { model in
                                modelSelectionRow(model: model)
                            }
                        }
                    }
                    .frame(maxHeight: 200)
                }
            }
            
            // Selected models count and actions
            if !selectedModelIds.isEmpty {
                HStack {
                    Text(String(format: "customProviders.selectedModels".localized(), selectedModelIds.count))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("customProviders.clearSelection".localized()) {
                        selectedModelIds.removeAll()
                    }
                    .font(.caption)
                }
            }
            
            // Select All / Deselect All buttons
            if !availableModels.isEmpty {
                HStack {
                    Button("customProviders.selectAll".localized()) {
                        selectedModelIds = Set(availableModels.map { $0.id })
                    }
                    .font(.caption)
                    
                    Button("customProviders.deselectAll".localized()) {
                        selectedModelIds.removeAll()
                    }
                    .font(.caption)
                }
            }
        }
    }
    
    private func modelSelectionRow(model: AvailableModel) -> some View {
        Button {
            if selectedModelIds.contains(model.id) {
                selectedModelIds.remove(model.id)
            } else {
                selectedModelIds.insert(model.id)
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: selectedModelIds.contains(model.id) ? "checkmark.square" : "square")
                    .foregroundStyle(selectedModelIds.contains(model.id) ? Color.accentColor : .secondary)
                
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.name)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                    if model.id != model.name {
                        Text(model.id)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    private var manualModelEntry: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("customProviders.enterManually".localized())
                .font(.caption)
                .foregroundStyle(.tertiary)
            
            Button {
                models.append(ModelMapping(name: "", alias: ""))
            } label: {
                Label("customProviders.addMapping".localized(), systemImage: "plus.circle")
                    .font(.caption)
            }
            .buttonStyle(.sectionHeader)
            
            if models.isEmpty {
                Text("customProviders.noMappings".localized())
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 8)
            } else {
                ForEach(Array(models.enumerated()), id: \.offset) { index, _ in
                    modelMappingRow(index: index)
                }
            }
        }
    }
    
    private func modelMappingRow(index: Int) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                TextField("customProviders.upstreamModel".localized(), text: Binding(
                    get: { models[safe: index]?.name ?? "" },
                    set: { if index < models.count { models[index].name = $0 } }
                ))
                .textFieldStyle(.roundedBorder)
                
                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)
                
                TextField("customProviders.localAlias".localized(), text: Binding(
                    get: { models[safe: index]?.alias ?? "" },
                    set: { if index < models.count { models[index].alias = $0 } }
                ))
                .textFieldStyle(.roundedBorder)
                
                Button {
                    models.remove(at: index)
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.rowActionDestructive)
            }
            
            HStack(spacing: 8) {
                Text("customProviders.thinkingBudget".localized())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                TextField("customProviders.thinkingBudgetHint".localized(), text: Binding(
                    get: { models[safe: index]?.thinkingBudget ?? "" },
                    set: { if index < models.count { models[index].thinkingBudget = $0.isEmpty ? nil : $0 } }
                ))
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 200)
                
                Spacer()
            }
            .padding(.leading, 4)
        }
        .padding(.vertical, 4)
    }
    
    // MARK: - Custom Headers Section
    
    private var customHeadersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("customProviders.customHeaders".localized())
                        .font(.headline)
                    
                    Text("customProviders.customHeadersDesc".localized())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Button {
                    headers.append(CustomHeader(key: "", value: ""))
                } label: {
                    Label("customProviders.addHeader".localized(), systemImage: "plus.circle")
                        .font(.caption)
                }
                .buttonStyle(.sectionHeader)
            }
            
            if headers.isEmpty {
                Text("customProviders.noHeaders".localized())
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 8)
            } else {
                ForEach(Array(headers.enumerated()), id: \.offset) { index, _ in
                    customHeaderRow(index: index)
                }
            }
        }
        .padding(16)
        .background(Color(.controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
    }
    
    private func customHeaderRow(index: Int) -> some View {
        HStack(spacing: 12) {
            TextField("customProviders.headerName".localized(), text: Binding(
                get: { headers[safe: index]?.key ?? "" },
                set: { if index < headers.count { headers[index].key = $0 } }
            ))
            .textFieldStyle(.roundedBorder)
            
            Text(":")
                .foregroundStyle(.secondary)
            
            TextField("customProviders.headerValue".localized(), text: Binding(
                get: { headers[safe: index]?.value ?? "" },
                set: { if index < headers.count { headers[index].value = $0 } }
            ))
            .textFieldStyle(.roundedBorder)
            
            Button {
                headers.remove(at: index)
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.rowActionDestructive)
        }
    }
    
    // MARK: - Enabled Section
    
    private var enabledSection: some View {
        HStack {
            Toggle("customProviders.enableProvider".localized(), isOn: $isEnabled)
            
            Spacer()
            
            if !isEnabled {
                Text("customProviders.disabledNote".localized())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(Color(.controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
    }
    
    // MARK: - Footer
    
    private var footerView: some View {
        HStack {
            Button("action.cancel".localized()) {
                dismiss()
            }
            .keyboardShortcut(.escape)
            .disabled(isTestingConnection)
            
            Spacer()
            
            if isTestingConnection {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("customProviders.testing".localized())
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            
            Button(isEditing ? "customProviders.saveChanges".localized() : "customProviders.addProvider".localized()) {
                saveProvider()
            }
            .keyboardShortcut(.return, modifiers: .command)
            .buttonStyle(.borderedProminent)
            .disabled(isTestingConnection)
        }
        .padding(20)
    }
    
    // MARK: - Actions
    
    private func loadProviderData() {
        guard let provider = provider else { return }
        
        name = provider.name
        providerType = provider.type
        baseURL = normalizedBaseURL(provider.baseURL, for: provider.type)
        prefix = provider.prefix ?? ""
        apiKeys = provider.apiKeys
        models = provider.models
        headers = provider.headers
        limitToSelectedModels = provider.limitToSelectedModels
        isEnabled = provider.isEnabled
        
        // Set selected models from existing provider
        selectedModelIds = Set(provider.models.map { $0.name })
    }

    private func normalizedBaseURL(_ rawValue: String, for type: CustomProviderType) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (type == .openaiCompatibility || type == .codexCompatibility), !trimmed.isEmpty,
              var components = URLComponents(string: trimmed) else {
            return trimmed
        }

        if baseURLIncludesVersion(components.path) {
            return components.string ?? trimmed
        }

        if components.path.isEmpty || components.path == "/" {
            components.path = "/v1"
        } else if components.path.hasSuffix("/") {
            components.path += "v1"
        } else {
            components.path += "/v1"
        }

        return components.string ?? trimmed
    }

    private func makeModelsURL(baseURL rawBaseURL: String, providerType: CustomProviderType) -> URL? {
        let normalizedBaseURL = normalizedBaseURL(rawBaseURL, for: providerType)
        guard let url = URL(string: normalizedBaseURL) else { return nil }

        let endpoint = baseURLIncludesVersion(url.path) ? "models" : "v1/models"
        return url.appendingPathComponent(endpoint)
    }

    /// Returns the alternate models endpoint by flipping the version-segment decision
    /// used in `makeModelsURL`. Used as a 404-only fallback during save validation.
    private func makeAlternateModelsURL(baseURL rawBaseURL: String, providerType: CustomProviderType) -> URL? {
        let normalizedBaseURL = normalizedBaseURL(rawBaseURL, for: providerType)
        guard let url = URL(string: normalizedBaseURL) else { return nil }

        let endpoint = baseURLIncludesVersion(url.path) ? "v1/models" : "models"
        return url.appendingPathComponent(endpoint)
    }

    /// Outcome of a single models-endpoint probe attempt. Surfaces raw HTTP status
    /// and body so callers can render their own error messages without duplicating
    /// the HTTP plumbing. `transportError` represents a network-layer failure
    /// (DNS, TLS, timeout) that never produced a status code.
    private enum ModelsProbeOutcome {
        case success(HTTPURLResponse, Data)
        case notFound(HTTPURLResponse, Data)
        case other(HTTPURLResponse, Data)
        case transportError(Error)
    }

    /// Unified result of `probeModelsEndpoint`. The two 404 cases let callers tell
    /// whether the alternate was tried (and failed) versus whether the primary
    /// was the only 404. `fetchModelsFromAPI` uses `primaryNotFound` to show its
    /// banner immediately; `testConnection` collapses both into a single
    /// `endpointNotFound` throw.
    private enum ModelsProbeResult {
        /// Either attempt returned 2xx.
        case success(HTTPURLResponse, Data)
        /// Primary returned 404; alternate probe was issued and also returned 404.
        case primaryNotFound(HTTPURLResponse, Data)
        /// Primary returned 401/403; alternate not attempted.
        case unauthorized(HTTPURLResponse, Data)
        /// Primary returned a non-404 non-auth status; alternate not attempted.
        case serverError(HTTPURLResponse, Data)
        /// Network layer failure (DNS, TLS, timeout, etc.); alternate not attempted.
        case transportError(Error)
    }

    /// Probe the models endpoint with the canonical URL, retrying the alternate
    /// URL only on HTTP 404. All other statuses (200, 401/403, 5xx, etc.) are
    /// returned from the primary attempt without fallback.
    private func probeModelsEndpoint(
        primary: URL,
        alternate: URL,
        requestBuilder: @escaping (URL) -> URLRequest
    ) async -> ModelsProbeResult {
        let primaryRequest = requestBuilder(primary)
        let primaryOutcome = await performModelsRequest(primaryRequest)

        switch primaryOutcome {
        case .success(let response, let data):
            return .success(response, data)
        case .notFound(let response, let data):
            let alternateRequest = requestBuilder(alternate)
            let alternateOutcome = await performModelsRequest(alternateRequest)
            switch alternateOutcome {
            case .success(let altResponse, let altData):
                return .success(altResponse, altData)
            case .notFound(let altResponse, let altData):
                return .primaryNotFound(altResponse, altData)
            case .other(let altResponse, let altData):
                // Alternate resolved but with a non-2xx non-404 code — treat as a
                // server error so the user sees the real upstream status.
                return .serverError(altResponse, altData)
            case .transportError(let error):
                return .transportError(error)
            }
        case .other(let response, let data):
            switch response.statusCode {
            case 401, 403:
                return .unauthorized(response, data)
            default:
                return .serverError(response, data)
            }
        case .transportError(let error):
            return .transportError(error)
        }
    }

    /// Single HTTP GET against `URLSession.shared`. Network errors are captured
    /// as `transportError` so the caller's switch is exhaustive.
    private func performModelsRequest(_ request: URLRequest) async -> ModelsProbeOutcome {
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                // Defensive: URLSession data tasks always return HTTPURLResponse
                // for http(s) requests. Treat any other case as a transport error
                // rather than fabricating a fake response.
                let error = URLError(.badServerResponse)
                return .transportError(error)
            }
            switch httpResponse.statusCode {
            case 200..<300:
                return .success(httpResponse, data)
            case 404:
                return .notFound(httpResponse, data)
            default:
                return .other(httpResponse, data)
            }
        } catch {
            return .transportError(error)
        }
    }

    /// Builds a models-endpoint request for any URL — used by `probeModelsEndpoint`
    /// for both the primary and alternate attempts, so a non-canonical base URL
    /// is probed consistently on both paths. Custom headers run *after* the
    /// provider-set auth headers and therefore override them (pre-existing
    /// behavior, called out so a future maintainer doesn't "fix" it by accident).
    private func buildModelsRequest(
        for url: URL,
        providerType: CustomProviderType,
        apiKey: String,
        headers: [CustomHeader]
    ) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15

        switch providerType {
        case .openaiCompatibility, .codexCompatibility:
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        case .claudeCompatibility:
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        case .geminiCompatibility:
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            components?.queryItems = [URLQueryItem(name: "key", value: apiKey)]
            if let newURL = components?.url {
                request.url = newURL
            }
        case .glmCompatibility:
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        for header in headers {
            request.setValue(header.value, forHTTPHeaderField: header.key)
        }

        return request
    }

    private func baseURLIncludesVersion(_ path: String) -> Bool {
        guard let lastSegment = path.split(separator: "/").last else { return false }
        return isVersionPathSegment(lastSegment)
    }

    private func isVersionPathSegment(_ segment: Substring) -> Bool {
        guard segment.first == "v" else { return false }

        let remainder = segment.dropFirst()
        guard let firstCharacter = remainder.first, firstCharacter.isNumber else {
            return false
        }

        return remainder.allSatisfy { $0.isNumber || $0.isLetter }
    }
    
    private func fetchModelsFromAPI() {
        guard let firstKey = apiKeys.first, !firstKey.apiKey.trimmingCharacters(in: .whitespaces).isEmpty else {
            modelFetchError = "Enter an API key first"
            return
        }

        let effectiveBaseURL = baseURL.isEmpty
            ? (providerType.defaultBaseURL ?? "")
            : normalizedBaseURL(baseURL, for: providerType)

        guard let modelsURL = makeModelsURL(baseURL: effectiveBaseURL, providerType: providerType),
              let alternateURL = makeAlternateModelsURL(baseURL: effectiveBaseURL, providerType: providerType) else {
            modelFetchError = "Invalid base URL"
            return
        }

        // The request builder is reused by the helper for the alternate URL too;
        // Gemini's `?key=` query is re-derived from the URL the helper hands in,
        // so the query is correct on both attempts.
        // Capture into locals first so the closure does not implicitly capture
        // @MainActor-isolated view state, then delegate to the shared builder.
        let capturedProviderType = providerType
        let capturedAPIKey = firstKey.apiKey
        let capturedHeaders = headers
        let requestBuilder: (URL) -> URLRequest = { url in
            buildModelsRequest(
                for: url,
                providerType: capturedProviderType,
                apiKey: capturedAPIKey,
                headers: capturedHeaders
            )
        }

        isLoadingModels = true
        modelFetchError = nil

        Task {
            let result = await probeModelsEndpoint(primary: modelsURL, alternate: alternateURL, requestBuilder: requestBuilder)

            await MainActor.run {
                isLoadingModels = false

                switch result {
                case .success(_, let data):
                    do {
                        let modelsResponse = try JSONDecoder().decode(ModelsListResponse.self, from: data)
                        let fetchedModels = modelsResponse.allModels.map { $0.toAvailableModel() }
                        availableModels = fetchedModels.sorted { $0.name < $1.name }
                    } catch {
                        modelFetchError = "Failed to fetch models: \(error.localizedDescription)"
                    }
                case .primaryNotFound(let response, _):
                    // Show the canonical first-attempt status immediately so the
                    // user can see what went wrong, regardless of whether the
                    // alternate path would have succeeded (save flow handles that).
                    modelFetchError = "Failed to fetch models: HTTP \(response.statusCode)"
                case .unauthorized(let response, _):
                    modelFetchError = "Failed to fetch models: HTTP \(response.statusCode)"
                case .serverError(let response, let data):
                    let message = String(data: data, encoding: .utf8) ?? "Unknown error"
                    modelFetchError = "Failed to fetch models: HTTP \(response.statusCode) (\(message))"
                case .transportError(let error):
                    modelFetchError = "Failed to fetch models: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func saveProvider() {
        // Clear previous errors
        testError = nil
        
        // Convert selected model IDs to ModelMapping
        let selectedModelMappings = selectedModelIds.compactMap { modelId -> ModelMapping? in
            guard let model = availableModels.first(where: { $0.id == modelId }) else { return nil }
            return ModelMapping(name: model.id, alias: model.id)
        }
        
        // Merge with manually added models (deduplicate by name)
        var seenNames = Set<String>()
        var allModels: [ModelMapping] = []
        for model in models.filter({ !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }) + selectedModelMappings {
            if !seenNames.contains(model.name) {
                seenNames.insert(model.name)
                allModels.append(model)
            }
        }
        
        // Build provider
        let newProvider = CustomProvider(
            id: provider?.id ?? UUID(),
            name: name.trimmingCharacters(in: .whitespaces),
            type: providerType,
            baseURL: normalizedBaseURL(baseURL, for: providerType),
            prefix: prefix.trimmingCharacters(in: .whitespaces).isEmpty ? nil : prefix.trimmingCharacters(in: .whitespaces),
            apiKeys: apiKeys.filter { !$0.apiKey.trimmingCharacters(in: .whitespaces).isEmpty },
            models: limitToSelectedModels ? allModels : [],
            headers: headers.filter { !$0.key.trimmingCharacters(in: .whitespaces).isEmpty },
            limitToSelectedModels: limitToSelectedModels,
            isEnabled: isEnabled,
            createdAt: provider?.createdAt ?? Date(),
            updatedAt: Date()
        )
        
        // Validate basic fields
        validationErrors = CustomProviderService.shared.validateProvider(newProvider)
        
        if !validationErrors.isEmpty {
            showValidationAlert = true
            return
        }
        
        // Test connection before saving
        isTestingConnection = true
        pendingSaveProvider = newProvider

        Task {
            do {
                let success = try await testConnection(provider: newProvider)
                await MainActor.run {
                    isTestingConnection = false
                    pendingSaveProvider = nil
                    if success {
                        onSave(newProvider)
                        dismiss()
                    }
                }
            } catch {
                await MainActor.run {
                    isTestingConnection = false
                    testError = error.localizedDescription
                    showValidationAlert = true
                }
            }
        }
    }

    /// Force-saves the pending provider and dismisses the sheet, used when user
    /// chooses "Save Anyway" after a connection test failure.
    private func saveAndDismiss() {
        guard let provider = pendingSaveProvider else { return }
        onSave(provider)
        testError = nil
        pendingSaveProvider = nil
        dismiss()
    }
    
    private func testConnection(provider: CustomProvider) async throws -> Bool {
        guard let firstKey = provider.apiKeys.first else {
            throw CustomProviderTestError.noAPIKey
        }

        let effectiveBaseURL = provider.baseURL.isEmpty
            ? (provider.type.defaultBaseURL ?? "")
            : provider.baseURL

        guard let modelsURL = makeModelsURL(baseURL: effectiveBaseURL, providerType: provider.type),
              let alternateURL = makeAlternateModelsURL(baseURL: effectiveBaseURL, providerType: provider.type) else {
            throw CustomProviderTestError.invalidURL
        }

        // Build a request for any URL — the helper passes either the primary or
        // the alternate, both shaped the same way (headers, query, custom headers).
        // Capture into locals first so the closure does not implicitly capture
        // @MainActor-isolated view state, then delegate to the shared builder.
        let capturedProviderType = provider.type
        let capturedAPIKey = firstKey.apiKey
        let capturedHeaders = provider.headers
        let result = await probeModelsEndpoint(primary: modelsURL, alternate: alternateURL) { url in
            buildModelsRequest(
                for: url,
                providerType: capturedProviderType,
                apiKey: capturedAPIKey,
                headers: capturedHeaders
            )
        }

        switch result {
        case .success:
            return true
        case .primaryNotFound:
            throw CustomProviderTestError.endpointNotFound
        case .unauthorized:
            throw CustomProviderTestError.unauthorized
        case .serverError(let response, let data):
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw CustomProviderTestError.serverError(response.statusCode, errorMessage)
        case .transportError(let error):
            // Network-layer failure (DNS, TLS, timeout). Surface with a clear
            // prefix so the user can tell it apart from an upstream HTTP 5xx,
            // while still keeping the existing error enum unchanged.
            throw CustomProviderTestError.serverError(0, "Network error: \(error.localizedDescription)")
        }
    }
}

enum CustomProviderTestError: LocalizedError {
    case noAPIKey
    case invalidURL
    case invalidResponse
    case unauthorized
    case endpointNotFound
    case serverError(Int, String)
    
    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "No API key provided"
        case .invalidURL:
            return "Invalid base URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .unauthorized:
            return "API key is invalid or unauthorized"
        case .endpointNotFound:
            return "Models endpoint not found at this URL"
        case .serverError(let code, let message):
            return "Server error (\(code)): \(message)"
        }
    }
}

// MARK: - Models Response Parsing

private struct ModelsListResponse: Codable {
    let data: [ModelData]?
    let models: [ModelData]?
    
    var allModels: [ModelData] {
        data ?? models ?? []
    }
}

private struct ModelData: Codable {
    let id: String
    let name: String?
    let ownedBy: String?
    
    enum CodingKeys: String, CodingKey {
        case id, name
        case ownedBy = "owned_by"
    }
    
    func toAvailableModel() -> AvailableModel {
        AvailableModel(id: id, name: name ?? id, provider: ownedBy ?? "unknown", isDefault: false)
    }
}

// MARK: - Array Safe Subscript Extension

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Preview

#Preview {
    CustomProviderSheet(provider: nil) { provider in
        print("Saved: \(provider.name)")
    }
}
