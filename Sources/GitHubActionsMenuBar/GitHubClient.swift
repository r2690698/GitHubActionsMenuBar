import Foundation

struct GitHubClient {
    static let clientID = "Iv23lirXOtmqyN28ir6j"

    private let session: URLSession
    private let decoder: JSONDecoder

    init(session: URLSession = .shared) {
        self.session = session
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    func startDeviceFlow() async throws -> DeviceCodeResponse {
        try await oauthRequest(
            endpoint: "https://github.com/login/device/code",
            parameters: [
                "client_id": Self.clientID
            ]
        )
    }

    func pollForUserSession(deviceCode: String) async throws -> GitHubAuthSession? {
        let response: OAuthTokenResponse = try await oauthRequest(
            endpoint: "https://github.com/login/oauth/access_token",
            parameters: [
                "client_id": Self.clientID,
                "device_code": deviceCode,
                "grant_type": "urn:ietf:params:oauth:grant-type:device_code"
            ]
        )

        if let error = response.error {
            switch error {
            case "authorization_pending":
                return nil
            case "slow_down":
                throw GitHubError.slowDown
            case "expired_token":
                throw GitHubError.deviceCodeExpired
            case "access_denied":
                throw GitHubError.accessDenied
            default:
                throw GitHubError.oauthError(response.errorDescription ?? error)
            }
        }

        return try makeAuthSession(from: response)
    }

    func refreshUserSession(_ currentSession: GitHubAuthSession) async throws -> GitHubAuthSession {
        guard let refreshToken = currentSession.refreshToken, !currentSession.isRefreshTokenExpired else {
            throw GitHubError.reauthenticationRequired
        }

        let response: OAuthTokenResponse = try await oauthRequest(
            endpoint: "https://github.com/login/oauth/access_token",
            parameters: [
                "client_id": Self.clientID,
                "grant_type": "refresh_token",
                "refresh_token": refreshToken
            ]
        )

        return try makeAuthSession(from: response)
    }

    func fetchRepoStatuses(userToken: String) async throws -> [RepoActionStatus] {
        let repositories = try await fetchRepositories(userToken: userToken)
        return try await concurrentCompactMap(input: repositories, limit: 6) { repo in
            try await fetchRepoStatus(for: repo, token: userToken)
        }
        .sorted { lhs, rhs in
            lhs.latestActivityDate > rhs.latestActivityDate
        }
    }

    func fetchJobs(for repository: Repository, runID: Int, userToken: String) async throws -> [WorkflowJob] {
        var jobs: [WorkflowJob] = []
        var page = 1

        while true {
            let response: WorkflowJobsResponse = try await request(
                endpoint: "https://api.github.com/repos/\(repository.owner.login)/\(repository.name)/actions/runs/\(runID)/jobs?per_page=100&page=\(page)",
                token: userToken
            )

            if response.jobs.isEmpty {
                break
            }

            jobs.append(contentsOf: response.jobs)
            page += 1
        }

        return jobs
    }

    private func fetchRepositories(userToken: String) async throws -> [Repository] {
        let installations = try await fetchInstallations(userToken: userToken)
        guard !installations.isEmpty else {
            return []
        }

        let repositoriesByID = try await concurrentCompactMap(input: installations, limit: 4) { installation in
            try await fetchRepositories(for: installation, userToken: userToken)
        }
        .flatMap { $0 }

        var deduplicated: [Int: Repository] = [:]
        for repository in repositoriesByID {
            deduplicated[repository.id] = repository
        }

        return deduplicated.values.sorted { lhs, rhs in
            (lhs.pushedAt ?? .distantPast) > (rhs.pushedAt ?? .distantPast)
        }
    }

    private func fetchInstallations(userToken: String) async throws -> [AppInstallation] {
        var installations: [AppInstallation] = []
        var page = 1

        while true {
            let response: AppInstallationListResponse = try await request(
                endpoint: "https://api.github.com/user/installations?per_page=100&page=\(page)",
                token: userToken
            )

            if response.installations.isEmpty {
                break
            }

            installations.append(contentsOf: response.installations)
            page += 1
        }

        return installations
    }

    private func fetchRepositories(for installation: AppInstallation, userToken: String) async throws -> [Repository]? {
        var repositories: [Repository] = []
        var page = 1

        while true {
            let response: InstallationRepositoriesResponse = try await request(
                endpoint: "https://api.github.com/user/installations/\(installation.id)/repositories?per_page=100&page=\(page)",
                token: userToken
            )

            if response.repositories.isEmpty {
                break
            }

            repositories.append(contentsOf: response.repositories)
            page += 1
        }

        return repositories
    }

    private func fetchRepoStatus(for repository: Repository, token: String) async throws -> RepoActionStatus? {
        async let workflowList: WorkflowListResponse = request(
            endpoint: "https://api.github.com/repos/\(repository.owner.login)/\(repository.name)/actions/workflows?per_page=1",
            token: token
        )
        async let runs: WorkflowRunsResponse = request(
            endpoint: "https://api.github.com/repos/\(repository.owner.login)/\(repository.name)/actions/runs?per_page=1",
            token: token
        )

        do {
            let workflows = try await workflowList
            let latestRun = try await runs.workflowRuns.first
            guard workflows.totalCount > 0 || latestRun != nil else {
                return nil
            }

            return RepoActionStatus(
                repository: repository,
                latestRun: latestRun,
                workflowCount: workflows.totalCount
            )
        } catch let error as GitHubError where error == .notFound {
            return nil
        }
    }

    private func request<Response: Decodable>(endpoint: String, token: String) async throws -> Response {
        guard let url = URL(string: endpoint) else {
            throw GitHubError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.timeoutInterval = 20

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GitHubError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            return try decoder.decode(Response.self, from: data)
        case 401:
            throw GitHubError.unauthorized
        case 403:
            throw GitHubError.forbidden
        case 404:
            throw GitHubError.notFound
        default:
            throw GitHubError.httpStatus(httpResponse.statusCode)
        }
    }

    private func oauthRequest<Response: Decodable>(endpoint: String, parameters: [String: String]) async throws -> Response {
        guard let url = URL(string: endpoint) else {
            throw GitHubError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = parameters
            .map { key, value in
                "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value)"
            }
            .sorted()
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GitHubError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw GitHubError.httpStatus(httpResponse.statusCode)
        }

        return try decoder.decode(Response.self, from: data)
    }

    private func makeAuthSession(from response: OAuthTokenResponse) throws -> GitHubAuthSession {
        guard let accessToken = response.accessToken else {
            throw GitHubError.oauthError(response.errorDescription ?? "Missing access token.")
        }

        let now = Date()
        let accessTokenExpiresAt = response.expiresIn.map { now.addingTimeInterval(TimeInterval($0)) }
        let refreshTokenExpiresAt = response.refreshTokenExpiresIn.map { now.addingTimeInterval(TimeInterval($0)) }

        return GitHubAuthSession(
            accessToken: accessToken,
            refreshToken: response.refreshToken,
            accessTokenExpiresAt: accessTokenExpiresAt,
            refreshTokenExpiresAt: refreshTokenExpiresAt,
            tokenType: response.tokenType ?? "bearer"
        )
    }

    private func concurrentCompactMap<Input, Output>(
        input: [Input],
        limit: Int,
        operation: @escaping @Sendable (Input) async throws -> Output?
    ) async throws -> [Output] where Input: Sendable, Output: Sendable {
        guard !input.isEmpty else { return [] }

        return try await withThrowingTaskGroup(of: Output?.self) { group in
            var iterator = input.makeIterator()
            var activeTasks = 0
            var results: [Output] = []

            for _ in 0..<min(limit, input.count) {
                if let next = iterator.next() {
                    activeTasks += 1
                    group.addTask {
                        try await operation(next)
                    }
                }
            }

            while activeTasks > 0 {
                let taskResult = try await group.next()
                activeTasks -= 1

                if let taskResult, let value = taskResult {
                    results.append(value)
                }

                if let next = iterator.next() {
                    activeTasks += 1
                    group.addTask {
                        try await operation(next)
                    }
                }
            }

            return results
        }
    }
}

enum GitHubError: Error, Equatable, LocalizedError {
    case invalidURL
    case invalidResponse
    case unauthorized
    case forbidden
    case notFound
    case httpStatus(Int)
    case slowDown
    case deviceCodeExpired
    case accessDenied
    case reauthenticationRequired
    case oauthError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The GitHub API URL was invalid."
        case .invalidResponse:
            return "GitHub returned an invalid response."
        case .unauthorized:
            return "Authentication failed. Update the token in Settings."
        case .forbidden:
            return "GitHub rejected the request. Check that the token has Metadata read and Actions read access."
        case .notFound:
            return "The requested GitHub resource was not found."
        case .httpStatus(let statusCode):
            return "GitHub returned HTTP \(statusCode)."
        case .slowDown:
            return "GitHub asked the app to slow down while polling for authorization."
        case .deviceCodeExpired:
            return "The browser sign-in code expired. Start sign-in again."
        case .accessDenied:
            return "GitHub sign-in was denied."
        case .reauthenticationRequired:
            return "Your GitHub session expired. Sign in again."
        case .oauthError(let message):
            return "GitHub authentication failed: \(message)"
        }
    }
}
