import Foundation

protocol RecipePageLoading: Sendable {
    func load(url: URL) async throws -> String
}

struct URLSessionRecipePageLoader: RecipePageLoading {
    var timeout: TimeInterval = 20

    func load(url: URL) async throws -> String {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw ImportFailure.network
        }
        let slice = data.prefix(1_500_000)
        let html = String(data: slice, encoding: .utf8)
            ?? String(data: slice, encoding: .isoLatin1)
            ?? ""
        if html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ImportFailure.parsing
        }
        return html
    }
}

struct RecipeExtractionResult: Equatable, Sendable {
    var document: RecipeImportDocument
    var failure: ImportFailure?
}

/// JSON-LD Recipe first, then meta tags, then visible headings. Missing numbers stay nil.
enum RecipeExtractionService {
    static func extract(html: String, sourceURL: URL) -> RecipeExtractionResult {
        let platform = URLNormalizer.platform(for: sourceURL)
        var document = RecipeImportDocument.emptyManual()
        document.origin = .imported
        document.sourceURL = URLNormalizer.normalizedString(sourceURL.absoluteString) ?? sourceURL.absoluteString
        document.sourcePlatform = platform
        document.sourceKey = URLNormalizer.sourceKey(for: sourceURL)
        document.ingredients = []
        document.instructions = []

        if let structured = bestJSONLDRecipe(in: html) {
            apply(structured, to: &document)
            document.extractionConfidence = confidence(for: document, source: .jsonLD)
        } else {
            applyMetadata(html, to: &document)
            applyVisibleText(html, to: &document)
            document.extractionConfidence = confidence(for: document, source: document.ingredients.isEmpty ? .metadata : .visibleText)
        }

        if document.sourceTitle.isEmpty {
            document.sourceTitle = document.title
        }
        if document.ingredients.isEmpty {
            document.ingredients = [ImportedIngredient(name: "", isUncertain: true, sortOrder: 0, includeInGrocery: false)]
        }

        let named = document.ingredients.contains {
            !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let steps = document.instructions.contains {
            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let titled = !document.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if !titled && !named && !steps {
            let failure: ImportFailure = platform.isSocialPost ? .unsupportedSource : .missingRecipeData
            return RecipeExtractionResult(document: document, failure: failure)
        }
        return RecipeExtractionResult(document: document, failure: nil)
    }

    static func load(
        url: URL,
        loader: any RecipePageLoading = URLSessionRecipePageLoader()
    ) async -> RecipeExtractionResult {
        var shell = RecipeImportDocument.emptyManual()
        shell.origin = .imported
        shell.sourceURL = URLNormalizer.normalizedString(url.absoluteString) ?? url.absoluteString
        shell.sourcePlatform = URLNormalizer.platform(for: url)
        shell.sourceKey = URLNormalizer.sourceKey(for: url)
        do {
            try Task.checkCancellation()
            let html = try await loader.load(url: url)
            try Task.checkCancellation()
            return extract(html: html, sourceURL: url)
        } catch is CancellationError {
            return RecipeExtractionResult(document: shell, failure: .cancelled)
        } catch {
            return RecipeExtractionResult(document: shell, failure: ImportFailure.map(error))
        }
    }

    private enum ExtractionSource {
        case jsonLD
        case metadata
        case visibleText
    }

    private static func confidence(for document: RecipeImportDocument, source: ExtractionSource) -> Double {
        let named = document.ingredients.contains { !$0.name.isEmpty }
        let steps = document.instructions.contains { !$0.text.isEmpty }
        switch source {
        case .jsonLD:
            if named && steps && !document.title.isEmpty { return 0.9 }
            if named || steps { return 0.6 }
            return 0.4
        case .visibleText:
            return named && steps ? 0.55 : 0.35
        case .metadata:
            return 0.3
        }
    }

    private static func apply(_ object: [String: Any], to document: inout RecipeImportDocument) {
        if let name = stringValue(object["name"]) {
            document.title = decodeEntities(name)
            document.sourceTitle = document.title
        }
        if let summary = stringValue(object["description"]) {
            document.summary = decodeEntities(summary)
        }
        document.prepMinutes = object["prepTime"].flatMap { stringValue($0) }.flatMap(TimeParser.minutes(fromISO8601:))
        document.cookMinutes = object["cookTime"].flatMap { stringValue($0) }.flatMap(TimeParser.minutes(fromISO8601:))
        document.totalMinutes = object["totalTime"].flatMap { stringValue($0) }.flatMap(TimeParser.minutes(fromISO8601:))
        if let yield = object["recipeYield"] {
            let parsed = ServingParser.parse(yieldText(yield))
            document.servings = parsed.count
        }
        if let category = stringValue(object["recipeCategory"]) ?? firstString(object["recipeCategory"]) {
            document.category = decodeEntities(category)
        }
        if let cuisine = stringValue(object["recipeCuisine"]) ?? firstString(object["recipeCuisine"]) {
            document.cuisine = decodeEntities(cuisine)
        }
        let ingredientLines = stringList(object["recipeIngredient"])
        document.ingredients = ingredientLines.enumerated().map { index, line in
            IngredientParser.parse(line: decodeEntities(line), sortOrder: index)
        }
        document.instructions = instructions(from: object["recipeInstructions"])
    }

    private static func bestJSONLDRecipe(in html: String) -> [String: Any]? {
        let blocks = jsonLDBlocks(in: html)
        var best: [String: Any]?
        var bestScore = -1
        for block in blocks {
            guard let data = block.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) else { continue }
            for object in recipeObjects(in: json) {
                let score = stringList(object["recipeIngredient"]).count + instructions(from: object["recipeInstructions"]).count
                if score > bestScore {
                    best = object
                    bestScore = score
                }
            }
        }
        return best
    }

    private static func jsonLDBlocks(in html: String) -> [String] {
        let pattern = #"<script[^>]*type\s*=\s*["']application/ld\+json["'][^>]*>(.*?)</script>"#
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        return expression.matches(in: html, range: range).compactMap { match in
            guard let swiftRange = Range(match.range(at: 1), in: html) else { return nil }
            return String(html[swiftRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private static func recipeObjects(in json: Any) -> [[String: Any]] {
        if let array = json as? [Any] {
            return array.flatMap { recipeObjects(in: $0) }
        }
        guard let object = json as? [String: Any] else { return [] }
        var found: [[String: Any]] = []
        if isRecipe(object["@type"]) {
            found.append(object)
        }
        if let graph = object["@graph"] {
            found.append(contentsOf: recipeObjects(in: graph))
        }
        return found
    }

    private static func isRecipe(_ value: Any?) -> Bool {
        if let text = value as? String {
            return text.split(separator: "/").last?.lowercased() == "recipe"
        }
        if let list = value as? [Any] {
            return list.contains { isRecipe($0) }
        }
        return false
    }

    private static func instructions(from value: Any?) -> [ImportedInstruction] {
        let lines = instructionLines(from: value)
        return lines.enumerated().map { index, line in
            let decoded = decodeEntities(line)
            return ImportedInstruction(
                text: InstructionParser.stripNumbering(decoded),
                sortOrder: index,
                isUncertain: false,
                originalText: decoded
            )
        }
    }

    private static func instructionLines(from value: Any?) -> [String] {
        if let text = value as? String {
            return text.split(whereSeparator: \.isNewline).map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
        if let list = value as? [Any] {
            return list.flatMap { instructionLines(from: $0) }
        }
        if let object = value as? [String: Any] {
            if let text = stringValue(object["text"]) {
                var lines = [text]
                if let children = object["itemListElement"] {
                    lines.append(contentsOf: instructionLines(from: children))
                }
                return lines
            }
            if let children = object["itemListElement"] {
                return instructionLines(from: children)
            }
        }
        return []
    }

    private static func applyMetadata(_ html: String, to document: inout RecipeImportDocument) {
        if let title = metaContent(html, key: "og:title") ?? metaContent(html, key: "twitter:title") ?? titleTag(html) {
            document.title = decodeEntities(title)
            document.sourceTitle = document.title
        }
        if let description = metaContent(html, key: "og:description") ?? metaContent(html, key: "description") {
            document.summary = decodeEntities(description)
        }
    }

    private static func applyVisibleText(_ html: String, to document: inout RecipeImportDocument) {
        let visible = visibleText(html)
        guard !visible.isEmpty else { return }
        let folded = UnitNormalization.fold(visible)
        let headings = ["malzemeler", "ingredients", "yapilisi", "instructions", "directions"]
        guard headings.contains(where: { folded.contains($0) }) else { return }
        let parsed = RecipeTextParser.document(from: visible, origin: .imported)
        if document.title.isEmpty { document.title = parsed.title }
        if document.ingredients.allSatisfy({ $0.name.isEmpty }) && parsed.ingredients.contains(where: { !$0.name.isEmpty }) {
            document.ingredients = parsed.ingredients
        }
        if document.instructions.isEmpty && parsed.instructions.contains(where: { !$0.text.isEmpty }) {
            document.instructions = parsed.instructions.map { step in
                var copy = step
                copy.isUncertain = true
                return copy
            }
        }
        if document.prepMinutes == nil { document.prepMinutes = parsed.prepMinutes }
        if document.cookMinutes == nil { document.cookMinutes = parsed.cookMinutes }
        if document.totalMinutes == nil { document.totalMinutes = parsed.totalMinutes }
        if document.servings == nil { document.servings = parsed.servings }
    }

    private static func visibleText(_ html: String) -> String {
        var text = html
        let strips = ["(?is)<script[^>]*>.*?</script>", "(?is)<style[^>]*>.*?</style>", "(?is)<noscript[^>]*>.*?</noscript>"]
        for pattern in strips {
            if let expression = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(text.startIndex..<text.endIndex, in: text)
                text = expression.stringByReplacingMatches(in: text, range: range, withTemplate: "\n")
            }
        }
        text = text.replacingOccurrences(of: #"(?i)<br\s*/?>"#, with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: #"(?i)</p>"#, with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: #"(?i)</(h1|h2|h3|li|div|tr)>"#, with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        text = decodeEntities(text)
        let lines = text.split(whereSeparator: \.isNewline).map { line -> String in
            line.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        }.filter { !$0.isEmpty }
        return lines.joined(separator: "\n")
    }

    private static func metaContent(_ html: String, key: String) -> String? {
        let patterns = [
            #"<meta[^>]*(?:property|name)\s*=\s*["']\#(key)["'][^>]*content\s*=\s*["']([^"']*)["']"#,
            #"<meta[^>]*content\s*=\s*["']([^"']*)["'][^>]*(?:property|name)\s*=\s*["']\#(key)["']"#,
        ]
        for pattern in patterns {
            guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(html.startIndex..<html.endIndex, in: html)
            guard let match = expression.firstMatch(in: html, range: range),
                  let swiftRange = Range(match.range(at: 1), in: html) else { continue }
            let value = String(html[swiftRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { return value }
        }
        return nil
    }

    private static func titleTag(_ html: String) -> String? {
        let pattern = #"<title[^>]*>(.*?)</title>"#
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return nil
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = expression.firstMatch(in: html, range: range),
              let swiftRange = Range(match.range(at: 1), in: html) else { return nil }
        let value = String(html[swiftRange]).replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func stringValue(_ value: Any?) -> String? {
        if let text = value as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        return nil
    }

    private static func firstString(_ value: Any?) -> String? {
        if let text = stringValue(value) { return text }
        if let list = value as? [Any] {
            return list.compactMap { stringValue($0) }.first
        }
        return nil
    }

    private static func stringList(_ value: Any?) -> [String] {
        if let text = value as? String {
            return text.split(whereSeparator: \.isNewline).map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
        if let list = value as? [Any] {
            return list.flatMap { stringList($0) }
        }
        return []
    }

    private static func yieldText(_ value: Any) -> String {
        if let text = value as? String { return text }
        if let number = value as? Int { return String(number) }
        if let number = value as? Double { return String(Int(number)) }
        if let list = value as? [Any] {
            return list.map { yieldText($0) }.joined(separator: " ")
        }
        return ""
    }

    static func decodeEntities(_ raw: String) -> String {
        var text = raw
        let named = [
            "&amp;": "&", "&quot;": "\"", "&#39;": "'", "&apos;": "'",
            "&lt;": "<", "&gt;": ">", "&nbsp;": " ",
        ]
        for (entity, value) in named {
            text = text.replacingOccurrences(of: entity, with: value)
        }
        let pattern = #"&#(x?[0-9a-fA-F]+);"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = expression.matches(in: text, range: range).reversed()
        for match in matches {
            guard let tokenRange = Range(match.range(at: 1), in: text),
                  let full = Range(match.range, in: text) else { continue }
            let token = String(text[tokenRange])
            let scalar: UInt32?
            if token.lowercased().hasPrefix("x") {
                scalar = UInt32(token.dropFirst(), radix: 16)
            } else {
                scalar = UInt32(token)
            }
            guard let scalar, let unicode = UnicodeScalar(scalar) else { continue }
            text.replaceSubrange(full, with: String(Character(unicode)))
        }
        return text
    }
}
