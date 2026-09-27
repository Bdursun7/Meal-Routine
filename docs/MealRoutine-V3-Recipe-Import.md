# MealRoutine V3 — Recipe Import

**Product:** MealRoutine  
**Version:** V3  
**Codename:** Recipe Import  
**Previous version:** V2 — Personal Meal Memory  
**Next version:** V4 — Household / Shared Planning

## 1. Version Goal

V3 makes MealRoutine useful beyond its built-in recipe catalog. Users can save recipes they discover elsewhere and turn them into structured MealRoutine recipes that work with planning, grocery lists, Meal Memory, and feedback.

### Core promise

> Save a recipe you discover. Make it usable in your week.

### Product hypothesis

> Other apps help you save food content. MealRoutine turns saved recipes into meals you can actually plan and cook.

This is a hypothesis to validate through usage data, not an assumed permanent competitive advantage.

## 2. Scope

### Included

- iOS Share Sheet recipe import
- Public recipe URL import
- Copied recipe text import
- Manual recipe entry as guaranteed fallback
- Deterministic recipe extraction and normalization
- Editable review before saving
- Structured ingredients and instructions
- Time, servings, category, cuisine, and difficulty
- Source URL and source platform
- Import drafts and error handling
- Duplicate detection
- Imported recipe labels and filters
- Planning integration
- Grocery integration
- Meal Memory integration
- Local-first storage
- Re-import without silently overwriting user edits

### Not included

- Instagram/TikTok official API integration
- Login to private accounts
- Authentication bypass or private-content scraping
- Social video downloading
- Public recipe sharing or social feed
- Household/shared accounts or V4 approval/veto flows
- Cloud sync
- Android/web/Watch
- AI chatbot
- Mandatory LLM or paid AI API
- Automatic nutrition or allergy guarantees
- Ingredient price lookup, grocery delivery, pantry, or budget management

## 3. User Problem

A user sees a recipe online, saves it somewhere, and later struggles to turn that saved content into an actionable meal. The recipe gets forgotten, ingredients must be copied manually, and it never becomes part of the weekly plan.

### Main user job

> When I discover a recipe I want to try, I want to save it in a structured format so I can include it in my weekly meal plan and grocery list later.

## 4. Product Principles

### Import is not automatically trusted

Imported content may be incomplete, incorrectly parsed, or ambiguous. The application always provides an editable review step before saving.

### User confirmation is required

The user confirms or corrects the title, ingredients, instructions, time, servings, category, and any uncertain fields before the recipe becomes a normal recipe.

### Imported recipes are first-class recipes

After confirmation, imported recipes use the existing Recipe, planning, grocery, Meal Memory, favorite, feedback, and replacement systems. There is no separate planning engine.

### Source attribution is preserved

The source URL and platform are stored when available. MealRoutine does not present imported content as its own authored content.

### Failure has a usable fallback

Every failed automatic import leads to a clear option to retry, paste recipe text, or enter the recipe manually.

### Local-first remains the default

No account, backend, or cloud synchronization is required for V3.

## 5. Supported Import Entry Points

### 5.1 iOS Share Sheet — primary

The user shares a URL or text from Safari, Instagram, TikTok, YouTube, Notes, Messages, WhatsApp, Telegram, or another app that exposes a supported URL/text payload.

### 5.2 Paste URL

The user pastes a public recipe URL into MealRoutine and starts extraction.

### 5.3 Paste Text

The user pastes recipe text. The application attempts to identify title, ingredients, instructions, time, and servings. The user reviews the result.

### 5.4 Manual Entry

Manual entry is the guaranteed fallback and must work without automatic extraction.

## 6. Technical Constraints

- iPhone only
- SwiftUI + Swift
- SwiftData
- iOS 18.0 minimum
- Local-first
- No backend/login/cloud sync
- No mandatory AI API or paid service
- No social-media API dependency
- No authentication bypass
- No private-content scraping

The implementation uses Share Extension/share-target support, URL handling, HTML/structured metadata parsing, local persistence, request cancellation, and offline/manual fallback.

## 7. Import Pipeline

1. **Receive input:** URL, text, shared content, or manual data.
2. **Classify:** public URL, unsupported URL, recipe text, empty/invalid content.
3. **Extract:** JSON-LD Recipe data first; then recipe metadata; then Open Graph/page metadata; then visible text where feasible; otherwise manual fallback.
4. **Normalize:** whitespace, line breaks, time formats, servings, ingredient quantities where confidently identifiable, instruction numbering.
5. **Validate:** title, ingredients/instructions, URL, time, servings, and uncertain fields.
6. **Review:** user edits and confirms.
7. **Detect duplicates:** normalized URL first, then title/ingredient similarity.
8. **Save:** Recipe + ingredients + instructions + source metadata + import event.

No missing quantity, time, instruction, or category may be silently invented.

## 8. Extraction Strategy

### JSON-LD first

Prioritize Schema.org Recipe structured data:

- name
- recipeIngredient
- recipeInstructions
- prepTime
- cookTime
- totalTime
- recipeYield
- recipeCategory
- recipeCuisine
- image
- author
- datePublished

Structured data is an extraction source, not a guarantee of correctness.

### HTML metadata fallback

Use recipe-specific metadata, Open Graph title/URL, page title, and visible page text when available.

### Social media

An Instagram/TikTok URL is not assumed to contain a complete recipe. Use shared text or publicly accessible information when technically available. If incomplete, ask the user to paste the missing text or use manual entry. Never bypass authentication or platform restrictions.

## 9. Data Model

Existing V1/V2 Recipe identity and relationships remain intact. V3 extends the model with import metadata.

```swift
enum RecipeOrigin: String, Codable {
    case builtIn
    case imported
    case manual
}

enum RecipeImportStatus: String, Codable {
    case pending
    case extracting
    case needsReview
    case ready
    case failed
    case cancelled
}

enum RecipeSourcePlatform: String, Codable {
    case website
    case instagram
    case tiktok
    case youtube
    case safari
    case notes
    case messages
    case unknown
}
```

Suggested fields:

```swift
var origin: RecipeOrigin
var sourceURL: String?
var sourceTitle: String?
var sourcePlatform: RecipeSourcePlatform?
var importedAt: Date?
var lastImportedAt: Date?
var importStatus: RecipeImportStatus?
var extractionConfidence: Double?
var requiresReview: Bool
var isUserEdited: Bool
```

## 10. Ingredient Model

Ingredients are structured records.

```swift
var name: String
var quantity: Double?
var unit: String?
var preparationNote: String?
var isOptional: Bool
var isUncertain: Bool
var originalText: String?
var sortOrder: Int
```

Rules:

- Never invent quantities.
- Preserve original ingredient text.
- Mark ambiguous quantities as uncertain.
- Do not merge incompatible units.
- Do not assume universal cup-to-gram conversions.
- Preserve preparation notes.
- Allow an unstructured line when parsing fails.

The existing grocery pipeline remains the source of truth for aggregation.

## 11. Instruction Model

Instructions are ordered steps.

```swift
var text: String
var sortOrder: Int
var isUncertain: Bool
var originalText: String?
```

Preserve original meaning and order. Do not infer missing temperatures, cooking times, or methods. Allow edit/add/delete/reorder.

## 12. Import Review Screen

`Review Recipe` is the critical V3 screen.

### Sections

**Source**
- Source URL
- Source platform
- Open source
- Source title
- Import date

**Basic information**
- Title
- Description
- Category
- Cuisine
- Prep time
- Cook time
- Total time
- Servings
- Difficulty

**Ingredients**
- Quantity/unit/name editing
- Preparation notes
- Optional toggle
- Uncertainty indicators
- Add/delete/reorder

**Instructions**
- Edit/add/delete/reorder

**Warnings**
- Missing time
- Uncertain quantities
- Missing instructions
- Incomplete source
- Social post without full recipe

### Actions

- Cancel
- Save as draft
- Save recipe
- Try again
- Enter manually

`Save recipe` requires enough data to produce a usable recipe or an explicit manual-completion path.

## 13. Drafts

Incomplete imports are saved as drafts so the user does not lose work.

Draft states:

- Started
- Extracting
- Needs review
- Incomplete
- Ready
- Cancelled
- Failed

Drafts are excluded from planning, grocery generation, and recommendations until explicitly saved as recipes.

## 14. Duplicate Detection

### Strong signals

- Same normalized source URL
- Same URL after tracking parameters are removed
- Same source identifier

### Medium signals

- Very similar title
- Similar ingredient list
- Same source + matching title

When a possible duplicate exists, show the existing and new recipe and let the user choose:

- Use existing recipe
- Import as separate recipe
- Cancel

Never silently delete or overwrite an existing recipe.

## 15. Editing and Re-import

Imported recipes remain editable after saving.

Editable fields:

- Title
- Description
- Category
- Cuisine
- Time
- Servings
- Difficulty
- Ingredients
- Instructions
- Source label
- Notes

The source URL is preserved. User edits are distinguished from imported content.

Re-importing the same source never silently overwrites user edits. When extracted content differs, show a comparison and allow the user to keep the current version, review changes, replace selected fields, or cancel.

## 16. Planning Integration

Imported recipes use the existing V2 planning/scoring system after validation.

### Eligibility

A saved imported recipe must have:

- A title
- Usable ingredients or explicit manual confirmation
- Usable instructions or explicit manual confirmation
- No Never again state
- No current constraint violation
- No draft status

### Personalization

V2 Meal Memory remains the source of truth. Imported recipes participate in preference, behavior, variety, repetition, and discovery scoring.

### Important rule

Importing a recipe means the user showed interest. It does **not** mean the user likes it.

A newly imported recipe has no cooking history and must not automatically become a favorite. Import interest is weaker than explicit Favorite, Cooked, Loved, or Never again feedback.

## 17. Imported Recipe Labels

Use factual labels such as:

- Imported
- New to your collection
- Needs review
- User edited

Do not imply that an imported recipe has been cooked or liked unless the user's behavior supports it.

## 18. Recipe Library

The Recipes tab adds:

### Sections

- Recommended for you
- Your imported recipes
- Built-in recipes
- Favorites
- Recently added
- Needs review
- Drafts

### Filters

- All
- Built-in
- Imported
- Favorites
- Not tried
- Cooked
- Needs review

### Sorting

- Recently added
- Recently cooked
- Most cooked
- Favorites
- Alphabetical

## 19. Share Sheet UX

1. User shares content to MealRoutine.
2. MealRoutine identifies URL/text.
3. Compact import UI opens.
4. Extraction starts when possible.
5. Review screen opens.
6. User saves or cancels.

Do not auto-save without review.

V3 handles one recipe per import session. Multiple shared items are not silently combined.

## 20. Import Errors

Errors must be actionable and human-readable.

- **Invalid URL:** This link is not valid. Paste a public recipe link or enter the recipe manually.
- **Unsupported source:** This source cannot be read automatically. Paste the recipe text or enter it manually.
- **Missing recipe data:** The page was found, but it does not contain enough recipe information.
- **Network error:** The recipe could not be loaded. Check your connection and try again.
- **Timeout:** The source took too long to respond. Try again or enter the recipe manually.
- **Parsing error:** The page was loaded, but the recipe could not be structured reliably.
- **Incomplete recipe:** Some information is missing. Review the fields before saving.
- **Duplicate:** A similar recipe already exists in your collection.

Never expose stack traces.

## 21. Privacy and Source Handling

V3 remains local-first.

Stored locally:

- Imported recipe content
- Source URL/platform
- Import date/status
- User corrections and notes
- Drafts
- Related Meal Memory events

Not required:

- User account
- Backend
- Cloud storage
- Social credentials
- Private account access

Never request social passwords or bypass authentication. Do not publicly redistribute imported recipes. Preserve source attribution.

## 22. Delete Behavior

Deleting an imported recipe removes it from:

- Recipe library
- Future planning candidates
- Recommendations
- Favorites
- Discovery lists
- Future grocery generation

Historical plans must remain readable through a safe snapshot/reference where needed. If the recipe has cooking history, show a confirmation before deletion.

## 23. Meal Memory Integration

V2 behavior tracking works with imported recipes.

Relevant events:

- Imported
- Viewed
- Selected
- Cooked
- Replaced
- Skipped
- Loved
- Okay
- Never again
- Favorited
- Edited

Rules:

- Importing does not equal cooking.
- Saving does not equal liking.
- Favoriting is a positive signal.
- Cooking creates normal behavioral history.
- Explicit feedback outranks inferred behavior.
- Never again remains a strong exclusion.
- Editing does not automatically change preference scores.

## 24. Grocery Integration

Imported recipes use the existing grocery pipeline.

Requirements:

- Convert structured ingredients into grocery items.
- Aggregate compatible ingredients.
- Preserve uncertain quantities.
- Preserve optional ingredients.
- Allow manual edits.
- Recalculate after planned recipe replacement.
- Avoid false aggregation.

If ingredients remain unstructured, show the original lines and require/manual-enable conversion rather than inventing quantities.

## 25. Time, Difficulty, Categories, and Tags

Time fields:

- Preparation time
- Cooking time
- Total time
- Unknown time

Use source total time when available. Do not silently calculate or invent time. User-confirmed edits become the values used by planning.

Difficulty:

- Easy
- Medium
- Hard
- Unknown

Unknown is never silently converted to Easy.

Categories/tags may include:

- Chicken
- Beef
- Fish
- Vegetarian
- Pasta
- Rice
- Breakfast
- Quick
- Oven
- Soup
- Salad
- International
- One-pot
- Meal prep
- High effort
- Family-style

Unknown categories remain editable instead of being forced into an inaccurate category.

## 26. Search

Local search includes:

- Recipe title
- Ingredient name
- Category
- Cuisine
- Tags
- Source title
- User notes

Search works offline, tolerates basic capitalization differences, distinguishes drafts, and displays recipe origin.

## 27. Analytics

### Import events

- import_started
- import_input_received
- import_extraction_started
- import_extraction_completed
- import_extraction_failed
- import_review_opened
- import_review_edited
- import_draft_saved
- import_saved
- import_cancelled
- import_duplicate_detected
- import_manual_fallback_used
- import_source_opened

### Outcome events

- imported_recipe_viewed
- imported_recipe_favorited
- imported_recipe_added_to_plan
- imported_recipe_replaced
- imported_recipe_cooked
- imported_recipe_feedback_given
- imported_recipe_deleted

Analytics must not contain full recipe text, ingredient lists, private messages, social credentials, or sensitive source content.

## 28. V3 Success Metrics

These are initial beta targets, not permanent product truths.

### Activation

- 40%+ of beta users attempt one import.
- 70%+ of started imports reach review.
- 60%+ of review sessions save a recipe.

### Data quality

- 80%+ of saved imports require no major correction after review.
- Fewer than 10% of saved imports are reported unusable.
- Every failed automatic import has a manual fallback.

### Usage

- 30%+ of imported recipes are reopened within 14 days.
- 25%+ are added to a weekly plan.
- 20%+ are cooked within 30 days.
- 15%+ receive explicit feedback.

### Product value

Measure whether importing is easier than manual recreation, whether imported recipes contribute to grocery usage, and whether they preserve V1/V2 planning reliability.

## 29. V3 Beta Plan

### Participants

- 30 users
- 15+ existing V2 users
- 15+ new users
- Mix of social-media recipe savers and website-recipe users

### Duration

21 days.

### Required actions

Each participant should:

- Import at least 2 recipes
- Complete review
- Correct at least one import where necessary
- Add at least one imported recipe to a weekly plan
- Generate a grocery list containing an imported recipe
- Cook at least one imported recipe
- Give feedback
- Attempt one difficult or incomplete source

### Beta questions

- Was Share Sheet easy to understand?
- Did extraction save time?
- Were quantities reliable?
- Were instructions complete?
- Did users trust review?
- Did imported recipes enter real weekly plans?
- Did grocery lists need too much correction?
- Which sources failed most often?
- Which import method was preferred?

## 30. Definition of Done

### Import

- Share Sheet accepts URL/text.
- URL paste works.
- Text paste works.
- Manual entry works.
- Unsupported sources have fallback.
- Cancellation works.
- Timeout works.
- Network failure is handled.

### Extraction

- JSON-LD extraction works.
- Basic metadata extraction works.
- Visible-text fallback exists where feasible.
- Uncertainty is visible.
- No missing data is silently invented.

### Review

- Title editable.
- Ingredients editable.
- Instructions editable.
- Time/servings editable.
- Source visible.
- Warnings visible.
- Save requires confirmation.
- Drafts can be preserved.

### Data and behavior

- Recipe origin stored.
- Source URL stored when available.
- Import status stored.
- Grocery compatibility preserved.
- Meal Memory compatibility preserved.
- Existing built-in recipes continue to work.
- Duplicate detection works.
- Imported recipes can be planned, cooked, rated, edited, and deleted.
- Re-import never silently overwrites user edits.

### Quality

- Extraction normalization tests.
- Duplicate detection tests.
- Ingredient parsing tests.
- Import state tests.
- Failed import tests.
- Grocery regression tests.
- Meal Memory regression tests.
- V1/V2 regression tests.

## 31. Suggested Architecture

```text
Core/
  Models/
    Recipe.swift
    RecipeIngredient.swift
    RecipeInstruction.swift
    RecipeImport.swift
    RecipeImportDraft.swift
    RecipeOrigin.swift
    RecipeSourcePlatform.swift

  Services/
    RecipeImportService.swift
    RecipeExtractionService.swift
    RecipeNormalizationService.swift
    RecipeValidationService.swift
    RecipeDuplicateService.swift
    RecipeDraftService.swift
    RecipeSourceService.swift

  Utilities/
    URLNormalizer.swift
    TimeParser.swift
    ServingParser.swift
    IngredientParser.swift

Features/
  RecipeImport/
    ImportEntryView.swift
    ImportReviewView.swift
    ImportDraftView.swift
    ImportErrorView.swift
    ImportViewModel.swift

  Recipes/
    ImportedRecipesView.swift
    RecipeFiltersView.swift

  MealPlanning/
    ImportedRecipePlanningAdapter.swift
```

Follow the existing project structure where appropriate, but keep import logic separated from UI code.

## 32. Development Phases / Commits

### Phase 1 — Data model and import session

```text
feat: add recipe import data models
```

- Recipe origin
- Source metadata
- Import status
- Draft/import session
- SwiftData migration
- Existing recipe compatibility

### Phase 2 — Manual import

```text
feat: add manual recipe import flow
```

- Manual entry
- Ingredient editor
- Instruction editor
- Validation
- Persistence

Implement the fallback first so automatic extraction never becomes the only path.

### Phase 3 — URL + structured extraction

```text
feat: add structured recipe url extraction
```

- URL validation
- Network loading
- Timeout/cancellation
- JSON-LD extraction
- Normalization
- Error states

### Phase 4 — Review and drafts

```text
feat: add recipe import review and drafts
```

- Review screen
- Warnings
- Draft persistence
- Resume import
- Corrections
- Save confirmation

### Phase 5 — Share Sheet

```text
feat: add recipe share sheet import
```

- Share extension
- URL payload
- Text payload
- Unsupported content handling
- Single-item flow

### Phase 6 — Duplicate detection and re-import

```text
feat: add imported recipe duplicate handling
```

- URL normalization
- Duplicate matching
- Duplicate review
- Re-import comparison
- User-edit preservation

### Phase 7 — Planning, grocery, Meal Memory

```text
feat: integrate imported recipes with planning and memory
```

- Planning eligibility
- V2 scoring integration
- Grocery conversion
- Meal Memory events
- Smart replacement compatibility
- Library filters

### Phase 8 — Beta

```text
chore: prepare MealRoutine V3 beta
```

- Analytics
- Regression tests
- Import error review
- Performance checks
- Privacy checks
- Beta onboarding
- Feedback collection

## 33. Main Risks

### Social platforms do not expose full recipe data

Treat social URLs as source references, support pasted text, provide manual entry, and never promise universal automatic extraction.

### Incorrect ingredient parsing

Preserve original text, mark uncertain fields, require review, never invent quantities, and allow manual correction.

### Import flow becomes too complicated

Keep the main flow short and put advanced corrections in the review screen.

### Imported recipes increase planning noise

Do not treat imports as favorites automatically. Use import interest as a weak discovery signal and let explicit feedback dominate.

### Grocery quality decreases

Use structured ingredients, preserve uncertainty, avoid false aggregation, and allow manual correction.

### Copyright/source attribution issues

Preserve source URLs, avoid public redistribution, do not unnecessarily copy source images, and do not present imported recipes as MealRoutine-authored content.

### V3 becomes an uncontrolled AI project

Use deterministic extraction first. AI is not required. Never save unreviewed generated data. Prefer a reliable fallback over a complex parser.

## 34. V3 Product Boundary

V3 ends when a user can reliably:

1. Share or paste a recipe source.
2. Import the available content.
3. Review and correct it.
4. Save it locally.
5. Find it in the recipe library.
6. Add it to a weekly plan.
7. Generate a grocery list.
8. Cook it.
9. Give feedback.
10. Have it participate in Meal Memory.

V3 does not solve household decision-making, shared accounts, collaborative planning, pantry intelligence, budget optimization, public recipe sharing, automatic nutrition analysis, or universal extraction from every social platform.

## 35. Final V3 Principle

The goal of V3 is not to build a universal recipe scraper.

The goal is to remove the distance between:

> “I saw a recipe I want to try”

and

> “That recipe is now part of my weekly meal routine.”

The feature succeeds when saved recipes become usable, planned, cooked, and learned from by MealRoutine.
