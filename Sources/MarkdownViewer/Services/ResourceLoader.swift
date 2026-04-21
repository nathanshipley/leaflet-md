import Foundation

enum ResourceLoader {
    private static let resourceBundleName = "MarkdownViewer_MarkdownViewerCore.bundle"

    static func text(named name: String, extension fileExtension: String) -> String {
        guard let url = resourceURL(named: name, extension: fileExtension) else {
            return ""
        }

        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    static func url(
        named name: String,
        extension fileExtension: String,
        subdirectory: String? = nil
    ) -> URL? {
        resourceURL(named: name, extension: fileExtension, subdirectory: subdirectory)
    }

    static func dataURL(
        named name: String,
        extension fileExtension: String,
        subdirectory: String? = nil,
        mimeType: String
    ) -> String? {
        guard let url = resourceURL(named: name, extension: fileExtension, subdirectory: subdirectory),
              let data = try? Data(contentsOf: url)
        else {
            return nil
        }

        return "data:\(mimeType);base64,\(data.base64EncodedString())"
    }

    private static func resourceURL(
        named name: String,
        extension fileExtension: String,
        subdirectory: String? = nil
    ) -> URL? {
        let directory = subdirectory.map {
            resourceRootURL.appendingPathComponent($0, isDirectory: true)
        } ?? resourceRootURL

        let url = directory
            .appendingPathComponent(name)
            .appendingPathExtension(fileExtension)

        if FileManager.default.fileExists(atPath: url.path) {
            return url
        }

        let fontsURL = resourceRootURL
            .appendingPathComponent("Fonts", isDirectory: true)
            .appendingPathComponent(name)
            .appendingPathExtension(fileExtension)

        return FileManager.default.fileExists(atPath: fontsURL.path) ? fontsURL : nil
    }

    private static let resourceRootURL: URL = {
        let fileManager = FileManager.default
        let bundleCandidates = [
            Bundle.main.resourceURL?.appendingPathComponent(resourceBundleName, isDirectory: true),
            Bundle.main.bundleURL.deletingLastPathComponent()
                .appendingPathComponent(resourceBundleName, isDirectory: true),
            Bundle.main.bundleURL.appendingPathComponent(resourceBundleName, isDirectory: true),
            Bundle.main.executableURL?.deletingLastPathComponent()
                .appendingPathComponent(resourceBundleName, isDirectory: true)
        ].compactMap { $0 }

        if let packagedBundle = bundleCandidates.first(where: { fileManager.fileExists(atPath: $0.path) }) {
            return packagedBundle
        }

        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources", isDirectory: true)
    }()
}
