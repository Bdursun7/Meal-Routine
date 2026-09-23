# MealRoutine

Personal iOS meal planner. The week, already planned.

TR-first UI. Local-first Swift, SwiftUI, and SwiftData. Minimum iOS 18. V1 has no backend, login, or network call on the happy path.

Recipe data: UniTools — theunitools.com (CC BY-SA 4.0)

## Open in Xcode

1. On a Mac, clone this repo and open `MealRoutine.xcodeproj` (Xcode 16 or newer).
2. Select the **MealRoutine** scheme and an iOS 18+ simulator.
3. If you run on a device, pick your Development Team under Signing & Capabilities. The simulator can use Sign to Run Locally.
4. Run. The first launch imports `MealRoutine/Recipes/recipes.v1.json` into SwiftData.

`project.yml` is an optional [XcodeGen](https://github.com/yonaskolb/XcodeGen) spec. You do not need it to open the checked-in project. Running `xcodegen generate` rewrites `MealRoutine.xcodeproj`.

## V1 scope

- Onboarding: welcome, then four steps (household, dislikes, up to 8 taste ratings, summary). The week is created only from “Haftamı oluştur” on the summary. Household size is 1–8, evenings are 1–5, max cook time is 30 / 45 / 60 / 90 minutes (default 60). Egg and eggs share one “Yumurta” dislike chip.
- Tabs: **Bu Hafta**, **Tarifler**, **Market**, **Profil**.
- This week is filled by a naive deterministic picker (time cap, dislikes, “never”, loved boost, curated score). It is not the full recommender yet.
- Grocery list merges UniTools ingredient `id`s when the unit matches, and flags unit conflicts instead of summing them.
- Recipe steps stay English. Names and the rest of the UI are Turkish.
- No ads, paywall, or LLM calls. Photos are not downloaded; the detail screen uses a local placeholder.

## Recipe data

Bundled catalog: `MealRoutine/Recipes/recipes.v1.json` (125 dinners).

Turkish ingredient alias reference: `MealRoutine/Recipes/ingredient-aliases.tr.json`.

Source: UniTools World Recipes, CC BY-SA 4.0. Do not scrape commercial recipe sites, and do not invent recipes. Dataset derivatives stay CC BY-SA 4.0. App code may stay under its own license.

Recipe data: UniTools — theunitools.com (CC BY-SA 4.0)

---

# MealRoutine

Kişisel iOS yemek planlayıcı. Haftan, önceden planlı.

Arayüz önce Türkçe. Swift, SwiftUI ve SwiftData; veri cihazda. En düşük sürüm iOS 18. V1'de hesap, sunucu ve mutlu yolda ağ çağrısı yok.

Recipe data: UniTools — theunitools.com (CC BY-SA 4.0)

## Xcode'da açmak

1. Repoyu Mac'te klonla ve `MealRoutine.xcodeproj` dosyasını aç (Xcode 16 veya daha yeni).
2. **MealRoutine** şemasını ve iOS 18+ bir simülatör seç.
3. Gerçek cihazda çalıştıracaksan Signing & Capabilities altından Development Team seç. Simülatör için Sign to Run Locally yeter.
4. Çalıştır. İlk açılışta `MealRoutine/Recipes/recipes.v1.json` SwiftData'ya alınır.

`project.yml`, isteğe bağlı bir XcodeGen tarifidir. Projeyi açmak için gerekmez. `xcodegen generate` mevcut `MealRoutine.xcodeproj` dosyasını yeniden yazar.

## V1 kapsamı

- Kurulum: karşılama, sonra dört adım (ev, sevmediğin malzemeler, en fazla 8 tat puanı, özet). Hafta yalnızca özetteki “Haftamı oluştur” ile kurulur. Ev halkı 1–8, akşam 1–5, en fazla pişirme 30 / 45 / 60 / 90 dk (varsayılan 60). Yumurta chip’i `egg` ve `eggs` kimliklerini birlikte saklar.
- Sekmeler: **Bu Hafta**, **Tarifler**, **Market**, **Profil**.
- Hafta, basit ve deterministik bir seçiciyle dolar (süre, sevmediğin malzeme, “bir daha asla”, sevdim önceliği, kürasyon skoru). Tam öneri motoru bu iskelette yok.
- Market listesi, UniTools malzeme `id` değerlerini birim aynıysa toplar; birim çakışırsa miktarları birbirine katmaz, satırı işaretler.
- Adımlar İngilizce kalır. İsimler ve arayüzün geri kalanı Türkçe.
- Reklam, ödeme duvarı ve LLM yok. Fotoğraflar indirilmez; detayda yerel bir yer tutucu vardır.

## Tarif verisi

Paket: `MealRoutine/Recipes/recipes.v1.json` (125 akşam yemeği).

Türkçe malzeme eşanlamlıları: `MealRoutine/Recipes/ingredient-aliases.tr.json`.

Kaynak: UniTools World Recipes, CC BY-SA 4.0. Ticari tarif sitelerini kazıma ve tarif uydurma yok. Veri setinin türevleri CC BY-SA 4.0 olarak kalır. Uygulama kodu kendi lisansında durabilir.

Recipe data: UniTools — theunitools.com (CC BY-SA 4.0)
