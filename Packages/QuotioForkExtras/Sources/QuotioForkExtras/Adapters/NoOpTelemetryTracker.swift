import Foundation
import QuotioApplication
import QuotioDomain

/// Fork: anonymous usage sharing is removed. This tracker satisfies the
/// `TelemetryTracking` port without PostHog; `configure()` returns false so
/// `TelemetryController` treats telemetry as permanently unavailable and no
/// event ever leaves the process.
public final class NoOpTelemetryTracker: TelemetryTracking {
    public init() {}

    public func configure() -> Bool { false }
    public func identify(_ anonymousInstallID: String, properties: [String: String]) {}
    public func capture(_ payload: TelemetryPayload) {}
    public func flush() {}
    public func stopAndReset() {}
}
