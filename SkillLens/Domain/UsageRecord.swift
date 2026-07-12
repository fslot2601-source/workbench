import Foundation

struct UsageSnapshot: Equatable, Sendable {
    let rateLimits: [RateLimitRecord]
    let resetCreditsAvailable: Int?
    let tokenSummary: TokenUsageSummary
    let dailyUsage: [DailyTokenUsage]
    let refreshedAt: Date
}

struct RateLimitRecord: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let planType: String?
    let primary: RateLimitWindowRecord?
    let secondary: RateLimitWindowRecord?
    let reachedType: String?
    let creditBalance: String?
}

struct RateLimitWindowRecord: Equatable, Sendable {
    let usedPercent: Int
    let windowDurationMinutes: Int?
    let resetsAt: Date?

    var remainingPercent: Int { max(0, min(100, 100 - usedPercent)) }
}

struct TokenUsageSummary: Equatable, Sendable {
    let lifetimeTokens: Int64?
    let peakDailyTokens: Int64?
    let longestRunningTurnSeconds: Int64?
    let currentStreakDays: Int64?
    let longestStreakDays: Int64?
}

struct DailyTokenUsage: Identifiable, Equatable, Sendable {
    var id: String { startDate }
    let startDate: String
    let tokens: Int64
}
