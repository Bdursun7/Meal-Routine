# MealRoutine v1.0 — Teknik Rapor

**Kaynak depo:** `Bdursun7/Meal-Routine`  
**Ref:** `v1.0` (commit `4e8c0820f7b3d7f1e46fdf0b437557fe71fd1aa3`, `main` ile aynı)  
**Yöntem:** GitHub API `get_file_contents` / `get_git_tree` (klon yok)  
**Tarih:** 2026-09-24 (Europe/Istanbul)

---

## 1. Özet ve kapsam

### V1 ne
MealRoutine, iOS üzerinde çalışan kişisel bir **akşam yemeği planlayıcıdır**. Ürün cümlesi: “Haftan, önceden planlı.” Arayüz Türkçe-öncelikli (TR-first); veri **cihazda** SwiftData ile tutulur. V1’de hesap, sunucu, reklam, ödeme duvarı ve LLM çağrısı yoktur.

Kullanıcı onboarding’de ev halkı / akşam sayısı / süre / sevmediği malzemeler / isteğe bağlı tat puanlarını verir; “Haftamı oluştur” ile deterministik `MealRecommender` haftayı doldurur. Dört sekme: **Bu Hafta**, **Tarifler**, **Market**, **Profil**. Pişirme sonrası Sevdim / İdare eder / Bir daha asla puanı sonraki haftaların skorunu etkiler. Market listesi planlı yemek malzemelerini UniTools `ingredientId` üzerinden birleştirir.

Tek ağ kullanımı: katalogdaki HTTPS tarif fotoğrafı, disk önbelleğinde yoksa indirilir. Hafta planı, market ve pişirme akışları ağı beklemez.

### V1 ne değil
- Backend / auth / çok cihaz senkronu / CloudKit (`cloudKitDatabase: .none`)
- TestFlight veya App Store CI/CD hattı (repoda workflow yok)
- Kullanıcı tarif ekleme-düzenleme
- Kahvaltı / öğle / çok öğün planı (`PlannedMeal.slot` sabit `"evening"`)
- Canlı analytics SDK veya kimlikli olay gönderimi
- Katalogda “yalnızca TR mutfağı” kilidi (125 dünya yemeği; `trDogfoodScore` ile TR dogfood ağırlığı)
- İngilizce UI locale (developmentLanguage `tr`)

### Platform ve stack
| Alan | Değer |
|------|--------|
| OS | iOS **18.0+** |
| Cihaz | iPhone + iPad (`TARGETED_DEVICE_FAMILY: 1,2`) |
| Dil / UI | Swift 5, SwiftUI, SwiftData |
| Bundle ID | `com.mealroutine.app` |
| Sürüm | MARKETING_VERSION `1.0.0`, CURRENT_PROJECT_VERSION `1` |
| Proje | Checked-in `MealRoutine.xcodeproj`; isteğe bağlı XcodeGen `project.yml` |
| Orientasyon | Portrait (iPad + upsideDown) |
| Encryption beyanı | `ITSAppUsesNonExemptEncryption: NO` |
| Privacy | `PrivacyInfo.xcprivacy`: `NSPrivacyTracking=false`, collected data boş, accessed API boş |

---

## 2. Mimari genel bakış

### Katmanlar
| Katman | Path | Rol |
|--------|------|-----|
| App | `MealRoutine/App/` | `@main`, ModelContainer, RootView, MainTabView |
| Features | `MealRoutine/Features/{Onboarding,ThisWeek,Recipes,Grocery,Profile}/` | Ekran + `@Observable` ViewModel |
| Services | `MealRoutine/Services/` (+ `Catalog/`) | Plan, öneri, market, seed, foto, analytics |
| Models | `MealRoutine/Models/` | SwiftData `@Model` |
| Design | `MealRoutine/Design/` | Theme token, FlowLayout, chip/button/empty state |
| Recipes | `MealRoutine/Recipes/` | Paketlenmiş JSON + TR alias |
| Support | `MealRoutine/Support/` | Takvim, formatlayıcılar, aisle, Attribution, RecipeRoute |
| Assets | `MealRoutine/Assets.xcassets/` | AppIcon, AppIconMark, AccentColor |

### Başlatma
1. `MealRoutineApp.init` → `ModelContainerFactory.make()`; hata → `fatalError`.
2. `RootView`:
   - `task`: `RecipeSeedService.seedIfNeeded`
   - seeding UI: “Tarifler yükleniyor…”
   - hata: “Katalog açılamadı” + Tekrar dene
   - `UserPrefs.hasCompletedOnboarding` → `MainTabView` else `OnboardingView`
   - `onAppear`: `Analytics.trackOnce(.appOpened)`
3. `MainTabView`: TabView — Bu Hafta / Tarifler / Market / Profil; tint `Theme.accent`.

### Bağımlılık yönü
Features → Services → Models. SwiftData `@Query` Features’ta; yazma Services’te (`@MainActor`). ViewModel’ler `@Observable` + `@MainActor`.

---

## 3. Veri modeli (SwiftData)

Schema kaydı: `ModelContainerFactory` — `Recipe`, `IngredientLine`, `RecipeStep`, `PlanWeek`, `PlannedMeal`, `GroceryItem`, `IngredientCheck`, `UserPrefs`, `RecipeFeedback`, `CatalogImportState`.

### Recipe (`Models/Recipe.swift`)
Akşam yemeği kataloğu satırı. `slug` unique (= JSON `id`).

Önemli alanlar: `nameEN`/`nameTR`/`nativeName`, `summaryEN`/`summaryTR`, `country`, `category` (genelde `dinner`), `unitoolsCategory` (course / çeşitlilik), `diets`, `difficulty`, `baseServings`, `prepMinutes`/`cookMinutes`/`totalMinutes`, `tags`, `trDogfoodScore`, `hardIngredientPenalty`, besin (`calories`/`protein`/`fat`/`carbs`), `sourceProvider`/`sourceLicense`/`sourceAttribution`, `photoURL`/`photoAuthor`/`photoLicense`.

İlişkiler: `ingredients: [IngredientLine]` cascade inverse `recipe`; `steps: [RecipeStep]` cascade.  
Hesaplanan: `displayName`, `displaySummary` (TR tercih), `ingredientIDs: Set`.

### IngredientLine
`ingredientId` (UniTools merge anahtarı), `nameEN`/`nameTR`, `quantity: Double?`, `unit`, `scaling` (`linear`|`damped`|`fixed`), `note`/`noteTR`, `trAliasCurated`, `sortIndex`, `recipe?`.  
`displayName` / `displayNote`: TR yoksa EN.

### RecipeStep
`textEN`/`textTR`, `minutes?`, `sortIndex`, `recipe?`. UI: `displayText` TR öncelikli.

### PlanWeek
`uuid`, `weekStart` (Pazartesi gün başı), `createdAt`, `householdSize`.  
`meals: [PlannedMeal]` cascade; `groceries: [GroceryItem]` cascade.

### PlannedMeal
`uuid`, `dayOffset` (0=Pzt), `slot` (default `"evening"`), `recipeSlug`, `servings` (akşam override; 1–8), `cookedAt?`, `week?`.  
`servings` yok/≤0 sayılırsa household kullanılır (`ActiveServings`).

### GroceryItem
`uuid`, `ingredientId`, `nameTR`/`nameEN`, `quantity?`, `unit`, `hasUnitConflict`, `isChecked`, `isManual`, `quantityIsCustom` (default false), `uncoveredQuantity?` (kısmi cover), `week?`.  
Manuel: `ingredientId = "manual:<UUID>"`.

### IngredientCheck
`mealUUID: UUID?` — **nil** ise yalnız tarif ekranı (Market etkilenmez); set ise planlı akşam.  
`recipeSlug`, `ingredientId`, `sortIndex`, `isChecked`, `coveredQuantity?`, `unit`.  
Porsiyon değişince `GroceryCoverage.stillCovers` false → check düşer.

### UserPrefs
Tek yerel profil: `householdSize`, `eveningsPerWeek`, `maxCookMinutes`, `dislikedIngredientIds`, `hasCompletedOnboarding`, `createdAt`.  
Okuma: `UserPrefsStore.existing` → `createdAt` en eski kayıt. Varsayılan init: 2 kişi, 5 akşam, 60 dk.

### RecipeFeedback
`uuid`, `recipeSlug`, `ratingRaw`, `cooked`, `createdAt`.  
`FeedbackIndex.latestRatings`: aynı slug için en yeni `createdAt` kazanır.

### CatalogImportState
`fingerprint`, `importedAt`. Store silinince gate de silinir.

### MealRating (Codable enum)
`loved` / `okay` / `never` — UI: Sevdim / İdare eder / Bir daha asla.

---

## 4. Paketlenmiş katalog ve seed

### Dosyalar
- `MealRoutine/Recipes/recipes.v1.json` — **125** tarif, `schemaVersion: 1`, `app: "MealRoutine"`.
- `MealRoutine/Recipes/ingredient-aliases.tr.json` — `locale: "tr"`, `aliases` map; seed’de `name.tr` boşsa fallback.

### JSON yapı (örnek `menemen`)
Üst alanlar: `id`, `source{provider,slug,license,attribution,licenseUrl,landingPage}`, `name`/`summary` `{en,tr}`, `nativeName`, `country` (`TR`), `category` (`dinner`), `unitoolsCategory` (`breakfast` vb.), `diets`, `difficulty`, `baseServings`, `prep/cook/totalMinutes`, `tags` (ör. `quick`,`spicy`,`one-pan`), `trDogfoodScore` (ör. 91), `hardIngredientPenalty`, `nutritionPerServing`, `ingredients[]`, `steps[]`, `photo?`, `feedbackDefaults?`.

Malzeme satırı: `id`, `name{en,tr}`, `quantity`, `unit`, `scaling`, `note{en,tr}?`, `trAliasCurated`.  
Adım: `text{en,tr}`, `minutes?`.  
Foto örnek: `url: https://theunitools.com/recipes/menemen.jpg`, `author`, `license: CC BY-SA 4.0`.  
İstatistik: ~103 tarifte foto, ~22’de `photo` null.  
Katalog birimleri (tam 12): `g`,`kg`,`ml`,`l`,`piece`,`tbsp`,`tsp`,`clove`,`toTaste`,`sprig`,`pinch`,`slice`.

DTO decode: `RecipeCatalogDTO.swift` — `FlexibleJSONNumber` (int/double quantity); note hem LocalizedText hem düz string kabul.

### Seed akışı (`RecipeSeedService`)
1. `RecipeCatalogLoader.loadBundled` → Data + fingerprint; şema ≠ 1 → `CatalogError.unsupportedSchema`.
2. Skip koşulu (`CatalogFingerprint.shouldSkipImport`): store count > 0 **ve** count == katalog count **ve** saklanan fingerprint == güncel.
3. Import: tüm Recipe sil → save (unique slug çakışması önleme) → her DTO insert (alias + `RecipePhoto.persisted`) → `CatalogImportState` yaz → save.
4. `PlanIntegrityService.repair` — orphan `recipeSlug`.
5. `GroceryListService.rebuild` (her launch; fingerprint skip ile ucuz).

**Fingerprint:** `"\(schemaVersion):\(fnv1a64Hex(fileBytes))"`. FNV-1a 64 (offset `0xcbf29ce484222325`, prime `0x100000001b3`). Aynı boyutlu byte değişimi yeniden import eder.

Kaynak çözüm: bundle `Recipes/` alt dizini veya düz kök (Xcode group flatten).

### CC BY-SA
`Attribution.uniTools` sabit metin (About + README). Veri seti türevleri CC BY-SA 4.0; uygulama kodu ayrı lisanslanabilir. Foto URL/yazar/lisans katalogdan; UI invent etmez. EN metinler orijinal; TR yerelleştirme.

---

## 5. Tercihler ve onboarding

Dosyalar: `Features/Onboarding/OnboardingView.swift`, `OnboardingViewModel.swift`.

### Adımlar
| Enum | Progress | UI |
|------|----------|-----|
| `welcome` | — | Hero, 3 bullet, “Kuruluma başla” → analytics `onboardingStarted` |
| `slogan` | — | AppIconMark 112pt + sabit slogan; “Devam” |
| `household` | 1/4 | Ev halkı stepper, akşam chip’leri, süre chip’leri |
| `dislikes` | 2/4 | En çok görülen 24 malzeme chip (pantry hariç) |
| `taste` | 3/4 | trDogfoodScore’a göre top 8; Sevdim/İdare/Asla; “Atla” |
| `summary` | 4/4 | Özet satırları + Düzenle; “Haftamı oluştur” |

Slogan progress’e dahil değil (`progressTotal = 4`). Özetten Düzenle → `editingFromSummary`; sonraki Devam/Atla özete döner.

### Kilitlemeler
- **householdSize:** `HouseholdSizeLimits` **1…8**.
- **evenings:** `EveningCountOptions` **1…5**; etiket `"N akşam"`.
- **maxCookMinutes:** **[30, 45, 60, 90]**, **default 60**; `CookTimeOptions.resolved` liste dışı → 60.
- **Yumurta chip:** `DislikeChipMerge.groups` — chipID `egg`, name “Yumurta”, ids `["egg","eggs"]`; toggle her iki id’yi prefs’e yazar.
- Pantry (chip üretilmez): `salt`,`oil`,`pepper`,`water`,`blackpepper`,`black-pepper`.

### finish(in:)
1. UserPrefs insert/update; `hasCompletedOnboarding` henüz false.
2. Taste → yeni `RecipeFeedback` (değişenler).
3. `WeekPlanService.replaceCurrentWeek(planRequest)`.
4. Planlı meal sayısı 0 → haftayı sil, hata: süre yükselt / dislike azalt.
5. `GroceryListService.rebuild`; `hasCompletedOnboarding = true`; `onboardingCompleted`.

---

## 6. Hafta planlama

### Takvim (`Support/WeekCalendar.swift`)
ISO8601, cihazın firstWeekday’inden bağımsız **Pazartesi** başlangıç. `dayNames`: Pazartesi…Pazar. `shortDate`: Bugün veya `d MMM` (tr_TR).

### ensureCurrentWeek / replaceCurrentWeek (`WeekPlanService`)
- `currentWeek`: `weekStart == WeekCalendar.weekStart(now)`.
- `ensureCurrentWeek`: yoksa ve onboarding tamamsa `replaceCurrentWeek`.
- `replaceCurrentWeek`:
  1. Eski hafta varsa meal sighting’leri `MealExposureLog.record`; meal’e bağlı `IngredientCheck` sil; meal+grocery+week sil; **save**.
  2. Candidate’lar: tüm Recipe + `FeedbackIndex.latestRatings` → `pickerCandidates` (protein = `MealRecommender.proteinFamily(ordered ingredient ids)`, category = `unitoolsCategory` boşsa `category`).
  3. `recentSightings`: mevcut PlannedMeal (cookedAt veya plan tarihi) + cooked feedback + `MealExposureLog.load()`.
  4. `MealRecommender.pick` → yeni PlanWeek; her slug için PlannedMeal (`dayOffset` sırayla, `servings = householdSize`, `cookedAt = nil`).
  5. `Analytics.planGenerated`.

`ThisWeekView.onAppear`: `ensureWeek` + grocery rebuild; `planViewed`. Boş state: “Planı yeniden kur” → `regenerate`.

### MealRecommender pipeline (`Services/MealRecommender.swift`)

Sabitler:
- `eveningCap = 5`, `recencyWindowDays = 21`, `secondsPerDay = 86400`
- `lovedBoost = 56`
- `plannedPenaltyCap = 62`, `cookedPenaltyCap = 78`
- `sameCuisinePenalty = 18`, `similarCuisinePenalty = 10`, `sameCategoryPenalty = 8`, `sameProteinPenalty = 18`, `sharedTagPenalty = 14`, `diversityPenaltyCap = 140`

Sıra:
1. **Hard filter** (`passesFilters`): `totalMinutes ≤ maxCookMinutes`, slug blocked değil, `rating != .never`, `ingredientIds ∩ disliked = ∅`.
2. **Curation:** `trDogfoodScore`.
3. **Loved:** rating loved ise +56 (ayrı sort değil; skor boost).
4. **Recency:** 21 günde linear fade; age≤0 → full cap; age≥window → 0; integer rounding `(cap * remaining + window/2) / window`. Aynı slug için max penalty (cooked vs planned).
5. **Diversity:** her anchor için ülke (aynı / `cuisineRegion` benzeri), category, protein, paylaşılan tag sayısı × 14; toplam ≤ 140.
6. **Greedy fill:** en yüksek `total` seç → anchor’a ekle → tekrar; tie → slug ascending. **Random yok.**

Protein aileleri: chicken→poultry; beef/lamb/pork…→red-meat; fish/salmon…→seafood; egg/eggs→egg; lentils/chickpeas→legume; tofu; paneer/feta…→dairy. İlk eşleşen id kazanır.

Bölgeler: TR/GR/IT…→mediterranean; BG/RS…→balkan; LB/EG…→mena; IN/PK…→south-asia; CN/JP…→east-asia; vb.

### MealExposureLog
Key: `mealroutine.recentMealExposures.v1` (UserDefaults string array).  
Encode: `slug\t<unixSeconds>\t0|1`.  
Hafta silindiğinde / Değiştir ile slug üzerine yazıldığında uncooked plan SwiftData’dan kaybolur; log recency’yi korur. Merge: pencere dışı düş, slug başına `recencyPenalty` daha yüksek olanı tut.

### Replace meal
**Otomatik** `replaceMeal(uuid:)`: haftadaki tüm slug’lar exclude + anchor; 1 pick; yoksa `WeekPlanError.noAlternative`.

**Sheet** (`MealReplacement` + `MealReplacementView`): chip’ler `faster` / `different` / `noChicken` / `vegetarian` / `loved` / `surprise` (surprise diğerlerini temizler). Hard filter aynı; soft chip filtreleri; rank breakdown; max **8**; surprise = `stableIndex(slug unicode sum % count)`, gerekirse 2. eleman.  
Seçim → `replaceMeal(uuid:with:)`: filtre kontrol, duplicate yasak, outgoing exposure, meal checks sil, slug değiştir, cookedAt nil, `mealReplaced`.

### Cook state
- `markCooked`: `cookedAt` yalnızca nil iken set; `mealCooked`.
- Detay: `allowsCookBar` yalnız Bu Hafta `navigationDestination`; meal bu haftanın `weekStart`’ına ait olmalı.
- “Bunu pişirdim” → prompt; **Vazgeç** → ne cookedAt ne feedback.
- Kayıt: markCooked + `recordFeedback(cooked:true)` + rated/feedback/loved|disliked.
- Favori kalp: `setFavorite` loved↔okay, cooked false.

### PreferenceInsight
≥3 loved feedback; 21g penceresinde baskın protein (≥2) → “Son zamanlarda N tavuk/…” kartı Bu Hafta’da.

### Hafta rollover
Yeni Pazartesi: `ensureCurrentWeek` yeni PlanWeek üretir. Eski PlanWeek store’da kalabilir. Orphan: mevcut hafta regenerate (onboarding tamamsa, manual grocery snapshot restore); diğer haftalar orphan meal sil.

---

## 7. Market / grocery

### Rebuild (`GroceryListService`)
1. currentWeek + prefs yoksa return.
2. `inputFingerprint` (household, weekStart, meals, checks, custom qty) == `appliedFingerprint` → skip.
3. Her meal: `ActiveServings.resolve` → her ingredient `PortionScaler.scale` → source + contribution.
4. `reconcileStoredChecks`: meal artık yoksa veya satır kaybolduysa sil; miktar kaydıysa uncheck.
5. `GroceryMerger.merge` → `GroceryListReconciler.plan`.
6. Her satır için `GroceryCoverage.outcome` → `isChecked` / `uncoveredQuantity`.
7. Save + fingerprint güncelle. Katalog/reset sonrası `discardRebuildCache()`.

### Merge (`GroceryMerger` + `UnitNormalization`)
- Group by `ingredientId`.
- Unit fold (harf/rakam, TR diacritic fold): g/gr/gram…, kg…, ml…, l/lt…, piece/adet, tbsp/yemek kaşığı/yk, tsp/tatlı kaşığı/tk, clove/diş, pinch/tutam, slice/dilim, sprig/dal, toTaste/damak tadına.
- **Çapraz çeviri yalnız** mass (g base) ve volume (ml base). Aynı ailede karışık kod → base’e çevir → ≥1000 ise kg/l göster.
- Tek kodlu bucket kendi kodunda kalır (yalnız g’ler toplamı g kalır).
- Birden fazla bucket → her biri ayrı `MergedGroceryLine`, `hasUnitConflict=true`.
- `rowIdentity`: `ingredientId|family:mass|volume` veya `unit:<code>` — rebuild’de g↔kg aynı satır kimliği.

### PortionScaler
- `linear`: q × (active/base)
- `damped`: q × √(active/base)
- `fixed` / diğer default linear; `fixed` değişmez  
`ActiveServings`: mealServings>0 → clamp; else household clamp 1…8.

### Coverage ↔ ingredient check
- Tarif checkbox → `setIngredientCheck` + `applyCoverage` (mealUUID set ise).
- `mealUUID == nil` → Market’e yazılmaz.
- Kısmi: 3/5 domates işaretli → satır unchecked, `uncoveredQuantity`≈2, UI “… kaldı”.
- Market toggle: satırın contribution’larının hepsine check yazar; tüm satırlar checked → `groceryListCompleted`.
- Custom qty: rebuild saklar; görünen miktar değişince check düşer (`GroceryCheckState`).

### UI
`GroceryViewModel.presentation`: açık satırlar `GroceryCategory.sectionOrder` (Sebze ve meyve → Protein → Süt ve yumurta → Kiler → Baharat ve soslar → Diğer); checked ayrı.  
Search: isim veya aisle title. Manuel ekle (unit listesi piece/g/kg/ml/l/tbsp/tsp/clove/toTaste), sil, miktar edit (`1,25` kabul).

---

## 8. Tarifler

### Browse
`RecipeBrowseCategory`: all, chicken(poultry), beef(red-meat), fish(seafood), vegetarian(vegan|vegetarian), pasta(tag), rice(tag), quick(tag veya ≤30dk), oven(tag `bake`).  
`RecipeCookTimeFilter`: any / ≤30/45/60/90.  
lovedOnly; search: displayName, nameEN, country, tags. Sort: localizedDisplayName, slug.  
Favori: `WeekPlanService.setFavorite`.

### RecipeDetail
Hero (`RecipePhotoView` .hero) + “Fotoğraf: author · license” + Attribution; özet; diets; porsiyon stepper + kaydet; malzemeler (ölçekli + MealCheckBox); adımlar.  
Porsiyon kaydet: mealUUID varsa yalnız o akşam; yoksa household + açık haftanın tüm meals + rebuild.  
**Cook bar:** `allowsCookBar && currentWeekCookMeal != nil`. Tarifler/Profil history: `allowsCookBar: false`.  
Mevcut puan satırı + “Puanı değiştir”. `recipeOpened` onAppear.

### Foto cache
`RecipePhotoDiskCache`: Caches/`RecipePhotos`/`{fnv1a64(urlString)}.img`.  
`RecipePhotoLoader`: URLCache kapalı, timeout 20/30s, UA `MealRoutine/1.0`, Accept image/*, max 8MB, magic JPEG/PNG/GIF/WebP, HTTPS only. Fail → placeholder; plan/market beklemez. ~14MB tam katalog tahmini.

---

## 9. Profil

| Bölüm | İşlev |
|------|--------|
| Ev | Stepper/picker; **Porsiyonu kaydet** (`PortionSaveService.saveHouseholdSize` + evenings/cook prefs); **Bu haftayı yeniden kur** (prefs save + replaceCurrentWeek + rebuild) |
| Sevmediğin malzemeler | İsim listesi; **Kurulumu tekrar aç** |
| Pişirme ve puanlar | CookingHistoryView (cooked feedback, tarih+puan); RatedRecipesView loved / never |
| Katalog | `recipes.count`; öneri açıklaması |
| Uygulama | `AppAppearance` (`mealroutine.appearance`); PrivacyView; **Yerel veriyi sıfırla** |
| Hakkında | Attribution, linkler, foto notu, sürüm |

**resetLocalData:** rebuild cache discard; tüm PlanWeek (cascade); orphan meal/item; RecipeFeedback; IngredientCheck; UserPrefs; `UserDefaults` exposure key; **Recipe + CatalogImportState kalır**.

PrivacyView metni: hesap/bulut yok; konum yok; foto cache; analytics yerel; sıfırlama kapsamı.

---

## 10. Tema / tasarım token’ları

`Design/Theme.swift` + AccentColor asset:

| Token | Hex / değer |
|-------|-------------|
| Accent (terracotta) | **#C4622D** — CTA, tab tint, seçili chip |
| bgCream light | **#F8F4ED** |
| bgCream dark | **#1C1916** |
| cardSurface light | **#FFFCF7** |
| cardSurface dark | **#2A2622** |
| textCharcoal light | **#2C2A26** |
| textCharcoal dark | **#F7F3EC** |
| sage | **#8FA88A** — progress / başarı (primary değil) |
| Radius | card 22, chip 14, button 16, hero 24, sheet 28 |
| Spacing | screenPadding 20, cardGap 16, sectionGap 28 |

Bileşenler: `FilterChip`, `ThinSageProgress`, `PrimaryButtonStyle`, `MealCheckBox`, `WarmEmptyState`, `mealCardSurface` / `mealCanvas` / `mealAppearance`.  
AppIcon: 1024 universal PNG; in-app `AppIconMark` (AppIcon named UIImage iOS’ta boş).

---

## 11. Analytics (stub)

`Services/Analytics.swift` — ağ yok, SDK yok.

| Event rawValue | Tetik |
|----------------|--------|
| `app_opened` | RootView once |
| `onboarding_started` / `_completed` | Onboarding |
| `plan_generated` / `plan_viewed` | replace / ThisWeek appear |
| `meal_replaced` / `meal_cooked` / `meal_feedback_given` | replace / cook / rate |
| `recipe_opened` / `recipe_rated` / `recipe_loved` / `recipe_disliked` | detail / feedback |
| `grocery_opened` / `grocery_item_checked` / `grocery_list_completed` | Market |

Buffer 200; `os_log`; sanitize: name/email/phone/address key drop, value ≤40 char.

---

## 12. Testler / Tools scriptleri

Xcode test target yok. Repo kökünden çalışan kontroller:

| Araç | Ne doğrular |
|------|-------------|
| `Tools/catalog_integrity_check.py` | FNV vektörleri, fingerprint skip, orphan decide, 125 TR summary/step/note, tag==`recipe_tags.assign_tags`, Swift seed gate |
| `Tools/recipe_tags.py` | ALLOWLIST (quick…stuffed), `--write` ile JSON tags |
| `run_recommender_checks.sh` + `meal_recommender_checks.swift` | Rank / filter / exposure / tags |
| `run_grocery_checks.sh` + `grocery_merge_checks.swift` | Unit synonym, merge, aisle |
| `run_portion_checks.sh` + `portion_scale_checks.swift` | linear/damped/fixed |
| `run_recipe_photo_checks.sh` + `recipe_photo_checks.swift` | URL/cache/magic |
| `run_product_gap_checks.sh` + `product_gap_checks.swift` | Ürün boşlukları |

---

## 13. Bilinçli V1 dışı / park edilmiş konular

- Backend, login, sync, CloudKit
- TestFlight / App Store pipeline
- TR-only catalog filter (skor var, ülke kilidi yok)
- Kullanıcı tarif CRUD; LLM; gerçek analytics sink
- Reklam / paywall
- Çok öğün / kahvaltı planı (unitoolsCategory breakfast olsa da slot evening)
- SwiftData migration ihtiyacı (foto alanları zaten modelde; re-seed fingerprint ile)
- Widget, Live Activity, push
- EN UI localization

---

## 14. Dosya envanteri

```
README.md
project.yml
MealRoutine.xcodeproj/project.pbxproj
MealRoutine/PrivacyInfo.xcprivacy
MealRoutine/App/MealRoutineApp.swift
MealRoutine/App/RootView.swift
MealRoutine/App/MainTabView.swift
MealRoutine/App/ModelContainerFactory.swift
MealRoutine/Design/Theme.swift
MealRoutine/Design/FlowLayout.swift
MealRoutine/Models/Recipe.swift
MealRoutine/Models/IngredientLine.swift
MealRoutine/Models/RecipeStep.swift
MealRoutine/Models/PlanWeek.swift
MealRoutine/Models/PlannedMeal.swift
MealRoutine/Models/GroceryItem.swift          # + IngredientCheck
MealRoutine/Models/UserPrefs.swift
MealRoutine/Models/RecipeFeedback.swift
MealRoutine/Models/MealRating.swift
MealRoutine/Models/CatalogImportState.swift
MealRoutine/Services/MealRecommender.swift
MealRoutine/Services/WeekPlanService.swift
MealRoutine/Services/MealReplacement.swift
MealRoutine/Services/MealExposureLog.swift
MealRoutine/Services/GroceryListService.swift
MealRoutine/Services/GroceryMerger.swift
MealRoutine/Services/GroceryListReconciler.swift
MealRoutine/Services/UnitNormalization.swift
MealRoutine/Services/PortionScaler.swift
MealRoutine/Services/PortionSaveService.swift
MealRoutine/Services/RecipeSeedService.swift
MealRoutine/Services/PlanIntegrityService.swift
MealRoutine/Services/RecipeBrowse.swift
MealRoutine/Services/RecipePhoto.swift
MealRoutine/Services/RecipePhotoLoader.swift
MealRoutine/Services/Analytics.swift
MealRoutine/Services/FeedbackIndex.swift
MealRoutine/Services/PreferenceInsight.swift
MealRoutine/Services/UserPrefsStore.swift
MealRoutine/Services/GroceryQuantityEdit.swift
MealRoutine/Services/Catalog/RecipeCatalogDTO.swift
MealRoutine/Services/Catalog/RecipeCatalogLoader.swift
MealRoutine/Services/Catalog/CatalogIntegrity.swift
MealRoutine/Features/Onboarding/OnboardingView.swift
MealRoutine/Features/Onboarding/OnboardingViewModel.swift
MealRoutine/Features/ThisWeek/ThisWeekView.swift
MealRoutine/Features/ThisWeek/ThisWeekViewModel.swift
MealRoutine/Features/ThisWeek/MealReplacementView.swift
MealRoutine/Features/Recipes/RecipeListView.swift
MealRoutine/Features/Recipes/RecipeListViewModel.swift
MealRoutine/Features/Recipes/RecipeDetailView.swift
MealRoutine/Features/Recipes/RecipeDetailViewModel.swift
MealRoutine/Features/Recipes/CookRatingPrompt.swift
MealRoutine/Features/Recipes/RecipePhotoView.swift
MealRoutine/Features/Grocery/GroceryView.swift
MealRoutine/Features/Grocery/GroceryViewModel.swift
MealRoutine/Features/Profile/ProfileView.swift
MealRoutine/Features/Profile/ProfileViewModel.swift
MealRoutine/Features/Profile/PrivacyView.swift
MealRoutine/Support/WeekCalendar.swift
MealRoutine/Support/Formatters.swift
MealRoutine/Support/GroceryCategory.swift
MealRoutine/Support/Attribution.swift
MealRoutine/Support/RecipeRoute.swift
MealRoutine/Recipes/recipes.v1.json
MealRoutine/Recipes/ingredient-aliases.tr.json
MealRoutine/Assets.xcassets/AppIcon.appiconset/
MealRoutine/Assets.xcassets/AppIconMark.imageset/
MealRoutine/Assets.xcassets/AccentColor.colorset/
Tools/catalog_integrity_check.py
Tools/recipe_tags.py
Tools/meal_recommender_checks.swift
Tools/grocery_merge_checks.swift
Tools/portion_scale_checks.swift
Tools/recipe_photo_checks.swift
Tools/product_gap_checks.swift
Tools/run_recommender_checks.sh
Tools/run_grocery_checks.sh
Tools/run_portion_checks.sh
Tools/run_recipe_photo_checks.sh
Tools/run_product_gap_checks.sh
```

---

## Ek: uçtan uca akış özeti

1. **İlk launch:** seed (125 Recipe) → onboarding welcome→slogan→Ev(1–8,1–5 akşam,30/45/60/90)→dislikes(Yumurta=egg+eggs)→taste(≤8)→summary→Haftamı oluştur→PlanWeek+Grocery→sekmeler.
2. **Bu Hafta:** ensureCurrentWeek; Tonight + liste; Değiştir sheet; RecipeRoute(allowsCookBar:true).
3. **Pişir:** prompt → cookedAt + RecipeFeedback → exposure/loved sonraki pick’i etkiler.
4. **Market:** merge+scale+coverage; search; manuel; check ↔ IngredientCheck.
5. **Tarifler:** filtre/favori/search; detay cook barsız; foto cache.
6. **Profil:** porsiyon/hafta yeniden kur; history/loved/never; appearance; gizlilik; yerel sıfırla (katalog kalır).
7. **Rollover:** yeni Pazartesi yeni plan; MealExposureLog + feedback recency/diversity’yi taşır.

---

*Rapor `v1.0` koduna dayanır; depo klonlanmamıştır.*
