import AppKit
import DotFolioIntegrations
import DotFolioModels
import SwiftUI

/// The current step of a GitHub/GitLab sign-in.
struct ConnectionFlowSteps: View {
    @Bindable var model: ConnectionFlowModel

    var body: some View {
        switch model.step {
        case .idle: EmptyView()
        case .gitLabHost: GitLabHostStep(model: model)
        case .waitingForGitHub(let code): WaitingStep(model: model, code: code)
        case .connected(let account): ConnectedStep(model: model, account: account)
        case .failed(let failure): FailedStep(model: model, failure: failure)
        case .loading(let message): ProgressStep(title: message, onCancel: model.cancel)
        case .choosingRepos: RepoPickerStep(model: model)
        case .importing(let done, let total): ImportProgressView(model: model, done: done, total: total)
        case .importFinished(let summary): ImportFinishedView(model: model, summary: summary)
        }
    }
}
