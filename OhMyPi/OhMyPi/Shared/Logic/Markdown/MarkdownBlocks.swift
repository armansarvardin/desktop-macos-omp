//
//  MarkdownBlocks.swift
//  OhMyPi
//
//  Created by Arman Sarvardin on 22/9/26.
//

import Foundation

/// Block-level markdown structure. Inline formatting inside paragraphs is
/// left to `AttributedString(markdown:)`, which only understands inline syntax.
nonisolated enum MarkdownBlock: Hashable, Identifiable, Sendable {
    case paragraph(String)
    case heading(level: Int, text: String)
    case code(language: String?, code: String)
    case list(ordered: Bool, items: [String])
    case quote(String)
    case rule

    var id: Int { hashValue }

    /// Splits text into blocks. Tolerates an unterminated code fence while streaming.
    static func parse(_ markdown: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var listItems: [String] = []
        var listOrdered = false
        var quoteLines: [String] = []
        var codeLines: [String] = []
        var codeLanguage: String?
        var inCode = false

        func flushParagraph() {
            let text = paragraph.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { blocks.append(.paragraph(text)) }
            paragraph.removeAll()
        }

        func flushList() {
            if !listItems.isEmpty { blocks.append(.list(ordered: listOrdered, items: listItems)) }
            listItems.removeAll()
        }

        func flushQuote() {
            let text = quoteLines.joined(separator: "\n")
            if !text.isEmpty { blocks.append(.quote(text)) }
            quoteLines.removeAll()
        }

        func flushAll() {
            flushParagraph()
            flushList()
            flushQuote()
        }

        for rawLine in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if inCode {
                if trimmed.hasPrefix("```") {
                    blocks.append(.code(language: codeLanguage, code: codeLines.joined(separator: "\n")))
                    codeLines.removeAll()
                    inCode = false
                } else {
                    codeLines.append(line)
                }
                continue
            }

            if trimmed.hasPrefix("```") {
                flushAll()
                inCode = true
                let language = trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces)
                codeLanguage = language.isEmpty ? nil : language
                continue
            }

            if trimmed.isEmpty {
                flushAll()
                continue
            }

            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                flushAll()
                blocks.append(.rule)
                continue
            }

            if let heading = headingLevel(of: trimmed) {
                flushAll()
                let text = trimmed.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
                blocks.append(.heading(level: heading, text: text))
                continue
            }

            if trimmed.hasPrefix("> ") || trimmed == ">" {
                flushParagraph()
                flushList()
                quoteLines.append(String(trimmed.dropFirst(trimmed == ">" ? 1 : 2)))
                continue
            }

            if let item = unorderedItem(of: trimmed) {
                flushParagraph()
                flushQuote()
                if !listItems.isEmpty, listOrdered { flushList() }
                listOrdered = false
                listItems.append(item)
                continue
            }

            if let item = orderedItem(of: trimmed) {
                flushParagraph()
                flushQuote()
                if !listItems.isEmpty, !listOrdered { flushList() }
                listOrdered = true
                listItems.append(item)
                continue
            }

            if !listItems.isEmpty, line.hasPrefix("  ") {
                // Continuation of the previous list item.
                listItems[listItems.count - 1] += "\n" + trimmed
                continue
            }

            flushList()
            flushQuote()
            paragraph.append(line)
        }

        if inCode {
            blocks.append(.code(language: codeLanguage, code: codeLines.joined(separator: "\n")))
        }
        flushAll()

        return blocks
    }

    // MARK: - Line classifiers

    private static func headingLevel(of line: String) -> Int? {
        let hashes = line.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(hashes), line.dropFirst(hashes).first == " " else { return nil }
        return hashes
    }

    private static func unorderedItem(of line: String) -> String? {
        for marker in ["- ", "* ", "+ "] where line.hasPrefix(marker) {
            return String(line.dropFirst(marker.count))
        }
        return nil
    }

    private static func orderedItem(of line: String) -> String? {
        let digits = line.prefix(while: \.isNumber)
        guard !digits.isEmpty, digits.count <= 3 else { return nil }
        let rest = line.dropFirst(digits.count)
        guard rest.hasPrefix(". ") || rest.hasPrefix(") ") else { return nil }
        return String(rest.dropFirst(2))
    }
}
