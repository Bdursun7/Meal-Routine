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
        case .produce: "leaf"
        case .protein: "fork.knife"
        case .dairyAndEggs: "cup.and.saucer"
        case .pantry: "archivebox"
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
    ]

    private static let proteinIDs: Set<String> = [
        "bacon", "barramundi", "beef", "chicken", "chinesesausage", "chourico",
        "clams", "cockles", "cod", "codfish", "crab", "cuttlefish",
        "fish", "guanciale", "ham", "hilsa", "lamb", "leanbeef",
        "merguez", "mussels", "pork", "porkbelly", "prawns", "prosciutto",
        "rabbit", "ribs", "salmon", "salmonbones", "sardines", "sausage",
        "tofu", "trout", "tuna", "veal"
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

enum GroceryListGrouping {
    /// Open rows follow the market walk. Checked rows are not returned here.
    static func openCategories(in rows: [GroceryGroupInput]) -> [GroceryCategory] {
        let open = rows.filter { !$0.isChecked }
        return GroceryCategory.sectionOrder.filter { category in
            open.contains { $0.category == category }
        }
    }
}
