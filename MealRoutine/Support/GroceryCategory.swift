import Foundation

/// Shopping aisle for one grocery row. Catalog ids are classified here so the
/// bundled recipe file stays unchanged.
enum GroceryCategory: String, CaseIterable, Identifiable, Sendable {
    case produce
    case protein
    case dairyAndEggs
    case pantry
    case spicesAndSauces
    case other

    var id: String { rawValue }

    /// Turkish section title. Order matches a typical market walk.
    var title: String {
        switch self {
        case .produce: "Sebze ve meyve"
        case .protein: "Protein"
        case .dairyAndEggs: "Süt ve yumurta"
        case .pantry: "Kiler"
        case .spicesAndSauces: "Baharat ve soslar"
        case .other: "Diğer"
        }
    }

    /// Lightweight aisle mark. Not a custom illustration.
    var symbolName: String {
        switch self {
        case .produce: "carrot"
        case .protein: "fish"
        case .dairyAndEggs: "cup.and.saucer"
        case .pantry: "cabinet"
        case .spicesAndSauces: "flame"
        case .other: "basket"
        }
    }

    static let sectionOrder: [GroceryCategory] = [
        .produce, .protein, .dairyAndEggs, .pantry, .spicesAndSauces, .other
    ]

    /// Known catalog ids win. The id is the dictionary canonical id, never a
    /// `pantry-auto:` key and never the display name. Typed `manual:` rows and
    /// unknown ids use the display name only as an aisle hint.
    static func classify(ingredientId: String, name: String) -> GroceryCategory {
        let bare = GroceryMerger.shoppingIngredientId(ingredientId)
        if bare.lowercased().hasPrefix("manual:") {
            return inferred(from: name)
        }
        if let known = byID[normalize(bare)] {
            return known
        }
        return inferred(from: name)
    }

    /// Nil when the id is not in the catalog map. Checks use this to catch new ids.
    static func knownCategory(ingredientId: String) -> GroceryCategory? {
        byID[normalize(ingredientId)]
    }

    private static func normalize(_ raw: String) -> String {
        raw.lowercased()
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: " ", with: "")
    }

    private static let byID: [String: GroceryCategory] = {
        var map: [String: GroceryCategory] = [:]
        func fill(_ ids: Set<String>, _ category: GroceryCategory) {
            for id in ids {
                map[id] = category
            }
        }
        fill(produceIDs, .produce)
        fill(proteinIDs, .protein)
        fill(dairyAndEggsIDs, .dairyAndEggs)
        fill(pantryIDs, .pantry)
        fill(spicesAndSaucesIDs, .spicesAndSauces)
        fill(otherIDs, .other)
        return map
    }()

    private static let produceIDs: Set<String> = [
        "aji", "aubergine", "basil", "beansprouts", "beetroot", "cabbage",
        "carrot", "cassava", "celery", "chayote", "chili", "chilli",
        "chillies", "chives", "cilantro", "corn", "courgette", "cucumber",
        "cucumbers", "curryleaves", "daikon", "dill", "fennel", "freshmint",
        "garlic", "ginger", "gomen", "greenbanana", "greenbeans", "greenchili",
        "greenchilli", "greenpepper", "holybasil", "kale", "leek", "lemon",
        "lettuce", "lime", "mint", "molokhia", "mushrooms", "onion",
        "onions", "pandan", "papaya", "parsley", "peas", "peppers",
        "pineapple", "piripiri", "plantain", "pomegranate", "potato", "potatoes",
        "pumpkin", "radish", "redcabbage", "rocket", "rosemary", "scallion",
        "scotchbonnet", "shallot", "shallots", "spinach", "spring", "springonion",
        "sweetpotato", "tarragon", "tomato", "tomatoes", "vegetables", "watermelon",
        "artichoke", "broadbeans", "cauliflower", "chard", "grapeleaves", "okra",
    ]

    private static let proteinIDs: Set<String> = [
        "bacon", "barramundi", "beef", "chicken", "chinesesausage", "chourico",
        "clams", "cockles", "cod", "codfish", "crab", "cuttlefish",
        "fish", "guanciale", "ham", "hilsa", "lamb", "leanbeef",
        "merguez", "mussels", "pork", "porkbelly", "prawns", "prosciutto",
        "rabbit", "ribs", "salmon", "salmonbones", "sardines", "sausage",
        "tofu", "trout", "tuna", "veal",
        "anchovy", "liver", "mackerel", "pastirma", "seabass", "sucuk", "tripe",
    ]

    private static let dairyAndEggsIDs: Set<String> = [
        "ayib", "brinedcheese", "brynza", "butter", "butterfat", "cheese",
        "cream", "curd", "curdcheese", "egg", "eggs", "eggwhite",
        "feta", "ghee", "gruyere", "halloumi", "kajmak", "kefir",
        "matsun", "milk", "mozzarella", "paneer", "parmesan", "pecorino",
        "qurut", "sourcream", "vacherin", "yoghurt", "yogurt", "yolks",
    ]

    private static let pantryIDs: Set<String> = [
        "almonds", "apricots", "attieke", "baguette", "bakingpowder", "beans",
        "bread", "breadcrumbs", "bucatini", "bulgur", "bun", "butterbeans",
        "cashew", "chickpeaflour", "chickpeas", "coconutmilk", "cornflour", "cornmeal",
        "crackers", "dashi", "dzavar", "fat", "fatir", "filo",
        "flatbread", "flour", "freekeh", "fries", "fryoil", "gundruk",
        "honey", "injera", "katsuobushi", "kombu", "lard", "lentils",
        "lingonberry", "macaroni", "mantou", "moongdal", "mustardoil", "naan",
        "noodles", "oil", "oliveoil", "olives", "palmsugar", "pancakeflour",
        "peanuts", "pide", "pinenuts", "pita", "prunes", "raisins",
        "rice", "ricenoodles", "roti", "ryebread", "sesameoil", "sesameseeds",
        "soda", "somun", "soybeans", "spaghetti", "starch", "stock",
        "borlotti", "semolina", "tarhana", "vermicelli",
        "stockcube", "sugar", "sunfloweroil", "tahini", "tortillas", "wakame",
        "walnuts", "yeast"
    ]

    private static let spicesAndSaucesIDs: Set<String> = [
        "achiote", "ajiamarillo", "ajwain", "allspice", "amba", "ancho",
        "asafoetida", "baharat", "bay", "bayleaf", "berbere", "biber",
        "blackpepper", "caraway", "cardamom", "chilipaste", "chilipowder", "chillipowder",
        "chutney", "cinnamon", "clove", "coarsesalt", "coriander", "cumin",
        "curry", "currypowder", "currysauce", "darksoy", "doubanjiang", "douchi",
        "doughsalt", "driedchili", "driedchilli", "driedmint", "dryginger", "fenugreek",
        "fishsauce", "garammasala", "gingergarlic", "gochujang", "goraka", "gravy",
        "guajillo", "harissa", "kashmirichili", "kecap", "kecapmanis", "khmelisuneli",
        "lemonmyrtle", "lightsoy", "lizano", "mayonnaise", "methi", "mirin",
        "miso", "mitmita", "mustard", "mustardseeds", "nigella", "nutmeg",
        "oregano", "oystersauce", "paprika", "pepper", "peppercorns", "pepperflakes",
        "pepperpaste", "saffron", "salt", "sambal", "savory", "sevenspice",
        "sichuanpepper", "soy", "soysauce", "sumac", "tamarind", "terasi",
        "thyme", "timur", "tomatoketchup", "tomatopassata", "tomatopaste", "tomatosauce",
        "turmeric", "vinegar", "worcestershire", "zhug"
    ]

    private static let otherIDs: Set<String> = [
        "bananaleaf", "beer", "coldwater", "icewater", "ink", "kirsch",
        "sake", "sparklingwater", "water", "whitewine", "wine"
    ]

    private static func inferred(from name: String) -> GroceryCategory {
        let text = name
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "tr_TR"))
            .lowercased()
        func contains(_ needles: [String]) -> Bool {
            let tokens = text.split { !$0.isLetter }.map(String.init)
            return needles.contains { needle in
                if needle.count <= 4 {
                    return tokens.contains(needle)
                }
                return text.contains(needle)
            }
        }
        if contains(["yumurta", "sut", "peynir", "tereyag", "yogurt", "krema", "kaymak", "egg", "milk", "cheese", "butter", "cream"]) {
            return .dairyAndEggs
        }
        if contains(["tavuk", "kiyma", "balik", "somon", "karides", "sosis", "jambon", "kuzu", "dana", "chicken", "beef", "fish", "pork", "lamb", "salmon", "tofu", "tuna"]) {
            return .protein
        }
        if contains(["tuz", "karabiber", "kimyon", "tarcin", "kekik", "zerdecal", "salca", "hardal", "sirke", "baharat", "sos", "sauce", "spice", "cumin", "paprika", "vinegar", "salt"]) {
            return .spicesAndSauces
        }
        if contains(["un", "pirinc", "makarna", "ekmek", "zeytinyag", "seker", "nohut", "mercimek", "bulgur", "yag", "flour", "rice", "pasta", "bread", "oil", "sugar", "lentil"]) {
            return .pantry
        }
        if contains(["domates", "sogan", "sarimsak", "patates", "havuc", "salatalik", "limon", "marul", "ispanak", "mantar", "elma", "brokoli", "kabak", "patlican", "tomato", "onion", "garlic", "potato", "carrot", "lemon", "lettuce", "spinach"]) {
            return .produce
        }
        return .other
    }
}

/// One row handed to the aisle grouper. Checked rows leave the open sections.
struct GroceryGroupInput: Equatable, Sendable {
    var name: String
    var category: GroceryCategory
    var isChecked: Bool
}

/// One stored shopping line handed to the Market card grouper.
struct GroceryCardInput: Equatable, Sendable {
    var id: UUID
    var ingredientId: String
    var name: String
    var quantity: Double?
    var unit: String
    var hasUnitConflict: Bool
    var isChecked: Bool
    var isManual: Bool
    var sourceRaw: String
    var remainingDetail: String?
}

struct GroceryCardPart: Equatable, Sendable, Identifiable {
    var id: UUID
    /// Every stored row this part still represents. A folded shortfall has one label and one amount.
    var memberIDs: [UUID]
    var quantity: Double?
    var unit: String
    var source: GroceryLineSource
    var isChecked: Bool
    var isManual: Bool
    var hasUnitConflict: Bool
    var remainingDetail: String?
    var amountText: String

    var label: String { "\(source.title): \(amountText)" }
}

struct GroceryCardModel: Equatable, Sendable, Identifiable {
    var id: String
    var name: String
    var category: GroceryCategory
    var parts: [GroceryCardPart]

    var isFullyChecked: Bool { !parts.isEmpty && parts.allSatisfy(\.isChecked) }
    var isMixed: Bool { parts.contains(where: \.isChecked) && !isFullyChecked }
    var hasUnitConflict: Bool { parts.contains(where: \.hasUnitConflict) }
    /// Parts stay separate. This is not a sum of plan and shortfall.
    var breakdown: String { parts.map(\.label).joined(separator: " · ") }
    var coverageNote: String? {
        parts.first { $0.source == .plan }?.remainingDetail ?? parts.compactMap(\.remainingDetail).first
    }
    var singlePart: GroceryCardPart? { parts.count == 1 ? parts.first : nil }
    var canDelete: Bool { parts.allSatisfy(\.isManual) }
    var primaryPartID: UUID? {
        parts.first { $0.source == .plan }?.id ?? parts.first?.id
    }
}

/// One Market card per canonical ingredient and unit bucket.
///
/// Plan, threshold, cook gap and a typed row share the card. Their quantities
/// stay on separate parts. A typed row joins only when its name is an unambiguous
/// dictionary name (`Domates` → tomato). A similar name does not (`Cherry domates`).
enum GroceryCardGrouper {
    static func group(
        _ inputs: [GroceryCardInput],
        dictionary: IngredientDictionary = .shared
    ) -> [GroceryCardModel] {
        var buckets: [String: [GroceryCardInput]] = [:]
        var order: [String] = []
        for input in inputs {
            let key = groupKey(input, dictionary: dictionary)
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(input)
        }
        return order.compactMap { key in
            guard let rows = buckets[key], !rows.isEmpty else { return nil }
            let ingredientId = groupIngredientId(rows, dictionary: dictionary)
            let name = cardName(rows, ingredientId: ingredientId, dictionary: dictionary)
            let parts = fold(rows.map { row in
                let source = GroceryLineSource.resolve(
                    ingredientId: row.ingredientId,
                    isManual: row.isManual,
                    stored: row.sourceRaw
                )
                return GroceryCardPart(
                    id: row.id,
                    memberIDs: [row.id],
                    quantity: row.quantity,
                    unit: row.unit,
                    source: source,
                    isChecked: row.isChecked,
                    isManual: row.isManual,
                    hasUnitConflict: row.hasUnitConflict,
                    remainingDetail: row.remainingDetail,
                    amountText: QuantityFormat.quantityAndUnit(quantity: row.quantity, unit: row.unit)
                )
            })
            return GroceryCardModel(
                id: key,
                name: name,
                category: GroceryCategory.classify(ingredientId: ingredientId, name: name),
                parts: parts
            )
        }
    }

    /// One part per source label. Two shortfall rows are one set: the larger amount, not the sum.
    /// Several cook gaps stay one “Pişirme eksiği” label and list each amount.
    private static func fold(_ parts: [GroceryCardPart]) -> [GroceryCardPart] {
        let sorted = parts.sorted { lhs, rhs in
            if lhs.source.sort != rhs.source.sort { return lhs.source.sort < rhs.source.sort }
            if lhs.amountText != rhs.amountText { return lhs.amountText < rhs.amountText }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        var order: [GroceryLineSource] = []
        var groups: [GroceryLineSource: [GroceryCardPart]] = [:]
        for part in sorted {
            if groups[part.source] == nil { order.append(part.source) }
            groups[part.source, default: []].append(part)
        }
        return order.compactMap { source in
            guard let rows = groups[source], let first = rows.first else { return nil }
            if rows.count == 1 { return first }
            let members = rows.flatMap(\.memberIDs)
            switch source {
            case .shortfall, .threshold:
                guard let picked = GroceryShortfallCollapse.largestSet(
                    rows.map { (quantity: $0.quantity, unit: $0.unit, isChecked: $0.isChecked) }
                ) else { return first }
                let winner = rows.max { lhs, rhs in
                    let left = (lhs.quantity ?? 0) * UnitNormalization.parse(lhs.unit).basePerUnit
                    let right = (rhs.quantity ?? 0) * UnitNormalization.parse(rhs.unit).basePerUnit
                    if left != right { return left < right }
                    return lhs.id.uuidString > rhs.id.uuidString
                } ?? first
                return GroceryCardPart(
                    id: winner.id,
                    memberIDs: members,
                    quantity: picked.quantity,
                    unit: picked.unit,
                    source: source,
                    isChecked: picked.isChecked,
                    isManual: rows.allSatisfy(\.isManual),
                    hasUnitConflict: rows.contains(where: \.hasUnitConflict),
                    remainingDetail: winner.remainingDetail,
                    amountText: QuantityFormat.quantityAndUnit(quantity: picked.quantity, unit: picked.unit)
                )
            case .plan, .cookGap, .typed:
                return GroceryCardPart(
                    id: first.id,
                    memberIDs: members,
                    quantity: nil,
                    unit: first.unit,
                    source: source,
                    isChecked: rows.allSatisfy(\.isChecked),
                    isManual: rows.allSatisfy(\.isManual),
                    hasUnitConflict: rows.contains(where: \.hasUnitConflict),
                    remainingDetail: rows.compactMap(\.remainingDetail).first,
                    amountText: rows.map(\.amountText).joined(separator: ", ")
                )
            }
        }
    }

    private static func groupKey(_ input: GroceryCardInput, dictionary: IngredientDictionary) -> String {
        let bucket = GroceryMerger.unitBucket(input.unit)
        if input.ingredientId.hasPrefix("manual:") {
            if let entry = dictionary.exactMatch(for: input.name) {
                return "\(entry.id)|\(bucket)"
            }
            return "\(input.ingredientId)|\(bucket)"
        }
        let id = GroceryMerger.shoppingIngredientId(input.ingredientId, dictionary: dictionary)
        return "\(id)|\(bucket)"
    }

    private static func groupIngredientId(_ rows: [GroceryCardInput], dictionary: IngredientDictionary) -> String {
        if let linked = rows.compactMap({ row -> String? in
            if row.ingredientId.hasPrefix("manual:") {
                return dictionary.exactMatch(for: row.name)?.id
            }
            let id = GroceryMerger.shoppingIngredientId(row.ingredientId, dictionary: dictionary)
            return id.hasPrefix("manual:") ? nil : id
        }).first {
            return linked
        }
        return rows[0].ingredientId
    }

    private static func cardName(
        _ rows: [GroceryCardInput],
        ingredientId: String,
        dictionary: IngredientDictionary
    ) -> String {
        if let entry = dictionary.entry(ingredientId), !entry.name.isEmpty { return entry.name }
        return rows.first { !$0.name.isEmpty }?.name ?? ingredientId
    }
}

enum GroceryListGrouping {
    /// Open rows follow the market walk. Checked rows are not returned here.
    static func openCategories(in rows: [GroceryGroupInput]) -> [GroceryCategory] {
        let open = rows.filter { !$0.isChecked }
        return GroceryCategory.sectionOrder.filter { category in
            open.contains { $0.category == category }
        }
    }
}
