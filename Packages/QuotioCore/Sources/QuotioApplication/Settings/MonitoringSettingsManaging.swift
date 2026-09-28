import QuotioDomain

public protocol MonitoringSettingsManaging: Sendable {
    func monitoringProviders() async throws -> [MonitoringProvider]
    func monitoringSettings() async throws -> MonitoringSettings
    func updateMonitoringSettings(_ settings: MonitoringSettings) async throws -> MonitoringSettings
}
