import AppKit
import WebKit

struct PreviewSlackSelectionSnapshot {
    let plainText: String
    let htmlFragment: String?
    let slackTexty: String?
}

struct NativePreviewClipboardSelection {
    let plainText: String
    let htmlDocument: String?
}

@MainActor
final class PreviewSelectionBridge: NSObject {
    private static let sourceSelectionHelperScript = """
      function extractSourceSelectionText(root, selection) {
        const sourceRoot = root?.classList?.contains('source-view')
          ? root
          : root?.querySelector?.('.source-view');

        if (!sourceRoot || !selection || selection.rangeCount === 0 || selection.isCollapsed) {
          return '';
        }

        const primaryRange = selection.getRangeAt(0);
        const lines = [];

        Array.from(sourceRoot.querySelectorAll('.line-content')).forEach((cell) => {
          if (!primaryRange.intersectsNode(cell)) {
            return;
          }

          const cellRange = document.createRange();
          cellRange.selectNodeContents(cell);

          const slice = document.createRange();
          if (cell.contains(primaryRange.startContainer)) {
            slice.setStart(primaryRange.startContainer, primaryRange.startOffset);
          } else {
            slice.setStart(cellRange.startContainer, cellRange.startOffset);
          }

          if (cell.contains(primaryRange.endContainer)) {
            slice.setEnd(primaryRange.endContainer, primaryRange.endOffset);
          } else {
            slice.setEnd(cellRange.endContainer, cellRange.endOffset);
          }

          lines.push(
            slice.toString()
              .replace(/\\u00a0/g, '')
              .replace(/\\u200b/g, '')
          );
        });

        return lines.join('\\n');
      }
    """

    weak var webView: WKWebView?

    func installSelectionEnhancements() async {
        guard let webView else {
            return
        }

        let script = """
        return (() => {
          const root = document.querySelector('.markdown-body, .source-view');
          if (!root) {
            return false;
          }

          const installedFlag = '__markdownViewerSelectionEnhancementsInstalled';
          const cachedTextKey = '__markdownViewerCachedSelectionText';
          const cachedHTMLKey = '__markdownViewerCachedSelectionHTML';
          const cachedSourceTextKey = '__markdownViewerCachedSourceSelectionText';

          \(Self.sourceSelectionHelperScript)

          function clearCachedSelection() {
            window[cachedTextKey] = '';
            window[cachedHTMLKey] = '';
            window[cachedSourceTextKey] = '';
          }

          function updateSelectionCache() {
            const selection = window.getSelection();
            if (!selection || selection.rangeCount === 0 || selection.isCollapsed) {
              return;
            }

            const text = selection.toString();
            if (text.trim().length > 0) {
              const container = document.createElement('div');
              for (let index = 0; index < selection.rangeCount; index += 1) {
                container.appendChild(selection.getRangeAt(index).cloneContents());
              }

              window[cachedTextKey] = text;
              window[cachedHTMLKey] = container.innerHTML;

              const sourceText = extractSourceSelectionText(root, selection);
              if (sourceText.trim().length > 0) {
                window[cachedSourceTextKey] = sourceText;
              }
            }
          }

          if (!window[installedFlag]) {
            root.addEventListener('mousedown', clearCachedSelection, true);
            document.addEventListener('selectionchange', updateSelectionCache);
            document.addEventListener('mouseup', updateSelectionCache);
            document.addEventListener('keyup', updateSelectionCache);
            window[installedFlag] = true;
          }

          updateSelectionCache();
          return true;
        })();
        """

        _ = try? await webView.callAsyncJavaScript(
            script,
            arguments: [:],
            in: nil,
            contentWorld: .page
        )
    }

    func selectedText() async -> String? {
        guard let webView else {
            return nil
        }

        let script = """
        return (() => {
          const cachedTextKey = '__markdownViewerCachedSelectionText';
          const selection = window.getSelection();
          if (!selection || selection.rangeCount === 0 || selection.isCollapsed) {
            const cachedText = window[cachedTextKey];
            if (typeof cachedText === 'string' && cachedText.trim().length > 0) {
              return cachedText;
            }

            return "";
          }

          return selection.toString();
        })();
        """

        guard
            let value = try? await webView.callAsyncJavaScript(
                script,
                arguments: [:],
                in: nil,
                contentWorld: .page
            ) as? String
        else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : value
    }

    func selectedSourceText() async -> String? {
        guard let webView else {
            return nil
        }

        let script = """
        return (() => {
          const root = document.querySelector('.markdown-body, .source-view');
          const cachedSourceTextKey = '__markdownViewerCachedSourceSelectionText';
          const selection = window.getSelection();

          \(Self.sourceSelectionHelperScript)

          if (!selection || selection.rangeCount === 0 || selection.isCollapsed) {
            const cachedSourceText = window[cachedSourceTextKey];
            if (typeof cachedSourceText === 'string' && cachedSourceText.trim().length > 0) {
              return cachedSourceText;
            }

            return "";
          }

          return extractSourceSelectionText(root, selection);
        })();
        """

        guard
            let value = try? await webView.callAsyncJavaScript(
                script,
                arguments: [:],
                in: nil,
                contentWorld: .page
            ) as? String
        else {
            return nil
        }

        let normalized = value.replacingOccurrences(of: "\u{00A0}", with: "")
        let trimmed = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : normalized
    }

    // Finds all matches via TreeWalker and stores their positions
    // as global text offsets. Skips rebuild when query is unchanged
    // so Cmd-G keeps its position. Page reloads clear JS state
    // naturally, triggering a fresh rebuild.
    func countMatches(for query: String, caseSensitive: Bool = false) async -> Int {
        guard let webView else {
            return 0
        }

        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return 0
        }

        let script = """
        return (() => {
          const query = \(trimmedQuery.debugDescription);
          const caseSensitive = \(caseSensitive ? "true" : "false");

          if (query === (window.__findQuery || '') &&
              window.__findPositions && window.__findPositions.length > 0) {
            return window.__findPositions.length;
          }

          const root = document.querySelector('.markdown-body, .source-view');
          if (!root) { return 0; }

          const old = root.querySelector('.find-current-mark');
          if (old) { old.replaceWith(...old.childNodes); root.normalize(); }

          const needle = caseSensitive ? query : query.toLowerCase();
          const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
          const positions = [];
          let globalPos = 0;

          while (walker.nextNode()) {
            const node = walker.currentNode;
            const text = caseSensitive ? node.textContent : node.textContent.toLowerCase();
            let pos = 0;
            while (pos <= text.length - needle.length) {
              const idx = text.indexOf(needle, pos);
              if (idx === -1) break;
              positions.push({ globalStart: globalPos + idx, length: needle.length });
              pos = idx + Math.max(needle.length, 1);
            }
            globalPos += node.textContent.length;
          }

          window.__findQuery = query;
          window.__findPositions = positions;
          window.__findCurrent = -1;
          return positions.length;
        })();
        """

        guard
            let value = try? await webView.callAsyncJavaScript(
                script,
                arguments: [:],
                in: nil,
                contentWorld: .page
            ) as? Int
        else {
            return 0
        }

        return value
    }

    // Navigates to the next/previous match by wrapping it in a
    // DOM <span>. Only one span exists at a time — no compositor
    // layer, no stale highlights, no focus dependency.
    func findString(
        _ query: String,
        backwards: Bool = false,
        caseSensitive: Bool = false,
        resetAnchor: Bool = false
    ) async -> Bool {
        guard let webView else {
            return false
        }

        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            await clearFind()
            return false
        }

        let script = """
        return (() => {
            const positions = window.__findPositions || [];
            if (positions.length === 0) return false;

            let current = window.__findCurrent;
            if (\(resetAnchor ? "true" : "false")) {
                current = \(backwards ? "true" : "false") ? positions.length : -1;
            }

            if (\(backwards ? "true" : "false")) {
                current = current <= 0 ? positions.length - 1 : current - 1;
            } else {
                current = current >= positions.length - 1 ? 0 : current + 1;
            }

            window.__findCurrent = current;
            const match = positions[current];
            if (!match) return false;

            const root = document.querySelector('.markdown-body, .source-view');
            if (!root) return false;

            const old = root.querySelector('.find-current-mark');
            if (old) { old.replaceWith(...old.childNodes); root.normalize(); }

            const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
            let gPos = 0;
            let targetNode = null;
            let localOffset = 0;

            while (walker.nextNode()) {
                const node = walker.currentNode;
                const len = node.textContent.length;
                if (gPos + len > match.globalStart) {
                    targetNode = node;
                    localOffset = match.globalStart - gPos;
                    break;
                }
                gPos += len;
            }

            if (!targetNode) return false;

            const range = document.createRange();
            range.setStart(targetNode, localOffset);
            range.setEnd(targetNode, localOffset + match.length);

            const mark = document.createElement('span');
            mark.className = 'find-current-mark';
            range.surroundContents(mark);

            mark.scrollIntoView({ block: 'nearest', behavior: 'instant' });
            return true;
        })();
        """

        guard
            let found = try? await webView.callAsyncJavaScript(
                script,
                arguments: [:],
                in: nil,
                contentWorld: .page
            ) as? Bool
        else {
            return false
        }

        return found
    }

    func clearFind() async {
        guard let webView else {
            return
        }

        let script = """
        const root = document.querySelector('.markdown-body, .source-view');
        if (root) {
            const old = root.querySelector('.find-current-mark');
            if (old) { old.replaceWith(...old.childNodes); root.normalize(); }
        }
        window.__findQuery = '';
        window.__findPositions = [];
        window.__findCurrent = -1;
        """

        _ = try? await webView.callAsyncJavaScript(
            script,
            arguments: [:],
            in: nil,
            contentWorld: .page
        )
    }

    func copyNativeSelection() -> Bool {
        guard let webView else {
            return false
        }

        return NSApp.sendAction(#selector(NSText.copy(_:)), to: webView, from: nil)
    }

    func nativeClipboardSelection() -> NativePreviewClipboardSelection? {
        let pasteboard = NSPasteboard.general
        guard let plainText = pasteboard.string(forType: .string) else {
            return nil
        }

        let trimmed = plainText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let htmlDocument = pasteboard.data(forType: .html)
            .flatMap { String(data: $0, encoding: .utf8) }
            .map(Self.clipboardHTMLDocumentForSelectedFragment(from:))

        return NativePreviewClipboardSelection(
            plainText: plainText,
            htmlDocument: htmlDocument
        )
    }

    private static func clipboardHTMLDocumentForSelectedFragment(from htmlDocument: String) -> String {
        if let fragment = htmlClipboardFragment(from: htmlDocument) {
            return """
            <!doctype html>
            <html lang="en">
            <body>
            \(fragment)
            </body>
            </html>
            """
        }

        return htmlDocument
    }

    private func setFindAnchor(backwards: Bool) async {
        guard let webView else {
            return
        }

        let script = """
        return (() => {
          const root = document.querySelector('.markdown-body, .source-view');
          if (!root) {
            return false;
          }

          const selection = window.getSelection();
          if (!selection) {
            return false;
          }

          const range = document.createRange();
          if (\(backwards ? "true" : "false")) {
            range.selectNodeContents(root);
            range.collapse(false);
          } else {
            range.selectNodeContents(root);
            range.collapse(true);
          }

          selection.removeAllRanges();
          selection.addRange(range);
          return true;
        })();
        """

        _ = try? await webView.callAsyncJavaScript(
            script,
            arguments: [:],
            in: nil,
            contentWorld: .page
        )
    }

    private static func htmlClipboardFragment(from htmlDocument: String) -> String? {
        if
            let startMarkerRange = htmlDocument.range(of: "<!--StartFragment-->"),
            let endMarkerRange = htmlDocument.range(of: "<!--EndFragment-->"),
            startMarkerRange.upperBound <= endMarkerRange.lowerBound
        {
            let fragment = htmlDocument[startMarkerRange.upperBound..<endMarkerRange.lowerBound]
            let trimmed = fragment.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }

        let nsDocument = htmlDocument as NSString
        let startPattern = try? NSRegularExpression(pattern: "StartFragment:(\\d+)")
        let endPattern = try? NSRegularExpression(pattern: "EndFragment:(\\d+)")
        let range = NSRange(location: 0, length: nsDocument.length)

        guard
            let startMatch = startPattern?.firstMatch(in: htmlDocument, range: range),
            let endMatch = endPattern?.firstMatch(in: htmlDocument, range: range),
            startMatch.numberOfRanges > 1,
            endMatch.numberOfRanges > 1
        else {
            return nil
        }

        let startString = nsDocument.substring(with: startMatch.range(at: 1))
        let endString = nsDocument.substring(with: endMatch.range(at: 1))

        guard
            let startOffset = Int(startString),
            let endOffset = Int(endString),
            startOffset >= 0,
            endOffset > startOffset,
            endOffset <= htmlDocument.utf8.count
        else {
            return nil
        }

        let utf8 = Array(htmlDocument.utf8)
        let bytes = utf8[startOffset..<endOffset]
        let fragment = String(decoding: bytes, as: UTF8.self)
        let trimmed = fragment.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func slackHTMLFragment(selectionOnly: Bool) async -> String? {
        return await slackHTMLFragment(selectionOnly: selectionOnly, tableMode: .wrap)
    }

    func slackSelectionSnapshot(
        tableMode: SlackTableRenderingMode
    ) async -> PreviewSlackSelectionSnapshot? {
        guard let webView else {
            return nil
        }

        let script = """
        return (() => {
          const tableMode = "\(tableMode.rawValue)";
          const cachedTextKey = '__markdownViewerCachedSelectionText';
          const cachedHTMLKey = '__markdownViewerCachedSelectionHTML';

          function makeSpacer() {
            const spacer = document.createElement('p');
            spacer.className = 'slack-spacer';
            spacer.appendChild(document.createElement('br'));
            return spacer;
          }

          function hasMeaningfulText(node) {
            return (node.textContent || '').trim().length > 0;
          }

          function normalizeText(value) {
            return (value || '').replace(/\\s+/g, ' ').trim();
          }

          function separatorText() {
            return '────────────────────';
          }

          // Mirror the Swift exporter:
          //   * tableWideThreshold = 120 (line-width above which a table
          //     is "wide" enough to either wrap or flatten)
          //   * tableWrapColumnWidth = 60 (per-column cap when wrapping)
          function naturalCodeBlockLineWidth(rows) {
            if (rows.length === 0 || rows[0].length === 0) return 0;
            const widths = rows[0].map((_, c) =>
              Math.max(...rows.map((row) => (row[c] || '').length), 0)
            );
            return 4 + widths.reduce((a, b) => a + b, 0) + Math.max(0, 3 * (widths.length - 1));
          }

          function wrapCellText(text, width) {
            if (width <= 0) return [text];
            if (text.length <= width) return [text];
            const lines = [];
            let current = '';
            for (const word of text.split(' ')) {
              if (!word) continue;
              if (word.length > width) {
                if (current) { lines.push(current); current = ''; }
                let remaining = word;
                while (remaining.length > width) {
                  lines.push(remaining.slice(0, width));
                  remaining = remaining.slice(width);
                }
                current = remaining;
                continue;
              }
              if (!current) {
                current = word;
              } else if (current.length + 1 + word.length <= width) {
                current += ' ' + word;
              } else {
                lines.push(current);
                current = word;
              }
            }
            if (current) lines.push(current);
            return lines.length === 0 ? [''] : lines;
          }

          function tableToRows(table) {
            const rows = Array.from(table.querySelectorAll('tr')).map((row) =>
              Array.from(row.children).map((cell) => normalizeText(cell.textContent))
            );

            if (rows.length < 2) {
              const pre = document.createElement('pre');
              pre.textContent = normalizeText(table.innerText);
              return pre;
            }

            const headers = rows[0];
            const container = document.createElement('div');
            let rowCount = 0;

            for (const values of rows.slice(1)) {
              if (values.every((value) => !value)) {
                continue;
              }

              const row = document.createElement('p');
              row.className = 'slack-table-row';

              headers.forEach((header, index) => {
                if (index > 0) {
                  row.appendChild(document.createElement('br'));
                }
                row.appendChild(document.createTextNode(`${header}: `));
                row.appendChild(document.createTextNode(values[index] || ''));
              });

              if (rowCount > 0) {
                container.appendChild(makeSpacer());
              }

              container.appendChild(row);
              rowCount += 1;
            }

            if (!container.childNodes.length) {
              const pre = document.createElement('pre');
              pre.textContent = normalizeText(table.innerText);
              return pre;
            }

            return container;
          }

          function tableToCodeBlockText(table, { wrap }) {
            const rows = Array.from(table.querySelectorAll('tr')).map((row) =>
              Array.from(row.children).map((cell) => normalizeText(cell.textContent))
            );
            if (rows.length < 2) return normalizeText(table.innerText);

            const headerCells = rows[0];
            const valueRows = rows.slice(1);

            const naturalWidths = headerCells.map((_, c) =>
              Math.max(headerCells[c].length, ...valueRows.map((row) => (row[c] || '').length))
            );
            const naturalLine = 4 + naturalWidths.reduce((a, b) => a + b, 0) + Math.max(0, 3 * (naturalWidths.length - 1));

            const shouldWrap = wrap && naturalLine > 120;
            const widths = shouldWrap
              ? naturalWidths.map((w) => Math.min(w, 60))
              : naturalWidths;

            const padCell = (text, width) => (text || '').padEnd(width, ' ');
            const formatLine = (cells) =>
              `| ${cells.map((cell, i) => padCell(cell, widths[i])).join(' | ')} |`;

            const expandRow = (row) => {
              const wrapped = widths.map((w, c) => wrapCellText(row[c] || '', w));
              const lineCount = Math.max(...wrapped.map((cell) => cell.length));
              const lines = [];
              for (let i = 0; i < lineCount; i++) {
                const cells = wrapped.map((cell) => i < cell.length ? cell[i] : '');
                lines.push(formatLine(cells));
              }
              return lines;
            };

            const headerLines = expandRow(headerCells);
            const separatorLine = `| ${widths.map((width) => '-'.repeat(Math.max(width, 3))).join(' | ')} |`;
            const bodyLines = valueRows.flatMap(expandRow);

            return [...headerLines, separatorLine, ...bodyLines].join('\\n');
          }

          function pickTableRendering(table) {
            // Mirror the Swift exporter's resolveLayout. .flattenAll
            // always flattens; .flattenWide flattens only when the table
            // is wider than the threshold; .wrap always uses code-block
            // layout (with cell wrapping if wide).
            if (tableMode === 'flattenAll') {
              return tableToRows(table);
            }
            if (tableMode === 'flattenWide') {
              const rows = Array.from(table.querySelectorAll('tr')).map((row) =>
                Array.from(row.children).map((cell) => normalizeText(cell.textContent))
              );
              if (naturalCodeBlockLineWidth(rows) > 120) {
                return tableToRows(table);
              }
              return tableToCodeBlock(table);
            }
            // .wrap (default): use the wrapping code-block renderer.
            const pre = document.createElement('pre');
            const code = document.createElement('code');
            code.textContent = tableToCodeBlockText(table, { wrap: true });
            pre.appendChild(code);
            return pre;
          }

          function pad(value, width) {
            return (value || '').padEnd(width, ' ');
          }

          function tableToCodeBlock(table) {
            const rows = Array.from(table.querySelectorAll('tr')).map((row) =>
              Array.from(row.children).map((cell) => normalizeText(cell.textContent))
            );

            if (rows.length < 2) {
              const pre = document.createElement('pre');
              const code = document.createElement('code');
              code.textContent = normalizeText(table.innerText);
              pre.appendChild(code);
              return pre;
            }

            const widths = rows[0].map((_, columnIndex) => {
              return Math.max(...rows.map((row) => (row[columnIndex] || '').length), 3);
            });

            const formatRow = (values) => {
              return `| ${values.map((value, index) => pad(value || '', widths[index])).join(' | ')} |`;
            };

            const separator = `| ${widths.map((width) => '-'.repeat(width)).join(' | ')} |`;
            const formatted = [
              formatRow(rows[0]),
              separator,
              ...rows.slice(1).map(formatRow)
            ].join('\\n');

            const pre = document.createElement('pre');
            const code = document.createElement('code');
            code.textContent = formatted;
            pre.appendChild(code);
            return pre;
          }

          function convertHeadings(container) {
            container.querySelectorAll('h1, h2, h3, h4, h5, h6').forEach((heading) => {
              const wrapper = document.createElement('p');
              const strong = document.createElement('strong');
              strong.innerHTML = heading.innerHTML;
              wrapper.appendChild(strong);
              heading.replaceWith(wrapper);
            });
          }

          function listDepth(list) {
            let depth = 0;
            let parent = list.parentElement;
            while (parent) {
              if (parent.tagName === 'UL' || parent.tagName === 'OL') {
                depth += 1;
              }
              parent = parent.parentElement;
            }
            return depth;
          }

          function orderedListType(depth) {
            switch (depth % 3) {
              case 1:
                return 'a';
              case 2:
                return 'i';
              default:
                return '1';
            }
          }

          function unwrapListParagraphs(container) {
            container.querySelectorAll('li > p').forEach((paragraph) => {
              const listItem = paragraph.parentElement;
              if (!listItem) {
                return;
              }

              while (paragraph.firstChild) {
                listItem.insertBefore(paragraph.firstChild, paragraph);
              }

              paragraph.remove();
            });
          }

          function prepareLists(container) {
            unwrapListParagraphs(container);

            container.querySelectorAll('ol').forEach((list) => {
              list.setAttribute('type', orderedListType(listDepth(list)));
            });
          }

          function cleanup(container) {
            container.querySelectorAll('.anchor, .octicon, script, style, svg').forEach((node) => node.remove());

            container.querySelectorAll('del').forEach((strike) => {
              const replacement = document.createElement('s');
              replacement.innerHTML = strike.innerHTML;
              strike.replaceWith(replacement);
            });

            container.querySelectorAll('hr').forEach((rule) => {
              const paragraph = document.createElement('p');
              paragraph.className = 'slack-rule';
              paragraph.textContent = separatorText();
              rule.replaceWith(paragraph);
            });

            container.querySelectorAll('table').forEach((table) => {
              table.replaceWith(pickTableRendering(table));
            });

            convertHeadings(container);
            prepareLists(container);

            container.querySelectorAll('input.task-list-item-checkbox').forEach((input) => {
              const marker = document.createTextNode(input.checked ? '☑ ' : '☐ ');
              input.replaceWith(marker);
            });
          }

          function addSpacing(container) {
            const wrapper = document.createElement('div');
            const children = Array.from(container.childNodes).filter((node) => {
              return node.nodeType !== Node.TEXT_NODE || hasMeaningfulText(node);
            });

            children.forEach((child, index) => {
              if (child.nodeType === Node.TEXT_NODE) {
                const paragraph = document.createElement('p');
                paragraph.textContent = normalizeText(child.textContent);
                wrapper.appendChild(paragraph);
              } else {
                wrapper.appendChild(child);
              }

              if (index < children.length - 1) {
                wrapper.appendChild(makeSpacer());
              }
            });

            return wrapper;
          }

          function liveSelectionData() {
            const selection = window.getSelection();
            if (!selection || selection.rangeCount === 0 || selection.isCollapsed) {
              return null;
            }

            const text = selection.toString();
            if (text.trim().length === 0) {
              return null;
            }

            const container = document.createElement('div');
            for (let index = 0; index < selection.rangeCount; index += 1) {
              container.appendChild(selection.getRangeAt(index).cloneContents());
            }

            return {
              text,
              container
            };
          }

          function cachedSelectionData() {
            const text = window[cachedTextKey];
            const html = window[cachedHTMLKey];

            if (
              typeof text !== 'string' ||
              text.trim().length === 0 ||
              typeof html !== 'string' ||
              html.trim().length === 0
            ) {
              return null;
            }

            const container = document.createElement('div');
            container.innerHTML = html;
            return {
              text,
              container
            };
          }

          const selectionData = liveSelectionData() || cachedSelectionData();
          if (!selectionData) {
            return null;
          }

          cleanup(selectionData.container);
          const spaced = addSpacing(selectionData.container);
          return {
            plainText: (spaced.innerText || selectionData.text || '').trim(),
            htmlFragment: spaced.innerHTML
          };
        })();
        """

        guard
            let value = try? await webView.callAsyncJavaScript(
                script,
                arguments: [:],
                in: nil,
                contentWorld: .page
            ) as? [String: Any]
        else {
            return nil
        }

        guard let plainText = value["plainText"] as? String else {
            return nil
        }

        let trimmed = plainText.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let htmlFragment = value["htmlFragment"] as? String
        let normalizedHTMLFragment = htmlFragment?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty == true ? nil : htmlFragment
        var slackTexty: String?
        if let normalizedHTMLFragment {
            slackTexty = await buildSlackTexty(fromHTMLFragment: normalizedHTMLFragment)
        }
        return PreviewSlackSelectionSnapshot(
            plainText: plainText,
            htmlFragment: normalizedHTMLFragment,
            slackTexty: slackTexty
        )
    }

    private func buildSlackTexty(fromHTMLFragment htmlFragment: String) async -> String? {
        guard let webView else {
            return nil
        }

        let script = """
        return (() => {
          const container = document.createElement('div');
          container.innerHTML = htmlFragment;

          function hasMeaningfulText(node) {
            return (node.textContent || '').trim().length > 0;
          }

          function normalizeText(value) {
            return (value || '').replace(/\\s+/g, ' ').trim();
          }

          function normalizedAttributes(attributes) {
            if (!attributes) {
              return null;
            }

            const output = {};
            Object.entries(attributes).forEach(([key, value]) => {
              if (value !== undefined && value !== null && value !== false) {
                output[key] = value;
              }
            });

            return Object.keys(output).length > 0 ? output : null;
          }

          function sameAttributes(left, right) {
            const leftEntries = Object.entries(left || {});
            const rightEntries = Object.entries(right || {});
            if (leftEntries.length !== rightEntries.length) {
              return false;
            }

            return leftEntries.every(([key, value]) => right && right[key] === value);
          }

          function pushTextyOp(ops, insert, attributes) {
            if (!insert) {
              return;
            }

            const normalized = normalizedAttributes(attributes);
            const last = ops[ops.length - 1];
            if (last && sameAttributes(last.attributes || null, normalized)) {
              last.insert += insert;
              return;
            }

            const op = { insert };
            if (normalized) {
              op.attributes = normalized;
            }
            ops.push(op);
          }

          function mergedAttributes(base, extra) {
            return Object.assign({}, base || {}, extra || {});
          }

          function appendInlineNode(node, ops, inheritedAttributes = {}, options = {}) {
            if (node.nodeType === Node.TEXT_NODE) {
              const rawText = node.textContent || '';
              const text = options.collapseWhitespace
                ? rawText.replace(/\\s+/g, ' ')
                : rawText;
              if (!text || text.trim().length === 0) {
                return;
              }
              pushTextyOp(ops, text, inheritedAttributes);
              return;
            }

            if (node.nodeType !== Node.ELEMENT_NODE) {
              return;
            }

            const element = node;
            const tag = element.tagName;

            if (tag === 'BR') {
              pushTextyOp(ops, '\\n', inheritedAttributes);
              return;
            }

            if (tag === 'IMG') {
              const alt = element.getAttribute('alt') || '';
              if (alt.trim().length > 0) {
                pushTextyOp(ops, alt, inheritedAttributes);
              }
              return;
            }

            let nextAttributes = inheritedAttributes;
            switch (tag) {
              case 'STRONG':
              case 'B':
                nextAttributes = mergedAttributes(nextAttributes, { bold: true });
                break;
              case 'EM':
              case 'I':
                nextAttributes = mergedAttributes(nextAttributes, { italic: true });
                break;
              case 'S':
              case 'STRIKE':
              case 'DEL':
                nextAttributes = mergedAttributes(nextAttributes, { strike: true });
                break;
              case 'CODE':
                if (element.parentElement?.tagName !== 'PRE') {
                  nextAttributes = mergedAttributes(nextAttributes, { code: true });
                }
                break;
              case 'A': {
                const href = element.getAttribute('href');
                if (href) {
                  nextAttributes = mergedAttributes(nextAttributes, { link: href });
                }
                break;
              }
              default:
                break;
            }

            Array.from(element.childNodes).forEach((child) => {
              appendInlineNode(child, ops, nextAttributes, options);
            });
          }

          function appendInlineNodes(nodes, ops, inheritedAttributes = {}, options = {}) {
            Array.from(nodes).forEach((node) => {
              appendInlineNode(node, ops, inheritedAttributes, options);
            });
          }

          function trimTrailingWhitespace(ops) {
            const last = ops[ops.length - 1];
            if (!last || typeof last.insert !== 'string') {
              return;
            }

            const trimmed = last.insert.replace(/[ \\t\\r\\n]+$/, '');
            if (trimmed.length === 0) {
              ops.pop();
              return;
            }

            last.insert = trimmed;
          }

          function appendList(list, ops, indentLevel = 0) {
            const listType = list.tagName === 'OL' ? 'ordered' : 'bullet';

            Array.from(list.children).forEach((item) => {
              if (!(item instanceof HTMLElement) || item.tagName !== 'LI') {
                return;
              }

              const inlineNodes = [];
              const nestedLists = [];

              Array.from(item.childNodes).forEach((child) => {
                if (
                  child instanceof HTMLElement &&
                  (child.tagName === 'UL' || child.tagName === 'OL')
                ) {
                  nestedLists.push(child);
                } else {
                  inlineNodes.push(child);
                }
              });

              appendInlineNodes(inlineNodes, ops, {}, { collapseWhitespace: true });
              trimTrailingWhitespace(ops);
              pushTextyOp(
                ops,
                '\\n',
                indentLevel > 0
                  ? { list: listType, indent: indentLevel }
                  : { list: listType }
              );

              nestedLists.forEach((nestedList) => {
                appendList(nestedList, ops, indentLevel + 1);
              });
            });
          }

          function appendBlockquote(blockquote, ops) {
            const children = Array.from(blockquote.childNodes).filter((child) => {
              return child.nodeType !== Node.TEXT_NODE || hasMeaningfulText(child);
            });

            children.forEach((child) => {
              if (child instanceof HTMLElement && child.tagName === 'P') {
                appendInlineNodes(child.childNodes, ops);
              } else {
                appendInlineNode(child, ops);
              }

              trimTrailingWhitespace(ops);
              pushTextyOp(ops, '\\n', { blockquote: true });
            });
          }

          function appendCodeBlock(pre, ops) {
            const code = pre.querySelector('code');
            const text = (code?.innerText || pre.innerText || pre.textContent || '').replace(/\\n+$/, '');
            const lines = text.length > 0 ? text.split('\\n') : [''];
            lines.forEach((line) => {
              if (line.length > 0) {
                pushTextyOp(ops, line);
              }
              pushTextyOp(ops, '\\n', { 'code-block': true });
            });
          }

          function appendBlock(node, ops) {
            if (node.nodeType === Node.TEXT_NODE) {
              const text = normalizeText(node.textContent);
              if (text) {
                pushTextyOp(ops, text);
              }
              return;
            }

            if (!(node instanceof HTMLElement)) {
              return;
            }

            if (node.classList.contains('slack-spacer')) {
              pushTextyOp(ops, '\\n\\n');
              return;
            }

            switch (node.tagName) {
              case 'UL':
              case 'OL':
                appendList(node, ops);
                return;
              case 'BLOCKQUOTE':
                appendBlockquote(node, ops);
                return;
              case 'PRE':
                appendCodeBlock(node, ops);
                return;
              case 'DIV':
                Array.from(node.childNodes).forEach((child) => appendBlock(child, ops));
                return;
              case 'P':
                appendInlineNodes(node.childNodes, ops);
                return;
              default:
                appendInlineNode(node, ops);
                return;
            }
          }

          try {
            const ops = [];
            Array.from(container.childNodes).forEach((child) => {
              appendBlock(child, ops);
            });
            return ops.length > 0 ? JSON.stringify({ ops }) : null;
          } catch (error) {
            return null;
          }
        })();
        """

        let value = try? await webView.callAsyncJavaScript(
            script,
            arguments: ["htmlFragment": htmlFragment],
            in: nil,
            contentWorld: .page
        ) as? String

        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == true ? nil : trimmed
    }

    func slackHTMLFragment(
        selectionOnly: Bool,
        tableMode: SlackTableRenderingMode
    ) async -> String? {
        guard let webView else {
            return nil
        }

        let script = """
        return (() => {
          const selectionOnly = \(selectionOnly ? "true" : "false");
          const tableMode = "\(tableMode.rawValue)";
          const cachedHTMLKey = '__markdownViewerCachedSelectionHTML';

          function makeSpacer() {
            const spacer = document.createElement('p');
            spacer.className = 'slack-spacer';
            spacer.appendChild(document.createElement('br'));
            return spacer;
          }

          function hasMeaningfulText(node) {
            return (node.textContent || '').trim().length > 0;
          }

          function normalizeText(value) {
            return (value || '').replace(/\\s+/g, ' ').trim();
          }

          // Mirror the Swift exporter:
          //   * tableWideThreshold = 120 (line-width above which a table
          //     is "wide" enough to either wrap or flatten)
          //   * tableWrapColumnWidth = 60 (per-column cap when wrapping)
          function naturalCodeBlockLineWidth(rows) {
            if (rows.length === 0 || rows[0].length === 0) return 0;
            const widths = rows[0].map((_, c) =>
              Math.max(...rows.map((row) => (row[c] || '').length), 0)
            );
            return 4 + widths.reduce((a, b) => a + b, 0) + Math.max(0, 3 * (widths.length - 1));
          }

          function wrapCellText(text, width) {
            if (width <= 0) return [text];
            if (text.length <= width) return [text];
            const lines = [];
            let current = '';
            for (const word of text.split(' ')) {
              if (!word) continue;
              if (word.length > width) {
                if (current) { lines.push(current); current = ''; }
                let remaining = word;
                while (remaining.length > width) {
                  lines.push(remaining.slice(0, width));
                  remaining = remaining.slice(width);
                }
                current = remaining;
                continue;
              }
              if (!current) {
                current = word;
              } else if (current.length + 1 + word.length <= width) {
                current += ' ' + word;
              } else {
                lines.push(current);
                current = word;
              }
            }
            if (current) lines.push(current);
            return lines.length === 0 ? [''] : lines;
          }

          function tableToRows(table) {
            const rows = Array.from(table.querySelectorAll('tr')).map((row) =>
              Array.from(row.children).map((cell) => normalizeText(cell.textContent))
            );

            if (rows.length < 2) {
              const pre = document.createElement('pre');
              pre.textContent = normalizeText(table.innerText);
              return pre;
            }

            const headers = rows[0];
            const container = document.createElement('div');
            let rowCount = 0;

            for (const values of rows.slice(1)) {
              if (values.every((value) => !value)) {
                continue;
              }

              const row = document.createElement('p');
              row.className = 'slack-table-row';

              headers.forEach((header, index) => {
                if (index > 0) {
                  row.appendChild(document.createElement('br'));
                }
                row.appendChild(document.createTextNode(`${header}: `));
                row.appendChild(document.createTextNode(values[index] || ''));
              });

              if (rowCount > 0) {
                container.appendChild(makeSpacer());
              }

              container.appendChild(row);
              rowCount += 1;
            }

            if (!container.childNodes.length) {
              const pre = document.createElement('pre');
              pre.textContent = normalizeText(table.innerText);
              return pre;
            }

            return container;
          }

          function tableToCodeBlockText(table, { wrap }) {
            const rows = Array.from(table.querySelectorAll('tr')).map((row) =>
              Array.from(row.children).map((cell) => normalizeText(cell.textContent))
            );
            if (rows.length < 2) return normalizeText(table.innerText);

            const headerCells = rows[0];
            const valueRows = rows.slice(1);

            const naturalWidths = headerCells.map((_, c) =>
              Math.max(headerCells[c].length, ...valueRows.map((row) => (row[c] || '').length))
            );
            const naturalLine = 4 + naturalWidths.reduce((a, b) => a + b, 0) + Math.max(0, 3 * (naturalWidths.length - 1));

            const shouldWrap = wrap && naturalLine > 120;
            const widths = shouldWrap
              ? naturalWidths.map((w) => Math.min(w, 60))
              : naturalWidths;

            const padCell = (text, width) => (text || '').padEnd(width, ' ');
            const formatLine = (cells) =>
              `| ${cells.map((cell, i) => padCell(cell, widths[i])).join(' | ')} |`;

            const expandRow = (row) => {
              const wrapped = widths.map((w, c) => wrapCellText(row[c] || '', w));
              const lineCount = Math.max(...wrapped.map((cell) => cell.length));
              const lines = [];
              for (let i = 0; i < lineCount; i++) {
                const cells = wrapped.map((cell) => i < cell.length ? cell[i] : '');
                lines.push(formatLine(cells));
              }
              return lines;
            };

            const headerLines = expandRow(headerCells);
            const separatorLine = `| ${widths.map((width) => '-'.repeat(Math.max(width, 3))).join(' | ')} |`;
            const bodyLines = valueRows.flatMap(expandRow);

            return [...headerLines, separatorLine, ...bodyLines].join('\\n');
          }

          function pickTableRendering(table) {
            // Mirror the Swift exporter's resolveLayout. .flattenAll
            // always flattens; .flattenWide flattens only when the table
            // is wider than the threshold; .wrap always uses code-block
            // layout (with cell wrapping if wide).
            if (tableMode === 'flattenAll') {
              return tableToRows(table);
            }
            if (tableMode === 'flattenWide') {
              const rows = Array.from(table.querySelectorAll('tr')).map((row) =>
                Array.from(row.children).map((cell) => normalizeText(cell.textContent))
              );
              if (naturalCodeBlockLineWidth(rows) > 120) {
                return tableToRows(table);
              }
              return tableToCodeBlock(table);
            }
            // .wrap (default): use the wrapping code-block renderer.
            const pre = document.createElement('pre');
            const code = document.createElement('code');
            code.textContent = tableToCodeBlockText(table, { wrap: true });
            pre.appendChild(code);
            return pre;
          }

          function pad(value, width) {
            return (value || '').padEnd(width, ' ');
          }

          function tableToCodeBlock(table) {
            const rows = Array.from(table.querySelectorAll('tr')).map((row) =>
              Array.from(row.children).map((cell) => normalizeText(cell.textContent))
            );

            if (rows.length < 2) {
              const pre = document.createElement('pre');
              const code = document.createElement('code');
              code.textContent = normalizeText(table.innerText);
              pre.appendChild(code);
              return pre;
            }

            const widths = rows[0].map((_, columnIndex) => {
              return Math.max(...rows.map((row) => (row[columnIndex] || '').length), 3);
            });

            const formatRow = (values) => {
              return `| ${values.map((value, index) => pad(value || '', widths[index])).join(' | ')} |`;
            };

            const separator = `| ${widths.map((width) => '-'.repeat(width)).join(' | ')} |`;
            const formatted = [
              formatRow(rows[0]),
              separator,
              ...rows.slice(1).map(formatRow)
            ].join('\\n');

            const pre = document.createElement('pre');
            const code = document.createElement('code');
            code.textContent = formatted;
            pre.appendChild(code);
            return pre;
          }

          function cachedSelectionContainer() {
            const cachedHTML = window[cachedHTMLKey];
            if (
              typeof cachedHTML !== 'string' ||
              cachedHTML.trim().length === 0
            ) {
              return null;
            }

            const container = document.createElement('div');
            container.innerHTML = cachedHTML;
            return container;
          }

          function selectionContainer() {
            const selection = window.getSelection();
            if (!selection || selection.rangeCount === 0 || selection.isCollapsed) {
              return cachedSelectionContainer();
            }

            const container = document.createElement('div');
            for (let index = 0; index < selection.rangeCount; index += 1) {
              container.appendChild(selection.getRangeAt(index).cloneContents());
            }
            return container;
          }

          function documentContainer() {
            const root = document.querySelector('.markdown-body, .source-view');
            if (!root) {
              return null;
            }

            const container = document.createElement('div');
            Array.from(root.childNodes).forEach((node) => {
              container.appendChild(node.cloneNode(true));
            });
            return container;
          }

          function convertHeadings(container) {
            container.querySelectorAll('h1, h2, h3, h4, h5, h6').forEach((heading) => {
              const wrapper = document.createElement('p');
              const strong = document.createElement('strong');
              strong.innerHTML = heading.innerHTML;
              wrapper.appendChild(strong);
              heading.replaceWith(wrapper);
            });
          }

          function cleanup(container) {
            container.querySelectorAll('.anchor, .octicon, script, style, svg').forEach((node) => node.remove());

            container.querySelectorAll('input.task-list-item-checkbox').forEach((input) => {
              const marker = document.createTextNode(input.checked ? '☑ ' : '☐ ');
              input.replaceWith(marker);
            });

            container.querySelectorAll('table').forEach((table) => {
              table.replaceWith(pickTableRendering(table));
            });

            convertHeadings(container);
          }

          function addSpacing(container) {
            const wrapper = document.createElement('div');
            const children = Array.from(container.childNodes).filter((node) => {
              return node.nodeType !== Node.TEXT_NODE || hasMeaningfulText(node);
            });

            children.forEach((child, index) => {
              if (child.nodeType === Node.TEXT_NODE) {
                const paragraph = document.createElement('p');
                paragraph.textContent = normalizeText(child.textContent);
                wrapper.appendChild(paragraph);
              } else {
                wrapper.appendChild(child);
              }

              if (index < children.length - 1) {
                wrapper.appendChild(makeSpacer());
              }
            });

            return wrapper.innerHTML;
          }

          const container = selectionOnly ? selectionContainer() : documentContainer();
          if (!container) {
            return '';
          }

          cleanup(container);
          return addSpacing(container);
        })();
        """

        guard
            let fragment = try? await webView.callAsyncJavaScript(
                script,
                arguments: [:],
                in: nil,
                contentWorld: .page
            ) as? String
        else {
            return nil
        }

        let trimmed = fragment.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : fragment
    }

    func slackHTMLFragment(
        fromCopiedHTMLDocument htmlDocument: String,
        tableMode: SlackTableRenderingMode
    ) async -> String? {
        guard let webView else {
            return nil
        }

        let script = """
        return (() => {
          const sourceHTML = htmlDocument;
          const tableMode = "\(tableMode.rawValue)";

          function makeSpacer() {
            const spacer = document.createElement('p');
            spacer.className = 'slack-spacer';
            spacer.appendChild(document.createElement('br'));
            return spacer;
          }

          function hasMeaningfulText(node) {
            return (node.textContent || '').trim().length > 0;
          }

          function normalizeText(value) {
            return (value || '').replace(/\\s+/g, ' ').trim();
          }

          // Mirror the Swift exporter:
          //   * tableWideThreshold = 120 (line-width above which a table
          //     is "wide" enough to either wrap or flatten)
          //   * tableWrapColumnWidth = 60 (per-column cap when wrapping)
          function naturalCodeBlockLineWidth(rows) {
            if (rows.length === 0 || rows[0].length === 0) return 0;
            const widths = rows[0].map((_, c) =>
              Math.max(...rows.map((row) => (row[c] || '').length), 0)
            );
            return 4 + widths.reduce((a, b) => a + b, 0) + Math.max(0, 3 * (widths.length - 1));
          }

          function wrapCellText(text, width) {
            if (width <= 0) return [text];
            if (text.length <= width) return [text];
            const lines = [];
            let current = '';
            for (const word of text.split(' ')) {
              if (!word) continue;
              if (word.length > width) {
                if (current) { lines.push(current); current = ''; }
                let remaining = word;
                while (remaining.length > width) {
                  lines.push(remaining.slice(0, width));
                  remaining = remaining.slice(width);
                }
                current = remaining;
                continue;
              }
              if (!current) {
                current = word;
              } else if (current.length + 1 + word.length <= width) {
                current += ' ' + word;
              } else {
                lines.push(current);
                current = word;
              }
            }
            if (current) lines.push(current);
            return lines.length === 0 ? [''] : lines;
          }

          function tableToRows(table) {
            const rows = Array.from(table.querySelectorAll('tr')).map((row) =>
              Array.from(row.children).map((cell) => normalizeText(cell.textContent))
            );

            if (rows.length < 2) {
              const pre = document.createElement('pre');
              pre.textContent = normalizeText(table.innerText);
              return pre;
            }

            const headers = rows[0];
            const container = document.createElement('div');
            let rowCount = 0;

            for (const values of rows.slice(1)) {
              if (values.every((value) => !value)) {
                continue;
              }

              const row = document.createElement('p');
              row.className = 'slack-table-row';

              headers.forEach((header, index) => {
                if (index > 0) {
                  row.appendChild(document.createElement('br'));
                }
                row.appendChild(document.createTextNode(`${header}: `));
                row.appendChild(document.createTextNode(values[index] || ''));
              });

              if (rowCount > 0) {
                container.appendChild(makeSpacer());
              }

              container.appendChild(row);
              rowCount += 1;
            }

            if (!container.childNodes.length) {
              const pre = document.createElement('pre');
              pre.textContent = normalizeText(table.innerText);
              return pre;
            }

            return container;
          }

          function tableToCodeBlockText(table, { wrap }) {
            const rows = Array.from(table.querySelectorAll('tr')).map((row) =>
              Array.from(row.children).map((cell) => normalizeText(cell.textContent))
            );
            if (rows.length < 2) return normalizeText(table.innerText);

            const headerCells = rows[0];
            const valueRows = rows.slice(1);

            const naturalWidths = headerCells.map((_, c) =>
              Math.max(headerCells[c].length, ...valueRows.map((row) => (row[c] || '').length))
            );
            const naturalLine = 4 + naturalWidths.reduce((a, b) => a + b, 0) + Math.max(0, 3 * (naturalWidths.length - 1));

            const shouldWrap = wrap && naturalLine > 120;
            const widths = shouldWrap
              ? naturalWidths.map((w) => Math.min(w, 60))
              : naturalWidths;

            const padCell = (text, width) => (text || '').padEnd(width, ' ');
            const formatLine = (cells) =>
              `| ${cells.map((cell, i) => padCell(cell, widths[i])).join(' | ')} |`;

            const expandRow = (row) => {
              const wrapped = widths.map((w, c) => wrapCellText(row[c] || '', w));
              const lineCount = Math.max(...wrapped.map((cell) => cell.length));
              const lines = [];
              for (let i = 0; i < lineCount; i++) {
                const cells = wrapped.map((cell) => i < cell.length ? cell[i] : '');
                lines.push(formatLine(cells));
              }
              return lines;
            };

            const headerLines = expandRow(headerCells);
            const separatorLine = `| ${widths.map((width) => '-'.repeat(Math.max(width, 3))).join(' | ')} |`;
            const bodyLines = valueRows.flatMap(expandRow);

            return [...headerLines, separatorLine, ...bodyLines].join('\\n');
          }

          function pickTableRendering(table) {
            // Mirror the Swift exporter's resolveLayout. .flattenAll
            // always flattens; .flattenWide flattens only when the table
            // is wider than the threshold; .wrap always uses code-block
            // layout (with cell wrapping if wide).
            if (tableMode === 'flattenAll') {
              return tableToRows(table);
            }
            if (tableMode === 'flattenWide') {
              const rows = Array.from(table.querySelectorAll('tr')).map((row) =>
                Array.from(row.children).map((cell) => normalizeText(cell.textContent))
              );
              if (naturalCodeBlockLineWidth(rows) > 120) {
                return tableToRows(table);
              }
              return tableToCodeBlock(table);
            }
            // .wrap (default): use the wrapping code-block renderer.
            const pre = document.createElement('pre');
            const code = document.createElement('code');
            code.textContent = tableToCodeBlockText(table, { wrap: true });
            pre.appendChild(code);
            return pre;
          }

          function pad(value, width) {
            return (value || '').padEnd(width, ' ');
          }

          function tableToCodeBlock(table) {
            const rows = Array.from(table.querySelectorAll('tr')).map((row) =>
              Array.from(row.children).map((cell) => normalizeText(cell.textContent))
            );

            if (rows.length < 2) {
              const pre = document.createElement('pre');
              const code = document.createElement('code');
              code.textContent = normalizeText(table.innerText);
              pre.appendChild(code);
              return pre;
            }

            const widths = rows[0].map((_, columnIndex) => {
              return Math.max(...rows.map((row) => (row[columnIndex] || '').length), 3);
            });

            const formatRow = (values) => {
              return `| ${values.map((value, index) => pad(value || '', widths[index])).join(' | ')} |`;
            };

            const separator = `| ${widths.map((width) => '-'.repeat(width)).join(' | ')} |`;
            const formatted = [
              formatRow(rows[0]),
              separator,
              ...rows.slice(1).map(formatRow)
            ].join('\\n');

            const pre = document.createElement('pre');
            const code = document.createElement('code');
            code.textContent = formatted;
            pre.appendChild(code);
            return pre;
          }

          function convertHeadings(container) {
            container.querySelectorAll('h1, h2, h3, h4, h5, h6').forEach((heading) => {
              const wrapper = document.createElement('p');
              const strong = document.createElement('strong');
              strong.innerHTML = heading.innerHTML;
              wrapper.appendChild(strong);
              heading.replaceWith(wrapper);
            });
          }

          function cleanup(container) {
            container.querySelectorAll('.anchor, .octicon, script, style, svg').forEach((node) => node.remove());

            container.querySelectorAll('input.task-list-item-checkbox').forEach((input) => {
              const marker = document.createTextNode(input.checked ? '☑ ' : '☐ ');
              input.replaceWith(marker);
            });

            container.querySelectorAll('table').forEach((table) => {
              table.replaceWith(pickTableRendering(table));
            });

            convertHeadings(container);
          }

          function addSpacing(container) {
            const wrapper = document.createElement('div');
            const children = Array.from(container.childNodes).filter((node) => {
              return node.nodeType !== Node.TEXT_NODE || hasMeaningfulText(node);
            });

            children.forEach((child, index) => {
              if (child.nodeType === Node.TEXT_NODE) {
                const paragraph = document.createElement('p');
                paragraph.textContent = normalizeText(child.textContent);
                wrapper.appendChild(paragraph);
              } else {
                wrapper.appendChild(child);
              }

              if (index < children.length - 1) {
                wrapper.appendChild(makeSpacer());
              }
            });

            return wrapper.innerHTML;
          }

          const parsed = new DOMParser().parseFromString(sourceHTML, 'text/html');
          const sourceRoot = parsed.body;
          if (!sourceRoot) {
            return '';
          }

          const container = document.createElement('div');
          Array.from(sourceRoot.childNodes).forEach((node) => {
            container.appendChild(node.cloneNode(true));
          });

          cleanup(container);
          return addSpacing(container);
        })();
        """

        guard
            let fragment = try? await webView.callAsyncJavaScript(
                script,
                arguments: ["htmlDocument": htmlDocument],
                in: nil,
                contentWorld: .page
            ) as? String
        else {
            return nil
        }

        let trimmed = fragment.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : fragment
    }
}
