public enum ConnectionState: Equatable, Sendable {
    case connected
    case permissionRequired
    case reauthenticationRequired
    case notConnected
    case disabled
}
