import Foundation

struct RenderContext: Equatable, Sendable {
    enum Purpose: String, Equatable, Sendable {
        case preview
        case export
    }

    let baseURL: URL?
    let repoContext: GitHubRepositoryContext?
    let purpose: Purpose
    let title: String
}
