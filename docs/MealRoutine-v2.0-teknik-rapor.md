# MealRoutine v2.0 — Teknik Rapor

**Kaynak depo:** `Bdursun7/Meal-Routine`  
**Ref:** `V2.0` (Personal Meal Memory, PR #17 squash `f6321b12` / `f6321b12423817401a4783d05d2a19b62739f55d`)  
**Sürüm:** MARKETING_VERSION `2.0.0`, CURRENT_PROJECT_VERSION `2`  
**Yöntem:** `V2.0` ağacının kaynak okuması (ekran metinleri ve servisler)  
**Tarih:** 2026-09-25

**Dal politikası:** Ürün işi `V2.0` üzerindedir. `main` ve `v1.0` V1 için dondurulmuştur; V2 düzeltmesi veya dokümanı o dallara yazılmaz.

---

## 1. Özet ve kapsam

### V2 ne

V1 akşam planı, market ve puan akışının üstüne **Personal Meal Memory** ekler. Pişirme, değiştirme, atlama, puan ve favori cihazdaki `MealMemory` + `MealBehaviorEvent` satırlarına yazılır. Haftalık plan `MealRecommender.pick` yerine `PersonalizedScoringService.select` ile kurulur. Arayüz Türkçe kalır; hesap, bulut ve LLM yoktur.

Kullanıcıya görünen fark: **Bu haftanın notu**, karttaki neden cümlesi, **Tanıdık** / **Yeni** rozeti, **Atladım** / **Atlandı**, kişiselleştirilmiş **Değiştir** çipleri, Tarifler’de geçmişten sonra gelen raylar, Profil → **Yemek hafızan** ve **Sonraki plan** ayarları (Keşif, Tekrar, Zorluk, Hafta içi).

### V2 ne değil

- 30 kullanıcılı TestFlight beta ve canlı V1/V2 metrik karşılaştırması (bilinçli ertelendi; bölüm 12)
- UI kayıt / XCUITest paketi
- AI sohbet, LLM plan, market siparişi, sağlık hedefi, cloud sync
- `MealRecommender` silinmedi; mevcut Foundation kontrolleri ve bellek bağlamı boşken replacement’ın V1 filtresi durur

### Platform

| Alan | Değer |
|------|--------|
| OS | iOS **18.0+** |
| UI | SwiftUI, developmentLanguage `tr` |
| Persistence | SwiftData, `cloudKitDatabase: .none` |
| Bundle ID | `com.mealroutine.app` |
| Test target | `MealRoutineTests` (`com.mealroutine.app.tests`) |
| Şema | `MealRoutine.xcscheme` test hedefini derler ve çalıştırır |

---

## 2. Mimari

```text
Features (ThisWeek, Recipes, Profile, MealMemory, Discovery)
    → WeekPlanService / BehaviorTrackingService / MealMemoryService
        → PersonalizedScoringService, RecommendationReasonService,
          MealReplacement, DiscoverySections, MealPatternService
            → MealMemorySnapshot + PlanningPreferences (hesaplanır, skor saklanmaz)
SwiftData: MealMemory, MealBehaviorEvent (+ V1 modelleri)
```

Yazma `@MainActor` servislerde. Skor `RecipeMemoryScore` olarak plan veya liste kurulurken hesaplanır; kalıcı kolon değildir.

### Şema

`ModelContainerFactory` V1 tiplerine `MealMemory.self` ve `MealBehaviorEvent.self` ekler.

### V1 geri doldurma

`MealMemoryService.backfillIfNeeded` ilk plan kurulumunda bir kez çalışır (`UserPrefs.didBackfillMealMemory`). Mevcut `RecipeFeedback` ve `MealExposureLog` `MealMemoryBackfill` ile snapshot’a çevrilir. Sonraki pişirme ve puanlar `BehaviorTrackingService` üzerinden gider. Hafıza sıfırlanınca bayrak `true` kalır; kurulum tercihleri yeniden içe aktarılmaz.

---

## 3. Modeller

### MealMemory (`Models/MealMemory.swift`)

Tarif başına tek satır (`recipeSlug` unique). Alanlar snapshot ile aynıdır: `timesCooked`, `timesReplaced`, `timesSkipped`, `lastCookedAt`, `lastSelectedAt`, `lovedCount`, `okayCount`, `latestRatingRaw`, `neverAgain`, süre / zorluk / porsiyon / eksik malzeme / fazla malzeme / “yine yaparım” sayaçları, `isFavorite`, `discoveryStatusRaw`, `confidenceRaw`, `updatedAt`.

`snapshot` / `replace(with:)` SwiftData satırı ile `MealMemorySnapshot` arasında köprüdür.

### MealMemorySnapshot ve MealMemoryReducer

`Models/MealMemorySnapshot.swift`. Reducer bir olayı toplamlara işler, sonra `ConfidenceCalculator.level` yazar.

| Olay | Etki |
|------|------|
| `viewed` | Ayrılmış; toplam değişmez |
| `selected` | `lastSelectedAt` |
| `cooked` | `timesCooked`, son tarihler; ilk kez ise `explored`, değilse `familiar` |
| `replaced` | `timesReplaced` |
| `skipped` | `timesSkipped` |
| `loved` | `lovedCount`, favori, `latestRating = loved` |
| `okay` | `okayCount`, `latestRating = okay` |
| `neverAgain` | bayrak, favori kalkar, `latestRating = never` |
| `favorited` | `isFavorite = true` |

`FeedbackReason` sayaçları aynı uygulamada artar (puan ekranındaki isteğe bağlı notlar). `dataPointCount` pişirme + değiştirme + atlama + loved + okay + never + süre kaygısı + zorluk kaygısı + “yine yaparım” toplamıdır. Yalnızca favori kalbi veya porsiyon notu bu sayaca girmez; favori yolu ayrıca loved/okay olayı da yazar.

### MealBehaviorEvent (`Models/MealBehaviorEvent.swift`)

Ham yerel günlük. Alanlar: `uuid`, `recipeSlug`, `eventTypeRaw`, `createdAt`, `planWeekID?`, `plannedMealID?`, `replacementReason`. Analytics bu günlüğün tamamını dışarı göndermez; `meal_memory_updated` yalnızca kısa `kind` token’ı taşır.

`MealBehaviorEventType`: `viewed`, `selected`, `cooked`, `replaced`, `skipped`, `loved`, `okay`, `neverAgain`, `favorited`.

### Plan satırları

`PlanWeek.explanation` plan notunun metnidir. `PlannedMeal.skippedAt` atlamayı tutar; tarif ve market değişmez. `cookedAt` pişirmeyi tutar.

### PlanningPreferences

`UserPrefs` üzerinde sonraki plan düğmeleri: `discoveryLevel` (varsayılan `balanced`), `repeatPreference` (`balanced`), `difficultyPreference` (`mostlyEasy`), `weekdayStyle` (`mostlyQuick`), `dismissedPatternIDs`. Açık hafta bu alanlar değişince silinmez. Okuma `planningPreferences`.

---

## 4. PersonalizedScoringService

`Services/PersonalizedScoringService.swift`. Hafta üretimi ve (bellek doluysa) akıllı değiştirme bunu çağırır. `MealRecommender.pick` V1 kontrol yolu olarak durur.

### TasteProfile

Bellek + katalogdan kurulur. Sevilen kategori / protein / mutfak kümeleri **en az iki** loved sinyal ister. Sık mutfak: o mutfakta ≥3 pişirme veya kurulmuş sevgi. `usualCookMinutes` pişirilen tariflerin dakika ortancasıdır; **üç** pişirme örneğinden önce `nil`. Tek olay bu kümeleri doldurmaz.

### Sert filtre (`isEligible`)

Her keşif seviyesinde durur:

- engelli slug (aynı haftada ikinci kez)
- `rating == .never` veya `neverAgain`
- süre tavanı
- sevmediğin malzeme
- zorluk kapısı (`easyOnly` yalnızca kolay; `mostlyEasy` ve `openToMedium` `hard` tarifleri keser)
- istenirse loved boşluğu (`RepeatPreference.lovedGapDays`: ara sıra 14, dengeli ve sık sık 7; sık pişirilen ve `often` değilse +3 gün)

Havuz akşam sayısını dolduramazsa ikinci geçiş loved boşluğunu ve zorluk kapısını gevşetir. Never again ve disliked gevşemez.

### Skor (`RecipeMemoryScore.final`)

`preference + behavior + variety + discovery - repetitionPenalty`. Beraberlikte slug alfabetik.

**Preference:** `trDogfoodScore / 10`; kurulmuş sevilen kategori +5, protein +5, sık mutfak +3; süre `max(20, maxCook − 15)` altındaysa +2; hafta içi (`dayOffset < 5`) `mostlyQuick` için ≤30 dk +4, ≤45 +2, daha uzun −3; `balanced` için ≤45 dk +1. Zorluk: `mostlyEasy` + medium −4; `hard` −8.

**Behavior:** loved +10 (ölçeklenmez); okay +2; ≥2 pişirme `scale(6, cookRepeatConfidence)`; “yine yaparım” +3; loved’suz favori +4; her değiştirme `−scale(6, replacementConfidence)`; ≥2 atlama `−scale(4, …)`; süre kaygısı `−scale(7)`; zorluk kaygısı `−scale(6)`; never again −100. Loved yoksa benzer tarif bonusu +4 (protein, kategori veya etiket).

**Tekrar cezası** (son pişirme, yoksa son seçilme): ≤2 gün 10, ≤5 gün 5, ≤10 gün 2. ≥4 pişirme ve ≤14 gün ise taban en az 2. `occasionally` ×2, `balanced` ×1, `often` ÷2.

**Discovery:** yeni tarifte sevilen kategori +4, protein +3, mutfak +3, denenmemiş kategori +1. `familiar` skoru dörde böler, bilinen +6, yeni −2. `balanced` bilinen +1. `adventurous` skoru ikiye katlar, yeni +2.

**Variety:** aynı haftadaki çapalara karşı mutfak −3 / +1, protein −3 / +1, kategori −2; taban −12. `moreVariety` ve hafta içi yeni mutfak +2.

### Plan notu

`PlanExplanationBuilder` şablon kullanır, model çağrısı yok. Geçmiş yoksa veya akşam sayısı 0 ise: “Bu hafta süre sınırına ve sevmediğin malzemelere göre kuruldu.” Geçmiş varsa sevilenlerin sayısı, yeni tarif sayısı ve hafta içi ≤30 dk akşamlar cümleyi seçer. Sayı yalnızca seçilen planda varsa yazılır.

---

## 5. WeekPlanService entegrasyonu

`ensureCurrentWeek` / `replaceCurrentWeek`:

1. Onboarding bitmiş ve bu Pazartesi’nin haftası yoksa (veya yeniden kur).
2. `backfillIfNeeded`.
3. Eski hafta varsa `MealExposureLog`’a yaz, o haftanın malzeme işaretlerini sil, haftayı kaydederek kaldır.
4. `planningPreferences` ile `PersonalizedScoringService.select`.
5. `PlanWeek.explanation` + akşamlar (`cookedAt` boş, porsiyon = ev halkı).
6. Her akşam için `selected` olayı (`saves: false`), sonra tek `save`. Market’i çağıran taraf `GroceryListService.rebuild` eder.

`replaceMeal(uuid:with:reason:)` giden tarife `replaced`, gelene `selected` yazar; `cookedAt` ve `skippedAt` temizlenir; aynı haftadaki diğer akşamlar durur. Çağıran market’i yeniler.

Tek akşamlık `replaceMeal(uuid:)` da `select` kullanır: diğer akşamlar hem blok hem çapa, `startDayOffset` o günün ofsetidir.

---

## 6. Akıllı değiştirme

`ReplacementChip` / `ReplacementIntent` (`Features/ThisWeek/ReplacementIntent.swift` typealias). Ekran `SmartReplacementView` → `MealReplacementSheet`. Başlık **Değiştir**, soru **Bunun yerine ne istersin?**

| Çip | `rawValue` | Süzgeç |
|-----|------------|--------|
| Daha hızlı | `faster` | mevcut süreden kısa |
| Sevdiğime benzer | `similarLoved` | sevilenle protein / kategori / etiket |
| Tamamen farklı | `different` | protein varsa başka protein; yoksa mutfak veya çeşit |
| Bir favori kullan | `loved` | loved puanı veya favori; loved boşluğu bu çipte kapalı |
| Yeni bir tarif | `tryNew` | pişmemiş, loved değil, favori değil |
| Tavuksuz | `noChicken` | `poultry` veya `chicken` malzemesi yok |
| Vejetaryen | `vegetarian` | diyet `vegetarian` veya `vegan` |
| Alıştığım gibi | `usual` | sevilen kategori / protein / mutfak |
| Sürpriz | `surprise` | tek deterministik seçim (`Random` yok); diğer çipleri kapatır |

`ReplacementPresenter.board` katalog, bellek ve `planningPreferences` ile `MealReplacement.choices` çağırır. Bellek veya tercih varsa uygunluk `PersonalizedScoringService.isEligible`; ikisi de boşsa `MealRecommender.passesFilters`. Sıra bellek skoruna göredir. Liste tavanı 8. Boş liste: “Bu filtreye uyan tarif kalmadı. Çipleri gevşet.” Seçim `replaceMeal` + market rebuild + `smart_replacement_used`.

Neden cümleleri çipe bağlıdır (“Daha kısa sürer”, “Henüz denemediğin bir tarif”, “Sürpriz bir alternatif”, …).

---

## 7. Güven

`ConfidenceCalculator`:

| Durum | Seviye |
|-------|--------|
| `neverAgain` veya `lovedCount > 0` | `high` (hemen) |
| pişirme ≥2, değiştirme ≥2, süre veya zorluk kaygısı ≥2, atlama ≥3 | `medium` |
| diğer | `low` |

`scale`: low 0.4, medium 0.75, high 1; sonuç yuvarlanır. Loved +10 ve never −100 bu ölçekten geçmez. Değiştirme güveni: ≥3 high, ≥2 medium, aksi low. Tekrar pişirme güveni: ≥4 high, ≥2 medium, aksi low. Tek değiştirme bu yüzden −6’nın yaklaşık 0.4’ü kadar iner; tek davranış yerleşmiş tercih sayılmaz.

---

## 8. Soğuk başlangıç

`hasHistory` = `dataPointCount > 0`.

| Yüzey | Geçmiş yokken |
|-------|----------------|
| Rozet | `RecommendationReasonService.badge` `nil` — ne **Tanıdık** ne **Yeni** |
| Plan notu | `PlanExplanationBuilder.noMemory` |
| Tarifler rayları | `DiscoverySections.make` `[]` |
| Örüntü | `MealPatternService` üç noktadan önce boş |
| Tarif detayı “Neden uyuyor” | `dataPointCount == 0` ise yok |
| Yemek hafızan | “Henüz yemek hafızan yok…” |

Kurulumdaki Sevdim / İdare eder / Bir daha asla, ilk haftadan önce backfill ile geçmiş sayılır. Tat adımını atlayıp henüz pişirmeyen kullanıcı soğuk başlangıçtadır. Never again ve disliked bu durumda da sert filtredir. Yeterli veri yokken “her zaman” denmez; örüntü metinleri “gibisin” kalıbındadır.

Bu Hafta’da örüntü kartı yoksa ve son dönemde en az üç Sevdim varsa V1 `PreferenceInsight` kartı (**Tercihlerin netleşiyor**) yedek olarak durur. İkisi birlikte gösterilmez.

---

## 9. Atlama / pişirme durum makinesi

`Support/WeekPresentationRules.swift` (`SkipControl`) ve `WeekPlanService.markSkipped` / `markCooked`.

| Durum | Ekran | Kayıt |
|-------|--------|--------|
| Pişmemiş, atlanmamış | **Atladım** (çerçeve) + **Değiştir** | — |
| `skippedAt` dolu, `cookedAt` boş | **Atlandı** (dolu vurgu) + kart çerçevesi | ikinci atlama yok sayılır |
| `cookedAt` dolu | **Atladım** yok, atlandı çerçevesi yok | pişirme `skippedAt`’i siler |
| Kayıt sürerken | düğme `unavailable` | — |

`showsSkip` = pişmemiş. `recordsAsSkipped` = atlama tarihi var ve pişirme tarihi yok. İkisi birden yazılı olsa bile pişirme kazanır. Atlama tarifi ve market listesini değiştirmez; yalnızca `skipped` olayı ve `timesSkipped` artar. Pişirme `cooked` olayını bir kez yazar.

**Bunu pişirdim** çubuğu `CookBarGate`: `allowsCookBar`, planlı akşam kimliği ve haftanın bu Pazartesi olması. Bu Hafta rotası `allowsCookBar: true`. Tarifler ve hafıza geçmişi `false`.

---

## 10. Testler — MealRoutineTests

Hedef: `MealRoutineTests` (host `MealRoutine.app`). Şema `MealRoutine` test action’ına bağlı.

| Dosya | Ne |
|-------|-----|
| `PersonalizedScoringTests` | loved +10, tek değiştirmenin yumuşak cezası, never elenir, keşif seviyesi |
| `SmartReplacementTests` | çip süzgeçleri ve bellek sıralaması |
| `PresentationRuleTests` | soğuk rozet, rayların gizlenmesi, Atladım/Atlandı, pişirmede atlama yok, cook bar |
| `MealMemoryBehaviorTests` | reducer, güven, `dataPointCount` |
| `MealMemoryStoreTests` | backfill, reset, olay satırı |
| `TestFixtures` | ortak aday ve tarih |

Mac’te (PR #17’de geçen komut):

```text
xcodebuild test -project MealRoutine.xcodeproj -scheme MealRoutine \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.0,arch=arm64' \
  -only-testing:MealRoutineTests
```

Simülatörsüz Foundation kontrolleri: `Tools/run_memory_checks.sh` (`Tools/meal_memory_checks.swift`). Ürün boşluğu kontrolleri: `Tools/run_product_gap_checks.sh`.

---

## 11. Bilinçli park / bilinçli eksik

| Konu | Durum |
|------|--------|
| TestFlight beta | Park. Ürün notundaki 21 gün / en az 30 kullanıcı (15 V1 + 15 yeni) bu sürümde başlatılmadı. |
| V1/V2 metrikleri | Park. `Analytics` hâlâ yerel `os_log` + 200’lük bellek tamponu. Ağ sink’i ve V1 baseline karşılaştırması yok. Yeni olay adları (`meal_memory_updated`, `smart_replacement_used`, `meal_memory_reset`, …) yalnızca bu tampona yazılır. |
| UI recording testleri | Park. XCUITest veya ekran kaydı paketi yok. Sunum kuralları `PresentationRuleTests` ile birim testidir. |
| Kullanılmayan `planning` bağı | Bu PR’de kapatıldı. `ThisWeekViewModel.meals` içindeki `PlanningPreferences` yerel bağı ve artık okunmayan `prefs` parametresi kaldırıldı. Skor plan kurulurken ve **Değiştir** tahtasında hesaplanır; kart listesi yalnızca neden ve rozet üretir. |
| Bu Hafta insight widget | Eksik değil. Örüntü eşiği dolunca **Yemek hafızan** kartı (`MealPatternService`); değilse ve yeterli Sevdim varsa **Tercihlerin netleşiyor**. Ayrı bir cila widget’ı eklenmedi. |

Ayrıca ürün spekindeki chatbot, LLM plan, sosyal akış ve sağlık hedefleri V2 kapsamı dışında durur (`docs/MealRoutine-V2-Personal-Meal-Memory.md`).

---

## 12. Dosya envanteri (V2 ekleri)

```text
MealRoutine/Models/MealMemory.swift
MealRoutine/Models/MealMemorySnapshot.swift
MealRoutine/Models/MealBehaviorEvent.swift
MealRoutine/Models/RecipeMemoryScore.swift
MealRoutine/Models/UserDiscoveryPreference.swift
MealRoutine/Models/FeedbackReason.swift
MealRoutine/Services/PersonalizedScoringService.swift
MealRoutine/Services/ConfidenceCalculator.swift
MealRoutine/Services/BehaviorTrackingService.swift
MealRoutine/Services/MealMemoryService.swift
MealRoutine/Services/RecommendationReasonService.swift
MealRoutine/Services/PlanExplanationBuilder.swift
MealRoutine/Services/MealPatternService.swift
MealRoutine/Services/DiscoverySections.swift
MealRoutine/Support/WeekPresentationRules.swift
MealRoutine/Features/ThisWeek/SmartReplacementView.swift
MealRoutine/Features/ThisWeek/RecommendationReasonView.swift
MealRoutine/Features/ThisWeek/ReplacementIntent.swift
MealRoutine/Features/MealMemory/
MealRoutine/Features/Discovery/
MealRoutineTests/
Tools/meal_memory_checks.swift
Tools/run_memory_checks.sh
docs/MealRoutine-V2-Personal-Meal-Memory.md
```

`WeekPlanService`, `MealReplacement`, `ThisWeekView`, `ProfileView`, `RecipeDetailView`, `RecipeListView`, `CookRatingPrompt`, `Analytics`, `UserPrefs`, `PlanWeek`, `PlannedMeal` V1 dosyalarının üstüne V2 alanları taşır.

---

*Rapor `V2.0` kaynak ağacına dayanır. Ürün işi bu dalda kalır; `main` / `v1.0` V1 anlık görüntüsüdür.*
