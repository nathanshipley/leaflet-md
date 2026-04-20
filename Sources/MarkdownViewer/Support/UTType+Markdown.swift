import UniformTypeIdentifiers

extension UTType {
    static var markdownSource: UTType {
        UTType(filenameExtension: "md") ?? .plainText
    }
}
