# MealRoutine V5 — Smart Pantry

**Roadmap:** V1 Core Meal Planning → V2 Personal Meal Memory → V3 Personal Recipe Collection → V4 Household & Shared Planning → V4.1 Release Hardening → **V5 Smart Pantry** → V6 Balanced Nutrition → V7 Globalization & Localization

**Durum:** Dört durum birbirinin yerine geçmez.

- **Kodda uygulanmış:** Household pantry CRUD, `ingredientId` sözlüğü, `dateType` / `dateValue`, uyumlu birim birleştirme, açık kullanıcı eylemiyle market ↔ pantry, kişisel pantry’nin cihazda kalması, offline kuyruk ve `version` çakışması, planner’da geçmiş `useBy` stoğuna bonus verilmemesi. V5.1 buna ekler: onaylı pişirme düşümü, isteğe bağlı düşük stok bildirimi, `autoAddToGrocery` (varsayılan kapalı) ve cihaz saat diliminde takvim günü hatırlatması. Kaynak: `server/db/migrations/0012_pantry.sql`, `server/db/migrations/0013_pantry_auto_add.sql`, `server/src/pantryService.ts`, `server/src/boardApply.ts`, `MealRoutine/Services/PantryDomain.swift`, `MealRoutine/Services/PantryRules.swift`.
- **Otomatik testle doğrulanmış (2026-10-10, Linux, V5.1 pişirme ve bildirim):** `cd server && npm test` Postgres 16.15 ile 66/66 geçti, atlanan yok. `npm run typecheck` geçti. `Tools/run_pantry_domain_tests.sh` 42/42 geçti (Swift 6.0.3). Önceki re-audit 65/65 ve 35/35 idi (`docs/MealRoutine_V1-V5_Cross_Version_Audit_Report.md` §9). Bu satır SwiftData mağazasını, tarih seçiciyi, `UNUserNotificationCenter` teslimini ve pişirme onay sayfasının ekranını geçmiş saymaz.
- **Xcode / iOS cihazında doğrulanmış:** Doğrulanmadı. `PantryTests`, `PantryView`, VoiceOver, Dynamic Type ve Dark Mode Mac + Xcode ister. Bu belge onları geçmiş saymaz.
- **Ürün kabul kapısı kapandı:** Hayır. Nötr metin Linux testinde geçti. SwiftData yükseltmesi, tarih seçici ve iOS ekran kontrolleri Not verified (Mac). Not verified, Pass değildir. V6 başlamaz.

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

Aşağıdaki dört madde V5.0 kodunda yoktu. V5.1 onları bölüm 21’deki kurallarla ekler. V5.0 belgesi onları V5.0 özelliği gibi anlatmaz.

- Minimum stok eşiği geçilince market listesine ekleme (`autoAddToGrocery`, varsayılan kapalı)
- Düşük stok bildirimi (satır rozeti “Azaldı” tek başına bir bildirim değildir)
- `bestBefore` / `useBy` için tarih hatırlatması
- Pişirme sonrası onaylı stok düşümü

Hâlâ kapsam dışı:

- Barkod tarama
- Fiş veya OCR ile otomatik stok çıkarma
- LLM ile malzeme tanıma
- Tarif sitelerinden otomatik malzeme çıkarma
- Market fiyatı, bütçe, fiyat geçmişi, market sağlayıcı
- Son kullanma tarihi için dış veri servisi
- Otomatik tarih tahmini
- Household üye sınırını artırma

V5.0 kuralı, V5.1’de de durur: plan değişikliği stok miktarını sessizce düşürmez. “Pişirdim” tek başına stok düşürmez. Düşüm, kullanıcı tüketim sayfasında “Stoktan düş” derse olur. Reddederse stok değişmez. Ayrıntı bölüm 21.

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
  autoAddToGrocery     -- 0013; varsayılan false. Kişisel satırda da aynı alan, yalnız cihazda
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
- `minimumQuantity` boş olabilir. Doluysa negatif olamaz. Ayrı bir birimi yoktur; satırın `unit` değeriyle yorumlanır. Eşik tek başına market satırı açmaz. `autoAddToGrocery` kapalıyken (varsayılan) eşik altına inmek market satırı yazmaz. Açıkken kural bölüm 21’dedir.
- `autoAddToGrocery` `BOOLEAN NOT NULL DEFAULT false` (`0013_pantry_auto_add.sql`). Create, list ve patch gövdesindedir. Gövdede yoksa mevcut değer kalır. Kişisel pantry aynı alanı SwiftData’da tutar; sunucuya gitmez.
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
- Plan öğesini açmak, işaretlemek, market satırını tamamlamak veya planı yeniden kurmak stoktan düşüm yapmaz.
- “Pişirdim” (`WeekPlanService.markCooked`) pantry miktarını değiştirmez. Puan kaydı iptal edilirse yemek pişmiş sayılmaz ve stok da değişmez. Puan kaydedilip yemek pişmiş işaretlenince tüketim onayı açılır. “Stoktan düşme” stoku olduğu gibi bırakır. “Stoktan düş” bölüm 21’deki kuralı uygular.

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
| Otomatik market | `auto_add_to_grocery BOOLEAN NOT NULL DEFAULT false` (`0013`) | `boolean` | `autoAddToGrocery` | `Bool`, varsayılan `false` | `Bool`, eski gövdede yoksa `false` |
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

- `0001`–`0011` değiştirilmez. `0012_pantry` ingredients, pantry_items ve pantry_idempotency ekler. `0013_pantry_auto_add` yalnız `auto_add_to_grocery` kolonunu ekler. Household saat dilimi kolonu yoktur.
- `0012` öncesi pantry tablosu yoktur. Korunacak eski pantry satırı yoktur. V4.1 household, board ve hesap satırları `0012` ve `0013` uygulanırken silinmemelidir. Bunu `server/test/pantry.integration.test.ts` dener; sonuç audit report §10’dadır. `0013` `DEFAULT false` olduğu için kolonu yazmayan eski `INSERT` durur.
- Tekrar çalıştırma: `schema_migrations` kaydı varken `migrate` `0012`’yi yeniden uygulamaz. Seed `ON CONFLICT (id) DO NOTHING` kullanır.
- Geri alma: migration dosyasında `DROP TABLE` yoktur. Onarım, yayınlanmamış geliştirme veritabanı için `docs/v5-local-runbook.md` içindeki taslak düşürme notudur. Yayınlanmış şema için otomatik down migration yoktur.
- Hesap silinince pantry ve idempotency satırları hesap/household silme kurallarıyla gider (`ON DELETE CASCADE`).

Şemada olmayan alanlar: `lowStockNotificationsEnabled`, `dateReminderEnabled`, `dateReminderSchedule`. Bunlar cihaz `UserDefaults` anahtarı `mealroutine.pantry.notificationPreferences` içindedir ve senkron edilmez. Gövde `bestBefore` hâlâ reddedilir. Household `timezone` kolonu yoktur; V7 / `AUD-GLOB-001`.

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
4. Kullanıcı açıkça onaylamadıkça pişirme akışı stok düşmez. “Pişirdim” stok yazmaz. Onay sayfasında “Stoktan düş” denirse bölüm 21 uygulanır. “Stoktan düşme” stoku değiştirmez.
5. Kullanıcının girdiği tarih uydurulmaz. Tarih tek başına gıda güvenliği kararı üretmez. V5.1’de eski kişisel tarih anı takvim gününe çevrilmez; proje sahibi 2026-10-10’da bu satırların bir kez silinmesini kabul etti (bölüm 13). Ortak kiler tarihi sunucudan yeniden alınır.
6. V5’te fiyat, bütçe, fiyat geçmişi veya market sağlayıcı entegrasyonu yoktur.
7. Kişisel kiler, household kilerine otomatik ve sessizce birleştirilmez.
8. Stok ve market güncellemeleri tekrar denendiğinde çift kayıt veya çift düşüm üretmeyecek şekilde idempotent olmalıdır.
9. V5.0 kapsamı dışında kalan otomasyonlar uygulanmış özellik gibi gösterilmez.
10. Paylaşılan pantry’nin sunucu sahibi household’dır. Kişisel pantry yalnız cihazdadır; ayrı bir kişisel pantry backend’i yoktur.
11. V5 otomatik malzeme tanıma veya LLM eşlemesi yapmaz.
12. Plan oluşturmak pantry kullanmaya bağlı değildir.
13. Pantry migration listesi `0012_pantry` ve `0013_pantry_auto_add` dosyalarıdır. `0001`–`0012` yeniden yazılmaz.

## 16. Uygulama fazları

Fazlar V5.0’da nerede durduğunu anlatır. Fazın listelenmiş olması, içindeki her maddenin kabul kapısını kapattığı anlamına gelmez.

### Faz 1 — Domain ve kararlar

Pantry modeli, sözlük, birim aileleri, `bestBefore` / `useBy`, sahiplik, API ve `0012` tasarımı kodda karşılık buldu.

### Faz 2 — Server

CRUD, validation, household authorization, idempotency, conflict ve migration test dosyaları vardır. Geçip geçmedikleri audit report’taki komut çıktısıdır.

### Faz 3 — Local cache ve sync

SwiftData cache, pending operation, retry ve conflict recovery kodu vardır. `PantryTests` Mac’te koşar; bu belgede geçti denmez.

### Faz 4 — Pantry UI

Liste, ekleme, düzenleme, konum, minimum miktar, tarih türü ve boş/yükleme/hata/çevrimdışı metinleri kodda vardır. Geçmiş tarih rozetleri bölüm 6’daki nötr cümlelerdir. V5.1, Evdekiler ekranına düşük stok ve tarih hatırlatması anahtarlarını ekler. İzin reddi `PantryCopy.notificationPermissionDenied` ile yazılır; pantry yazmaya devam eder. Bu ekran Mac’te doğrulanmadı.

### Faz 5 — Market entegrasyonu

Eksik miktar, evdekilerden düşme, evdekilere ekleme, işaretli satır ve idempotent replay kodda vardır. Eşik eklemesi yalnız `autoAddToGrocery` açıkken ve bölüm 21’deki anahtarla çalışır.

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
- Plan stoku değiştirmez. “Pişirdim” tek başına stoku değiştirmez. Onaylı düşüm stoktan fazla düşmez.
- Offline queue bağlantı dönüşünde işlemleri çoğaltmadan gönderir.
- Conflict sunucu haliyle deterministik çözülür.
- `0012` ve `0013` mevcut V1–V4.1 verisini silmez.
- Account deletion pantry ownership kurallarına uyar.
- V1–V4.1 regresyon testleri korunur.
- Loading, empty, error, offline ve conflict metinleri Türkçedir.
- VoiceOver, Dynamic Type ve Dark Mode kontrol edilir.
- API, migration ve local runbook güncellenir.

## 18. Bildirimler

`1f07663` ve V5.0 kodunda pantry bildirimi yoktu. Sunucu türleri hâlâ yalnız `invite`, `weekly_plan`, `meal_veto`, `meal_replacement`, `plan_finalized` (`server/src/notifications.ts`). Uzak household push ve APNs, gerçek Apple hesabı canlı olmadığı için V6 sonrasına ertelenir. V5.1 bildirimleri cihazdaki `UNUserNotificationCenter` kayıtlarıdır.

Tercihler şema değildir: `lowStockNotificationsEnabled`, `dateReminderEnabled`, `dateReminderSchedule`. Varsayılan ikisi de kapalı. `dateReminderSchedule` açıkken `bestBefore` 2 gün önce ve o gün, `useBy` 1 gün önce ve o gündür. Kullanıcı programı kapatabilir.

Tarih hatırlatması yalnız kullanıcı tarih girdiyse ve hatırlatma açıksa planlanır. Gün, saklanan `YYYY-MM-DD` değeridir. Saat 09:00, cihazın o anki `TimeZone` değerindedir. Household saat dilimi yoktur; `AUD-GLOB-001` bunu V7’ye bırakır. İstanbul, Auckland ve Los Angeles için aynı takvim günü `PantryDomainTests.testDateRemindersUseTheCalendarDayInEachDeviceZone` içindedir. Tarih değişince yeni günler yazılır. Miktar sıfır, tarih silme veya hatırlatma kapalıyken plan boştur; uygulama `PantryDateReminders.allIdentifiers` kümesini iptal eder. Bu iptalin işletim sistemine ulaşması Mac’te doğrulanır.

Metin hatırlatmadır. “Güvenli”, “yenmez” veya tazelik hükmü yoktur. İşletim sistemi bildirimi erteleyebilir. İzin reddedilirse `mealroutine.pantry.notificationPermissionDenied` yazılır ve Evdekiler çalışmaya devam eder.

Düşük stok bildirimi, miktar minimumun üstünden minimuma veya altına ilk inince bir kez gider. “Azaldı” rozetiyle aynı çizgi kullanılır: `quantity <= minimumQuantity`. Eşitlikte bildirim bir kez gider; eksik miktar 0 olduğu için market satırı açılmaz. Aynı düşük bölümde tekrar gitmez. Miktar yeniden üstüne çıkınca kuruluş kalkar; tekrar inince yeni bildirim olabilir. Bildirim kapalıyken geçiş olursa kayıt yine tutulur, böylece kullanıcı bölüm ortasında açarsa spam olmaz.

## 19. Global-readiness kuralları

- Ingredient kimliği daima `ingredientId` olur.
- Görünen ad sunum katmanındadır. Ayrı bir `IngredientName(locale)` tablosu V5.0 şemasında yoktur; seed `display_name` ve `synonyms` taşır.
- Quantity ve unit ayrı alanlardır.
- `dateValue` tarih-only’dir. Hatırlatma saati takvim gününün üstüne, cihazın geçerli saat diliminde 09:00 olarak konur. Gün kaymaz. Household timezone V7’dedir.
- `TR`, `TRY`, `metric`, `tr-TR` pantry modelinin kalıcı koşulu değildir. Arayüz metinleri Türkçedir; bu, iş kuralının ülkeye kilitlendiği anlamına gelmez.
- Kullanıcının yazdığı tarif adı, notu ve talimat pantry tarafından çevrilmez.

## 20. V5 sonunda beklenen ürün davranışı

Kullanıcı evdeki malzemeleri görür, miktarı günceller ve ortak markette eksik miktarı kendi eylemiyle hesaplar. Household üyeleri aynı pantry state’ini sunucu üzerinden paylaşır. Offline değişiklikler kaybolmaz ve çakışmalar sessizce veri silmez.

V5, stok farkındalığı katar. Fiyat ve bütçe V5’te yoktur. V6 Balanced Nutrition ayrı bir ürün belgesindedir: yemek örüntüsü tercihleri (`balanced`, `vegetableForward`, `proteinForward`, `plantForward`). Bu modlar tercih sinyalidir; alerji, `Never Again`, malzeme dışlama ve ev halkı vetosunu geçersiz kılmaz. V6 kalori, makro, klinik iddia, market fiyatı ve bütçe içermez. V7 Globalization & Localization, çok dilli arayüz ve bölgesel/global lansmandır. V6 bu belgeyle başlatılmaz.

## 21. V5.1 pişirme düşümü ve eşik

Kararlar (2026-10-10): hatırlatma cihazın geçerli saat dilimindedir (D1=a). Tek yeni migration `0013` `auto_add_to_grocery` kolonudur (D2=b). Başka şema değişikliği yoktur.

### Onaylı düşüm

Planlı yemek pişmiş işaretlendikten sonra sayfa, tarif satırlarını ve Evdekiler miktarını listeler. Kişisel pantry `householdID == nil` satırlarını, ortak pantry o evin satırlarını kullanır. Red, stok yazmaz. Onay:

- Yalnız aynı `ingredientId` (sözlük kanonik kimliği; `tomatoes` ve `tomato` birleşir, `cherry-tomato` birleşmez).
- Yalnız güvenilir dönüşüm: g/kg ve ml/l. Adet ile gram düşülmez; satır atlanır, stok aynı kalır.
- Düşüm eldeki stokla sınırlıdır ve sıfırın altına inmez.
- Aynı onayda ikinci ihtiyaç, azalan stoku görür.
- Aynı yemek kimliği ikinci kez uygulanırsa düşüm tekrarlanmaz.
- Ortak satır mevcut outbox’a gider: `Idempotency-Key` `PantryStableUUID.make("cook:<mealId>:<itemId>")`, `baseVersion` düşüm öncesi `version`. 409 `requiresResolution` yolu değişmez.

Eksik miktar, `autoAddToGrocery` kapalıysa markete yazılmaz. Sayfa “Eksik miktarı markete ekle” gösterir. Açıksa tarif eksiği `pantry-cook:<mealId>:<ingredientId>|<unit>` anahtarıyla bir kez yazılır.

### Eşik ve market

`autoAddToGrocery` varsayılan kapalıdır. Açıkken satır minimumun üstünden minimuma veya altına ilk inince eksik miktar (`minimum - quantity`, sıfırdan küçük değil) bir kez yazılır. Eşitlikte eksik 0’dır; satır açılmaz.

Market anahtarı `pantry-auto:<ingredientId>|<canonicalUnit>` şeklindedir. Planın `ingredientId|unit` satırına eklenmez ve o satırın miktarı değiştirilmez: plan miktarını artırmak veya mutlak yazmak ya ikiye katlar ya da planı ezer, ayrı bir crossing kolonu da ikinci bir şema değişikliği olurdu. Defter, bu sabit anahtar ve mutlak miktardır.

Sunucu grocery `add` gövdesi `mode` almazsa eskisi gibi artırır. `mode: "set"` miktarı mutlak yazar. İki üye aynı miktarı `baseRevision: 0` ile gönderirse tek satır kalır (`board.test.ts`). Miktar zaten hedefse eski `baseRevision` bile ikinci kez artırmaz. İşaretli satır değişmez ve ikinci satır açılmaz. Ortak miktar `0008` tamsayısıdır (`1`…`999`, `GrocerySyncQuantity.whole`). Daha büyük bir eksik bu kolona sığmaz; kolon genişletilmedi.

Yerel defterler `UserDefaults` anahtarlarıdır: `mealroutine.pantry.autoCrossings`, `mealroutine.pantry.lowStockArmed`, `mealroutine.pantry.cookApplied`. Bunlar şema değildir.

Linux kanıtı: `PantryDomainTests` içindeki decline, tavan, birim uyuşmazlığı, retry, bildirim, autoAdd ve saat dilimi testleri; `pantry.test.ts` bayrağın create/patch/list yolu; `board.test.ts` iki üyeli `mode: set`. Ekran, bildirim izni ve SwiftData Mac kontrol listesindedir.
