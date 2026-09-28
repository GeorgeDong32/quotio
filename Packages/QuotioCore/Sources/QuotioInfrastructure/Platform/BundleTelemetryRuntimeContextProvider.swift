import Foundation
import QuotioApplication
import QuotioDomain

public struct BundleTelemetryRuntimeContextProvider: TelemetryRuntimeContextProviding {
    private let bundle: Bundle
    private let operatingSystemVersion: @Sendable () -> String

    public init(
        bundle: Bundle = .main,
        operatingSystemVersion: @escaping @Sendable () -> String = {
            ProcessInfo.processInfo.operatingSystemVersionString
        }
    ) {
        self.bundle = bundle
        self.operatingSystemVersion = operatingSystemVersion
    }

    public func context(updateChannel: UpdateChannel) -> TelemetryRuntimeContext? {
        TelemetryRuntimeContext(
            appVersion: bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0",
            buildNumber: bundle.infoDictionary?["CFBundleVersion"] as? String ?? "0",
            bundleIdentifier: bundle.bundleIdentifier ?? "unknown.bundle",
            macOSVersion: operatingSystemVersion(),
            updateChannel: updateChannel
        )
    }
}
