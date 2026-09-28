import Foundation

public struct QuotioHostResetCredits: Decodable, Sendable {
    public let availableCount: UInt64
    public let fetchedAt: Date
}

public struct QuotioHostCodexProfile: Decodable, Sendable {
    public struct DailyUsage: Decodable, Sendable {
        public let date: String
        public let tokens: UInt64
    }

    public let dailyUsage: [DailyUsage]
    public let latest30BucketsTokens: UInt64
    public let lifetimeTokens: UInt64?
    public let peakDailyTokens: UInt64?
    public let longestRunningTurnSeconds: UInt64?
    public let currentStreakDays: UInt64?
    public let longestStreakDays: UInt64?
    public let fetchedAt: Date
}

public struct QuotioHostCodexResetCredits: Decodable, Sendable {
    public struct Credit: Decodable, Sendable {
        public let id: String
        public let expiresAt: Date?
    }

    public let availableCount: UInt64
    public let credits: [Credit]
    public let fetchedAt: Date
}

public struct QuotioHostSubscription: Decodable, Sendable {
    public struct Tier: Decodable, Sendable {
        public let id: String?
        public let name: String?
        public let description: String?
    }

    public let currentTier: Tier?
    public let paidTier: Tier?
}
