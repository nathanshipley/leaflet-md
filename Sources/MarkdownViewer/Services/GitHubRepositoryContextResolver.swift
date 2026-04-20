import Foundation

enum GitHubRepositoryContextResolver {
    static func resolve(for fileURL: URL?) async -> GitHubRepositoryContext? {
        guard let baseDirectory = fileURL?.deletingLastPathComponent() else {
            return nil
        }

        return await Task.detached(priority: .utility) {
            do {
                let repositoryRoot = try ProcessRunner.run(
                    launchPath: "/usr/bin/env",
                    arguments: ["git", "-C", baseDirectory.path, "rev-parse", "--show-toplevel"]
                )
                let remoteURL = try ProcessRunner.run(
                    launchPath: "/usr/bin/env",
                    arguments: ["git", "-C", baseDirectory.path, "remote", "get-url", "origin"]
                )

                guard let slug = parseRepositorySlug(from: remoteURL) else {
                    return nil
                }

                return GitHubRepositoryContext(
                    slug: slug,
                    repositoryRootURL: URL(fileURLWithPath: repositoryRoot)
                )
            } catch {
                return nil
            }
        }.value
    }

    static func parseRepositorySlug(from remote: String) -> String? {
        let trimmedRemote = remote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedRemote.contains("github.com") else {
            return nil
        }

        if let range = trimmedRemote.range(of: "github.com:") {
            let slug = trimmedRemote[range.upperBound...]
            return normalize(slug: String(slug))
        }

        if let range = trimmedRemote.range(of: "github.com/") {
            let slug = trimmedRemote[range.upperBound...]
            return normalize(slug: String(slug))
        }

        return nil
    }

    private static func normalize(slug: String) -> String? {
        var normalized = slug.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.hasSuffix(".git") {
            normalized.removeLast(4)
        }
        normalized = normalized.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let components = normalized.split(separator: "/")
        guard components.count >= 2 else { return nil }
        return components.prefix(2).joined(separator: "/")
    }
}
