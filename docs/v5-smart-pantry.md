# MealRoutine V5 — Smart Pantry

**Roadmap:** V1 Core Meal Planning → V2 Personal Meal Memory → V3 Personal Recipe Collection → V4 Household & Shared Planning → V4.1 Release Hardening → **V5 Smart Pantry** → V6 Balanced Nutrition → V7 Globalization & Localization

**Durum:** Dört durum birbirinin yerine geçmez.

- **Kodda uygulanmış:** Household pantry CRUD, `ingredientId` sözlüğü, `dateType` / `dateValue`, uyumlu birim birleştirme, açık kullanıcı eylemiyle market ↔ pantry, kişisel pantry’nin cihazda kalması, offline kuyruk ve `version` çakışması, planner’da geçmiş `useBy` stoğuna bonus verilmemesi. Kaynak: `server/db/migrations/0012_pantry.sql`, `server/src/pantryService.ts`, `MealRoutine/Services/PantryDomain.swift`, `MealRoutine/Services/WeekPlanService.swift`.
- **Otomatik testle doğrulanmış (2026-10-10, Linux, V5.0 denetimi):** `cd server && npm test` Postgres 16.15 ile 65/65 geçti, atlanan yok. `npm run typecheck` geçti. `Tools/run_pantry_domain_tests.sh` 31/31 geçti (Swift 6.0.3). Diğer `Tools/run_*.sh` betikleri geçti. O koşunun ham çıktısı `docs/MealRoutine_V1-V5_Cross_Version_Audit_Report.md` içindedir ve nötr tarih metnini kapsamaz: o sürümdeki test “Güvenlik uyarısı” önekini bekliyordu. V5.1 kodu bu öneki kaldırdı. V5.1 komut çıktısı aynı raporda, bu cümlenin yerine geçecek şekilde yenilenir; bu paragraf tek başına V5.1 testinin geçtiği anlamına gelmez.
- **Xcode / iOS cihazında doğrulanmış:** Doğrulanmadı. `PantryTests`, `PantryView`, VoiceOver, Dynamic Type ve Dark Mode Mac + Xcode ister. Bu belge onları geçmiş saymaz.
- **Ürün kabul kapısı kapandı:** Hayır. Kapı, doküman–kod uyumu, geçmiş `useBy` için nötr metin ve platforma özgü iOS kontrolleri doğrulanmadan kapanmaz.

> V5.0 pantry işlevleri uygulanmış durumda; V5 kabul kapısının kapanması için doküman-kod uyumu, geçmiş `useBy` tarihindeki nötr metin ve platforma özgü iOS kontrolleri doğrulanmalıdır. Bu belgede test sonucu olarak yalnızca gerçek komut çıktısı veya CI kanıtı bulunan kontroller işaretlenir.

**V4.1 ön koşulu:** V4.1 kod ve otomatik test kapsamı V4.1 belgelerinde tanımlıdır. Apple Developer hesabı, gerçek APNs, iki fiziksel cihaz, TestFlight / App Store ve bazı manuel UX kontrolleri bilinçli olarak ertelendi. Bu karar V5 geliştirmesini engellemez. V4.1’in kendi kabul kapısı bu belgenin konusu değildir.

## 1. Amaç

V5, evde bulunan malzemeleri haftalık plan ve ortak market listesiyle birleştirir. Kullanıcı stoktaki malzemeyi ekler, miktarı günceller, tüketir ve gerektiğinde eksik miktarı market listesine taşır.

Pantry, planı sessizce değiştiren bir otomasyon değildir. Kullanıcı hangi malzemenin hesaba katıldığını ve hangi işlemin stoku değiştirdiğini görebilir.

V5, V1–V4.1 davranışlarını korur. Fiyat, bütçe, fiyat geçmişi ve market sağlayıcı entegrasyonu V5 kapsamı dışındadır. V6 Balanced Nutrition da kalori, makro, klinik beslenme, fiyat ve bütçe içermez.

## 2. Ürün sınırı

### V5.0 kapsamı

Kodda ve V5.0 testlerinde karşılığı olanlar:

- Pantry malzemesi ekleme, düzenleme, tüketme ve silme
- Sayısal miktar ve yapılandırılmış birim
- Pantry konumu: kiler, buzdolabı, dondurucu veya diğer
- İsteğe bağlı minimum miktar (eşik bilgisidir; tek başına market satırı açmaz)
- İsteğe bağlı tarih türü ve tarihi (`bestBefore` / `useBy`, `dateValue` takvim günü)
- Uyumlu birimlerin birleştirilmesi
- Uyumsuz birimlerin ayrı satırda tutulması (kullanıcı `confirmSeparate` ile onaylar)
- Ortak market listesinde eksik miktar hesabı (`compute-missing`; stok yazılmaz)
- Kullanıcının seçtiği satır için pantry’den düşme ve pantry’ye ekleme
- “Bitti” sonrası açık seçenek: markete ekle, minimuma göre eksik hesapla veya sil
- Pantry kullanan tarifler için açıklanabilir öneri sinyali
- Household üyeleri arasında server-authoritative senkronizasyon
- Offline görüntüleme ve bekleyen işlem kuyruğu
- Merkezi ingredient sözlüğü ve `custom:<uuid>` ev malzemesi

### V5.0 kapsamı dışında

Aşağıdakiler V5.0’da kod ve test olarak yoktur. Bu belge onları mevcut özellik gibi anlatmaz ve V5.0’a ekleme izni vermez. İleride eklenecekse ayrı kapsam kararı, ayar varsayılanı, idempotency kuralı, bildirim davranışı ve test seti gerekir.

- Minimum stok eşiği geçilince market listesine otomatik ekleme (`autoAddToGrocery` yok)
- Düşük stok bildirimi (satır rozeti “Azaldı” bir push bildirimi değildir)
- `bestBefore` / `useBy` için otomatik tarih hatırlatması ve hatırlatma takvimi
- Yemek pişirildikten sonra, onaylı olsa bile, otomatik stok düşümü
- Barkod tarama
- Fiş veya OCR ile otomatik stok çıkarma
- LLM ile malzeme tanıma
- Tarif sitelerinden otomatik malzeme çıkarma
- Market fiyatı, bütçe, fiyat geçmişi, market sağlayıcı
- Son kullanma tarihi için dış veri servisi
- Otomatik tarih tahmini
- Household üye sınırını artırma

V5.0 kuralı: Pantry → Grocery ve Grocery → Pantry değişiklikleri kullanıcı tarafından açıkça başlatılır. Plan değişikliği stok miktarını sessizce düşürmez. “Pişirdim” stok düşürmez.

## 3. Veri sahipliği

Paylaşılan pantry’nin sahibi household’dır. Ortak pantry V4.1 sunucu modeline uygun olarak server-authoritative’dir.

Household yokken kullanıcı kişisel, yerel pantry kullanır. Bu veri sunucuya yazılmaz (`PantryItem.householdID == nil`, `MealRoutine/Models/GroceryItem.swift`). Household oluşturulunca kişisel pantry otomatik olarak ortak veriye karışmaz. Uygulama aktar, kopyala veya ayrı tut seçeneklerini sunar (`PantryTransferPolicy`, `MealRoutine/Services/PantryDomain.swift`). Kullanıcı onaylamazsa kişisel pantry cihazda kalır.

Pantry verisi:

- Başka bir household tarafından okunamaz veya değiştirilemez.
- Kişisel Meal Memory’yi değiştirmez.
- V3 tarifinin sahipliğini değiştirmez.
- Account deletion kurallarına uyar.
- Ortak plan ve market listesiyle ilişkilendirilebilir, fakat bunların yerine geçmez.

## 4. Pantry modeli

Kanonik adlar `0012_pantry` SQL, sunucu modeli ve API gövdesinden gelir. `bestBefore` bir API alanı değildir. iOS kanonik gün `calendarDay` (`YYYY-MM-DD`) alanındadır; teldeki ad `dateValue`’dur. Eski `bestBefore: Date` kolonu mağazanın açılması için durur. Karşılaştırma bölüm 13’tedir.

```text
PantryItem
  id
  householdId          -- yanıtta; istek gövdesinde yok. Kişisel satırda iOS’ta nil
  ingredientId
  displayName          -- görünen metin; kimlik değil
  quantity             -- sayı, >= 0
  unit                 -- yapılandırılmış birim kodu
  location
  minimumQuantity?     -- aynı satırın birimi; negatif olamaz
  dateType?            -- bestBefore | useBy; dateValue ile birlikte veya hiçbiri
  dateValue?           -- YYYY-MM-DD takvim günü
  version
  createdAt
  updatedAt
```

### Alan kuralları

- `id` sunucuda kalıcı kimliktir. Offline oluşturulan öğe için istemci UUID’si idempotent biçimde korunur.
- `householdId` istek gövdesinden kabul edilmez. Üyelik erişim belirtecinden, household yolu URL’den doğrulanır (`POST /v1/households/:householdId/pantry/items`, gövde şeması strict).
- `ingredientId`, tarif, market ve pantry sözlüğündeki kimliktir. Görünen metinden türetilen bir anahtar değildir.
- `displayName` yalnız görüntüleme metnidir. Seed sözlükte Türkçe adlar vardır (`Domates`); İngilizce adlar da vardır (`Achiote paste`, `Cashews`, `0012_pantry.sql`). Dil, kimliği değiştirmez.
- Yazılan ad, büyük/küçük harf ve diakritik farkı yok sayılarak tek bir maddenin adı veya eş anlamlısıyla birebir örtüşürse o `ingredientId` bağlanır. Örtüşme yoksa veya birden fazla madde aynı ada sahipse `custom:<uuid>` oluşturulur. Ortak evde `POST /v1/households/:id/ingredients` ile kaydedilir. Kişisel pantry’de yalnız cihazda durur. “Domates” ile “Cherry domates” kendiliğinden birleşmez. Eşleşme LLM ile yapılmaz.
- `quantity` negatif olamaz. Sunucu binde birliğe yuvarlar (`roundPantryQuantity`).
- `unit` bilinmeyen veya geçersizse kayıt reddedilir. Kullanıcı uyumsuz birimi `confirmSeparate: true` ile ayrı satır yapabilir; bilinmeyen birim o bayrakla da reddedilir.
- `minimumQuantity` boş olabilir. Doluysa negatif olamaz. Ayrı bir birimi yoktur; satırın `unit` değeriyle yorumlanır. Eşik, market listesine otomatik satır eklemez.
- `dateType` yalnız `bestBefore` veya `useBy` olabilir. İkisi aynı anlama gelmez.
- `dateValue` takvim günüdür (`YYYY-MM-DD`, SQL `DATE`). Saat dilimi anına çevrilip bir gün kaydırılmaz. iOS kanonik alan `calendarDay` aynı stringi tutar. Ayrıntı ve kabul edilmiş eski kişisel satır istisnası bölüm 13’tedir.
- Kullanıcı tarih girmediyse sistem tarih uydurmaz. Tarih çifti ya ikisi birden vardır ya hiçbiri (`pantry_items_date_pair`).
- Sistem tarih üzerinden gıda güvenliği kararı vermez. Geçmiş bir tarih, türüyle birlikte ve tarihin geçmiş olduğu nötr bir metinle gösterilir. “Güvenlik uyarısı”, “Tazelik uyarısı”, “bu ürün yenmez”, “güvenlidir” / “güvenli değildir” ürün metni değildir.
- Geçmiş `useBy`, tarif öneri puanını artıran olumlu bir stok sinyali değildir (`PantryPlanningSignal.usable` bu satırı eler). Yaklaşan tarih, “Tarihi yaklaşan malzemeyi kullanıyor” açıklamasıyla küçük bir sinyal olabilir; bu bir güvenlik hükmü değildir.
- `updatedAt` ve `version` conflict çözümünde kullanılır.

### “Bitti” davranışı

“Bitti” bir pantry öğesini sessizce silmez. Seçim yapılmadan miktar değişmez. Kullanıcı şunlardan birini seçerse miktar sıfıra çekilir:

1. markete ekle,
2. minimum miktara göre eksik hesapla,
3. öğeyi sil.

İptal mevcut miktarı korur (`PantryFinishedFlow.quantity`).

## 5. Birim ve miktar kuralları

Dönüşüm yalnız desteklenen ve aynı birim ailesindeki çiftlerde yapılır. Dil veya ülke bir dönüşüm kuralı değildir.

Kanonik pantry birimleri (`0012_pantry.sql` `unit` kontrolü): `g`, `kg`, `ml`, `l`, `piece`, `tbsp`, `tsp`, `clove`, `pinch`, `slice`, `sprig`, `toTaste`.

- Gram ve kilogram `mass` ailesindedir (`unit_bucket`).
- Mililitre ve litre `volume` ailesindedir.
- Adet, kaşık, diş, tutam, dilim, dal ve “damak tadına” otomatik olarak grama veya litreye çevrilmez. Her biri kendi `unit_bucket` değeridir.
- Uyuşmayan birimler tek satırda birleştirilmez. Aynı household + `ingredientId` + `unit_bucket` tek satırdır.
- Kullanıcıya dönüşüm yapılamadığında açık bir seçim gösterilir (`pantry_unit_choice`, `confirmSeparate`).
- Yuvarlama, market birleştirmedeki binde birlik snap ile aynıdır.

Örnekler:

```text
Tarif ihtiyacı: 1 kg domates
Pantry: 400 g domates
Eksik: 600 g domates
```

```text
Tarif ihtiyacı: 6 adet yumurta
Pantry: 500 g yumurta ürünü
Sonuç: otomatik çıkarma yok; kullanıcı kararı gerekir
```

## 6. Pantry ekranı

Pantry, Market sekmesinden ayrıdır ve Profil’den açılır. Ortak household açık değilse kişisel yerel pantry gösterilir.

### Liste

Liste satırı şunları gösterir:

- Malzeme adı (`displayName`)
- Mevcut miktar ve birim (sayı ve birim kodundan; gösterim metninden parse edilmez)
- Konum
- Minimum miktar varsa eşik bilgisi
- Tarih varsa türün adı ve takvim günü
- Tarih geçmişse nötr durum: girilen tarihin geçmiş olduğu. Tür (`bestBefore` veya `useBy`) ayrıca görünür. Metin gıdanın güvenli veya güvensiz olduğuna karar vermez.

Geçmiş `useBy` rozeti “Girilen son tüketim tarihi geçti”, geçmiş `bestBefore` rozeti “Girilen tavsiye edilen tüketim tarihi geçti” (`PantryCopy.pastUseBy`, `PantryCopy.pastBestBefore`). Form alt yazısı paket üzerindeki tarih türünü seçip tarihi aynen girmeyi söyler (`PantryCopy.dateFooter`). “Güvenlik uyarısı”, “Tazelik uyarısı” ve “STT güvenlik içindir” kullanıcıya dönük metin değildir.

### Boş durum

İlk kullanımda açıklama:

> “Evdeki malzemelerini ekle. Planını ve marketini daha doğru hazırlayalım.”

Household verisi yüklenemediğinde boş liste gösterilmez; hata ve yeniden deneme eylemi gösterilir.

### Düzenleme

Miktar, birim, konum, minimum miktar ve tarih türü/tarihi tek düzenleme akışında değiştirilebilir. Kaydetme başarısız olursa yerel değer sessizce kesinleşmiş gibi gösterilmez.

### Malzeme adı

Kullanıcı adı serbest yazar. Yazarken sözlükteki adlar, eş anlamlılar ve bu evin (ya da kişisel listenin) özel malzemeleri önerilir. Öneriye basmak o `ingredientId` ile bağlar. Öneri seçilmezse bölüm 4’teki birebir / `custom:<uuid>` kuralı geçerlidir. Market satırında kimlik yoksa aynı kural geçerlidir.

## 7. Market listesi entegrasyonu

Pantry miktarı ortak market satırını otomatik olarak silmez. Market, kullanıcının açıkça onayladığı bir satın alma listesidir.

V5.0’da desteklenen işlemler:

- **Eksik miktarı hesapla:** Tarif ihtiyacından pantry miktarını düşerek eksik miktarı hesaplar. Stok yazılmaz (`compute-missing`).
- **Evdekilerden düş:** Kullanıcının seçtiği market satırını pantry miktarından azaltır (`consume`).
- **Evdekilere ekle:** Satın alınan miktarı pantry’ye ekler (`restock`).
- **Bitti olarak işaretle:** Kullanıcı bir seçenek onaylarsa miktarı sıfırlar ve seçeneğe göre markete ekleme veya silme önerir.

Kurallar:

- Pantry miktarı ihtiyacı karşılıyorsa eksik miktar sıfır olur.
- Pantry miktarı yetersizse yalnızca eksik miktar markete eklenir. Bu ekleme, “Eksik miktarı hesapla” eylemidir; eşik otomasyonu değildir.
- İşaretlenmiş market satırları korunur.
- Aynı mutation aynı `Idempotency-Key` ile yeniden gelirse market veya stok ikinci kez değişmez.
- Uyumsuz birimlerde otomatik çıkarma yapılmaz.
- Plan değişince pantry miktarı kendiliğinden azalmaz.
- Plan öğesini açmak, işaretlemek veya market satırını tamamlamak stoktan düşüm yapmaz.
- “Pişirdim” (`WeekPlanService.markCooked`) pantry miktarını değiştirmez. Onaylı pişirme düşümü V5.0’da yoktur.

## 8. Haftalık plan ve scoring

Pantry, öneri skoruna açıklanabilir bir sinyal olarak eklenebilir.

- Tarif, pantry’deki malzemelerin bir kısmını kullanıyorsa küçük bir avantaj alabilir (tavan, sert filtrelerin altında).
- Geçmiş `useBy` bu avantaja girmez ve “Evdeki malzemeleri kullanıyor” açıklaması üretmez.
- Geçmiş `bestBefore` güvenlik cezası değildir; stok hâlâ kullanılabilir sinyal olabilir. Metin gıda güvenliği hükmü vermez.
- Yaklaşan tarih (üç gün penceresi, bugün dahil) “Tarihi yaklaşan malzemeyi kullanıyor” notuyla işaretlenebilir.
- Pantry hiçbir zaman `Never Again`, household veto, pişirme süresi veya diğer hard filter kurallarını geçersiz kılmaz.
- Kişisel Meal Memory skorlaması korunur.
- Plan yeniden oluşturulunca pantry miktarı düşmez.
- Pantry boşsa mevcut V4.1 planlama davranışı aynen devam eder.

Pantry, otomatik planlama için zorunlu kaynak değildir. Kullanıcı planı pantry kullanmadan da oluşturabilir.

## 9. Mimari

```text
SwiftUI
  ↓
ViewModel / Repository
  ↓
SwiftData local cache
  ↕
SyncEngine + offline queue
  ↕
Versioned API
  ↕
Postgres server database
```

### Server

- Household üyeliği ve yetki sunucuda doğrulanır.
- Pantry item validation sunucuda tekrarlanır.
- Sunucu başka household erişimini reddeder.
- Sunucu conflict yanıtı ve `version` döner.
- `Idempotency-Key` aynı mutation’ın iki kez uygulanmasını engeller (24 saat, `pantry_idempotency`).
- Ingredient sözlüğü sunucuda authoritative kaynaktır. Başlangıç sözlüğü `0012_pantry.sql` seed’idir. Admin paneli yoktur.

### SwiftData

- Hızlı UI için cache tutar.
- Offline görüntülemeyi sağlar.
- Bekleyen pantry mutation’larını saklar.
- Server state yerine geçmez. Kişisel satırlar (`householdID == nil`) sunucu pantry’sine yazılmaz.

## 10. Offline ve sync

Offline yapılabilen işlemler:

- Daha önce senkronize edilmiş pantry’yi görüntüleme
- Miktar değiştirme
- Tüketim kaydetme
- Konum değiştirme
- Silme isteği oluşturma
- Market eksik miktarını son bilinen snapshot ile hesaplama

Bekleyen işlem alanları V4.1 ile aynı kalır:

```text
id
entityType
entityId
operationType
payload
createdAt
retryCount
status
idempotencyKey
```

Durumlar: `pending`, `syncing`, `completed`, `failed`, `requiresResolution`.

Retry exponential backoff ile yapılır. Bağlantı geri geldiğinde işlemler sırayla gönderilir; aynı işlem yeniden gönderilse de sonucu çoğalmaz.

## 11. Conflict resolution

İki cihaz aynı pantry öğesini değiştirirse sunucu sürümü kazanır. İstemci, kendi pending mutation’ını sessizce silmez. Eski `baseVersion` `409` ve `current` döner. Kuyruk `requiresResolution` olur.

Kullanıcıya şu metin gösterilir:

> “Bu malzeme başka bir cihazda güncellendi.”

Seçenekler: “Sunucudaki hali kullan” veya “Değişikliğimi yeniden uygula”. Sessiz veri kaybı kabul edilmez.

## 12. API sözleşmesi

V5, `0012_pantry` migration’ını ekler. `0001`–`0011` dosyaları değiştirilmez.

```text
GET    /v1/ingredients?householdId=&q=&limit=
POST   /v1/households/:id/ingredients
GET    /v1/households/:id/pantry
POST   /v1/households/:id/pantry/items
PATCH  /v1/households/:id/pantry/items/:itemId?baseVersion=
DELETE /v1/households/:id/pantry/items/:itemId?baseVersion=
POST   /v1/households/:id/pantry/reconcile-grocery
```

Yazımlar `Idempotency-Key` (8–200 karakter) ister. Aynı anahtar aynı gövdeyle ilk cevabı döner; farklı gövde `409` verir.

Gövde alanları: `ingredientId`, `displayName`, `quantity`, `unit`, `location`, `minimumQuantity`, `dateType`, `dateValue` (`YYYY-MM-DD`). Şema strict’tir. Eski `bestBefore` anahtarı oluşturma/yama isteğinde reddedilir (`invalid_request`). İstemci, kapı öncesi kuyrukta kalmış `bestBefore` / `revision` yükünü okuyabilir; telde kanonik ad `dateValue` / `version`’dır.

`reconcile-grocery` işlemi: `compute-missing`, `consume`, `restock`.

Endpoint kuralları:

- Access token zorunludur.
- Household üyeliği zorunludur.
- İstemci sahibi request body’den okunmaz.
- Geçersiz miktar, birim ve tarih reddedilir.
- Hata gövdesi `error` ve `recovery` taşır (`resolve`, `choose-unit`, `fix-input`, `new-key`, `refresh-household`, `retry-later`, `reauthenticate`).

## 13. Şema karşılaştırması (`0012_pantry`)

Karşılaştırma `V5-Alignment-Audit` `1f07663` üzerindedir. “Uyumlu” veya “tamamlandı” denmez. Aşağısı alan adı, nullability ve tarih temsilidir.

| Kavram | SQL `pantry_items` | Sunucu `PantryItem` | API JSON | iOS SwiftData `PantryItem` | iOS tel `PantryRemoteItem` |
| --- | --- | --- | --- | --- | --- |
| Kimlik | `id UUID` PK | `id: string` | `id` | `uuid` | `id` |
| Sahip | `household_id UUID NOT NULL` | `householdId` | yanıtta var; gövdede yok | `householdID: UUID?` (`nil` = kişisel, sunucuda yok) | `householdId` |
| Malzeme | `ingredient_id TEXT NOT NULL` FK | `ingredientId` | `ingredientId` | `ingredientID` | `ingredientId` |
| Görünen ad | `display_name TEXT NOT NULL` | `displayName` | `displayName` | `displayName` | `displayName` |
| Miktar | `quantity NUMERIC(12,3) NOT NULL` `>= 0` | `number` | `quantity` | `Double` | `Double` |
| Birim | `unit TEXT NOT NULL` (sabit liste) | `string` | `unit` | `unit` | `unit` |
| Birim kovası | `unit_bucket` üretildi, saklanır | yok | yok | yok | yok |
| Konum | `location TEXT NOT NULL` | `PantryLocation` | `location` | `locationRaw` | `location` |
| Minimum | `minimum_quantity NUMERIC(12,3) NULL` `>= 0` | `number \| null` | `minimumQuantity` nullable | `Double?` | `Double?` |
| Tarih türü | `date_type TEXT NULL` (`bestBefore`, `useBy`) | `dateType \| null` | `dateType` | `dateTypeRaw: String?` | `dateType?` |
| Tarih | `date_value DATE NULL` | `string \| null` `YYYY-MM-DD` | `dateValue` | `calendarDay: String?` (`YYYY-MM-DD`). Eski `bestBefore: Date?` kolonu durur; yeni yazım onu kullanmaz | `dateValue: String?` |
| Sürüm | `version INT NOT NULL` `>= 1` | `version` | `version` | `revision` | `version` (`revision` yalnız eski yük okuması) |
| Oluşturma | `created_at TIMESTAMPTZ NOT NULL` | `createdAt` ISO-8601 UTC | `createdAt` | modelde yok | `Date?` |
| Güncelleme | `updated_at TIMESTAMPTZ NOT NULL` | `updatedAt` ISO-8601 UTC | `updatedAt` | `updatedAt: Date` | `Date?` |

Tarih çifti: SQL `pantry_items_date_pair` — `date_type` ve `date_value` ikisi birden NULL ya da ikisi birden dolu. Sunucu `normalizeDatePair` aynı kuralı uygular ve `YYYY-MM-DD` dışını `invalid_date` ile reddeder. Postgres okuması `to_char(date_value, 'YYYY-MM-DD')` ile takvim gününü string döner (`server/src/pgPantry.ts`).

iOS farkları (davranış değişikliği değildir; kayıtlı eşlemedir):

- Kişisel satırın `householdID` değeri yoktur. SQL household satırı `household_id` olmadan duramaz. Bu, iki sahiplik modelidir.
- SwiftData kanonik gün `calendarDay` (`YYYY-MM-DD`) alanındadır. API bu adı görmez. Tel ve SQL adı `dateValue` / `date_value`’dur.
- `bestBefore: Date?` kolonu durur. Türü `String` yapılmaz. Mevcut mağaza bu yüzden açılır: eski kolonun tipi değişmez, `calendarDay` yeni opsiyonel bir kolondur ve boş satırlarda nil gelir. SwiftData hafif göç bunu açar; özel bir `VersionedSchema` yoktur.
- Yeni kayıt `calendarDay` yazar ve `bestBefore`’u nil bırakır. Okuma, gösterim, geçmiş/bugün/yaklaşan hesabı ve senkron gövdesi bu stringi kullanır. Saklanan `Date` cihaz saat diliminde tekrar okunmaz.
- Tarih seçici kenarında geçici bir `Date` üretilebilir. Kayıt, seçicinin takvimiyle okunan `YYYY-MM-DD` stringidir. Aynı string başka saat diliminde de aynı gündür.
- Eski kişisel satır (`householdID == nil`) hâlâ `bestBefore` anı taşıyorsa, proje sahibinin 2026-10-10 istisnasıyla bir kez silinir. Tarihsiz kişisel satır kalır. Adım `UserDefaults` anahtarı `mealroutine.pantry.v51.legacyPersonalDatedRowsRemoved` ile bir kez çalışır; ikinci açılış bir şey silmez. Bu, spec §2.5 ve §4.5’teki “belirsiz günü sessizce tahmin etme” kuralının veri kaybını kabul eden açık istisnasıdır (spec §6). Gün, cihaz saat diliminden tahmin edilmez.
- Eski ortak satır bu adımda silinmez ve `bestBefore` anından güne çevrilmez. `PantryCache.apply` sunucunun `YYYY-MM-DD` değerini `calendarDay`’e yazar ve anı siler. An hâlâ dururken giden yazı tarih alanlarını gövdeden çıkarır; sunucudaki günün üzerine kaymış bir gün yazılmaz.
- `dateTypeRaw` yalnız `calendarDay` doluyken tür olarak okunur. Sunucu yeni yazımda türsüz tarih kabul etmez.
- `unit_bucket` yalnız veritabanındadır.
- `createdAt` SwiftData modelinde yoktur. Saat damgaları sunucuda UTC anıdır; `dateValue` bir an değildir.

Migration:

- `0001`–`0011` değiştirilmez. `0012_pantry` ingredients, pantry_items ve pantry_idempotency ekler.
- `0012` öncesi pantry tablosu yoktur. Korunacak eski pantry satırı yoktur. V4.1 household, board ve hesap satırları `0012` uygulanırken silinmemelidir. Bunu `server/test/pantry.integration.test.ts` dener; sonuç audit report’tadır.
- Tekrar çalıştırma: `schema_migrations` kaydı varken `migrate` `0012`’yi yeniden uygulamaz. Seed `ON CONFLICT (id) DO NOTHING` kullanır.
- Geri alma: migration dosyasında `DROP TABLE` yoktur. Onarım, yayınlanmamış geliştirme veritabanı için `docs/v5-local-runbook.md` içindeki taslak düşürme notudur. Yayınlanmış şema için otomatik down migration yoktur.
- Hesap silinince pantry ve idempotency satırları hesap/household silme kurallarıyla gider (`ON DELETE CASCADE`).

Bu tabloda olmayan alanlar (`autoAddToGrocery`, `lowStockNotificationsEnabled`, `dateReminderEnabled`, `dateReminderSchedule`, gövdede `bestBefore`) V5.0 şemasına eklenmez.

## 14. Account deletion ve privacy

Kullanıcı hesabını sildiğinde:

- Kişisel pantry varsa kişisel veri olarak cihazdan silinir.
- Household pantry’si household ownership kuralına göre korunur veya, household siliniyorsa, household ile birlikte silinir.
- Silinen üyeye ait access ve refresh token’lar geçersiz kalır.
- Başka household üyelerinin verisi export’a karışmaz.
- Pantry idempotency satırı hesapla birlikte silinir. Kullanıcıya görünmeyen ayrı bir pantry kopyası bırakılmaz.

## 15. Kilitli kararlar

Bu liste tek yerdir. V5.0 uygulanırken yeniden açılmaz.

1. Ingredient kimliği `ingredientId`’dir. Çevrilmiş veya görünen ad kimlik değildir.
2. Birim dönüşümü yalnız desteklenen ve aynı birim ailesindeki dönüşümlerde yapılır.
3. Plan oluşturmak veya planı değiştirmek kiler stokunu sessizce değiştirmez.
4. Kullanıcı açıkça onaylamadıkça pişirme akışı stok düşmez. V5.0’da “Pişirdim” stok düşmez; onaylı düşüm akışı yoktur.
5. Kullanıcının girdiği tarih uydurulmaz. Tarih tek başına gıda güvenliği kararı üretmez. V5.1’de eski kişisel tarih anı takvim gününe çevrilmez; proje sahibi 2026-10-10’da bu satırların bir kez silinmesini kabul etti (bölüm 13). Ortak kiler tarihi sunucudan yeniden alınır.
6. V5’te fiyat, bütçe, fiyat geçmişi veya market sağlayıcı entegrasyonu yoktur.
7. Kişisel kiler, household kilerine otomatik ve sessizce birleştirilmez.
8. Stok ve market güncellemeleri tekrar denendiğinde çift kayıt veya çift düşüm üretmeyecek şekilde idempotent olmalıdır.
9. V5.0 kapsamı dışında kalan otomasyonlar uygulanmış özellik gibi gösterilmez.
10. Paylaşılan pantry’nin sunucu sahibi household’dır. Kişisel pantry yalnız cihazdadır; ayrı bir kişisel pantry backend’i yoktur.
11. V5 otomatik malzeme tanıma veya LLM eşlemesi yapmaz.
12. Plan oluşturmak pantry kullanmaya bağlı değildir.
13. `0012_pantry`, pantry şemasının kanonik migration’ıdır. `0001`–`0011` yeniden yazılmaz.

## 16. Uygulama fazları

Fazlar V5.0’da nerede durduğunu anlatır. Fazın listelenmiş olması, içindeki her maddenin kabul kapısını kapattığı anlamına gelmez.

### Faz 1 — Domain ve kararlar

Pantry modeli, sözlük, birim aileleri, `bestBefore` / `useBy`, sahiplik, API ve `0012` tasarımı kodda karşılık buldu.

### Faz 2 — Server

CRUD, validation, household authorization, idempotency, conflict ve migration test dosyaları vardır. Geçip geçmedikleri audit report’taki komut çıktısıdır.

### Faz 3 — Local cache ve sync

SwiftData cache, pending operation, retry ve conflict recovery kodu vardır. `PantryTests` Mac’te koşar; bu belgede geçti denmez.

### Faz 4 — Pantry UI

Liste, ekleme, düzenleme, konum, minimum miktar, tarih türü ve boş/yükleme/hata/çevrimdışı metinleri kodda vardır. Geçmiş tarih rozetleri bölüm 6’daki nötr cümlelerdir. Bildirim izni ve hatırlatma tercihleri V5.0’da yoktur.

### Faz 5 — Market entegrasyonu

Eksik miktar, evdekilerden düşme, evdekilere ekleme, işaretli satır ve idempotent replay kodda vardır. Otomatik eşik eklemesi yoktur.

### Faz 6 — Planner sinyali

Pantry kullanım sinyali ve geçmiş `useBy` için bonus verilmemesi kodda vardır. Metin güvenlik hükmü vermez.

### Faz 7 — QA ve release

Sunucu testleri ve Linux domain testleri audit report’ta kayıtlıdır. VoiceOver, Dynamic Type, Dark Mode ve Xcode `PantryTests` doğrulanmamıştır. Kabul kapısı açıktır.

## 17. V5 kabul kapısı

V5 tamamlanmış sayılmadan önce aşağıdakilerin hepsi sağlanır. Kutular bu belgede işaretlenmez. Sonuç audit report’tadır.

- Pantry CRUD testleri geçer.
- Household authorization testleri geçer.
- Başka household erişimi 403 veya tanımlı privacy davranışıyla reddedilir.
- Uyumlu birimler doğru birleşir.
- Uyumsuz birimler karıştırılmaz.
- Aynı ingredient kimliği dışındaki malzemeler yalnız görünen ad benzerliğiyle birleştirilmez.
- `bestBefore` ve `useBy` ayrı saklanır ve ayrı tür adıyla gösterilir.
- Kullanıcı girmediyse tarih üretilmez.
- Geçmiş tarih, nötr metinle gösterilir; gıda güvenliği hükmü verilmez.
- Eksik miktar hesabı doğru ve idempotent çalışır.
- İşaretlenmiş market satırları korunur.
- Plan ve “Pişirdim” stoku değiştirmez.
- Offline queue bağlantı dönüşünde işlemleri çoğaltmadan gönderir.
- Conflict sunucu haliyle deterministik çözülür.
- `0012` mevcut V1–V4.1 verisini silmez.
- Account deletion pantry ownership kurallarına uyar.
- V1–V4.1 regresyon testleri korunur.
- Loading, empty, error, offline ve conflict metinleri Türkçedir.
- VoiceOver, Dynamic Type ve Dark Mode kontrol edilir.
- API, migration ve local runbook güncellenir.

## 18. V5.0’da olmayan hatırlatma ve bildirim taslağı

v2 taslağının hatırlatma bölümü şunları tarif ediyordu: `bestBefore` için 2 gün önce ve tarihin kendisi, `useBy` için 1 gün önce ve tarihin kendisi; `lowStockNotificationsEnabled`, `dateReminderEnabled`, `dateReminderSchedule`.

`1f07663` kodunda bunlar yoktur:

- Sunucu bildirim türleri yalnız `invite`, `weekly_plan`, `meal_veto`, `meal_replacement`, `plan_finalized` (`server/src/notifications.ts`).
- Pantry için yerel takvim bildirimi, hatırlatma iptali veya düşük stok push’u yoktur.
- `minimumQuantity` satırda “Azaldı” rozeti üretir; market satırı açmaz.

Bu belge o taslağı V5.0 özelliği yapmaz. İleride eklenirse household timezone, cihaz bildirim izni, tarih değişince yeniden planlama, tüketim veya silmede iptal, idempotency ve testler ayrıca yazılır. Bildirim metni gıda güvenliği garantisi olmaz. Bildirim izni reddedilirse pantry’nin geri kalanı çalışmaya devam eder; bu cümle gelecekteki işin kuralıdır, V5.0’da bir izin ekranı olduğu iddiası değildir.

## 19. Global-readiness kuralları

- Ingredient kimliği daima `ingredientId` olur.
- Görünen ad sunum katmanındadır. Ayrı bir `IngredientName(locale)` tablosu V5.0 şemasında yoktur; seed `display_name` ve `synonyms` taşır.
- Quantity ve unit ayrı alanlardır.
- `dateValue` tarih-only’dir. Hatırlatma saati V5.0’da hesaplanmaz.
- `TR`, `TRY`, `metric`, `tr-TR` pantry modelinin kalıcı koşulu değildir. Arayüz metinleri Türkçedir; bu, iş kuralının ülkeye kilitlendiği anlamına gelmez.
- Kullanıcının yazdığı tarif adı, notu ve talimat pantry tarafından çevrilmez.

## 20. V5 sonunda beklenen ürün davranışı

Kullanıcı evdeki malzemeleri görür, miktarı günceller ve ortak markette eksik miktarı kendi eylemiyle hesaplar. Household üyeleri aynı pantry state’ini sunucu üzerinden paylaşır. Offline değişiklikler kaybolmaz ve çakışmalar sessizce veri silmez.

V5, stok farkındalığı katar. Fiyat ve bütçe V5’te yoktur. V6 Balanced Nutrition ayrı bir ürün belgesindedir: yemek örüntüsü tercihleri (`balanced`, `vegetableForward`, `proteinForward`, `plantForward`). Bu modlar tercih sinyalidir; alerji, `Never Again`, malzeme dışlama ve ev halkı vetosunu geçersiz kılmaz. V6 kalori, makro, klinik iddia, market fiyatı ve bütçe içermez. V7 Globalization & Localization, çok dilli arayüz ve bölgesel/global lansmandır. V6 bu belgeyle başlatılmaz.
