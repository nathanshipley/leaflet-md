import Foundation

struct GitHubRepositoryContext: Equatable, Sendable {
    let slug: String
    let repositoryRootURL: URL
}
