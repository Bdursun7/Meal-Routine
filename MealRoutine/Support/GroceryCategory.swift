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

    /// Section title in the display language. Order matches a typical market walk.
    var title: String {
        switch self {
        case .produce: L10n.text("grocery.category.produce", "Sebze ve meyve")
        case .protein: L10n.text("grocery.category.protein", "Protein")
        case .dairyAndEggs: L10n.text("grocery.category.dairyAndEggs", "Süt ve yumurta")
        case .pantry: L10n.text("grocery.category.pantry", "Kiler")
        case .spicesAndSauces: L10n.text("grocery.category.spicesAndSauces", "Baharat ve soslar")
        case .other: L10n.text("grocery.category.other", "Diğer")
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

    /// Known catalog ids win. Manual rows and unknown ids use the display name.
    static func classify(ingredientId: String, name: String) -> GroceryCategory {
        if ingredientId.lowercased().hasPrefix("manual:") {
            return inferred(from: name)
        }
        if let known = byID[normalize(ingredientId)] {
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

    /// Typed rows: the exact dictionary entry for the name in the content locale wins, then the
    /// locale-keyed hint words in `GroceryCategoryHints`. Never decides identity, only the aisle.
    private static func inferred(from name: String, dictionary: IngredientDictionary = .shared) -> GroceryCategory {
        if let entry = dictionary.exactMatch(for: name), let known = byID[normalize(entry.id)] {
            return known
        }
        let text = GroceryCategoryHints.fold(name)
        let tokens = Set(text.split(separator: " ").map(String.init))
        let hints = GroceryCategoryHints.hints(for: dictionary.locale)
        for category in GroceryCategoryHints.inferenceOrder {
            let needles = hints[category] ?? []
            let hit = needles.contains { needle in
                needle.count <= 4 ? tokens.contains(needle) : text.contains(needle)
            }
            if hit { return category }
        }
        return .other
    }
}

/// Aisle hint words for typed grocery rows, keyed by content locale (folded to ASCII, lowercase).
/// English words apply in every locale because recipe sites often mix them in. Data only: a new
/// country adds a locale here, no code changes.
enum GroceryCategoryHints {
    static let inferenceOrder: [GroceryCategory] = [.dairyAndEggs, .protein, .spicesAndSauces, .pantry, .produce]
    static let sharedLocale = "en"

    static let byLocale: [String: [GroceryCategory: [String]]] = [
        "tr-TR": [
            .dairyAndEggs: ["yumurta", "sut", "peynir", "tereyag", "yogurt", "krema", "kaymak"],
            .protein: ["tavuk", "kiyma", "balik", "somon", "karides", "sosis", "jambon", "kuzu", "dana"],
            .spicesAndSauces: ["tuz", "karabiber", "kimyon", "tarcin", "kekik", "zerdecal", "salca", "hardal", "sirke", "baharat", "sos"],
            .pantry: ["un", "pirinc", "makarna", "ekmek", "zeytinyag", "seker", "nohut", "mercimek", "bulgur", "yag"],
            .produce: ["domates", "sogan", "sarimsak", "patates", "havuc", "salatalik", "limon", "marul", "ispanak", "mantar", "elma", "brokoli", "kabak", "patlican"],
        ],
        "en": [
            .dairyAndEggs: ["egg", "milk", "cheese", "butter", "cream"],
            .protein: ["chicken", "beef", "fish", "pork", "lamb", "salmon", "tofu", "tuna"],
            .spicesAndSauces: ["sauce", "spice", "cumin", "paprika", "vinegar", "salt"],
            .pantry: ["flour", "rice", "pasta", "bread", "oil", "sugar", "lentil"],
            .produce: ["tomato", "onion", "garlic", "potato", "carrot", "lemon", "lettuce", "spinach"],
        ],
    ]

    static func hints(for locale: String) -> [GroceryCategory: [String]] {
        var merged: [GroceryCategory: [String]] = byLocale[sharedLocale] ?? [:]
        let language = locale.split(separator: "-").first.map(String.init) ?? locale
        let local = byLocale[locale]
            ?? byLocale.keys.sorted().first { $0.hasPrefix(language + "-") }.flatMap { byLocale[$0] }
            ?? [:]
        guard locale != sharedLocale else { return merged }
        for (category, words) in local {
            merged[category, default: []].append(contentsOf: words)
        }
        return merged
    }

    /// Lowercase ASCII letters and digits; every other character becomes a word break.
    static func fold(_ raw: String) -> String {
        let lowered = raw
            .replacingOccurrences(of: "İ", with: "i")
            .lowercased()
            .replacingOccurrences(of: "ı", with: "i")
            .decomposedStringWithCanonicalMapping
        var folded = ""
        var pendingSpace = false
        for scalar in lowered.unicodeScalars {
            let value = scalar.value
            if (0x61...0x7A).contains(value) || (0x30...0x39).contains(value) {
                if pendingSpace, !folded.isEmpty { folded.append(" ") }
                folded.unicodeScalars.append(scalar)
                pendingSpace = false
            } else if scalar.properties.generalCategory == .nonspacingMark {
                continue
            } else {
                pendingSpace = true
            }
        }
        return folded
    }
}

/// One row handed to the aisle grouper. Checked rows leave the open sections.
struct GroceryGroupInput: Equatable, Sendable {
    var name: String
    var category: GroceryCategory
    var isChecked: Bool
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
