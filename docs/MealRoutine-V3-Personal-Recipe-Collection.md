# MealRoutine V3 — Personal Recipe Collection

**Product:** MealRoutine  
**Version:** V3  
**Codename:** Personal Recipe Collection  
**Previous version:** V2 — Personal Meal Memory  
**Next version:** V4 — Household / Shared Planning  
**Status:** Implementation specification  

---

## 1. Version Goal

V3 makes MealRoutine useful for recipes that are discovered outside the built-in catalog.

The user can save a recipe from anywhere, keep its original source, optionally complete the recipe details later, and then use that recipe inside the existing MealRoutine planning and Meal Memory systems.

### Core promise

> **Save any recipe you want to try. Turn it into part of your MealRoutine.**

### Product principle

MealRoutine does **not** promise to reconstruct a recipe correctly from an arbitrary URL.

V3 treats an external source as a **source of discovery**, not as a reliable structured recipe database.

The product owns the structured recipe data only after the user has entered or confirmed it.

---

## 2. Why V3 Changes Direction

The original V3 concept was based on automatic URL extraction. That approach creates a technical problem that is larger than the product value it provides.

Recipe pages do not use one reliable structure. Some expose Schema.org Recipe data, some expose incomplete metadata, some put important information in rendered HTML, and social platforms frequently contain the actual recipe only inside captions, videos, images, comments, or spoken audio.

A URL therefore does not guarantee:

- complete ingredients
- correct quantities
- complete instructions
- correct servings
- correct preparation time
- reliable category information
- reliable source attribution
- stable access in the future

Building V3 around scraping would also create a permanent maintenance burden for a solo developer. Website layouts change, social platforms change, access rules change, and every new source introduces another failure mode.

### V3 decision

**Automatic URL-to-recipe extraction is removed from V3.**

V3 does not contain:

- JSON-LD recipe extraction
- HTML recipe parsing
- ingredient parsing from arbitrary pages
- recipe extraction confidence scoring
- social-media scraping
- platform-specific recipe scrapers
- automatic reconstruction of a complete recipe from a URL

The URL is stored as a source link.

The recipe itself is entered by the user.

---

## 3. User Problem

A user sees a recipe they want to try on Instagram, TikTok, YouTube, a recipe website, a message, or somewhere else.

The current behavior is usually one of these:

1. Save the post and forget about it.
2. Screenshot it and lose it among other screenshots.
3. Send it to themselves in a message.
4. Bookmark the page and never return to it.
5. Manually copy the ingredients when they finally decide to cook it.

The real problem is not finding recipes.

The problem is turning **“I want to try this”** into **“this is now part of my meal system.”**

### Main user job

> When I discover a recipe I want to try, I want to save it immediately and turn it into a usable MealRoutine recipe when I am ready.

---

## 4. V3 Product Flow

The complete V3 flow is:

```text
Discover recipe anywhere
        ↓
Share to MealRoutine
        ↓
Quick Save
        ↓
Recipe Collection
        ↓
Complete Recipe when needed
        ↓
Structured MealRoutine Recipe
        ↓
Weekly Plan
        ↓
Grocery List
        ↓
Cook
        ↓
Loved / Okay / Never Again + feedback
        ↓
Meal Memory
```

This connects V3 directly to V2.

V3 is not a separate recipe-management product. It expands the set of recipes that V2 can learn from.

---

## 5. Scope

### Included

- iOS Share Sheet / Share Extension
- Save external recipe as a Quick Save
- Save source URL when available
- Save source platform
- Save shared title when available
- Save shared image when available and permitted by the share payload
- Recipe Collection for saved recipes
- Quick Save status
- Complete Recipe flow
- Manual recipe creation
- Edit recipe after creation
- Structured ingredients
- Structured instructions
- Servings
- Preparation time
- Cooking time
- Total time
- Category
- Cuisine
- Difficulty
- Recipe notes
- Source attribution
- Open Original action
- Draft / incomplete recipe state
- Duplicate prevention based on source URL
- Planning integration
- Grocery integration
- Meal Memory integration
- Favorite integration
- Existing V2 feedback integration
- Existing V2 replacement/discovery integration
- Local-first persistence
- Offline use after the recipe is saved
- Clear distinction between incomplete saved content and usable recipes

### Not included

- Automatic URL recipe extraction
- Website scraping
- JSON-LD parsing
- HTML parsing
- Ingredient parser
- Automatic OCR of recipe screenshots
- Automatic transcription of cooking videos
- Automatic extraction from Instagram captions
- Automatic extraction from TikTok captions
- Instagram API integration
- TikTok API integration
- YouTube API integration
- Login to external platforms
- Authentication bypass
- Private-content access
- Video downloading
- Social feed
- Public recipe sharing
- Community features
- Household/shared planning
- Shared accounts
- Cloud sync
- Android
- Web
- Apple Watch
- AI chatbot
- Mandatory LLM/API dependency
- Nutrition calculations
- Allergy guarantees
- Grocery-store price lookup
- Pantry management
- Budget management

---

## 6. V3 Product Principles

### 6.1 Save first, complete later

The user must be able to save something without immediately filling every recipe field.

A user who shares a recipe is expressing:

> “I want to remember this.”

That action must not be blocked by a long form.

### 6.2 The source is not the recipe

A URL identifies where the user found the recipe.

It does not define the recipe stored in MealRoutine.

### 6.3 User-entered recipe data is authoritative

Once the user enters or edits a recipe, MealRoutine treats that structured data as the source of truth for:

- planning
- grocery aggregation
- cooking
- Meal Memory
- feedback

### 6.4 Incomplete data is allowed, unusable data is not

A Quick Save can exist with only a title and source.

A recipe cannot enter the normal weekly planning system until the minimum required recipe data is complete.

### 6.5 No silent invention

MealRoutine never invents:

- ingredient quantities
- ingredients
- cooking steps
- servings
- time values
- categories
- dietary properties

### 6.6 Manual entry is not a fallback hack

Manual entry is the primary guaranteed path for creating a correct recipe.

It must be treated as a first-class feature.

### 6.7 V3 stays local-first

No account or backend is required.

All saved recipes and collection state work locally.

---

## 7. Primary Entry Point — Share Sheet

The main V3 interaction is:

> **Share → MealRoutine**

The Share Sheet accepts whatever useful metadata the operating system provides.

The app does not promise that every source will provide the same data.

### Supported shared data

When available:

- URL
- plain text
- title
- image

The app stores only the information actually supplied by the share payload.

### Typical sources

- Safari
- Instagram
- TikTok
- YouTube
- Messages
- WhatsApp
- Telegram
- Notes
- Other applications exposing a share payload

The source application does not need to be integrated through an official API.

The Share Sheet only saves information that the operating system makes available to MealRoutine.

---

## 8. Quick Save

Quick Save is the central V3 feature.

The user should be able to save a recipe discovery in seconds.

### Quick Save screen

```text
┌─────────────────────────────┐
│        Save to MealRoutine  │
│                             │
│  [Recipe image]             │
│                             │
│  Creamy Garlic Pasta        │
│  Instagram                  │
│                             │
│  Source                      │
│  instagram.com/...          │
│                             │
│       [Save to Try]         │
└─────────────────────────────┘
```

The primary action is **Save to Try**.

The user does not need to enter ingredients at this point.

### Data saved by Quick Save

- Local recipe identifier
- Title, when available
- Source URL, when available
- Source platform
- Shared image, when available
- Date saved
- Collection status
- Completion status

### Result

After saving:

```text
Saved to Try ✓

You can complete the recipe whenever you're ready.
```

The user can dismiss the flow immediately.

---

## 9. Recipe Collection

V3 adds a dedicated personal collection for recipes discovered outside the built-in catalog.

### Collection sections

```text
My Recipes

[ Saved to Try ]
[ Ready to Cook ]
[ Favorites ]
```

The exact UI can use tabs, segmented controls, or filters, but the states must remain distinct.

### Saved to Try

Contains Quick Saves that do not yet contain enough information to be used as normal MealRoutine recipes.

Example:

```text
🥩 Beyti Sarma
Nefis Yemek Tarifleri
Saved 2 days ago

[Complete Recipe]
```

### Ready to Cook

Contains completed user-created or imported-source recipes that satisfy the minimum recipe requirements.

These recipes behave like normal MealRoutine recipes.

### Favorites

Uses the existing V2 favorite behavior.

No separate V3 favorite system is created.

---

## 10. Complete Recipe Flow

When the user opens a Quick Save and selects **Complete Recipe**, MealRoutine opens a structured manual-entry form.

### Required fields

- Recipe name
- At least one ingredient
- At least one instruction
- Servings

### Optional fields

- Prep time
- Cook time
- Total time
- Category
- Cuisine
- Difficulty
- Recipe image
- Recipe notes

### Source section

The source is displayed separately:

```text
Source
Instagram
Open Original
```

or:

```text
Source
Nefis Yemek Tarifleri
Open Original
```

The source URL remains attached to the recipe.

### Example

```text
Beyti Sarma

Servings
[ 4 ]

Ingredients

[ 400 ] [ g ] [ kıyma ]
[ 2 ]   [ adet ] [ yufka ]
[ 1 ]   [ adet ] [ soğan ]
[ ... ]

Instructions

1. Soğanı doğrayın...
2. Kıymayı hazırlayın...
3. Yufkayı sarın...

Prep time     [ 20 min ]
Cook time     [ 30 min ]

Category      [ Main Course ]
Difficulty    [ Medium ]

Source
Nefis Yemek Tarifleri
[Open Original]

[Save Recipe]
```

---

## 11. Manual Recipe Creation

Users must also be able to create a recipe without using Share Sheet.

Entry point:

```text
Recipes → + → New Recipe
```

This uses the same editor as **Complete Recipe**.

The implementation must not create two different recipe editors.

### Recipe creation modes

```text
New Recipe
    ↓
Manual Recipe
    ↓
Recipe Editor

Quick Save
    ↓
Complete Recipe
    ↓
Recipe Editor
```

Both paths produce the same Recipe model.

---

## 12. Recipe States

V3 uses explicit completion state.

```swift
enum RecipeCollectionState: String, Codable {
    case savedToTry
    case readyToCook
}
```

### savedToTry

The user has saved the discovery but has not completed the minimum recipe information.

It remains in the collection and is not automatically inserted into the weekly plan.

### readyToCook

The recipe contains all required data and can participate in the normal MealRoutine system.

The state changes to `readyToCook` only after validation succeeds.

---

## 13. Recipe Origin

V3 extends the existing recipe origin concept.

```swift
enum RecipeOrigin: String, Codable {
    case builtIn
    case manual
    case savedExternal
}
```

### builtIn

MealRoutine-authored recipes shipped with the app.

### manual

A recipe created directly by the user without an external source.

### savedExternal

A recipe created from a Quick Save and completed by the user.

The `savedExternal` origin identifies how the recipe entered the user's collection. It does not imply that MealRoutine extracted or verified the recipe automatically.

---

## 14. Source Platform

The source platform is metadata only.

```swift
enum RecipeSourcePlatform: String, Codable {
    case website
    case instagram
    case tiktok
    case youtube
    case safari
    case whatsapp
    case telegram
    case messages
    case notes
    case other
    case unknown
}
```

The platform is inferred from the share payload or URL only when the identification is deterministic.

If it cannot be determined, use `unknown`.

The platform must never change recipe behavior.

---

## 15. Data Model

Existing V1/V2 Recipe relationships remain intact.

V3 adds collection and source metadata.

Suggested fields:

```swift
var origin: RecipeOrigin
var collectionState: RecipeCollectionState

var sourceURL: String?
var sourceTitle: String?
var sourcePlatform: RecipeSourcePlatform?
var sourceImagePath: String?
var savedAt: Date?
var completedAt: Date?

var recipeNotes: String?
```

### Important rule

Do not add extraction-specific fields.

The following fields are intentionally removed from the V3 model:

```swift
var extractionConfidence: Double?
var importStatus: RecipeImportStatus?
var lastImportedAt: Date?
var requiresReview: Bool
```

They belonged to the abandoned automatic extraction architecture.

---

## 16. Ingredient Model

Ingredients remain structured records because Grocery List requires structured ingredients.

```swift
var name: String
var quantity: Double?
var unit: String?
var preparationNote: String?
var isOptional: Bool
var sortOrder: Int
```

### Rules

- Quantity may be empty while editing.
- Quantity must be present and greater than zero before a recipe becomes `readyToCook`.
- Quantity is a number. A decimal separator is allowed. Text such as "biraz" does not save as an empty amount.
- Every active ingredient (one with a name, quantity, unit, or preparation note) needs a unit chosen from the catalog list. Empty and "Birim yok" do not count. A cleared placeholder row does not.
- The stored unit is the catalog code (`g`, `piece`), including when the cook picked a known alias such as "adet".
- Preparation notes are preserved separately from the ingredient name.
- User-entered text is never rewritten into a different ingredient without explicit user action.
- No automatic ingredient normalization is required in V3.

### Example

```text
400 g kıyma, yağsız
```

is stored as:

```text
name: kıyma
quantity: 400
unit: g
preparationNote: yağsız
```

when the user enters it in structured fields.

---

## 17. Instruction Model

Instructions are stored as ordered steps.

```swift
var text: String
var sortOrder: Int
```

The user can:

- add a step
- edit a step
- delete a step
- reorder steps

No automatic instruction parsing is required.

---

## 18. Recipe Validation

Validation exists to prevent incomplete recipes from entering planning.

### Minimum valid recipe

A recipe is `readyToCook` when:

- name is not empty, after trimming whitespace, and within 80 characters
- at least one ingredient exists
- every active ingredient has a name (within 60 characters) and a quantity greater than zero
- every active ingredient has a catalog unit
- at least one instruction exists
- every instruction has non-empty text (within 500 characters)
- servings is a whole number, 1 or greater, at most 3 digits
- prep, cook, and total minutes, when filled in, are whole numbers of at most 4 digits. Empty minutes stay unknown and are not invented
- notes, source URL, source title, category, cuisine, and preparation notes stay within their character caps

### Optional fields

These may be left empty:

- prep time
- cook time
- total time
- category
- cuisine
- difficulty
- notes
- image
- source URL

A minute that is filled in must be a whole number. Category, cuisine, notes, preparation notes, and the source fields must stay within their character caps.

### Validation message

Do not show a generic error such as:

> Recipe is invalid.

Show the exact missing information:

```text
Complete these before saving:

• Add at least one ingredient quantity
• Add at least one cooking step
```

---

## 19. Editing Rules

A saved recipe is fully editable.

The user can change:

- name
- image
- servings
- ingredients
- instructions
- time
- category
- cuisine
- difficulty
- notes

Source metadata remains separate from recipe content.

Editing the recipe does not remove the source URL.

### Source editing

The user can remove a source URL manually.

Removing the source does not delete the recipe.

---

## 20. Source Attribution

Every externally saved recipe displays its source when one exists.

Example:

```text
Source
Nefis Yemek Tarifleri

[Open Original]
```

The source section is informational.

MealRoutine does not claim ownership of externally sourced recipe content.

The app does not copy or redistribute the external page.

---

## 21. Open Original

If `sourceURL` exists, the recipe detail page provides:

```text
Open Original
```

The action opens the URL using the system browser or appropriate system URL handling.

If the URL no longer works, the MealRoutine recipe remains usable because the structured recipe is stored locally.

This is an important distinction:

> The external URL is a reference, not a dependency for cooking the saved recipe.

---

## 22. Quick Save and Completion UX

The user must never be forced to complete a recipe immediately after sharing it.

### Share flow

```text
Share → MealRoutine
        ↓
Save to Try
        ↓
Done
```

### Later flow

```text
Recipes → Saved to Try
        ↓
Beyti Sarma
        ↓
Complete Recipe
        ↓
Fill fields
        ↓
Save Recipe
        ↓
Ready to Cook
```

### Optional convenience

After Quick Save, show:

```text
Saved to Try ✓

[Complete Now]   [Done]
```

`Done` is the default dismissal path.

---

## 23. Collection UX

The collection should feel like a personal recipe inbox, not an administrative database.

### Saved to Try card

Each card shows:

- recipe title
- image when available
- source/platform
- saved date
- completion state

Example:

```text
┌──────────────────────────────┐
│ [image]                      │
│                              │
│ Beyti Sarma                  │
│ Nefis Yemek Tarifleri       │
│ Saved 2 days ago             │
│                              │
│ [Complete Recipe]            │
└──────────────────────────────┘
```

### Ready to Cook card

```text
┌──────────────────────────────┐
│ [image]                      │
│                              │
│ Beyti Sarma                  │
│ 4 servings • 50 min          │
│                              │
│ ★ Favorite                   │
└──────────────────────────────┘
```

The UI must prioritize food imagery, title, and useful cooking information over metadata.

---

## 24. Planning Integration

Only `readyToCook` recipes can enter weekly planning.

No new planning algorithm is created.

The existing V1/V2 planner treats a user-created recipe as another eligible recipe.

### Eligibility

```text
builtIn + ready
manual + ready
savedExternal + ready
        ↓
Existing planning engine
```

### Saved-to-try recipes

```text
savedToTry
        ↓
Collection only
        ↓
Not eligible for weekly plan
```

The user must complete the recipe before it can be planned.

---

## 25. Grocery Integration

Completed recipes use the existing grocery aggregation system.

No separate V3 grocery implementation is created.

For example:

```text
Beyti Sarma
400 g kıyma
2 adet yufka
1 adet soğan

        ↓

Weekly Grocery List
400 g kıyma
2 adet yufka
1 adet soğan
```

The grocery system uses the structured ingredient values entered by the user.

Because V3 does not parse arbitrary text, it does not need an ingredient-parser layer.

---

## 26. Meal Memory Integration

V3 must use the existing V2 Meal Memory without creating a second memory system.

When a completed personal recipe is cooked, it participates in the same events as a built-in recipe:

- cooked
- loved
- okay
- never again
- replaced
- skipped
- favorite
- time feedback
- difficulty feedback
- portion feedback
- ingredient feedback

The source platform has no special influence on Meal Memory.

A recipe found on TikTok is not treated differently from a recipe created manually.

---

## 27. Discovery Integration

Completed personal recipes appear in the existing discovery/recommendation system.

Examples:

```text
Recommended for you

Your saved recipe

Similar to meals you loved
```

V3 does not add a new recommendation algorithm.

V2 personalization remains the single source of recommendation behavior.

---

## 28. Smart Replacement Integration

Completed V3 recipes can be selected by existing Smart Replacement actions.

For example:

```text
Replace

• Faster
• Similar to something loved
• Completely different
• Use favorite
• Try new
• Surprise me
```

No V3-specific replacement logic is required.

---

## 29. Duplicate Handling

Duplicate handling is intentionally simple.

### Primary duplicate key

If a shared source URL already exists in the collection, MealRoutine detects it.

Example:

```text
Already saved

You saved this recipe 8 days ago.

[Open Recipe]   [Save Anyway]
```

### No content-based duplicate engine

V3 does not compare ingredient lists or perform semantic recipe similarity to determine duplicates.

That complexity is not necessary for the first version of the personal collection.

The user remains in control.

---

## 30. Re-saving the Same Recipe

When the same source URL is shared again:

- do not create a duplicate automatically
- show the existing recipe
- allow the user to open it
- allow the user to save another copy explicitly

The app must not silently merge two recipes.

---

## 31. Deletion Rules

### Delete Quick Save

A `savedToTry` item can be deleted directly.

### Delete completed recipe

A completed personal recipe can be deleted with confirmation.

The existing Meal Memory policy determines whether associated history is retained or detached according to the V2 implementation.

V3 must not invent a second history-deletion policy.

---

## 32. Share Extension Behavior

The Share Extension must remain intentionally small.

### Responsibilities

1. Receive shared payload.
2. Extract available URL/text/title/image metadata.
3. Create a Quick Save record.
4. Persist locally.
5. Confirm success.
6. Close.

### Responsibilities it does not have

- recipe extraction
- HTML downloading
- webpage parsing
- AI processing
- social API calls
- recipe validation
- grocery processing
- recommendation processing

The Share Extension is a **capture tool**, not a recipe parser.

---

## 33. Local Persistence

Use the existing SwiftData architecture.

A Quick Save must be persisted before the Share Extension finishes.

The user must not lose a saved recipe because the main application was not open.

### Required persistence

```text
Saved Recipe
    ↓
SwiftData
    ↓
Main App
```

No backend is required.

---

## 34. Offline Behavior

After a recipe is saved, all local recipe information remains available offline.

Offline capabilities:

- view saved recipes
- complete recipes
- edit recipes
- plan completed recipes
- generate grocery list
- cook recipe
- record feedback
- update Meal Memory

The only action that naturally requires network access is:

```text
Open Original
```

because the source is external.

---

## 35. Error Handling

V3 has fewer technical failure states because it does not scrape external pages.

### Missing share data

If the shared payload contains no useful information:

```text
Nothing to save

MealRoutine couldn't find a recipe link or text in this share.

[Open MealRoutine]
```

The user can still create a manual recipe.

### Storage failure

If local persistence fails:

```text
Couldn't save this recipe.
Please try again.
```

The app must not report success before persistence succeeds.

### Invalid URL

An invalid URL is stored only as absent source metadata if the user continues with manual creation.

The recipe itself is not blocked by a broken source URL.

---

## 36. Security and Privacy

V3 does not request external account credentials.

MealRoutine must never:

- request Instagram credentials
- request TikTok credentials
- request YouTube credentials
- bypass authentication
- access private posts
- scrape content behind authentication

Shared content is processed only from the payload supplied by the operating system.

No external account access is required.

---

## 37. Analytics

Analytics are local-first and privacy-conscious.

If analytics infrastructure already exists, V3 records product events without storing external-content payloads unnecessarily.

### Events

```text
recipe_quick_saved
recipe_completion_started
recipe_completion_finished
recipe_completion_abandoned
recipe_added_manually
recipe_opened_original
recipe_added_to_plan
saved_recipe_deleted
saved_recipe_duplicate_detected
```

### Event properties

Use non-sensitive metadata such as:

- source platform
- recipe origin
- completion state
- whether the recipe was later planned

Do not store:

- full external page HTML
- private social content
- account credentials
- unnecessary copied personal messages

---

## 38. V3 Success Metrics

The goal is not to measure how many URLs MealRoutine can scrape.

The goal is to measure whether saved discoveries become useful meals.

### Primary metrics

#### Quick Save adoption

Percentage of active users who save at least one external recipe during the test period.

#### Completion rate

Percentage of Quick Saves that become `readyToCook` recipes.

#### Time to completion

Median time between Quick Save and recipe completion.

#### Planned saved recipes

Percentage of completed external recipes added to at least one weekly plan.

#### Cooked saved recipes

Percentage of completed external recipes that are actually cooked.

#### Meal Memory engagement

Percentage of completed external recipes receiving V2 feedback after cooking.

### Suggested beta targets

For the first beta:

- 30 users
- 21 days
- at least 50% save one external recipe
- at least 35% of saved recipes become ready-to-cook recipes
- at least 25% of completed external recipes enter a weekly plan
- at least 20% of completed external recipes are cooked
- at least 50% of cooked external recipes receive feedback

These are validation targets, not permanent product requirements.

---

## 39. UX Success Criteria

A successful V3 experience feels like:

> “I saw this recipe, saved it in one tap, and later added it to my week.”

It must not feel like:

> “I have another complicated recipe database to maintain.”

### Quick Save target

The Share Sheet save flow must require only a confirmation action after the system provides the shared metadata.

### Completion target

The recipe editor must be faster than manually recreating the recipe somewhere else.

### Planning target

Once complete, the recipe must behave exactly like a normal MealRoutine recipe.

---

## 40. UI Structure

### Recipes tab

```text
Recipes

[ Built-in ] [ My Recipes ]

My Recipes

[ Saved to Try ] [ Ready to Cook ]

--------------------------------

Saved to Try

Beyti Sarma
Nefis Yemek Tarifleri
[Complete Recipe]

Creamy Pasta
Instagram
[Complete Recipe]

--------------------------------

Ready to Cook

Chicken Bowl
4 servings • 30 min
```

The existing V1/V2 recipe browsing experience remains intact.

V3 adds the personal collection without redesigning the entire app.

---

## 41. Recipe Detail Structure

### Quick Save detail

```text
[Image]

Beyti Sarma

Saved to Try

Source
Nefis Yemek Tarifleri
[Open Original]

Saved 2 days ago

[Complete Recipe]
[Delete]
```

### Completed recipe detail

```text
[Image]

Beyti Sarma

4 servings • 50 min

Ingredients
...

Instructions
...

Source
Nefis Yemek Tarifleri
[Open Original]

[Cooked]
[Feedback]
```

The completed view uses the existing recipe-detail interaction patterns.

---

## 42. Recipe Editor Requirements

The editor must support:

- dynamic ingredient rows
- dynamic instruction rows
- add ingredient
- delete ingredient
- reorder ingredients
- add instruction
- delete instruction
- reorder instructions
- servings input
- time inputs
- category picker
- cuisine picker
- difficulty picker
- notes
- image selection
- source display
- save
- cancel

### Unsaved changes

If the user leaves with changes:

```text
Discard changes?

[Keep Editing] [Discard]
```

No data is silently discarded.

---

## 43. Image Handling

V3 supports an optional recipe image.

The image can come from:

- shared image payload
- user's photo library
- camera, if already supported by the app

The image is local to the user's MealRoutine collection.

No external image URL is required for recipe functionality.

If the shared source does not provide an image, the recipe works normally without one.

---

## 44. No AI Requirement

V3 must work completely without an LLM.

No recipe generation or interpretation is required.

AI can be used during development for:

- writing seed content
- generating test data
- helping author UI copy
- code assistance

But the shipped V3 feature does not depend on an AI API.

This keeps V3:

- free to operate
- deterministic
- private
- offline-capable
- maintainable by one developer

---

## 45. Architecture

V3 extends the existing feature-based architecture.

Suggested structure:

```text
Features/
├── Recipes/
│   ├── RecipeList
│   ├── RecipeDetail
│   ├── RecipeEditor
│   └── RecipeCollection
│
├── RecipeCapture/
│   └── ShareExtension
│
└── MealPlanning/
    └── existing V1/V2 implementation
```

### Services

Only services required by the new product behavior are added.

```text
RecipeCollectionService
RecipeSourceService
RecipeValidationService
```

No extraction services are created.

Do not create:

```text
RecipeExtractionService
RecipeNormalizationService
IngredientParser
RecipeScraper
RecipeImportConfidenceService
```

These are intentionally outside V3.

---

## 46. Repository / Model Boundaries

The recipe collection must use the existing Recipe model wherever possible.

Do not create a second `ImportedRecipe` domain object that duplicates Recipe.

The correct model is:

```text
Recipe
 ├── origin
 ├── collectionState
 ├── sourceURL
 ├── sourcePlatform
 ├── sourceTitle
 └── existing recipe data
```

This prevents two parallel recipe systems.

---

## 47. Share Extension Data Contract

The Share Extension passes a small capture object to the main app/persistence layer.

Conceptually:

```swift
struct RecipeCapture {
    let url: URL?
    let title: String?
    let text: String?
    let imageData: Data?
    let sourcePlatform: RecipeSourcePlatform
    let capturedAt: Date
}
```

The capture object is not a recipe.

It is only the information needed to create a Quick Save.

---

## 48. Completion Service

`RecipeCollectionService` owns collection state transitions.

Responsibilities:

- create Quick Save
- list saved-to-try recipes
- complete recipe
- move recipe to ready-to-cook
- delete saved recipe
- detect duplicate source URL

It does not:

- parse web pages
- call LLMs
- generate ingredients
- generate instructions
- plan meals

---

## 49. Validation Service

`RecipeValidationService` validates the recipe before completion.

Example API:

```swift
func validate(_ recipe: Recipe) -> RecipeValidationResult
```

Possible result:

```swift
enum RecipeValidationResult {
    case valid
    case invalid([RecipeValidationIssue])
}
```

The validation rules are deterministic and local.

---

## 50. Source Service

`RecipeSourceService` owns source metadata behavior.

Responsibilities:

- identify source platform from known URL patterns
- normalize a source URL for duplicate comparison
- provide display information
- open source URL

It does not fetch the page to reconstruct the recipe.

### URL normalization

Normalization is limited to deterministic URL cleanup required for duplicate detection.

Do not perform aggressive URL rewriting that could change the destination.

---

## 51. Testing Requirements

### Share Extension

Test:

- URL only
- title + URL
- text only
- image + URL
- title + image
- empty payload
- unsupported payload
- multiple shared items

### Quick Save

Test:

- creates local record
- preserves title
- preserves URL
- preserves source platform
- preserves image when supplied
- closes successfully after persistence

### Completion

Test:

- empty title rejected
- no ingredients rejected
- missing ingredient quantity rejected
- no instructions rejected
- empty instruction rejected
- zero servings rejected
- valid recipe becomes ready-to-cook

### Planning

Test:

- saved-to-try recipe is excluded
- ready-to-cook recipe is eligible
- completed recipe appears in existing planner

### Grocery

Test:

- completed recipe ingredients appear in grocery aggregation
- quantities are preserved

### Meal Memory

Test:

- cooked event works
- feedback works
- favorite works
- existing V2 recommendation behavior sees the recipe

### Duplicate

Test:

- same normalized URL is detected
- different URL can be saved
- duplicate does not silently overwrite existing recipe

---

## 52. Migration from V2

V2 recipes require no destructive migration.

Existing recipes default to:

```text
origin = builtIn or existing origin
collectionState = readyToCook
```

Only recipes created through V3 use the new external-source collection states.

Existing Meal Memory records remain unchanged.

Existing planner behavior remains unchanged.

---

## 53. Implementation Order

Implementation must follow this order.

### Step 1 — Model

Add:

- `RecipeCollectionState`
- `RecipeOrigin.savedExternal`
- source metadata fields
- saved/completed timestamps

### Step 2 — Recipe Collection

Implement:

- My Recipes
- Saved to Try
- Ready to Cook
- empty states

### Step 3 — Recipe Editor

Implement the single shared editor used by:

- New Recipe
- Complete Recipe
- Edit Recipe

### Step 4 — Validation

Implement minimum completion rules.

### Step 5 — Share Extension

Implement:

- receive payload
- create Quick Save
- persist
- success state

### Step 6 — Source Handling

Implement:

- platform detection
- source display
- Open Original
- URL duplicate detection

### Step 7 — Planning Integration

Allow only ready-to-cook personal recipes into the existing planner.

### Step 8 — Grocery Integration

Connect existing grocery aggregation to personal recipes.

### Step 9 — Meal Memory Integration

Connect existing V2 behavior tracking to personal recipes.

### Step 10 — Polish

Improve:

- cards
- empty states
- completion prompts
- source presentation
- save confirmation
- error states
- accessibility

---

## 54. Commit Strategy

Use small semantic commits.

Suggested sequence:

```text
feat(recipe): add personal recipe collection state
feat(recipe): add external source metadata
feat(recipe): add personal recipe editor
feat(recipe): add recipe completion validation
feat(share): add recipe capture extension
feat(recipe): add quick save flow
feat(recipe): add source attribution
feat(recipe): add duplicate source detection
feat(planner): include completed personal recipes
feat(grocery): aggregate personal recipe ingredients
feat(memory): track personal recipe feedback
feat(ui): polish personal recipe collection
```

Do not mix Share Extension implementation with unrelated V2 refactoring.

---

## 55. Definition of Done

V3 is complete when all of the following are true:

- A user can share a recipe link from Safari to MealRoutine.
- A user can share available recipe metadata from Instagram/TikTok/YouTube or another app without requiring an official platform API.
- MealRoutine can save the shared discovery as a Quick Save.
- Quick Save does not require ingredient entry.
- Saved recipes appear in the personal collection.
- A Quick Save can be completed later.
- A user can manually create a recipe without using Share Sheet.
- Both creation paths use the same Recipe Editor.
- A completed recipe passes deterministic validation.
- A completed recipe becomes `readyToCook`.
- A `savedToTry` recipe cannot enter the weekly plan.
- A `readyToCook` personal recipe can enter the weekly plan.
- Personal recipe ingredients appear in the existing grocery list.
- Personal recipes participate in V2 Meal Memory.
- Personal recipes participate in existing recommendation/replacement behavior.
- Source URL and platform are displayed when available.
- Open Original works when a source URL exists.
- Duplicate source URLs are detected.
- The same recipe is not silently overwritten.
- All saved data works locally without an account.
- The app works without an AI API.
- No automatic URL recipe extraction exists in the shipped V3 implementation.

---

## 56. V3 Boundaries

The following decisions are locked for V3.

### Locked in

- Share Sheet
- Quick Save
- Personal Recipe Collection
- Manual recipe completion
- Manual recipe creation
- Source URL storage
- Source platform metadata
- Ready-to-cook state
- Planning integration
- Grocery integration
- Meal Memory integration
- Local-first architecture

### Explicitly deferred

- automatic URL extraction
- OCR
- video transcription
- AI recipe extraction
- automatic ingredient normalization
- social platform APIs
- recipe scraping
- cloud sync
- household sharing
- pantry
- budget
- nutrition

These are not hidden requirements for V3.

---

## 57. Product Rationale

The important V3 insight is simple:

> **MealRoutine does not need to understand every recipe on the internet. It needs to make the recipes the user actually cares about usable inside MealRoutine.**

The user can discover a recipe anywhere.

MealRoutine captures that discovery immediately.

The user completes the recipe once.

From that point forward, MealRoutine owns the useful structured representation and can apply the systems already built in V1 and V2:

```text
Recipe Collection
      ↓
Weekly Planning
      ↓
Grocery List
      ↓
Cooking
      ↓
Feedback
      ↓
Meal Memory
      ↓
Better Future Plans
```

This keeps V3 focused on a real user behavior instead of turning the product into a web-scraping project.

---

## 58. V3 North Star

The V3 feature should make the user think:

> **“Bunu kaydedeyim, sonra MealRoutine zaten halleder.”**

The immediate action is saving.

The long-term value comes from what happens after saving:

```text
Save
→ Complete
→ Plan
→ Shop
→ Cook
→ Remember
→ Recommend better
```

That is the complete V3 loop.
