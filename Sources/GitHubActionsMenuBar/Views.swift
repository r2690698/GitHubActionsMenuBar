import SwiftUI

struct MenuBarContentView: View {
    @Bindable var store: GitHubActionsStore
    @State private var selectedRepoStatus: RepoActionStatus?

    var body: some View {
        Group {
            if let selectedRepoStatus {
                RepoDetailView(
                    store: store,
                    repoStatus: selectedRepoStatus,
                    onBack: { self.selectedRepoStatus = nil }
                )
            } else {
                repoListScreen
            }
        }
        .padding(14)
        .frame(width: 560)
    }

    private var repoListScreen: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if let errorMessage = store.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if store.isAuthenticated {
                repoList
            } else {
                unauthenticatedState
            }

            Divider()

            HStack {
                Button("Refresh Now") {
                    Task { await store.refresh() }
                }
                .disabled(!store.isAuthenticated || store.isRefreshing)

                SettingsLink {
                    Text("Settings")
                }

                Spacer()

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                GitHubLockupView()
                    .frame(width: 118, height: 28, alignment: .leading)

                Text("Actions")
                    .font(.headline)

                Text(lastUpdatedLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(store.authStatusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if store.isRefreshing {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    private var lastUpdatedLabel: String {
        if let lastUpdatedAt = store.lastUpdatedAt {
            return "Updated \(lastUpdatedAt.formatted(date: .omitted, time: .standard))"
        }

        return "Waiting for first sync"
    }

    private var repoList: some View {
        Group {
            if store.repoStatuses.isEmpty && !store.isRefreshing {
                ContentUnavailableView("No Actions Data", systemImage: "tray", description: Text(emptyStateMessage))
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(store.repoStatuses) { repoStatus in
                            RepoStatusRow(repoStatus: repoStatus) {
                                store.loadJobs(for: repoStatus)
                                selectedRepoStatus = repoStatus
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxHeight: 620)
            }
        }
    }

    private var emptyStateMessage: String {
        "No repositories with GitHub Actions were visible through the current GitHub App sign-in. Install the app on the personal account or organizations you want to monitor, then grant it repository access."
    }

    private var unauthenticatedState: some View {
        ContentUnavailableView(
            store.deviceCode == nil ? "GitHub Sign-In Required" : "Complete Browser Sign-In",
            systemImage: store.deviceCode == nil ? "person.crop.circle.badge.questionmark" : "desktopcomputer.and.arrow.down",
            description: Text(unauthenticatedDescription)
        )
    }

    private var unauthenticatedDescription: String {
        if let deviceCode = store.deviceCode {
            return "GitHub opened a browser sign-in. Enter code \(deviceCode.userCode) at \(deviceCode.verificationURI)."
        }

        return "Open Settings and sign in with the GitHub App. After sign-in, install the app on your personal account and any organizations you want to monitor."
    }
}

struct RepoStatusRow: View {
    let repoStatus: RepoActionStatus
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: repoStatus.latestRun?.runState.symbolName ?? "line.3.horizontal.circle.fill")
                    .foregroundStyle(repoStatus.latestRun?.runState.tint ?? .secondary)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(repoStatus.repository.fullName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)

                        if repoStatus.repository.isPrivate {
                            Image(systemName: "lock.fill")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text(repoStatus.summaryText)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(repoStatus.latestActivityDate.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
        }
        .buttonStyle(.plain)
    }
}

struct RepoDetailView: View {
    @Bindable var store: GitHubActionsStore
    let repoStatus: RepoActionStatus
    let onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button(action: onBack) {
                    Label("Back", systemImage: "chevron.left")
                }
                .buttonStyle(.plain)

                Spacer()

                if let latestRun = repoStatus.latestRun {
                    Link("Open in GitHub", destination: latestRun.htmlURL)
                        .font(.caption)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(repoStatus.repository.fullName)
                    .font(.headline)

                Text(repoStatus.summaryText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text(repoStatus.latestActivityDate.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    switch store.jobsState(for: repoStatus) {
                    case .idle, .loading:
                        ProgressView("Loading jobs…")
                            .font(.caption)
                    case .failed(let message):
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.red)
                    case .loaded(let jobs):
                        if jobs.isEmpty {
                            Text("No jobs returned for this workflow run.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(jobs) { job in
                                WorkflowJobDetailView(job: job)
                            }
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(maxHeight: 620)
        }
        .onAppear {
            store.loadJobs(for: repoStatus)
        }
    }
}

struct WorkflowJobDetailView: View {
    let job: WorkflowJob

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: job.runState.symbolName)
                    .foregroundStyle(job.runState.tint)
                    .frame(width: 16)

                Text(job.name)
                    .font(.caption.weight(.medium))

                Spacer()

                Text(job.runState.label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(job.steps ?? []) { step in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: step.runState.symbolName)
                            .foregroundStyle(step.runState.tint)
                            .frame(width: 16)

                        Text(step.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Spacer()
                    }
                }
            }
            .padding(.leading, 10)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
}

struct SettingsView: View {
    @Bindable var store: GitHubActionsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            GitHubLockupView()
                .frame(width: 160, height: 38, alignment: .leading)

            Form {
                Section("GitHub App") {
                    Text("Client ID: \(GitHubClient.clientID)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let deviceCode = store.deviceCode {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Verification code")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(deviceCode.userCode)
                                .font(.title2.monospaced())
                        }
                    } else if let session = store.authSession {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Signed in")
                            Text(session.maskedAccessToken)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("Not signed in")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Installations") {
                    Text("After browser sign-in, install this GitHub App on your personal account and on any organizations you want included. The installation step happens on GitHub, not in this app.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Refresh") {
                    Text("The menu bar refreshes every 30 seconds and can notify when actions start, pass, or fail.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Notifications") {
                    Toggle("Notify when actions start", isOn: Binding(
                        get: { store.notificationPreferences.notifyOnStarted },
                        set: { newValue in
                            store.updateNotificationPreferences { $0.notifyOnStarted = newValue }
                        }
                    ))

                    Toggle("Notify when actions pass", isOn: Binding(
                        get: { store.notificationPreferences.notifyOnPassed },
                        set: { newValue in
                            store.updateNotificationPreferences { $0.notifyOnPassed = newValue }
                        }
                    ))

                    Toggle("Notify when actions fail", isOn: Binding(
                        get: { store.notificationPreferences.notifyOnFailed },
                        set: { newValue in
                            store.updateNotificationPreferences { $0.notifyOnFailed = newValue }
                        }
                    ))

                    Button("Send Test Notification") {
                        store.sendTestNotification()
                    }
                }

                if let errorMessage = store.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                HStack {
                    Button(store.deviceCode == nil ? "Sign In With Browser" : "Open Verification Page") {
                        if store.deviceCode == nil {
                            store.beginSignIn()
                        } else {
                            store.openDeviceVerificationPage()
                        }
                    }
                    .keyboardShortcut(.defaultAction)

                    if store.authSession != nil || store.deviceCode != nil {
                        Button("Sign Out") {
                            store.signOut()
                        }
                    }

                    Spacer()
                }
            }
        }
        .padding(20)
    }
}
