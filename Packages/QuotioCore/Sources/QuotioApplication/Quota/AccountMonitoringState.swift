import Foundation
import QuotioDomain

public struct AccountMonitoringState: Equatable, Sendable {
    public let connection: ConnectionState
    public let quota: QuotaRefreshState

    public init(connection: ConnectionState, quota: QuotaRefreshState) {
        self.connection = connection
        self.quota = quota
    }

}

public enum QuotaRecoveryAction: Equatable, Sendable {
    case signIn
    case refreshInSourceApp
    case authorize
    case retry
}
