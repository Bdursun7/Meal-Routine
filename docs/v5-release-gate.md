# V5 release gate

Yönerge bölüm 16. Ürün sınırı `docs/v5-smart-pantry.md`. Yerel kurulum `docs/v5-local-runbook.md`.

`MARKETING_VERSION` `5.0.0`. `CURRENT_PROJECT_VERSION` `5`. Migration `0012_pantry` ve `0013_pantry_auto_add`. `0001`–`0012` dosyaları bu değişiklikte yeniden yazılmadı; `server/test/migrations.test.ts` `0001`–`0011` içinde pantry izi olmadığını ve `0013` kolonunun `ADD COLUMN` olduğunu doğrular.

## Bu ortamda koşan kontroller

| Komut | Sonuç |
| --- | --- |
| `cd server && npm run typecheck` | geçti |
| `cd server && npm test` | 2026-10-11 kısa-satır düzeltmesi: 63 geçti, 4 atlandı (Postgres yok). `remove` eski `pantry-auto:` anahtarını düşer. Postgres’li 66 / 66 kaydı 2026-10-10’dadır |
| `cd server && DATABASE_URL=postgres://… npm test` | 66 / 66 geçti, Postgres 16.15, atlanan yok (2026-10-10, V5.1 pişirme ve bildirim). Önceki re-audit 65 / 65, §9 |
| `Tools/run_pantry_domain_tests.sh` | `PantryDomainTests` 44 / 44, XCTest, Swift 6.0.3 Linux (2026-10-11, kanonik market kartı). Önceki kayıt 42 / 42 (2026-10-10) |
| `Tools/run_grocery_checks.sh`, `run_portion_checks.sh`, `run_household_checks.sh`, `run_memory_checks.sh`, `run_recommender_checks.sh`, `run_product_gap_checks.sh` | 2026-10-11 geçti. 125 g + 1 kg `1,125 kg` kalır. `tomato` + `tomatoes` tek satır. `run_recipe_photo_checks.sh` bu değişiklikte yeniden koşulmadı |

Swift dosyalarından SwiftUI ve SwiftData kullananlar (`PantryView`, `PantryRules`, `GroceryView`, `GroceryViewModel`, `HouseholdSession`, `APIClient`) ve `MealRoutineTests/PantryTests.swift` Linux’ta derlenemez. Bunlar Mac’te Xcode ile derlenip koşulur.

## Kapı

| Madde | Durum | Kanıt |
| --- | --- | --- |
| Pantry CRUD | pass | `pantry.test.ts` “creates, lists, updates and deletes…”, idempotent create replay; Postgres’te “enforces the pantry rules…” |
| Household authorization | pass | Üye olmayan hesap `GET`, `POST`, `PATCH`, `DELETE`, `reconcile-grocery` ve `POST …/ingredients` için 403 |
| Başka household erişimi | pass | Başka evin `itemId`’si 404; liste ve export yalnız kendi evini döner |
| Uyumlu birimler | pass | 400 g + 1 kg → 1400 g tek satır; g ↔ kg düzenlemesi stoku korur (`testSwitchingGramsToKilogramsKeepsTheSameStock`) |
| Uyumsuz birimler | pass | Adet gram satırına karışmaz; `confirmSeparate` ile ayrı satır. Bilinmeyen birim `confirmSeparate` ile de reddedilir |
| Yalnız ingredient kimliği | pass | Sunucu ve istemci `ingredientId` ile eşler. “Domates” / “Cherry domates” ayrı kalır. Sözlük `0012` ile seed edilir. Serbest ad, tekil birebir ad/eş anlamlıysa ona bağlanır; değilse `custom:<uuid>` olur (`testFreeTextLinksOneExactNameAndOtherwiseCreatesACustomIngredient`) |
| `bestBefore` / `useBy` | Linux metin Pass; Mac ekran ve SwiftData Not verified | Tarih yalnız kullanıcı girerse vardır ve `YYYY-MM-DD` olarak kalır. Geçmiş `useBy` “Girilen son tüketim tarihi geçti”, geçmiş `bestBefore` “Girilen tavsiye edilen tüketim tarihi geçti”. Bu cümleler güvenlik veya tazelik hükmü değildir. Planner geçmiş `useBy` stoğa bonus vermez. Ekran ve SwiftData mağazası Mac’te doğrulanır. Not verified, Pass sayılmaz |
| Eksik miktar | pass | 1000 g ihtiyaç, 400 g stok → 600 g. Replay aynı gövdeyi döner, stok değişmez. İstemcide iki kez hesaplamak tekrar düşmez (`PantryTests`) |
| İşaretli market satırı | pass | `checked` satır hesapta aynen kalır (sunucu ve `testIncompatibleUnitsAndCheckedRowsStayAsWritten`) |
| Sessiz düşüm yok | pass (Linux kural) / Mac ekran | Plan, planı açmak, işaretlemek, market satırını tamamlamak ve planı yenilemek stok düşmez. “Pişirdim” tek başına düşmez. Red stoku değiştirmez. Onay, aynı `ingredientId` ve g/kg ile ml/l için stokla sınırlı düşer (`testDeclineAndOtherPlanEventsDoNotChangeStock`, `testConfirmDeductsOnlyConvertibleStockAndCapsAtWhatIsThere`). `PantryTests.testPlanningAndCookingNeverChangePantry` Mac’te |
| “Bitti” | pass | Seçim yapılmadan stok değişmez; İptal miktarı korur |
| Offline queue | pass | Her household yazımı önce cache’e, sonra sabit `Idempotency-Key` ve `baseVersion` ile kuyruğa girer. Çevrimdışıyken gönderilmez, dönüşte bir kez gönderilir; sunucu replay’i ikinci kez uygulamaz |
| Conflict | pass | Eski `baseVersion` 409 ve `current` döner. Kuyruk `requiresResolution`, satır sunucu halini gösterir, “Bu malzeme başka bir cihazda güncellendi.” görünür. “Sunucudaki hali kullan” veya “Değişikliğimi yeniden uygula”; ikisinde de sessiz kayıp yok |
| Reddedilen istek | pass | 400/422 sonsuz retry olmaz, `failed` olur; kullanıcı yeniden dener veya atar |
| Migration | pass | `0012` ve `0013` V4.1 verisi olan Postgres’te household, board ve hesap satırlarını silmeden uygulanır (`pantry.integration.test.ts`). `0013` yalnız `auto_add_to_grocery BOOLEAN NOT NULL DEFAULT false` ekler. `DROP TABLE` yok |
| Account deletion | pass | Tek üyeli ev silinince pantry gider; partner kalırsa kalır. Silinen hesabın idempotency satırı silinir; telefon kişisel pantry’yi ve ev kopyasını temizler. Evden çıkınca o evin cache’i telefonda kalmaz |
| V1–V4.1 regresyon | pass (Linux) / Mac | Sunucu paketi yeşil. Linux check betikleri yeşil. Boş pantry V4.1 planını ve açıklamasını değiştirmez. Tam XCTest paketi Mac’te |
| Türkçe metinler | pass | Yükleniyor, boş, hata + yeniden dene, çevrimdışı, conflict, failed metinleri `PantryCopy` içinde; boş metin yönergedeki cümle |
| VoiceOver / Dynamic Type / Dark Mode | Mac | Satır tek VoiceOver etiketi okur (ad, miktar, konum, minimum, tarih, uyarılar, eşitleme). Varsayılan yazı boyutunda satır içeriğe göre sıkıdır; kontroller yalnız erişilebilirlik boyutlarında alt alta dizilir. Renkler sistem semantik renkleri. Cihazda görsel tur Mac + simülatör gerektirir |
| Onaylı pişirme düşümü | Linux pass / Mac ekran | Red ve plan olayları stok yazmaz. Onay tavanlar, uyumsuz birimi atlar, aynı yemeği ikinci kez düşmez |
| Düşük stok bildirimi | Linux pass / Mac teslim | Üstten alta bir kez; aynı bölümde tekrar yok; üstüne çıkınca yeniden kurulur. Kapalıyken geçiş spam yapmaz. Uzak push yok |
| `autoAddToGrocery` | Linux pass | Varsayılan kapalı. Açıkken eksik miktar `pantry-auto:<kanonikId>\|<kova>` anahtarına bir kez yazılır (`family:mass`, `unit:piece`). İşaretli satır durur. İki üye `mode: set` ile tek satır (`board.test.ts`). `pantry-cook:` eşik miktarını ezmez |
| Market kartı | Linux pass | Plan kimliği kanonik id + birim kovası (2026-10-11). `tomato` ve `tomatoes` tek satır; `cherry-tomato` ayrı. Görünen ad birleştirmez. Kart parçaları toplanmaz. Etiketler Plan, Evdekiler eksiği, Eşik, Pişirme eksiği, Elle eklendi. Eski kısa satırlar tek `pantry-auto:` satırına iner; 1 ve 2 toplanmaz, büyük olan kalır. Aynı etiket iki kez görünmez |
| Tarih hatırlatması | Linux pass / Mac izin | `YYYY-MM-DD` günü İstanbul, Auckland ve Los Angeles takvimlerinde aynı kalır. Saat 09:00 cihaz dilimindedir. Household timezone yok |
| iOS XCTest | Mac | `PantryDomainTests` Linux’ta 44 / 44. `PantryTests` (SwiftData cache, outbox, conflict, transfer, plan/cook; plan satırı `tomato`) Xcode’da koşulur |
| API, migration, runbook | pass | `docs/v5-local-runbook.md`, `server/db/README.md` |

Kapsam dışı ve bilerek yapılmayan: barkod, OCR, LLM tanıma, tarif sitesi çıkarımı, fiyat / bütçe (V6), harici son kullanma API’si, otomatik tarih tahmini, üye sınırı artışı, Apple Sign in / APNs / TestFlight.

## Mac’te yapılacaklar

1. `MealRoutine.xcodeproj` aç, `MealRoutine` şemasını iOS 18 simülatöründe derle.
2. `MealRoutineTests` koş; özellikle `PantryTests` ve `PantryDomainTests`.
3. Pantry ekranında VoiceOver, en büyük Dynamic Type ve Dark Mode ile liste, form, conflict ve hata durumlarını gez.
4. `Debug-Local` ile yerel sunucuya bağlanıp iki simülatörde aynı satırı düzenleyerek conflict akışını dene.
5. Planlı bir yemeği pişir, puanı kaydet. “Evdekilerden düş” sayfası sekmenin üstünde açılır. “Vazgeç” stoku bırakır. “Düş” yalnız çevrilebilir birimi ve eldeki miktarı düşer; sayfa kapanır ve kısa bir onay görünür. Uyumsuz birim düşülmez. Stok 0 “Stok kadar düşülür” demez.
6. `autoAddToGrocery` kapalıyken eşiğin market satırı açmadığını, açıkken `pantry-auto:<kanonikId>\|<kova>` satırının bir kez yazıldığını ve işaretli satırın durduğunu kontrol et. İki simülatör aynı eşiği görünce ikinci market satırı açılmamalı. Pişirme eksiği aynı kartta ayrı parça olarak durur ve eşik miktarını değiştirmez.
7. Market’te “Domates” ara. `tomato` ve `tomatoes` tek karttır. Plan, evdekiler eksiği ve elle eklenen miktar ayrı ayrı görünür, toplanmaz. Kartın kutusu bütün parçaları işaretler; kısmi durumda eksi görünür. Koridor “Sebze ve meyve”dir. “X daha alınacak” plan kalanıdır. Bitti ikinci bir eksik satırı açmaz. Hafta yokken Bitti “Önce bu haftanın planını kur…” der.
8. Tarih hatırlatmasını aç. İzin verilmezse “Bildirim izni kapalı…” cümlesi görünür ve Evdekiler kaydı yine çalışır. Tarih değişince eski gün, silinince bekleyen hatırlatma kalkar.
9. VoiceOver, en büyük Dynamic Type ve Dark Mode ile pişirme onay sayfasını ve Evdekiler anahtarlarını gez.
