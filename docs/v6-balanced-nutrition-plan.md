# V6 Balanced Nutrition — uygulama planı (Adım 1)

**Durum:** Yalnızca plan. Özellik kodu yok.  
**Taban:** `V6.0` @ `e84a525` (V5.1 kapanışı). `V5.0` ve `V5-Alignment-Audit` bu işte değiştirilmez.  
**Kilitli spec:** `docs/MealRoutine-V6-Balanced-Nutrition.md` (eklenen belgenin birebir kopyası).  
**Kural:** Aşağıdaki kararlar onaylanmadan spec’ten sapılmaz. Öneri, sapma değildir; ilk kod PR’si bu listedeki blok kararlar cevaplanmadan açılmaz.

V5.1, 2026-10-12 kaydıyla kapandı (`docs/MealRoutine_V1-V5_Cross_Version_Audit_Report.md` başlığı: V6 başlayabilir). VoiceOver, Dynamic Type, Dark Mode, işletim sistemi bildirimi, APNs ve ev saat dilimi hâlâ Pass değildir; audit onları V6 engeli saymaz. Bu plan o satırları Pass yapmaz.

## 1. Kodun bugünkü hali (kısa)

Haftalık kişisel plan `PersonalizedScoringService.select` ile kurulur. `MealRecommender.pick` V1 altın yoludur; hafta üretimi onu çağırmaz. Ortak plan `HouseholdPlanner.slugs` ile kurulur. Üçü de deterministiktir; LLM yoktur.

`MealPatternService` / `MealPattern` V2 yemek hafızası cümleleridir (“tavuk tariflerini sık pişiriyor gibisin”). V6 modu değildir. İsim çakışması vardır.

Tarif gövdesi `MealRoutine/Recipes/recipes.v1.json` (`schemaVersion: 1`, 325 satır). Sunucuda katalog tablosu yoktur. Kişisel tarifler SwiftData’dadır; hesap aktarımı `personal_recipes` (migration `0005`) ile gider. Ortak tercih `household_preferences` (migration `0004`) üzerindedir ve `POST /v1/households/:id/mutations` (`entityType: preference`) ile, revizyon çatışması ve `Idempotency-Key` ile yazılır.

WidgetKit hedefi yoktur. App Group `group.com.mealroutine.app` paylaşım uzantısının `captures.json`, `collection-index.json` ve `RecipeImages` dosyaları içindir. SwiftData bu grupta değildir (`ModelContainerFactory`). İmzalı `MealRoutine.entitlements` grubu içerir. `MealRoutine.Local.entitlements` grubu içermez.

## 2. (a) Spec–kod boşluk tablosu

| Spec | Kodda bugün | Boşluk |
| --- | --- | --- |
| Dört mod: `balanced`, `vegetableForward`, `proteinForward`, `plantForward`. Varsayılan `balanced`, açık. Kapatınca V5 sıralaması. | Böyle bir tercih yok. `UserPrefs` keşif, tekrar, zorluk ve hafta içi stilini tutar. “Dengeli” bu üç yerde de ayrı bir değerdir. | Yeni tercih. Mevcut “Dengeli” etiketlerinin üzerine yazılmaz. |
| Kişisel ve ev tercihi ayrı. Kişisel tercih eve sessiz kopyalanmaz. Ev kaydı ancak kullanıcı ev ayarını açar veya değiştirirse oluşur. | Kişisel plan yerel. Ev kurulunca `household_preferences` satırı varsayılanlarla hemen oluşur (pişirme günleri, süre, serbest metin protein listesi). | V6 ev modu bu satıra yazılırsa NULL kalmalı; satırın kendisi zaten var. Ayrı tablo açılırsa spec’teki “kayıt ancak açıkça” kuralı uygulanabilir. |
| Sıra: sert dışlama → güncel veto → Never Again ve güçlü hoşlanmama → süre/uygulanabilirlik → ev uyumu ve yemek hafızası → V5 kiler → V6 örüntü ve çeşit → keşif ve kontrollü tekrar. V6 üst sırayı geçemez. | Kişisel planda sert filtreler önce gelir (süre, sevilen malzeme değil, Never Again, zorluk, sevilen tekrar aralığı). Sonra tek tamsayı skor. Kiler en fazla +24 ve skora eklenir. Kilitli akşamları dolduran yol kiler stokunu geçirmez. Ortak planlayıcı kiler sinyalini hiç almaz. | V6 sinyali iki kişisel doldurma yoluna ve ortak planlayıcıya eklenmeli. Kiler’i ortak planlayıcıya eklemek V5 davranışını değiştirir; bu planda yapılmaz (K7). |
| Açıklama örnekleri İngilizce. Ham ağırlık, “protein ihtiyacını karşılar”, “beslenme olarak tam”, “sağlıklı” yok. | `PlanExplanationBuilder` ve `RecommendationReasonService` Türkçe şablon kullanır. Ağırlık göstermez. Beslenme iddiası da yoktur. | Yeni cümleler Türkçe olmalı. İngilizce örnekler ürün metni değildir (K11). |
| “Haftana bakış”: yalnız bilinen metadata sayılır. Bilinmeyen sıfır diye yazılmaz. Yüzde yok. | Bu Hafta’da pişirme halkası ve V2 hafıza kartı var. Sınıf sayımı yok. | Yeni bölüm. Yemek kartı, değiştirme ve ev kararı durur. |
| `foodGroupIds`, `proteinId`, `plantPattern`, `classificationSource`. Eksik değer `unknown`. Başlık veya mutfaktan çıkarım yok. | Bu dört alan JSON’da, DTO’da ve SwiftData’da yok. Ayrıntı bölüm 3. | Alanlar eklenir. Otomatik doldurma K1–K3 cevabına bağlıdır. |
| Mevcut mutfak, kategori ve protein alanları yeni adla kopyalanmaz. | `Recipe.category` 325/325 `dinner`. Çeşit `unitoolsCategory` ile kurulur. `Recipe.protein` gram tamsayısıdır. `PickerCandidate.protein` malzeme sırasından türetilen ailedir (`poultry`, `red-meat`, `seafood`, `egg`, `legume`, `tofu`, `dairy`); boş aile tekrar sayılmaz. | `proteinId` gram alanına veya türetilmiş aileye sessiz eşitlenmez. |
| Elle tarifte besin grubu isteğe bağlı, giriş ağırlaşmaz. | `RecipeEditorView` bu alanları sormaz. İçe aktarılan tarifte kalori ve protein 0 yazılır. | İsteğe bağlı, kapalı bir bölüm. 0, bilinmeyen besin değeri değildir; V6 bu sayıları kullanmaz. |
| Katalog metadata’sı küratörlü ve sürümlü. | `schemaVersion: 1`. `RecipeSeedService` 1 dışında sürümü reddeder. | Alan eklenince sürüm 2 aynı PR’de açılır. Eski migration dosyaları değişmez. |
| Yeni migration. Uygulanmış migration düzenlenmez. Yükseltme yemek hafızasını yazmaz, yeni karşılama açmaz. | Sunucu `0001`–`0015`. İstemci SwiftData varsayılanlı hafif göç. | Sonraki dosya `0016`. `meal_memory` ve karşılama akışı yok. |
| Önerilen uçlar `GET/PATCH /v1/users/me/meal-pattern-preference` ve ev karşılığı. Mimari yerel kalacaksa uç açılmaz. Ev tercihi ortak planı etkiliyorsa sunucu otoritesindedir. | Kişisel planlama tercihinin canlı senkronu yok; `0005` yalnız hesap aktarımında gider. Ev tercihi board mutasyonudur. API sürümü `v1`; `X-Client-API-Version` yoksa serbest, `1` veya `v1` kabul, başkası 406. | Ayrı uç açılmaz (K5). Ev yazımı mevcut mutasyon, üyelik, revizyon ve idempotency ile gider. |
| Bugünün Yemeği widget’ı. Küçük: bugünün akşamı, görsel veya yer tutucu, bilinen hazırlık süresi. Orta: bugün ve yarın. Ağ yok. Bayat veya çevrimdışı son plan, taze senkron iddiası yok. Dokunuş yemek detayını açar. Market ve kiler widget’ı yok. Plan widget’sız çalışır. | Widget hedefi yok. Plan `PlannedMeal` (`slot` akşam, `dayOffset` pazartesiden). `featuredEvening` bugün yoksa sonraki pişmemiş akşama düşer. Fotoğraflar ağdan indirilir. Derin bağlantı `mealroutine://week/meal?id=` kartı vurgular, detayı açmaz. | Yeni hedef ve anlık görüntü dosyası. SwiftData gruba taşınmaz. |
| Testler bölüm 14. Erişilebilirlik, Dynamic Type, koyu görünüm, boş ve çevrimdışı. | Birim testler ve `MealRoutineUITests` (sekme, fotoğraf, pişirme, kiler, market, ev test modu) var. Widget testi yok. Bu ortamda Xcode yok. | Yeni testler yazılır. Widget ve VoiceOver’ın Mac koşusu kabul kapısının parçasıdır; bu plan onları geçmiş saymaz. |
| Kalori, makro, tıbbi diyet, fiyat, bütçe, beslenme API’si, yapay tarif, V7 dil paketi yok. | Gramlar modelde durur ve arayüzde gösterilmez. Fiyat alanı yoktur. | V6 bu sayıları ekrana çıkarmaz ve sıralamaya koymaz. |

## 3. Katalog metadata sayımı

Kaynak: `MealRoutine/Recipes/recipes.v1.json`, 325 tarif (`unitools` 125, `mealroutine` 200). Sözlük `ingredients.v1.json`: 312 malzeme; alanlar yalnız `id`, `name`, `synonyms`, `sourceIds`. Besin grubu yok.

Hiçbir tarifte `proteinId`, `foodGroupIds`, `plantPattern` veya `classificationSource` yok. **Dört modun istediği küratörlü alan kapsaması 0/325.**

| Modun ihtiyaç duyduğu yapı | Bugün duran yapı | Pozitif sinyal, yalnız kesin ve mevcut alan | Tahmin kullanılırsa (önerilmez) |
| --- | --- | --- | --- |
| Dengeli: besin grubu ve kategori çeşitliliği; V2 tekrar sinyali | Besin grubu yok. Çeşit zaten mutfak, `unitoolsCategory`, türetilmiş protein ailesi ve etiket üzerinden var. V2 tekrar cezası `PersonalizedScoringService.repetitionPenalty`. | Besin grubu çeşitliliği **0/325**. Mevcut çeşit ve tekrar, mod kapalıyken de çalışır. | Ürün listesindeki malzeme varlığını gruba çevirmek spec’e aykırı olur. |
| Sebze ağırlıklı: küratörlü sebze-ağırlık işareti | Böyle bir alan yok. `unitoolsCategory == salad` 18 tariftir; bunların 7’sinde türetilmiş aile `dairy`. | **0/325** | Market kategorisindeki ürün kimliği 312/325 tarifte geçer. Bu, sebze-ağırlık değildir; neredeyse tüm katalog yanar. |
| Protein ağırlıklı: bilinen `proteinId` | Saklı kimlik yok. Sıralama anında ilk eşleşen malzemeden aile üretilir. | **0/325** (tahmin `proteinId` sayılmazsa) | Aile boş değil: **278/325**. Boş: **47/325**. Dağılım: kırmızı et 128, süt ürünü 45, deniz 40, kümes 34, baklagil 20, yumurta 9, tofu 2. |
| Bitki ağırlıklı: `plantBased` veya `plantDominant` | `plantPattern` yok. `diets` var. | `vegan` **38/325** ve hepsi aynı zamanda `vegetarian`. Hayvan ailesiyle çelişen vegan tarif **0**. Bu eşleme K2 onayı olmadan yazılmaz. Onaysız kapsama **0/325**. | `vegetarian` bitki temelli değildir. Vegan olmayan vejetaryen **77**: süt ürünü 43, baklagil 12, yumurta 7, aile boş 15. Bunların 72’sinde süt veya yumurta malzemesi var; 5’inde yok. O 5 tarif `plantBased` yapılmaz. |

Diğer diyet etiketleri sinyal değildir: `gluten-free` 146 (93’ü vejetaryen veya vegan değil), `pescatarian` 39 (38 deniz, 1 tofu). Boş diyet listesi 101.

`category` 325/325 `dinner`. Kurs çeşitliliği `unitoolsCategory`: ana 264, çorba 42, salata 18, kahvaltı 1.

Etiketler stil ve biçimdir, besin grubu değildir: stew 90, spicy 69, rice 64, quick 61, bake 58, bread 48, potato 45, one-pan 33, slow 33, fry 31, grill 28, stuffed 19, cold 18, pie 14, bulgur 12, curry 8, steam 8, stir-fry 8, pasta 7, dumpling 6, noodle 4.

Beslenme nesnesi 325/325 dolu ve protein gramı hepsinde sıfırdan büyük. V6 bunu okumaz. `prepMinutes` katalogda 0 olan tarif yok (en küçük 5). `cookMinutes` 0 olan 12 tarif var (soğuk veya çiğ). `totalMinutes` 0 olan yok. Fotoğraf URL’si **195/325**.

Kişisel ve içe aktarılan tarifler bu 325’in dışındadır. Hepsi, kullanıcı işaretlemedikçe `unknown` kalır.

## 4. (b) Sıralı PR kırılımı

Bu belge PR 0’dır. Sonrakiler özellik kodudur ve blok kararlar cevaplanınca açılır. `0001`–`0015` düzenlenmez.

### PR 0 — bu PR

Plan ve spec kopyası. Davranış yok.

### PR 1 — sabit kimlikler ve katalog sözleşmesi

- Yeni tipler, V2 `MealPattern` adını kullanmadan: mod, besin grubu, `plantPattern`, `classificationSource`.
- `Recipe` / `RecipeDTO` / `PickerCandidate` üzerine eksik alanlar. Gram `protein` durur.
- `recipes.v1.json` `schemaVersion` 2. `RecipeSeedService` 2’yi kabul eder, 1’i göçle okumaya devam etmez; tek katalog dosyası 2 olur.
- K2 onayına göre yalnız `vegan` → `plantBased` yazılır. K1 ve K3 onayı yoksa `proteinId` ve besin grubu `unknown` kalır.
- Sunucu SQL yok. Katalog sunucuda durmuyor.
- Test: çözücü bilinmeyen alanı tahmin etmez; kimlikler yerelle değişmez; başlık anahtarı sıralamayı değiştirmez.

### PR 2 — `0016` tercih saklama

`server/db/migrations/0016_meal_pattern_preference.sql`:

- `household_preferences.meal_pattern_mode TEXT NULL`
- `household_preferences.meal_pattern_enabled BOOLEAN NULL`
- Bilinen modlar için `CHECK`. NULL, “ev henüz seçmedi” demektir. Satır ev kurulunca zaten oluşur; bu iki kolon açık bir yazıma kadar NULL kalır.
- `personal_preferences` ve `personal_recipes` aynı dosyada kolon alır. Amaç canlı uç değil, hesap aktarımının yeni alanları düşürmemesi.
- Kişisel tarif kolonları: `protein_id`, `food_group_ids`, `plant_pattern`, `classification_source`. Varsayılan `unknown` / boş dizi. Başlıktan doldurma yok.
- Board mutasyonu yeni anahtarları doğrular. Bilinmeyen mod 400. Eski sunucu anahtarı yok sayacağı için istemci, eksik ev alanını `balanced` sanmaz.
- Ayrı `GET/PATCH` uçları açılmaz (K5 önerisi). Üyelik `assertMember` (sahip ayrıcalığı bugün de yok). Çatışma mevcut `revision`. `Idempotency-Key` aynı mutasyon yolunda kalır.
- Test: üye olmayan 404, üye yazar, bayat revizyon çatışır, kişisel tercih ev satırına kopyalanmaz, bilinmeyen enum reddedilir, `0015` dosyası değişmeden `0016` uygulanır.

### PR 3 — tercih arayüzü

- `UserPrefs` alanları. Yükseltmede kişisel varsayılan `balanced` + açık. Karşılama açılmaz. Yemek hafızası yazılmaz.
- Profilde ayrı bölüm. Sıfırla → `balanced` ve açık. Kapat → V5 sıralaması. Üç mevcut “Dengeli” kontrolü durur.
- Ev ayarı ayrı. Kayıt ancak kullanıcı seçerse. Seçilmemiş ev “ayarlanmadı” görünür; kişisel mod oraya yazılmaz.
- Elle tarifte isteğe bağlı, daraltılmış işaretler. Zorunlu alan yapılmaz.
- XCUITest: modu değiştir, sıfırla, kapat; ev satırı kişisel değerle dolmaz.

### PR 4 — sıralama

- `PersonalizedScoringService` taze hafta ve kilitli akşam doldurma. İkisi de aynı V6 terimini görür.
- `HouseholdPlanner`. Ev modu NULL veya kapalıysa terim yok. Kişisel mod ortak skora girmez.
- `MealRecommender.pick` değişmez. V1 kontrol betikleri altın yol olarak kalır.
- K6 cevabına göre terimin tavanı. Kapalı tercih, bugünkü skorla birebir test edilir.
- Açıklama cümlesi yalnız gerçekten sınıflanmış bir seçim varsa eklenir. Ağırlık metne girmez.
- Akıllı değiştirme K8 onayıyla aynı terimi alır. Onay yoksa değiştirme akışı olduğu gibi kalır.
- Test: dört mod, bilinmeyen metadata nötr, dışlama / Never Again / veto kazanır, yerelle kimlik değişmez, kapalı tercih yemek hafızasını ve skoru değiştirmez.

### PR 5 — hafta özeti

- Bu Hafta’ya kompakt bölüm. K9’daki sayımlar. Yüzde yok. Bilinmeyen öğün sıfır hanesi değildir. Kapsam eksikse “Elindeki tarif bilgisine göre”.
- Kalori, gram ve sağlık cümlesi yok. Kart, değiştirme ve ev kararı durur.
- XCUITest: özet bilinmeyeni sıfır yazmaz; ekranda kalori veya makro yoktur.

### PR 6 — Bugünün Yemeği

- Yeni WidgetKit hedefi. Çekirdek şema widget’sız derlenir ve plan kurar.
- Anlık görüntü `group.com.mealroutine.app` içinde ayrı dosya (`widget-today.json`). `captures.json` ile karışmaz. SwiftData taşınmaz.
- Görsel, uygulama önceden kopyaladıysa dosyadır. Widget ağ açmaz. Dosya yoksa sabit yer tutucu.
- Zaman çizelgesi yenileme sözü vermez.
- Dokunuş yemek detayına gider (bugünkü bağlantı yalnız vurguyu açar; yol genişler, eski bildirim yolu bozulmaz).
- Market ve kiler widget’ı yok.
- Yerel şemada App Group yoktur. Anlık görüntü orada uygulama desteğine düşer; widget o şemada boş kalabilir. Plan yine kurulur.
- Test: boş plan, bayat hafta, görselsiz, süresi bilinmeyen, dolu plan, yanlış dosyaya yazmama, widget yüklü değilken plan. Widget arayüz koşusu Mac’tedir.

### PR 7 — kürasyon miktarı (K4)

Test fikstürleri katalog dolmadan da modları kanıtlar. Köpek maması için katalogda her modun tuttuğu ve tutmadığı örnek satırlar gerekir. 325’in tamamı bu sürümün şartı değildir; kabul kapısı “etiketler yapılandırılmış metadata’ya dayanır” dediği için işaretsiz tarif özet’te bilinmeyen kalır.

### PR 8 — belgeler

API notu (uç yok, mutasyon var), `0016` runbook satırı, küreselleşme denetimindeki V6 maddeleri kanıtla güncellenir. Kanıtsız kutu işaretlenmez.

## 5. Test ekleri

Birim ve sunucu, PR 1–6 ile birlikte:

- Her mod, fikstürde işaretli tarifi öne alır; işaretsiz tarife artı veya eksi vermez.
- Başlık, mutfak adı ve Türkçe görünen ad sıralamayı ve kimliği değiştirmez.
- Sert dışlama, Never Again ve güncel veto mod açıkken de eler.
- Tercih kapalıyken `PersonalizedScoringService` çıktısı bugünkü çıktıyla aynıdır. Yemek hafızası satırı değişmez.
- Kişisel kayıt ev kolonuna kopyalanmaz. Ev NULL iken ortak plan kişisel modu uygulamaz.
- `0016` boş veritabanında ve `0015` uygulanmış veritabanında bir kez çalışır. Eski dosyaların özeti değişmez.
- Üye olmayan ev ucuna yazamaz. Bayat `baseRevision` çatışır. Aynı `Idempotency-Key` ikinci kez işi tekrarlamaz. Bilinmeyen mod 400.
- Özet yüzdesi, kalori, gram ve “ihtiyacı karşılar / tam / sağlıklı” üretmez. Bilinmeyen öğün paydaya sıfır diye girmez.
- Widget modeli: plan yok, bu haftadan eski anlık görüntü, görsel dosyası yok, `timeIsUnknown`, bugün ve yarın dolu. Çekirdek plan bu dosya olmadan kurulur.
- Dokunuş rotası ilgili `PlannedMeal` kimliğini detaya taşır.

XCUITest (`MealRoutineUITests`, `-uitest`), mevcut sekiz akışa ek:

- `testMealPatternCanChangeResetAndDisable` — Profil’de mod, sıfırla, kapat. Karşılama açılmaz.
- `testHouseholdPatternStaysUnsetUntilChosen` — kişisel mod ev kartına yazılmaz.
- `testWeekGlanceSkipsUnknownAndHidesNutrition` — özet ve tarif detayında kalori veya protein gramı yok.
- `testWeekStillPlansWhenWidgetSnapshotMissing` — anlık görüntü dosyası yokken Bu Hafta kurulur.

WidgetKit süreç testi bu Linux kopyasında koşmaz. Sağlayıcı modeli birim testiyle kanıtlanır. Galeri, VoiceOver ve gerçek zaman çizelgesi Mac kabulündedir. Dynamic Type ve koyu görünüm, yeni Profil bölümü ve hafta özeti için birim veya anlık görüntü değil, mevcut UI test iskeletine erişilebilirlik kimliği ve büyük metin kaydırması olarak eklenir. VoiceOver’ı bu depo kopyası geçmiş sayamaz.

## 6. (c) Çelişki, belirsizlik ve daha iyi yol

Her maddede belgenin dediği, kodun yaptığı, seçenekler ve öneri var. **Blok** olanlar cevaplanmadan o alana kod yazılmaz.

### K1 — `proteinId` nereden gelir? (blok)

Spec: `proteinId` varsa mevcut kararlı protein kimliği kullanılır. Bilinmeyen tahmin edilmez. Başlıktan çıkarım yok. Var olan protein alanı yeni adla kopyalanmaz.

Kod: Saklı `proteinId` yok. `Recipe.protein` gramdır ve 325 tarifte de içe aktarılan tarifte de doludur (içe aktarma 0 yazar). Sıralamadaki aile, malzeme listesinde ilk eşleşen kimliktir. Menemen’de ilk eşleşme yumurtadır; sebze önce gelse ve protein sonra gelse aile değişir. Boş aile “yok” demektir, `unknown` diye saklı değildir.

- A: 325 tarif `proteinId = unknown`. Aile fonksiyonu çeşit için durur, V6 sinyali olmaz. Protein ağırlıklı mod, kürasyon gelene kadar sıralamayı değiştirmez.
- B: Aile fonksiyonunun çıktısını `proteinId` yap. 278 tarif sinyal alır. Bu, spec’in “tahmin etme” cümlesiyle çelişir; sıra bağımlıdır.
- C: Aile çıktısı taslak liste olur, insan onayından sonra `curated` yazılır. Onaysız satır `unknown` kalır.

Öneri: **A şimdi, C ayrı kürasyon PR’sinde.** B uygulanmaz.

### K2 — `vegan` etiketi `plantBased` olur mu? (blok)

Spec: Mevcut yapılandırılmış alandan kesin eşlenen değer `unknown` kalmayabilir. Başlık ve mutfak kullanılmaz. Vegan veya vejetaryen güvenliği sözü yoktur.

Kod: `diets` küratörlü bir dizidir. `vegan` 38 tarif, hayvan ailesiyle çelişki 0. `vegetarian` süt ve yumurtayı dışlamaz.

- A: Eşleme yok. Bitki modu 0/325 ile başlar.
- B: Yalnız `vegan` → `plantBased`, kaynak `curated` (etiket zaten küratörlü). Vejetaryen, pesketaryen ve salata kursu `unknown` kalır.
- C: Vejetaryen ve içinde süt veya yumurta olmayan 5 tarifi de `plantBased` say.

Öneri: **B.** C, diyet etiketinin söylemediği bir yükseltmedir. Güvenlik metni yine “vegan filtresi değildir; malzeme dışlama ve tarif ayrıntısı geçerlidir” olarak kalır.

### K3 — Sebze ağırlıklı metadata (blok)

Spec: Küratörlü veya yapılandırılmış sebze-ağırlık. Başlık ve mutfaktan çıkarım yok. Bilinmeyen tarife artı veya eksi yok.

Kod: Bu işaret yok. Salata kursu 18 ve market ürün kümesi 312 tarifte geçiyor. İkisi de sebze ağırlık tanımı değildir.

- A: Alan eklenir, 325 satır `unknown`. Mod sıralamayı değiştirmez; özet bunu dürüst söyler.
- B: Salata kursunu veya ürün malzemesini pozitif sinyal say.
- C: Küçük bir küratör listesi (K4) `vegetables` grubunu elle işaretler.

Öneri: **A + C.** B spec’e aykırı. Mod, işaret yokken “daha sebzeli hafta” cümlesini kurmaz.

### K4 — Kürasyonun ölçüsü (blok, PR 7)

Spec: Yerleşik metadata küratörlüdür. Kabul kapısı etiketlerin yapılandırılmış veriye dayanmasını ister. 325’in tamamını şart koşmaz.

- A: Yalnız test fikstürü. Katalog 0/325 kalır. Dört mod kontrol edilir ama köpek mamasında fark görünmez.
- B: Her mod için pozitif ve negatif örnekler katalogda elle işaretlenir. Gerisi `unknown`.
- C: 325 tarifin tamamı bu sürümde işaretlenir.

Öneri: **B.** C bu adımın veri işidir, sıralama kodunun önkoşulu değildir. İşaretsiz tarif asla sıfır hanesine yazılmaz.

Besin grubu kimlikleri spec’te örnektir, kapalı liste değildir: `vegetables`, `legumes`, `grains`, `fruit`. Öneri bu dörtle sınırlı kalsın. Süt, yumurta ve et `proteinId` ailesindedir; besin grubuna ikinci kez konmaz.

### K5 — Uç mü, mevcut mutasyon mu? (blok)

Spec: Mevcut sürüm, kimlik, yetki, idempotency ve çatışma. Uçlar “gerekirse” önerilir. Tercih yerel kalacaksa kullanılmayan uç açılmaz. Ev tercihi ortak planı etkiliyorsa sunucu otoritesindedir.

Kod: Ev yazımı `POST /v1/households/:householdId/mutations`, `entityType: preference`, `baseRevision`, `Idempotency-Key`. Üyelik yeter; sahip şartı yok. Kişisel planlama tercihinin canlı API’si yok. `X-Client-API-Version` yalnız `1` ve `v1` kabul eder. Yeni bir `/v2` bu kapıyla uyumsuzdur.

- A: Spec’teki dört yeni uç.
- B: Ev alanları mevcut tercih mutasyonuna eklenir. Kişisel tercih SwiftData’da kalır ve hesap aktarımı `0016` kolonlarına gider. Canlı kişisel uç yok.

Öneri: **B.** A, aynı iş için ikinci yazma yolu açar ve idempotency’yi unutma riski taşır. Ev değeri sunucudadır; kişisel plan zaten cihaz yerelindedir.

### K6 — “Üst önceliği geçemez” nasıl kodlanır? (blok)

Spec: V6 sıralama sinyalidir ve üst kuralı geçemez. Deterministik planlayıcı kalır.

Kod: Üst kuralların sert olanları elemedir. Hafıza, çeşit, keşif ve kiler aynı tamsayıdadır. Kiler adımı 8’dir (tavan 24). Bir puanlık fark bile sırayı değiştirir.

- A: Sıralama anahtarı `(mevcut V5 toplamı + kiler, V6, slug)`. V6 yalnız beraberliği bozar. Üst skor bir puan farklıysa V6 sırayı değiştirmez. “Tercihi artır” cümlesi zayıf kalır.
- B: V6 ayrı terimdir, mutlak değeri 7’yi geçmez. Bir kiler adımını (8) geçemez. Hafıza farkı 6 ise geçebilir.
- C: Sözlük sırası: önce hafıza, sonra kiler, sonra V6. Mevcut tek tamsayı sıralama değişir; kapalı modda bile V5 sırası kayabilir.

Öneri: **B, ve kapalı modda terim sıfır.** A spec’teki “artır” etkisini neredeyse kapatır. C, kapalı modda V5’i koruma testini kırar. Sert eleme (dışlama, veto, Never Again, süre) her seçenekte filtredir, skora girmez.

### K7 — Ortak planlayıcıda kiler yok

Spec sırası kilere 6, V6’ya 7 numara verir.

Kod: `HouseholdPlanner` kiler almaz. Kişisel planda kilitli akşamları dolduran `refillAroundLockedMeals` da `pantryStock` geçirmez. Taze kişisel hafta geçirir.

- A: V6’yı her iki kişisel yola ve ortak planlayıcıya ekle. Kiler koduna dokunma.
- B: V6 bahanesiyle kileri ortak planlayıcıya ve kilitli doldurmaya ekle.

Öneri: **A.** B, V5 ortak haftasını ve kilitli yenilemeyi değiştirir. Ayrı bir iş olarak sorulmadan yapılmaz.

### K8 — Akıllı değiştirme V6’yı görür mü? (blok)

Spec: Değiştirme akışı durur. Sıralama entegrasyonunu hafta seçimine yazar, değiştirme listesine yazmaz.

Kod: `MealReplacement` kendi skorunu kullanır. Mod yalnız hafta seçimindeyse, sebze ağırlıklı haftadan yapılan değiştirme modu yok sayar.

- A: Akış aynı kalır, skor aynı kalır.
- B: Aynı V6 terimi değiştirme skoruna da eklenir. Ekran ve veto kuralları değişmez.

Öneri: **B.** Aksi halde mod, kullanıcının bir sonraki dokunuşunda düşer.

### K9 — Özet hangi sayıları gösterir? (blok)

Spec örneği: “Vegetable-forward: 2 meals”, “Plant-forward: 1 meal”. Yüzde yok. Bilinmeyen sıfır değildir. Beslenme yeterliliği ima edilmez.

Kod: Böyle bir bölüm yok.

- A: Yalnız aktif modun sayısı.
- B: Bilinen sınıflar: sebze grubu olan öğün, `plantBased` veya `plantDominant` öğün, `proteinId` kayıtlı öğün. Sonuncunun metni “Protein kaynağı kayıtlı”, “protein ağırlıklı” değil. `animalForward` sağlık cümlesi olmaz.
- C: Dört modun dördünü her hafta göster; bilinmeyenleri 0 yaz.

Öneri: **B.** C spec’e aykırı. A, “haftanın karışımı” cümlesinden dar.

Kapsam eksikliği: plandaki öğünlerden biri, gösterilen sınıfta `unknown` ise dipnot düşer. Hepsi `unknown` ise sayı satırı hiç çizilmez, yalnız dipnot kalır.

### K10 — Ev kaydı yokken ortak plan hangi modda?

Spec: Varsayılan `balanced` ve açık. Ev kaydı ancak açık seçimle oluşur. Kişisel tercih eve kopyalanmaz. Kapatmak V5 sıralamasına döner.

Bu üç cümle birlikte okununca ev için iki anlam çıkar.

- A: Ev kolonu NULL ise ortak plan V5’tir (kapalı gibi). Kişisel planda yükseltme `balanced` + açıktır.
- B: Ev kaydı yoksa da ortak plan `balanced` uygulanır, satır yazılmaz.
- C: Kişisel mod, ev boşken ortak plana uygulanır.

Öneri: **A.** B, evin seçmediği bir sinyali uygular. C, sessiz kopyadır ve spec’e aykırıdır. Arayüz ev için “Ayarlanmadı” der; “Dengeli” yazıp kaydetmiş gibi durmaz.

Kişisel planda `balanced` + tüm metadata `unknown` iken skor, kapalı modla aynı olmalıdır. Yükseltme haftayı kendiliğinden değiştirmez. Bu bir değişmezdir, seçenek değildir.

### K11 — Dil

Spec örnekleri İngilizce. “Your week at a glance”, “Today's Meal”. Tam çok dil V7’dir. Görünen adlar kimlikten ayrıdır.

Kod: Arayüz Türkçedir. Kimlikler İngilizce ve kararlıdır (`ingredientId`, `protein` ailesi).

Öneri: Kimlikler spec’teki İngilizce kodlar olarak kalır. Görünen metin Türkçe olur: hafta bölümü “Haftana bakış”, widget galeri adı “Bugünün yemeği”. İngilizce örnek cümleler ürün metni olarak kopyalanmaz. Bu, V7’yi öne çekmez; mevcut tek dili sürdürür.

### K12 — Widget “bugün” ve “hazırlık süresi”

Spec: Bugünün planlı akşamı. Yarın orta boyutta. Hazırlık süresi yalnız biliniyorsa. Plan yoksa boş durum ve uygulamayı açma. Bayat veya çevrimdışı son plan, taze senkron iddiası yok. Yenileme anı sözü yok.

Kod: `featuredEvening` bugün yoksa sonraki pişmemiş akşama, o da yoksa son akşama düşer. Kart süresi `totalMinutes`. `prepMinutes` katalogda her zaman en az 5; içe aktarmada `timeIsUnknown` süresi bilinmiyor demektir, 0 dakika değildir. Fotoğraf URL’si 195 tarifte var ama indirme ağ ister.

- A: Widget yalnız takvimdeki bugünün akşamını gösterir. Bugün planda yoksa “Bugün planlı akşam yok”. Uygulamanın “sıradaki akşam” kartı değişmez.
- B: Widget da sıradaki akşama düşer.

Süre:

- A: `prepMinutes`, `timeIsUnknown` değilse ve 0’dan büyükse. Karttaki toplam süreyle farklı sayı görünebilir.
- B: Kartla aynı toplam süre. Metin “hazırlık” değil, karttaki süre dilidir.

Bayat:

- A: Taze senkron cümlesi hiç yazılmaz. `weekStart` bu haftadan eskiyse “Son bilinen plan”.
- B: Dakika eşiği uydurmak.

Görsel:

- A: App Group’ta kopya dosya varsa o, yoksa yer tutucu. URL var diye ağ açılmaz.
- B: Widget URL’yi indirir.

Öneri: bugün için **A**, süre için **B**, bayat için **A**, görsel için **A**. Spec “prep time” der; kartla iki farklı dakika göstermek kullanıcının aynı yemeği iki süre sanmasına yol açar. Süre seçeneği bloktur. Bugün, bayat ve görsel önerileri spec’in boş ve ağsız kurallarıyla aynı yöndedir; süre sapması onay ister.

Orta boyutta yarın yoksa o yüz boş kalır, bir sonraki gün ödünç alınmaz.

### K13 — Widget verisi ve App Group

Spec: Paylaşılan yerel önbellek. Ağ yok. Önbellek şeması mevcut uygulama verisini bozmaz.

Kod: SwiftData uygulama sandbox’ındadır. App Group paylaşım yakalamasına aittir. Grubu SwiftData’ya bağlamak mevcut mağaza yolunu değiştirir.

Öneri: SwiftData yerinde kalır. Uygulama, plan değişince küçük bir JSON ve varsa küçültülmüş görsel dosyası yazar. Widget yalnız onu okur. Dosya adları `captures.json` ve `collection-index.json` değildir.

Ev modunda Bu Hafta, sunucu planı yerel `PlanWeek` üzerine işler (`HouseholdPlanBridge`). Widget bu yerel haftayı okur. Ayrı bir ağ planı çekmez.

### K14 — `MealPatternPreference` tablosu

Spec tek tip gösterir: `id`, `ownerType`, `ownerId`, `mode`, `enabled`, zamanlar, `version`.

Kod: Kişisel tercih tek `UserPrefs` satırıdır. Ev tercihi `household_preferences` ve `revision` kullanır. `created_at` bu ev tablosunda yoktur, `updated_at` vardır.

Öneri: Yeni çok biçimli tablo açılmaz. Kişisel alanlar `UserPrefs` ve aktarım kolonlarıdır. Ev alanları mevcut satırın NULL kolonlarıdır. Spec’teki `version` evde mevcut `revision` olur. İkinci sürüm sayacı eklenmez.

### K15 — Evdeki “tercih edilen protein” metni

Spec: Protein ağırlıklı mod, kayıtlı protein kaynağını öne alır. Gram hesabı yoktur.

Kod: Ev ayarında serbest metin “Tercih edilen protein” vardır. `HouseholdRecommendation` eşleşince +10 verir. Değer enum değildir.

Öneri: Bu alan V6 moduna dönüştürülmez ve silinmez. İkisi birlikte durabilir. Metin kutusuna `proteinForward` yazmak mod seçmek değildir.

### K16 — Bilinmeyen enum ve eski sunucu

Spec: Yeni istemcinin bilinmeyen enum değeri reddedilir veya sürüm kuralıyla ele alınır. Tahmin edilmez.

Kod: Zod katı pantry gövdelerinde bilinmeyen anahtarı reddeder. Tercih mutasyonunun `payload` alanı serbest kayıttır; `boardApply` yalnız bildiği anahtarları okur. Eski sunucu yeni anahtarı sessizce düşürür.

Öneri: Yeni sunucu bilinmeyen modda 400 döner. İstemci, cevapta alan yoksa ev modunu `balanced` varsaymaz; NULL sayar. API yolu `v1` kalır.

### K17 — Ortak tarif projeksiyonu

Spec: Ev tercihi ortak sıralamayı etkiler. Katalog metadata’sı sürümlüdür.

Kod: Katalog iki cihazda da paketle gelir; sunucu katalog tutmaz. Eşin kişisel tarifi `HouseholdRecipeProjection` üzerindedir (`protein` dizesi, `diets`). SQL tablosu `household_recipe_projections` (`payload JSONB`) migration `0004` içindedir. TypeScript board bu tabloyu okumaz. Board belgesi tercih, plan, market ve etkinliktir.

Öneri: V6 katalog sıralaması bu tabloyu açmadan çalışır. Kişisel tarifin yeni sınıfları projeksiyon yapısına eklenir; böylece aynı cihazdaki ortak plan o tarifi sınıflayabilir. O projeksiyonun eşin cihazına bugün gidip gitmediği PR 4’te doğrulanır. Gitmiyorsa V6 yeni bir tarif senkronu icat etmez; kişisel tarif eşte `unknown` kalır ve özet bunu saklamaz.

### K18 — Beslenme gramları modelde duruyor

Spec: V6 kalori ve makro hesaplamaz, ekranda toplam göstermez. Ayrı bir karar belgesi olmadan ulusal veri kümesi “dünya için tam” sayılmaz.

Kod: `calories`, `protein`, `fat`, `carbs` SwiftData’da. Arayüz bugün göstermiyor. İçe aktarma 0 yazıyor; 0, “yok” ile aynı görünür.

Öneri: Alanlar silinmez (hafif göç ve mevcut mağaza). V6 okumaz, sıralamaz, widget’a koymaz, özet ve detayda çizmez. Ayrı beslenme kararı bu PR’lerin konusu değildir.

### K19 — İsim çakışmaları

Bunlar sapma değil, uygulama kuralıdır:

- V6 tipi `MealPatternService` olmaz. O tip V2 hafıza kartıdır.
- Modun `balanced` değeri `DiscoveryLevel.balanced`, `RepeatPreference.balanced` ve `WeekdayStyle.balanced` ile aynı sözcük değildir. Profil metni üçünü ayırır.
- `Recipe.protein` gram kalır. V6 kimliği başka alandadır.

### K20 — Önkoşul cümlesi

Spec: V5 kabul kapısı geçmeli; küreselleşme denetimi koşulmalı; P0 ve P1 kapanmadan V6 yok. Ayrı V5.1 yalnız denetim kod istiyorsa açılır.

Kod ve kayıt: V5.1 açıldı ve 2026-10-12’de kapandı. Kalan Not verified satırlar Pass yapılmadı. Bu plan onları yeniden açmaz ve V6 özelliği saymaz.

## 7. Onaylanmadan değişmeyecek kurallar

- Dört mod tercih sinyalidir, sert diyet filtresi değildir. Dışlama, veto ve Never Again eler.
- Başlık, adım metni ve mutfak adından sınıf üretilmez.
- `0001`–`0015` dosyaları ve V5.0 / V5-Alignment-Audit dalları değişmez.
- Yükseltme karşılama açmaz ve yemek hafızasını yeniden yazmaz.
- Kalori, makro, fiyat, bütçe, beslenme API’si, tıbbi iddia ve sohbet bu sürüme girmez.
- Çekirdek plan, widget yüklü olmadan kurulur.
- Kişisel mod ev satırına kopyalanmaz.

## 8. Bu adımda yapılmayanlar

Özellik kodu, migration dosyası, katalog düzenlemesi, widget hedefi ve birleştirme yoktur. Blok kararlar (K1–K6, K8–K10, K12 süre) cevaplanınca PR 1 açılır.
