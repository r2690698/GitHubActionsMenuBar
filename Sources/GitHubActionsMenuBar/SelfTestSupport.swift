import Foundation

public enum GitHubActionsMenuBarSelfTestSuite {
    public static func run() -> [String] {
        var failures: [String] = []

        expect(RunState(status: "in_progress", conclusion: nil) == .running, "RunState should map in_progress to .running", failures: &failures)
        expect(RunState(status: "completed", conclusion: "success") == .success, "RunState should map completed success to .success", failures: &failures)
        expect(RunState(status: "completed", conclusion: "failure") == .failure, "RunState should map completed failure to .failure", failures: &failures)

        let activeSession = GitHubAuthSession(
            accessToken: "token",
            refreshToken: "refresh",
            accessTokenExpiresAt: Date().addingTimeInterval(3600),
            refreshTokenExpiresAt: Date().addingTimeInterval(7200),
            tokenType: "bearer"
        )
        expect(activeSession.isAccessTokenExpired == false, "Active session should not be expired", failures: &failures)
        expect(activeSession.isRefreshTokenExpired == false, "Active refresh token should not be expired", failures: &failures)

        let expiredSession = GitHubAuthSession(
            accessToken: "token",
            refreshToken: "refresh",
            accessTokenExpiresAt: Date().addingTimeInterval(-10),
            refreshTokenExpiresAt: Date().addingTimeInterval(-10),
            tokenType: "bearer"
        )
        expect(expiredSession.isAccessTokenExpired, "Expired session should be marked expired", failures: &failures)
        expect(expiredSession.isRefreshTokenExpired, "Expired refresh token should be marked expired", failures: &failures)

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            let workflowRunsJSON = """
            {
              "workflow_runs": [
                {
                  "id": 123,
                  "name": "CI",
                  "display_title": "build-and-test",
                  "html_url": "https://github.com/example/repo/actions/runs/123",
                  "status": "completed",
                  "conclusion": "success",
                  "created_at": "2026-03-26T10:00:00Z",
                  "updated_at": "2026-03-26T10:05:00Z",
                  "run_number": 19,
                  "head_branch": "main"
                }
              ]
            }
            """
            let workflowRuns = try decoder.decode(WorkflowRunsResponse.self, from: Data(workflowRunsJSON.utf8))
            expect(workflowRuns.workflowRuns.count == 1, "Workflow runs response should decode one run", failures: &failures)
            expect(workflowRuns.workflowRuns[0].runState == .success, "Decoded workflow run should be success", failures: &failures)

            let jobsJSON = """
            {
              "jobs": [
                {
                  "id": 987,
                  "name": "deploy-to-dev",
                  "status": "in_progress",
                  "conclusion": null,
                  "started_at": "2026-03-26T10:00:00Z",
                  "completed_at": null,
                  "steps": [
                    {
                      "number": 1,
                      "name": "Set up job",
                      "status": "completed",
                      "conclusion": "success"
                    },
                    {
                      "number": 2,
                      "name": "Unit tests",
                      "status": "in_progress",
                      "conclusion": null
                    }
                  ]
                }
              ]
            }
            """
            let jobs = try decoder.decode(WorkflowJobsResponse.self, from: Data(jobsJSON.utf8))
            expect(jobs.jobs.count == 1, "Workflow jobs response should decode one job", failures: &failures)
            expect(jobs.jobs[0].runState == .running, "Decoded workflow job should be running", failures: &failures)
            expect(jobs.jobs[0].steps?.count == 2, "Workflow job should decode steps", failures: &failures)

            let deviceCodeJSON = """
            {
              "device_code": "abc123",
              "user_code": "ABCD-EFGH",
              "verification_uri": "https://github.com/login/device",
              "expires_in": 900,
              "interval": 5
            }
            """
            let deviceCode = try decoder.decode(DeviceCodeResponse.self, from: Data(deviceCodeJSON.utf8))
            expect(deviceCode.userCode == "ABCD-EFGH", "Device flow response should decode user code", failures: &failures)
        } catch {
            failures.append("Decoding test failed with error: \(error)")
        }

        return failures
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String, failures: inout [String]) {
        if !condition() {
            failures.append(message)
        }
    }
}
