import Foundation
import SwiftUI

struct GitHubAuthSession: Codable, Hashable {
    let accessToken: String
    let refreshToken: String?
    let accessTokenExpiresAt: Date?
    let refreshTokenExpiresAt: Date?
    let tokenType: String

    var isAccessTokenExpired: Bool {
        guard let accessTokenExpiresAt else { return false }
        return accessTokenExpiresAt <= Date().addingTimeInterval(60)
    }

    var isRefreshTokenExpired: Bool {
        guard let refreshTokenExpiresAt else { return false }
        return refreshTokenExpiresAt <= Date().addingTimeInterval(60)
    }

    var maskedAccessToken: String {
        guard accessToken.count > 8 else { return "Saved" }
        return "\(accessToken.prefix(4))…\(accessToken.suffix(4))"
    }
}

struct Repository: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String
    let fullName: String
    let htmlURL: URL
    let owner: Owner
    let isPrivate: Bool
    let pushedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case fullName = "full_name"
        case htmlURL = "html_url"
        case owner
        case isPrivate = "private"
        case pushedAt = "pushed_at"
    }
}

struct Owner: Decodable, Hashable {
    let login: String
}

struct AppInstallationListResponse: Decodable {
    let installations: [AppInstallation]
}

struct AppInstallation: Decodable, Identifiable, Hashable {
    let id: Int
    let account: Owner
    let targetType: String
    let repositorySelection: String
    let permissions: [String: String]?

    enum CodingKeys: String, CodingKey {
        case id
        case account
        case targetType = "target_type"
        case repositorySelection = "repository_selection"
        case permissions
    }
}

struct InstallationRepositoriesResponse: Decodable {
    let repositories: [Repository]
}

struct DeviceCodeResponse: Decodable {
    let deviceCode: String
    let userCode: String
    let verificationURI: String
    let expiresIn: Int
    let interval: Int

    enum CodingKeys: String, CodingKey {
        case deviceCode = "device_code"
        case userCode = "user_code"
        case verificationURI = "verification_uri"
        case expiresIn = "expires_in"
        case interval
    }
}

struct OAuthTokenResponse: Decodable {
    let accessToken: String?
    let expiresIn: Int?
    let refreshToken: String?
    let refreshTokenExpiresIn: Int?
    let tokenType: String?
    let error: String?
    let errorDescription: String?
    let interval: Int?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case refreshTokenExpiresIn = "refresh_token_expires_in"
        case tokenType = "token_type"
        case error
        case errorDescription = "error_description"
        case interval
    }
}

struct WorkflowListResponse: Decodable {
    let totalCount: Int

    enum CodingKeys: String, CodingKey {
        case totalCount = "total_count"
    }
}

struct WorkflowRunsResponse: Decodable {
    let workflowRuns: [WorkflowRun]

    enum CodingKeys: String, CodingKey {
        case workflowRuns = "workflow_runs"
    }
}

struct WorkflowRun: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String?
    let displayTitle: String
    let htmlURL: URL
    let status: String
    let conclusion: String?
    let createdAt: Date
    let updatedAt: Date
    let runNumber: Int
    let headBranch: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case displayTitle = "display_title"
        case htmlURL = "html_url"
        case status
        case conclusion
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case runNumber = "run_number"
        case headBranch = "head_branch"
    }
}

struct WorkflowJobsResponse: Decodable {
    let jobs: [WorkflowJob]
}

struct WorkflowJob: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String
    let status: String
    let conclusion: String?
    let startedAt: Date?
    let completedAt: Date?
    let steps: [WorkflowStep]?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case status
        case conclusion
        case startedAt = "started_at"
        case completedAt = "completed_at"
        case steps
    }

    var runState: RunState {
        RunState(status: status, conclusion: conclusion)
    }
}

struct WorkflowStep: Decodable, Identifiable, Hashable {
    let number: Int
    let name: String
    let status: String
    let conclusion: String?

    var id: Int { number }

    var runState: RunState {
        RunState(status: status, conclusion: conclusion)
    }
}

struct RepoActionStatus: Identifiable, Hashable {
    let repository: Repository
    let latestRun: WorkflowRun?
    let workflowCount: Int

    var id: Int { repository.id }

    var latestActivityDate: Date {
        latestRun?.updatedAt ?? repository.pushedAt ?? .distantPast
    }

    var summaryText: String {
        guard let latestRun else {
            return workflowCount == 1 ? "1 workflow, no runs yet" : "\(workflowCount) workflows, no runs yet"
        }

        let descriptor = latestRun.name ?? latestRun.displayTitle
        let branch = latestRun.headBranch.map { " on \($0)" } ?? ""
        return "\(descriptor) • \(latestRun.statusSummary)\(branch)"
    }
}

struct NotificationPreferences: Codable, Hashable {
    var notifyOnStarted: Bool = true
    var notifyOnPassed: Bool = true
    var notifyOnFailed: Bool = true
}

enum RunJobsLoadState: Hashable {
    case idle
    case loading
    case loaded([WorkflowJob])
    case failed(String)
}

enum RunState: Hashable {
    case running
    case success
    case failure
    case cancelled
    case queued
    case neutral
    case unknown

    init(status: String, conclusion: String?) {
        let normalizedStatus = status.lowercased()
        let normalizedConclusion = conclusion?.lowercased()

        if normalizedStatus != "completed" {
            switch normalizedStatus {
            case "queued", "requested", "waiting", "pending":
                self = .queued
            case "in_progress":
                self = .running
            default:
                self = .unknown
            }
            return
        }

        switch normalizedConclusion {
        case "success":
            self = .success
        case "failure", "startup_failure", "timed_out", "action_required", "stale":
            self = .failure
        case "cancelled", "skipped":
            self = .cancelled
        case "neutral":
            self = .neutral
        default:
            self = .unknown
        }
    }

    var label: String {
        switch self {
        case .running:
            return "Running"
        case .success:
            return "Passed"
        case .failure:
            return "Failed"
        case .cancelled:
            return "Cancelled"
        case .queued:
            return "Queued"
        case .neutral:
            return "Neutral"
        case .unknown:
            return "Unknown"
        }
    }

    var symbolName: String {
        switch self {
        case .running:
            return "arrow.triangle.2.circlepath.circle.fill"
        case .success:
            return "checkmark.circle.fill"
        case .failure:
            return "xmark.circle.fill"
        case .cancelled:
            return "minus.circle.fill"
        case .queued:
            return "clock.fill"
        case .neutral, .unknown:
            return "questionmark.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .running:
            return .blue
        case .success:
            return .green
        case .failure:
            return .red
        case .cancelled:
            return .orange
        case .queued:
            return .yellow
        case .neutral, .unknown:
            return .secondary
        }
    }
}

extension WorkflowRun {
    var runState: RunState {
        RunState(status: status, conclusion: conclusion)
    }

    var statusSummary: String {
        runState.label
    }
}
