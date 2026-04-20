import Foundation

enum ResourceLoader {
    static func text(named name: String, extension fileExtension: String) -> String {
        guard let url = resourceURL(named: name, extension: fileExtension) else {
            return ""
        }

        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
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
        if let subdirectory {
            return Bundle.module.url(
                forResource: name,
                withExtension: fileExtension,
                subdirectory: subdirectory
            )
        }

        return Bundle.module.url(forResource: name, withExtension: fileExtension)
    }
}
