import Foundation

struct HTMLDocumentFactory {
    private let githubStyles: String
    private let appStyles: String

    init(
        githubStyles: String = ResourceLoader.text(named: "github-markdown", extension: "css"),
        appStyles: String = ResourceLoader.text(named: "app", extension: "css")
    ) {
        self.githubStyles = githubStyles
        self.appStyles = appStyles
    }

    func makeDocument(
        bodyHTML: String,
        title: String,
        containerClass: String = "preview-shell",
        contentClass: String = "markdown-body",
        contentTag: String = "article",
        renderingPreferences: PreviewRenderingPreferences = .standard
    ) -> String {
        """
        <!doctype html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <meta name="color-scheme" content="light">
          <title>\(title.htmlEscaped)</title>
          <style>\(githubStyles)</style>
          <style>\(appStyles)</style>
          <style>\(renderingPreferences.cssOverrides)</style>
        </head>
        <body>
          <main class="document-shell \(containerClass)">
            <\(contentTag) class="\(contentClass)">
              \(bodyHTML)
            </\(contentTag)>
          </main>
        </body>
        </html>
        """
    }
}
