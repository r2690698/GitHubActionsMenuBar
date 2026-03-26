import AppKit
import Foundation
import SwiftUI

@MainActor
@Observable
final class GitHubActionsStore {
    var repoStatuses: [RepoActionStatus] = []
    var authSession: GitHubAuthSession?
    var deviceCode: DeviceCodeResponse?
    var notificationPreferences = NotificationPreferences()
    var jobsByRunID: [Int: RunJobsLoadState] = [:]
    var lastUpdatedAt: Date?
    var isRefreshing = false
    var isAuthenticating = false
    var errorMessage: String?

    private let client = GitHubClient()
    private let notificationManager = NotificationManager()
    private var refreshTask: Task<Void, Never>?
    private var authTask: Task<Void, Never>?
    private var hasEstablishedBaseline = false
    private var seenLatestRunIDs: [Int: Int] = [:]

    init() {
        authSession = KeychainStore.loadSession()
        notificationPreferences = PreferencesStore.loadNotificationPreferences()
    }

    var isAuthenticated: Bool {
        authSession != nil
    }

    var menuBarPrimaryColor: Color {
        switch overallRunState {
        case .failure:
            return .red
        case .running, .queued:
            return .blue
        case .success:
            return .green
        case .cancelled:
            return .orange
        case .neutral, .unknown:
            return isAuthenticated ? .secondary : .gray
        }
    }

    var menuBarStatusBadgeGlyph: String {
        switch overallRunState {
        case .failure:
            return "x"
        case .running, .queued:
            return "…"
        case .success:
            return "✓"
        case .cancelled:
            return "−"
        case .neutral, .unknown:
            return isAuthenticated ? "•" : "/"
        }
    }

    var errorSummaryFailures: [RepoActionStatus] {
        repoStatuses.filter { $0.latestRun?.runState == .failure }
    }

    var overallRunState: RunState {
        if repoStatuses.contains(where: { $0.latestRun?.runState == .failure }) {
            return .failure
        }

        if repoStatuses.contains(where: { $0.latestRun?.runState == .running || $0.latestRun?.runState == .queued }) {
            return .running
        }

        if repoStatuses.contains(where: { $0.latestRun?.runState == .success }) {
            return .success
        }

        if repoStatuses.contains(where: { $0.latestRun?.runState == .cancelled }) {
            return .cancelled
        }

        return .unknown
    }

    var authStatusText: String {
        if let authSession {
            return "Signed in • \(authSession.maskedAccessToken)"
        }

        if let deviceCode {
            return "Waiting for browser approval • code \(deviceCode.userCode)"
        }

        return "Not signed in"
    }

    func start() async {
        await notificationManager.requestAuthorization()
        await refresh()
        startPolling()
    }

    func startPolling() {
        guard refreshTask == nil else { return }

        refreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                await refresh()
            }
        }
    }

    func beginSignIn() {
        guard !isAuthenticating else { return }

        authTask?.cancel()
        authTask = Task {
            await runDeviceFlow()
        }
    }

    func signOut() {
        authTask?.cancel()
        deviceCode = nil
        authSession = nil
        repoStatuses = []
        jobsByRunID = [:]
        lastUpdatedAt = nil
        errorMessage = nil
        hasEstablishedBaseline = false
        seenLatestRunIDs = [:]

        do {
            try KeychainStore.deleteSession()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func openDeviceVerificationPage() {
        guard let verificationURI = deviceCode?.verificationURI, let url = URL(string: verificationURI) else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    func refresh() async {
        guard var session = authSession else {
            repoStatuses = []
            errorMessage = nil
            return
        }

        guard !isRefreshing else { return }

        isRefreshing = true
        defer { isRefreshing = false }

        do {
            if session.isAccessTokenExpired {
                session = try await client.refreshUserSession(session)
                authSession = session
                try KeychainStore.saveSession(session)
            }

            let statuses = try await client.fetchRepoStatuses(userToken: session.accessToken)
            let previousRuns = seenLatestRunIDs
            repoStatuses = statuses
            jobsByRunID = jobsByRunID.filter { runID, _ in
                statuses.contains { $0.latestRun?.id == runID }
            }
            lastUpdatedAt = Date()
            errorMessage = statuses.isEmpty
                ? "No repositories were visible through this GitHub App installation. Install the app on your personal account or orgs, then grant it access to the repositories you want to monitor."
                : nil

            await processNotifications(with: statuses, previousRuns: previousRuns)
            for status in statuses {
                if let latestRun = status.latestRun {
                    seenLatestRunIDs[status.repository.id] = latestRun.id
                }
            }
            hasEstablishedBaseline = true
        } catch {
            if case GitHubError.reauthenticationRequired = error {
                signOut()
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func runDeviceFlow() async {
        isAuthenticating = true
        errorMessage = nil
        defer { isAuthenticating = false }

        do {
            let deviceCode = try await client.startDeviceFlow()
            self.deviceCode = deviceCode
            openDeviceVerificationPage()

            var pollingInterval = deviceCode.interval
            let deadline = Date().addingTimeInterval(TimeInterval(deviceCode.expiresIn))

            while Date() < deadline {
                try Task.checkCancellation()
                try await Task.sleep(for: .seconds(pollingInterval))

                do {
                    if let session = try await client.pollForUserSession(deviceCode: deviceCode.deviceCode) {
                        authSession = session
                        self.deviceCode = nil
                        try KeychainStore.saveSession(session)
                        hasEstablishedBaseline = false
                        seenLatestRunIDs = [:]
                        await refresh()
                        return
                    }
                } catch GitHubError.slowDown {
                    pollingInterval += 5
                }
            }

            self.deviceCode = nil
            errorMessage = "The GitHub sign-in code expired before authorization completed."
        } catch is CancellationError {
            return
        } catch {
            self.deviceCode = nil
            errorMessage = error.localizedDescription
        }
    }

    private func processNotifications(with statuses: [RepoActionStatus], previousRuns: [Int: Int]) async {
        guard hasEstablishedBaseline else { return }

        for status in statuses {
            guard let latestRun = status.latestRun else { continue }
            let previousRunID = previousRuns[status.repository.id]
            guard previousRunID != latestRun.id else { continue }
            await notificationManager.notifyLatestRun(for: status, preferences: notificationPreferences)
        }
    }

    func loadJobs(for repoStatus: RepoActionStatus) {
        guard let latestRun = repoStatus.latestRun else { return }
        guard jobsByRunID[latestRun.id] == nil || jobsByRunID[latestRun.id] == .idle else { return }
        guard let session = authSession else { return }

        jobsByRunID[latestRun.id] = .loading

        Task {
            do {
                let jobs = try await client.fetchJobs(
                    for: repoStatus.repository,
                    runID: latestRun.id,
                    userToken: session.accessToken
                )
                await MainActor.run {
                    self.jobsByRunID[latestRun.id] = .loaded(jobs)
                }
            } catch {
                await MainActor.run {
                    self.jobsByRunID[latestRun.id] = .failed(error.localizedDescription)
                }
            }
        }
    }

    func jobsState(for repoStatus: RepoActionStatus) -> RunJobsLoadState {
        guard let latestRun = repoStatus.latestRun else { return .idle }
        return jobsByRunID[latestRun.id] ?? .idle
    }

    func updateNotificationPreferences(_ update: (inout NotificationPreferences) -> Void) {
        update(&notificationPreferences)
        PreferencesStore.saveNotificationPreferences(notificationPreferences)
    }

    func sendTestNotification() {
        Task {
            await notificationManager.sendTestNotification()
        }
    }
}
