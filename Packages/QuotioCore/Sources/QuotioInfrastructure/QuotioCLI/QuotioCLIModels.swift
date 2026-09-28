import Foundation

struct QuotioCLIOperation: Decodable, Sendable {
    let id: String
    let status: String
    let error: String?
}

struct QuotioCLIOAuthSession: Decodable, Sendable {
    let provider: String
    let workflow: String
    let userCode: String?
    let id: String
    let url: String
    let expiresAt: Int64
    let status: String
    let accountId: String?
    let errorCode: String?
}
