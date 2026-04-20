import XCTest
@testable import MarkdownViewerCore

final class GitHubRepositoryContextResolverTests: XCTestCase {
    func testParsesHTTPSGitHubRemote() {
        let slug = GitHubRepositoryContextResolver.parseRepositorySlug(
            from: "https://github.com/octo-org/octo-repo.git"
        )

        XCTAssertEqual(slug, "octo-org/octo-repo")
    }

    func testParsesSSHGithubRemote() {
        let slug = GitHubRepositoryContextResolver.parseRepositorySlug(
            from: "git@github.com:octo-org/octo-repo.git"
        )

        XCTAssertEqual(slug, "octo-org/octo-repo")
    }
}
