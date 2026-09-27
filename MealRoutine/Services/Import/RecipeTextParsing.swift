import Foundation

/// How a paste or share was classified. One session carries one input.
enum ImportInputKind: Equatable, Sendable {
    case empty
    case url(URL)
    case unsupportedURL(String)
    case text(String)
}

enum ImportFailure: Equatable, Sendable, Error {
    case invalidURL
    case unsupportedSource
    case missingRecipeData
    case network
    case timeout
    case parsing
    case cancelled

    var message: String {
        switch self {
        case .invalidURL:
            "Bu bağlantı geçerli değil. Herkese açık bir tarif linki yapıştır veya tarifi elle gir."
        case .unsupportedSource:
            "Bu kaynak otomatik okunamıyor. Tarif metnini yapıştır veya elle gir."
        case .missingRecipeData:
            "Sayfa açıldı ama yeterli tarif bilgisi yok."
        case .network:
            "Tarif yüklenemedi. Bağlantını kontrol edip yeniden dene."
        case .timeout:
            "Kaynak çok geç yanıt verdi. Yeniden dene veya tarifi elle gir."
        case .parsing:
            "Sayfa yüklendi ama tarif güvenilir biçimde ayrılamadı."
        case .cancelled:
            "İçe aktarma iptal edildi."
        }
    }

    static func map(_ error: Error) -> ImportFailure {
        if error is CancellationError { return .cancelled }
        if let failure = error as? ImportFailure { return failure }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut:
                return .timeout
            case .cancelled:
                return .cancelled
            default:
                return .network
            }
        }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorTimedOut {
            return .timeout
        }
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled {
            return .cancelled
        }
        return .network
    }
}

/// Public URL cleanup. Tracking parameters do not make a second recipe.
enum URLNormalizer {
    private static let trackingNames: Set<String> = [
        "fbclid", "gclid", "igshid", "igsh", "si", "feature",
        "mc_cid", "mc_eid", "ref", "ref_src", "share_id", "tt_from",
        "_branch_match_id", "spm", "mibextid",
    ]

    static func classify(_ raw: String) -> ImportInputKind {
        let text = normalizeBlock(raw)
        guard !text.isEmpty else { return .empty }
        if text.contains("\n") { return .text(text) }
        if text.contains(" "), !looksLikeBareURL(text) { return .text(text) }
        if let url = publicURL(text) { return .url(url) }
        if text.contains("://") { return .unsupportedURL(text) }
        return .text(text)
    }

    static func publicURL(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: candidate), let scheme = url.scheme?.lowercased() else { return nil }
        guard scheme == "http" || scheme == "https" else { return nil }
        guard let host = url.host, host.contains(".") else { return nil }
        return url
    }

    /// Canonical string used for duplicate checks. Nil when the text is not an http(s) URL.
    static func normalizedString(_ raw: String) -> String? {
        guard let url = publicURL(raw) else { return nil }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let scheme = (components.scheme ?? "https").lowercased()
        components.scheme = (scheme == "http" || scheme == "https") ? "https" : scheme
        var host = components.host?.lowercased() ?? ""
        if host.hasPrefix("www.") {
            host.removeFirst(4)
        }
        components.host = host
        components.fragment = nil
        if let items = components.queryItems {
            let kept = items.filter { item in
                let name = item.name.lowercased()
                if name.hasPrefix("utm_") { return false }
                return !trackingNames.contains(name)
            }
            .sorted { lhs, rhs in
                if lhs.name != rhs.name { return lhs.name < rhs.name }
                return (lhs.value ?? "") < (rhs.value ?? "")
            }
            components.queryItems = kept.isEmpty ? nil : kept
        }
        var path = components.percentEncodedPath
        if path.count > 1, path.hasSuffix("/") {
            path.removeLast()
        }
        components.percentEncodedPath = path
        guard var text = components.string else { return nil }
        if text.hasSuffix("?") { text.removeLast() }
        return text
    }

    static func platform(for url: URL) -> RecipeSourcePlatform {
        let host = (url.host ?? "").lowercased()
        if host.contains("instagram.com") { return .instagram }
        if host.contains("tiktok.com") { return .tiktok }
        if host.contains("youtube.com") || host == "youtu.be" || host.hasSuffix(".youtube.com") {
            return .youtube
        }
        return .website
    }

    static func platform(sourceHint: String?, url: URL?) -> RecipeSourcePlatform {
        let hint = (sourceHint ?? "").lowercased()
        if hint.contains("instagram") { return .instagram }
        if hint.contains("tiktok") { return .tiktok }
        if hint.contains("youtube") { return .youtube }
        if hint.contains("safari") { return .safari }
        if hint.contains("notes") || hint.contains("notlar") { return .notes }
        if hint.contains("message") || hint.contains("whatsapp") || hint.contains("telegram") {
            return .messages
        }
        if let url { return platform(for: url) }
        return .unknown
    }

    /// Stable public id when the host exposes one. Empty when it does not.
    static func sourceKey(for url: URL) -> String {
        let host = (url.host ?? "").lowercased()
        let parts = url.path.split(separator: "/").map(String.init)
        if host.contains("instagram.com") {
            for marker in ["p", "reel", "tv"] {
                if let index = parts.firstIndex(of: marker), parts.count > index + 1 {
                    return "instagram:\(parts[index + 1])"
                }
            }
        }
        if host.contains("tiktok.com"), let index = parts.firstIndex(of: "video"), parts.count > index + 1 {
            return "tiktok:\(parts[index + 1])"
        }
        if host == "youtu.be", let id = parts.first, !id.isEmpty {
            return "youtube:\(id)"
        }
        if host.contains("youtube.com"),
           let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
           let id = items.first(where: { $0.name == "v" })?.value,
           !id.isEmpty {
            return "youtube:\(id)"
        }
        return ""
    }

    private static func looksLikeBareURL(_ text: String) -> Bool {
        guard !text.contains(" ") else { return false }
        return text.contains("://") || text.contains(".")
    }
}

enum TimeParser {
    /// ISO-8601 duration (`PT1H30M`). Unparsed text stays unknown. Seconds alone are not rounded into minutes.
    static func minutes(fromISO8601 raw: String) -> Int? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard text.hasPrefix("P") else { return nil }
        let pattern = #"^P(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+(?:\.\d+)?)S)?)?$"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = expression.firstMatch(in: text, range: range) else { return nil }
        func capture(_ index: Int) -> Double? {
            let part = match.range(at: index)
            guard part.location != NSNotFound, let swiftRange = Range(part, in: text) else { return nil }
            return Double(text[swiftRange])
        }
        let days = capture(1)
        let hours = capture(2)
        let minutes = capture(3)
        guard days != nil || hours != nil || minutes != nil else { return nil }
        let total = (days ?? 0) * 24 * 60 + (hours ?? 0) * 60 + (minutes ?? 0)
        guard total >= 0, total < 10_000 else { return nil }
        return Int(total)
    }

    /// "15 dk", "1 saat 20 dakika", "45 min". No number means unknown, not zero.
    static func minutes(fromText raw: String) -> Int? {
        let folded = fold(raw)
        guard !folded.isEmpty else { return nil }
        if let iso = minutes(fromISO8601: raw) { return iso }
        var total = 0
        var found = false
        if let hours = firstNumber(before: ["saat", "hour", "hours", "hr", "hrs"], in: folded) {
            total += hours * 60
            found = true
        }
        if let minutes = firstNumber(before: ["dakika", "dak", "dk", "minute", "minutes", "min", "mins"], in: folded) {
            total += minutes
            found = true
        }
        guard found else { return nil }
        return total
    }

    private static func firstNumber(before labels: [String], in text: String) -> Int? {
        for label in labels {
            let pattern = #"(\d+(?:[.,]\d+)?)\s*"# + NSRegularExpression.escapedPattern(for: label)
            guard let expression = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            guard let match = expression.firstMatch(in: text, range: range),
                  let swiftRange = Range(match.range(at: 1), in: text) else { continue }
            let token = text[swiftRange].replacingOccurrences(of: ",", with: ".")
            guard let value = Double(token) else { continue }
            return Int(value.rounded(.down))
        }
        return nil
    }

    private static func fold(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "İ", with: "i")
            .lowercased()
    }
}

struct ParsedServings: Equatable, Sendable {
    var count: Int?
    var isUncertain: Bool
}

enum ServingParser {
    static func parse(_ raw: String) -> ParsedServings {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return ParsedServings(count: nil, isUncertain: false) }
        let rangePattern = #"(\d+)\s*[-–—]\s*(\d+)"#
        if let expression = try? NSRegularExpression(pattern: rangePattern),
           let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)),
           let firstRange = Range(match.range(at: 1), in: text),
           let count = Int(text[firstRange]),
           (1...99).contains(count) {
            return ParsedServings(count: count, isUncertain: true)
        }
        let numberPattern = #"(\d+)"#
        guard let expression = try? NSRegularExpression(pattern: numberPattern),
              let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)),
              let swiftRange = Range(match.range(at: 1), in: text),
              let count = Int(text[swiftRange]),
              (1...99).contains(count) else {
            return ParsedServings(count: nil, isUncertain: false)
        }
        return ParsedServings(count: count, isUncertain: false)
    }
}

enum IngredientParser {
    private static let knownCodes: Set<String> = [
        "g", "kg", "ml", "l", "piece", "tbsp", "tsp", "clove", "pinch", "slice", "sprig", "toTaste",
    ]

    /// Recognized spellings that must not be converted into grams or millilitres.
    private static let extraUnits: [String: String] = [
        "subardagi": "cup",
        "caybardagi": "tea-cup",
        "caykasigi": "tsp",
        "bardak": "cup",
        "paket": "packet",
        "kase": "bowl",
        "avuc": "handful",
        "kup": "cube",
        "konserve": "can",
        "cup": "cup",
        "cups": "cup",
    ]

    static func parse(line raw: String, sortOrder: Int) -> ImportedIngredient {
        let original = normalizeLine(raw)
        guard !original.isEmpty else {
            return ImportedIngredient(
                name: "",
                isUncertain: true,
                originalText: "",
                sortOrder: sortOrder,
                includeInGrocery: false
            )
        }
        var working = original
        let optional = peelOptional(&working)
        var uncertain = false
        if peelApproximate(&working) {
            uncertain = true
        }
        let quantity = peelQuantity(&working, uncertain: &uncertain)
        let unit = peelUnit(&working)
        var name = working.trimmingCharacters(in: .whitespacesAndNewlines)
        var note: String?
        if let comma = name.firstIndex(of: ",") {
            let left = String(name[..<comma]).trimmingCharacters(in: .whitespacesAndNewlines)
            let right = String(name[name.index(after: comma)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !left.isEmpty {
                name = left
                if !right.isEmpty { note = right }
            }
        }
        if quantity == nil {
            uncertain = true
        }
        let structured = !name.isEmpty
        return ImportedIngredient(
            name: name,
            quantity: quantity,
            unit: unit,
            preparationNote: note,
            isOptional: optional,
            isUncertain: uncertain,
            originalText: original,
            sortOrder: sortOrder,
            includeInGrocery: structured
        )
    }

    static func parseLines(_ text: String) -> [ImportedIngredient] {
        text.split(whereSeparator: \.isNewline)
            .map { normalizeLine(String($0)) }
            .filter { !$0.isEmpty }
            .enumerated()
            .map { parse(line: $0.element, sortOrder: $0.offset) }
            .filter { !$0.name.isEmpty || !$0.originalText.isEmpty }
    }

    private static func peelOptional(_ text: inout String) -> Bool {
        let folded = UnitNormalization.fold(text)
        let markers = ["istegebagli", "opsiyonel", "optional"]
        guard markers.contains(where: { folded.contains($0) }) else { return false }
        let patterns = [
            #"\(?\s*isteğe bağlı\s*\)?"#,
            #"\(?\s*istege bagli\s*\)?"#,
            #"\(?\s*opsiyonel\s*\)?"#,
            #"\(?\s*optional\s*\)?"#,
        ]
        for pattern in patterns {
            if let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(text.startIndex..<text.endIndex, in: text)
                text = expression.stringByReplacingMatches(in: text, range: range, withTemplate: " ")
            }
        }
        text = normalizeLine(text)
        return true
    }

    private static func peelApproximate(_ text: inout String) -> Bool {
        let patterns = [#"^yaklaşık\s+"#, #"^yaklasik\s+"#, #"^about\s+"#, #"^approx\.?\s+"#, #"^~\s*"#]
        var found = false
        for pattern in patterns {
            guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            if expression.firstMatch(in: text, range: range) != nil {
                text = expression.stringByReplacingMatches(in: text, range: range, withTemplate: "")
                found = true
            }
        }
        text = normalizeLine(text)
        return found
    }

    private static func peelQuantity(_ text: inout String, uncertain: inout Bool) -> Double? {
        let fractions: [Character: Double] = ["½": 0.5, "¼": 0.25, "¾": 0.75, "⅓": 1.0 / 3.0, "⅔": 2.0 / 3.0, "⅛": 0.125]
        if let first = text.first, let value = fractions[first] {
            text = String(text.dropFirst())
            text = normalizeLine(text)
            return value
        }
        let rangePattern = #"^(\d+(?:[.,]\d+)?)\s*[-–—]\s*(\d+(?:[.,]\d+)?)"#
        if let expression = try? NSRegularExpression(pattern: rangePattern),
           let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)),
           let firstRange = Range(match.range(at: 1), in: text),
           let full = Range(match.range, in: text),
           let value = doubleToken(String(text[firstRange])) {
            uncertain = true
            text = String(text[full.upperBound...])
            text = normalizeLine(text)
            return value
        }
        let mixed = #"^(\d+)\s+(\d+)\s*/\s*(\d+)"#
        if let expression = try? NSRegularExpression(pattern: mixed),
           let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)),
           let wholeRange = Range(match.range(at: 1), in: text),
           let numRange = Range(match.range(at: 2), in: text),
           let denRange = Range(match.range(at: 3), in: text),
           let whole = Double(text[wholeRange]),
           let numerator = Double(text[numRange]),
           let denominator = Double(text[denRange]),
           denominator != 0,
           let full = Range(match.range, in: text) {
            text = String(text[full.upperBound...])
            text = normalizeLine(text)
            return whole + numerator / denominator
        }
        let fraction = #"^(\d+)\s*/\s*(\d+)"#
        if let expression = try? NSRegularExpression(pattern: fraction),
           let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)),
           let numRange = Range(match.range(at: 1), in: text),
           let denRange = Range(match.range(at: 2), in: text),
           let numerator = Double(text[numRange]),
           let denominator = Double(text[denRange]),
           denominator != 0,
           let full = Range(match.range, in: text) {
            text = String(text[full.upperBound...])
            text = normalizeLine(text)
            return numerator / denominator
        }
        let number = #"^(\d+(?:[.,]\d+)?)"#
        if let expression = try? NSRegularExpression(pattern: number),
           let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)),
           let tokenRange = Range(match.range(at: 1), in: text),
           let value = doubleToken(String(text[tokenRange])),
           let full = Range(match.range, in: text) {
            text = String(text[full.upperBound...])
            text = normalizeLine(text)
            return value
        }
        return nil
    }

    private static func peelUnit(_ text: inout String) -> String? {
        let words = text.split(separator: " ").map(String.init)
        guard !words.isEmpty else { return nil }
        let maxLength = min(3, words.count)
        for length in stride(from: maxLength, through: 1, by: -1) {
            let phrase = words.prefix(length).joined(separator: " ")
            guard let code = canonicalUnit(phrase) else { continue }
            text = words.dropFirst(length).joined(separator: " ")
            return code
        }
        return nil
    }

    private static func canonicalUnit(_ phrase: String) -> String? {
        let parsed = UnitNormalization.parse(phrase)
        if knownCodes.contains(parsed.code) { return parsed.code }
        let folded = UnitNormalization.fold(phrase)
        return extraUnits[folded]
    }

    private static func doubleToken(_ token: String) -> Double? {
        Double(token.replacingOccurrences(of: ",", with: "."))
    }

    private static func normalizeLine(_ raw: String) -> String {
        raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

enum InstructionParser {
    static func parse(lines rawLines: [String], uncertain: Bool) -> [ImportedInstruction] {
        rawLines
            .map { normalizeBlock($0) }
            .filter { !$0.isEmpty }
            .enumerated()
            .map { index, line in
                let stripped = stripNumbering(line)
                return ImportedInstruction(
                    text: stripped,
                    sortOrder: index,
                    isUncertain: uncertain,
                    originalText: line
                )
            }
    }

    static func stripNumbering(_ line: String) -> String {
        let patterns = [
            #"^\s*\d+\s*[\.\)]\s+"#,
            #"^\s*adım\s+\d+\s*[:.\-]?\s+"#,
            #"^\s*step\s+\d+\s*[:.\-]?\s+"#,
        ]
        var text = line
        for pattern in patterns {
            guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            if expression.firstMatch(in: text, range: range) != nil {
                text = expression.stringByReplacingMatches(in: text, range: range, withTemplate: "")
                break
            }
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Pasted recipe text. Headings win. Without headings, quantity lines are ingredients and the split is marked uncertain.
enum RecipeTextParser {
    static func document(from raw: String, origin: RecipeOrigin = .imported) -> RecipeImportDocument {
        let block = normalizeBlock(raw)
        var document = RecipeImportDocument.emptyManual()
        document.origin = origin
        document.ingredients = []
        document.instructions = []
        guard !block.isEmpty else { return document }

        let lines = block.split(separator: "\n", omittingEmptySubsequences: false).map { String($0).trimmingCharacters(in: .whitespaces) }
        let headingIndexes = lines.enumerated().compactMap { index, line -> (Int, Heading)? in
            guard let heading = headingKind(line) else { return nil }
            return (index, heading)
        }
        applyMetadata(lines, to: &document)

        if let ingredientIndex = headingIndexes.first(where: { $0.1 == .ingredients })?.0 {
            let instructionIndex = headingIndexes.first(where: { $0.1 == .instructions && $0.0 > ingredientIndex })?.0
            let ingredientLines = Array(lines[(ingredientIndex + 1)..<(instructionIndex ?? lines.count)])
            document.ingredients = IngredientParser.parseLines(ingredientLines.joined(separator: "\n"))
            if let instructionIndex {
                let stepLines = Array(lines[(instructionIndex + 1)...])
                document.instructions = InstructionParser.parse(lines: stepLines, uncertain: false)
            }
            if document.title.isEmpty {
                document.title = titleCandidate(in: lines, before: ingredientIndex) ?? ""
            }
        } else {
            let body = lines.filter { headingKind($0) == nil && !isMetadataLine($0) }
            let title = body.first { !$0.isEmpty && $0.count <= 80 }
            document.title = title ?? ""
            let rest = body.filter { $0 != title }
            let ingredientLines = rest.filter { lineHasQuantity($0) }
            let stepLines = rest.filter { !lineHasQuantity($0) }
            document.ingredients = IngredientParser.parseLines(ingredientLines.joined(separator: "\n"))
            document.instructions = InstructionParser.parse(lines: stepLines, uncertain: true)
        }
        document.ingredients = reindexedIngredients(document.ingredients)
        document.instructions = reindexedSteps(document.instructions)
        if document.ingredients.isEmpty {
            document.ingredients = [ImportedIngredient(name: "", isUncertain: true, sortOrder: 0, includeInGrocery: false)]
        }
        return document
    }

    private enum Heading {
        case ingredients
        case instructions
    }

    private static func headingKind(_ line: String) -> Heading? {
        let folded = UnitNormalization.fold(line.trimmingCharacters(in: CharacterSet(charactersIn: ":.- ")))
        let ingredients: Set<String> = ["malzemeler", "malzeme", "ingredients", "ingredient"]
        let steps: Set<String> = [
            "yapilisi", "hazirlanisi", "hazirlanis", "talimatlar", "instructions",
            "directions", "method", "steps", "adimlar", "yapilis",
        ]
        if ingredients.contains(folded) { return .ingredients }
        if steps.contains(folded) { return .instructions }
        return nil
    }

    private static func applyMetadata(_ lines: [String], to document: inout RecipeImportDocument) {
        for line in lines {
            let folded = line.lowercased()
            if folded.contains("hazırlık") || folded.contains("hazirlik") || folded.contains("prep") {
                if document.prepMinutes == nil { document.prepMinutes = TimeParser.minutes(fromText: line) }
            } else if folded.contains("piş") || folded.contains("pis") || folded.contains("cook") {
                if document.cookMinutes == nil { document.cookMinutes = TimeParser.minutes(fromText: line) }
            } else if folded.contains("toplam") || folded.contains("total") || folded.contains("süre") || folded.contains("sure") {
                if document.totalMinutes == nil { document.totalMinutes = TimeParser.minutes(fromText: line) }
            }
            if document.servings == nil {
                let servings = ServingParser.parse(line)
                if folded.contains("kişilik") || folded.contains("kisilik") || folded.contains("porsiyon")
                    || folded.contains("serves") || folded.contains("servings") || folded.contains("yield") {
                    document.servings = servings.count
                }
            }
        }
    }

    private static func isMetadataLine(_ line: String) -> Bool {
        let folded = line.lowercased()
        if folded.contains("hazırlık") || folded.contains("prep") { return true }
        if folded.contains("pişirme") || folded.contains("cook time") { return true }
        if folded.contains("kişilik") || folded.contains("serves") { return true }
        return false
    }

    private static func titleCandidate(in lines: [String], before index: Int) -> String? {
        lines[..<index].first { line in
            !line.isEmpty && headingKind(line) == nil && !isMetadataLine(line) && line.count <= 80
        }
    }

    private static func lineHasQuantity(_ line: String) -> Bool {
        let parsed = IngredientParser.parse(line: line, sortOrder: 0)
        return parsed.quantity != nil
    }

    private static func reindexedIngredients(_ items: [ImportedIngredient]) -> [ImportedIngredient] {
        items.enumerated().map { index, item in
            var copy = item
            copy.sortOrder = index
            return copy
        }
    }

    private static func reindexedSteps(_ items: [ImportedInstruction]) -> [ImportedInstruction] {
        items.enumerated().map { index, item in
            var copy = item
            copy.sortOrder = index
            return copy
        }
    }
}

func normalizeBlock(_ raw: String) -> String {
    raw.replacingOccurrences(of: "\r\n", with: "\n")
        .replacingOccurrences(of: "\r", with: "\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)
}
