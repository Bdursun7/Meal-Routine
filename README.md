# MealRoutine

Personal iOS meal planner. The week, already planned.

TR-first UI. Local-first Swift, SwiftUI, and SwiftData. Minimum iOS 18. V1 has no backend or login. The week, grocery list, and cooking stay on device. Opening a recipe photo is the only network call, and only when that photo is not already cached.

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
- This week is filled by a deterministic recommender: cook time, disliked ingredients, and Never-again are hard filters; the curated score and Loved still boost; meals cooked or planned in the last 21 days rank lower; the same week avoids repeating cuisine, course, protein, and tags. No LLM.
- Grocery list merges UniTools ingredient `id`s. Equivalent unit spellings sum together, and grams convert with kilograms (millilitres with litres). Incompatible units stay on separate rows and are flagged. Each evening scales from the recipe base to that meal’s servings (1–8). The default is the household size. Recipe detail shows the same scaled amounts. **Porsiyonu kaydet** on Profile locks the household onto every evening; on a planned meal it locks that evening only.
- UniTools summaries and cooking steps are Turkish localizations of the UniTools text. English source strings stay on those rows for CC BY-SA attribution. MealRoutine original dinners are separate bilingual text and do not use that license. Names and the rest of the UI are Turkish.
- No ads, paywall, or LLM calls. When a catalog `photo` URL is HTTPS, recipe detail shows it under the title and the week and recipe lists show a fixed thumbnail. The catalog author and license are shown with the image. The file is cached on disk after the first successful fetch. A fork-and-knife placeholder is used when the recipe has no photo, or when the image is not cached and cannot be fetched. Planning, the grocery list, and cooking do not wait on the network.

## Recipe data

Bundled catalog: `MealRoutine/Recipes/recipes.v1.json` (225 dinners: 125 UniTools + 100 MealRoutine originals).

Turkish ingredient alias reference: `MealRoutine/Recipes/ingredient-aliases.tr.json`.

UniTools rows stay UniTools World Recipes, CC BY-SA 4.0. Do not scrape commercial recipe sites into those rows. Dataset derivatives of the UniTools rows stay CC BY-SA 4.0. App code may stay under its own license. UniTools photo files stay on UniTools URLs with the catalog's own author and license; they are not replaced with other images.

The original Turkish evening pack is MealRoutine text. Those rows use `source.provider` `mealroutine`, not CC BY-SA, and they ship without photos. Recipe detail shows their own credit. The fork-and-knife placeholder covers a missing photo. Adding them changes the catalog file bytes, so the import fingerprint (`schemaVersion` plus FNV-1a) changes and the next launch re-imports. `schemaVersion` stays 1.

`Recipe.photoURL`, `photoAuthor`, and `photoLicense` are already on the SwiftData model. Seed copies `photo.url`, `photo.author`, and `photo.license`, or empty strings when `photo` is null. The catalog file bytes are the import fingerprint, and showing photos does not add model fields, so no SwiftData migration is required. An install that already seeded this catalog already has the photo strings.

Recipe data: UniTools — theunitools.com (CC BY-SA 4.0)

---

# MealRoutine

Kişisel iOS yemek planlayıcı. Haftan, önceden planlı.

Arayüz önce Türkçe. Swift, SwiftUI ve SwiftData; veri cihazda. En düşük sürüm iOS 18. V1'de hesap ve sunucu yok. Hafta, market ve pişirme cihazda kalır. Tarif fotoğrafı, yalnızca önbellekte yoksa ağ ister.

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
- Hafta, deterministik bir öneri motoruyla dolar: süre, sevmediğin malzeme ve “bir daha asla” elenir; kürasyon skoru ve Sevdim hâlâ yükseltir; son 21 günde pişen veya planlanan tarif geride kalır; aynı hafta mutfak, tür, protein ve etiketi tekrarlamamaya çalışır. LLM yok.
- Market listesi, UniTools malzeme `id` değerlerini toplar. Eş anlamlı birimler birleşir; gram ile kilogram ve mililitre ile litre çevrilir. Uyumsuz birimler ayrı satırda kalır ve işaretlenir. Her akşam, tarif tabanından o akşamın porsiyonuna ölçeklenir (1–8). Varsayılan ev halkıdır. Tarif detayı aynı ölçekli miktarı gösterir. Profil’de **Porsiyonu kaydet** ev halkını bütün akşamlara yazar; planlı bir akşamda yalnız o akşamı kilitler.
- UniTools satırlarında özet ve pişirme adımları, kaynak metnin Türkçe yerelleştirmesidir. İngilizce kaynak CC BY-SA atfı için o satırlarda durur. MealRoutine özgün akşam tarifleri ayrı iki dilli metindir ve bu lisansı taşımaz. İsimler ve arayüzün geri kalanı Türkçe.
- Reklam, ödeme duvarı ve LLM yok. Katalogdaki `photo` adresi HTTPS ise tarif detayında başlığın altında, hafta ve tarif listesinde sabit bir küçük görsel olarak gösterilir. Yazar ve lisans katalogdaki metindir. İlk başarılı indirme önbelleğe yazılır. Fotoğraf yoksa veya önbellekte olmayıp indirilemiyorsa çatal-bıçak yer tutucusu kalır. Hafta, market ve pişirme ağı beklemez.

## Tarif verisi

Paket: `MealRoutine/Recipes/recipes.v1.json` (225 akşam yemeği: 125 UniTools + 100 MealRoutine özgün).

Türkçe malzeme eşanlamlıları: `MealRoutine/Recipes/ingredient-aliases.tr.json`.

UniTools satırları UniTools World Recipes, CC BY-SA 4.0 olarak durur. Bu satırlara ticari tarif sitesi kazınmaz. UniTools türevleri CC BY-SA 4.0 kalır. Uygulama kodu kendi lisansında durabilir. UniTools fotoğrafları kendi adresinde kalır; yazar ve lisans katalogdaki `photo` alanıdır.

Özgün Türkçe akşam paketi MealRoutine metnidir. `source.provider` değeri `mealroutine` olur, CC BY-SA taşımaz, fotoğrafsız gelir. Tarif detayı kendi kredisini gösterir. Fotoğraf yoksa çatal-bıçak yer tutucusu kalır. Eklenen tarifler dosya baytını değiştirdiği için içe aktarma parmak izi (`schemaVersion` + FNV-1a) değişir ve sonraki açılış kataloğu yeniden alır. `schemaVersion` 1 olarak kalır.

`Recipe.photoURL`, `photoAuthor` ve `photoLicense` SwiftData modelinde zaten var. Seed, `photo.url`, `photo.author` ve `photo.license` değerlerini yazar; `photo` yoksa boş metin kalır. İçe aktarma parmak izi katalog dosyasının baytlarıdır. Fotoğraf göstermek modele yeni alan eklemez, SwiftData göçü gerekmez. Bu kataloğu daha önce alan kurulumda fotoğraf metinleri zaten durur.

Recipe data: UniTools — theunitools.com (CC BY-SA 4.0)
