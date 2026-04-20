import Foundation

extension URL {
    func removingFragment() -> URL {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else {
            return self
        }

        components.fragment = nil
        return components.url ?? self
    }

    func isSameDocumentAnchor(for mainDocumentURL: URL?) -> Bool {
        guard let mainDocumentURL else { return false }
        guard let fragment, !fragment.isEmpty else { return false }
        return removingFragment() == mainDocumentURL.removingFragment()
    }
}
