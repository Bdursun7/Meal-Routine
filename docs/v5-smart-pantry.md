# MealRoutine V5 — Smart Pantry

**Roadmap:** V1 Core Meal Planning → V2 Personal Meal Memory → V3 Personal Recipe Collection → V4 Household & Shared Planning → V4.1 Release Hardening → **V5 Smart Pantry** → V5.1 Integration Readiness Fixes (if required) → V6 Balanced Nutrition → V7 Globalization & Localization

**Durum (kod dalı denetimi):** V5.0'ın ana Pantry akışları (merkezi ingredient sözlüğü, dateType / dateValue, server-authoritative household pantry, offline queue, conflict çözümü, market/planner entegrasyonu) V5.0 dalında mevcut. docs/v5-release-gate.md otomatik sunucu/Postgres/domain testlerinin geçtiğini bildiriyor; Xcode derlemesi, PantryTests ve cihazda VoiceOver / Dynamic Type / Dark Mode turu Mac doğrulaması gerektiriyor. Güncellenen ürün kararlarındaki tarih hatırlatmaları, düşük stok bildirimleri ve Cooked sonrası onaylı stok tüketimi bu kod incelemesinde doğrulanmadı; bunlar docs/v5.1-integration-readiness-fixes.md içinde V6 öncesi kapı olarak izlenir.

**V4.1 ön koşulu:** V4.1 kod ve otomatik test kapsamı tamamlandı. Apple Developer hesabı, gerçek APNs, iki fiziksel cihaz, TestFlight / App Store ve bazı manuel UX kontrolleri bilinçli olarak ertelendi. Bu karar V5 geliştirmesini engellemez.

## 1. Amaç

V5, evde bulunan malzemeleri haftalık plan ve ortak market listesiyle birleştirir. Kullanıcı stoktaki malzemeyi kolayca ekler, miktarı günceller, tüketir ve gerektiğinde eksik miktarı market listesine taşır.

Pantry, planı sessizce değiştiren bir otomasyon değildir. Kullanıcı hangi malzemenin hesaba katıldığını, ne kadar eksik kaldığını ve hangi işlemin stoktan düşüm yaptığını görebilir.

V5, V1–V4.1 davranışlarını korur. Fiyat ve bütçe hesabı V5 kapsamı dışındadır; V6 Balanced Nutrition da fiyat/bütçe sürümü değildir.

## 2. Ürün sınırı

### V5 kapsamı

- Pantry malzemesi ekleme, düzenleme, tüketme ve silme
- Miktar ve birim yönetimi
- Pantry konumu: kiler, buzdolabı, dondurucu veya diğer
- İsteğe bağlı minimum miktar
- İsteğe bağlı tarih bilgisi
- Uyumlu birimlerin birleştirilmesi
- Uyumsuz birimlerin ayrı tutulması
- Ortak market listesinde eksik miktar hesabı
- Pantry kullanan tarifler için açıklanabilir öneri sinyali
- Household üyeleri arasında server-authoritative senkronizasyon
- Offline görüntüleme ve bekleyen işlem kuyruğu
- Tarif/market/pantry malzemelerini ortak bir `Ingredient` kimliği üzerinden eşleştirme
- Malzeme eş anlamlıları ve görünen adlarının merkezi sözlükten yönetilmesi

### V5 kapsamı dışında

- Barkod tarama
- Fiş veya OCR ile otomatik stok çıkarma
- LLM ile malzeme tanıma
- Tarif sitelerinden otomatik malzeme çıkarma
- Market fiyatı ve bütçe hesabı
- Son kullanma / tavsiye edilen tüketim tarihi için dış veri servisi
- Otomatik son kullanma tarihi tahmini
- Household üye sınırını artırma
- V5 içinde market fiyatı saklama veya fiyat geçmişi oluşturma

## 3. Veri sahipliği

Pantry verisinin ana sahibi household'dır. Household sahibi olan pantry V4.1 mimarisine uygun olarak server-authoritative olur.

Household dışı kullanım için V5'te kalıcı ayrı bir server pantry hesabı oluşturulmaz. Household sahibi olmayan kullanıcı yalnızca yerel `Personal Pantry` kullanabilir. Bu veri V5 içinde cihaz üzerinde tutulur.

Kullanıcı daha sonra household oluşturur veya mevcut household'a katılırsa kişisel pantry otomatik olarak ortak veriye karıştırılmaz. Kullanıcıya açık bir aktarım/kopyalama adımı gösterilir. Kullanıcı onaylamazsa kişisel pantry yerel olarak kalır.

Böylece V5'te iki farklı sahiplik modeli bilinçli olarak vardır:

- `Personal Pantry`: yalnızca household dışında kullanılan yerel veri
- `Household Pantry`: household'a ait, server-authoritative ortak veri

Household pantry oluşturulduktan sonra plan, grocery ve sync entegrasyonlarında yalnızca household pantry kullanılır.

Pantry verisi:

- Başka bir household tarafından okunamaz veya değiştirilemez.
- Kişisel Meal Memory'yi değiştirmez.
- V3 tarifinin sahipliğini değiştirmez.
- Account deletion kurallarına uyar.
- Ortak plan ve market listesiyle ilişkilendirilebilir, fakat bunların yerine geçmez.

## 4. Pantry modeli

Önerilen alanlar:

```text
PantryItem
  id
  householdId
  ingredientId
  displayName
  quantity
  unit
  location
  minimumQuantity?
  dateType?
  dateValue?
  createdAt
  updatedAt
  version
```

### Alan kuralları

- `id` server tarafından kalıcı kimlik olarak tanınır; offline oluşturulan öğe için istemci kimliği idempotent biçimde korunur.
- `householdId` istek gövdesinden kabul edilmez; erişim belirtecindeki üyelikten doğrulanır.
- `ingredientId`, tarif, grocery ve pantry tarafında kullanılan merkezi malzeme kimliğidir; görünen metin karşılaştırmasıyla oluşturulmaz.
- `displayName`, kullanıcının gördüğü Türkçe addır; `ingredientId` yerine geçmez.
- Aynı `ingredientId` altında bilinen eş anlamlı/alternatif görünen adlar merkezi sözlükte tutulabilir. Örneğin `domates`, `cherry domates` otomatik olarak aynı malzeme kabul edilmez; bunun kararı ingredient sözlüğünde açıkça tanımlanır.
- `quantity` negatif olamaz.
- `unit` bilinmeyen veya geçersizse kayıt reddedilir; kullanıcı uyumsuz birim olarak kaydedemez.
- `minimumQuantity` boş olabilir; doluysa negatif olamaz ve `quantity` ile aynı birim ailesinde olmalıdır.
- Tarih bilgisi isteğe bağlıdır. Sistem kullanıcı girmediyse tarih uydurmaz.
- `dateType` yalnızca `bestBefore` veya `useBy` olabilir.
- useBy ve bestBefore farklı tarih türleridir. Uygulama kullanıcının girdiği tarihi ve tarih türünü gösterir; güvenli/güvensiz gıda kararı vermez. Geçmiş tarih rozeti de güvenlik hükmü değil, yalnızca girilen tarihin geçtiğini bildiren nötr bir uyarı olmalıdır.
- `updatedAt` ve `version` conflict çözümünde kullanılır.

### “Bitti” davranışı

“Bitti” bir pantry öğesini sessizce silmez. Miktar sıfıra çekilir ve kullanıcıya:

1. markete ekle,
2. minimum miktara göre eksik hesapla,
3. öğeyi sil

seçenekleri gösterilir.

## 5. Birim ve miktar kuralları

Mevcut market kuralları V5'te korunur:

- Gram ve kilogram aynı ağırlık ailesinde dönüştürülebilir.
- Mililitre ve litre aynı hacim ailesinde dönüştürülebilir.
- Aynı malzemenin uyumlu birimleri birleştirilebilir.
- Adet, paket, demet, kaşık ve benzeri birimler otomatik olarak grama veya litreye çevrilmez.
- Uyuşmayan birimler tek pantry satırında birleştirilmez.
- Kullanıcıya dönüşüm yapılamadığında açık bir seçim gösterilir.
- Yuvarlama, mevcut grocery birim yuvarlama kurallarıyla aynı olur.

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

Pantry, V5'te Market sekmesinden ayrı ve Profil'den erişilebilir bir household alanı olarak tasarlanır. Ortak household açık değilse kişisel yerel pantry durumu gösterilir.

### Liste

Liste satırı en az şunları gösterir:

- Malzeme adı
- Mevcut miktar ve birim
- Konum
- Minimum miktar varsa eşik bilgisi
- Tarih bilgisi varsa tarih ve türü
- Eksik veya yaklaşan durum için açık Türkçe etiket
- useBy veya bestBefore tarihi geçmişse tarih türünü açıkça belirten, gıdanın güvenli/güvensiz olduğunu iddia etmeyen tarih uyarısı

### Boş durum

İlk kullanımda açıklama:

> “Evdeki malzemelerini ekle. Planını ve marketini daha doğru hazırlayalım.”

Household verisi yüklenemediğinde boş liste gösterilmez; hata ve yeniden deneme eylemi gösterilir.

### Düzenleme

Miktar, birim, konum, minimum miktar ve tarih türü/tarihi tek düzenleme akışında değiştirilebilir. Kaydetme başarısız olursa yerel değer sessizce kesinleşmiş gibi gösterilmez.

### Malzeme adı

Kullanıcı adı serbest yazar. Yazarken sözlükteki adlar, eş anlamlılar ve bu evin (ya da kişisel listenin) özel malzemeleri öneri olarak görünür. Öneriye basmak o `ingredientId` ile bağlar.

Öneri seçilmezse kayıt şöyle çözülür:

- Yazılan ad, büyük/küçük harf ve diakritik farkı yok sayılarak **tek** bir maddenin adı veya eş anlamlısıyla birebir örtüşüyorsa o `ingredientId` bağlanır.
- Örtüşme yoksa ya da birden fazla madde aynı ada sahipse yeni `custom:<uuid>` oluşturulur. Ortak evde bu kimlik mevcut `POST /v1/households/:id/ingredients` ile kaydedilir; kişisel evdekilerde yalnız cihazda durur.
- “Domates” ile “Cherry domates” gibi benzer adlar asla kendiliğinden birleşmez. Eşleşme LLM ile yapılmaz. Yazılan metin `ingredientId` olmaz.

Market satırında kimlik yoksa aynı kural geçerlidir: alan yazılır, öneriye basılabilir, Kaydet ikinci bir onay istemez.

## 7. Market listesi entegrasyonu

Pantry miktarı ortak market satırını otomatik olarak silmez. Market kullanıcının açıkça onayladığı bir satın alma listesidir.

Desteklenen işlemler:

- **Eksik miktarı hesapla:** Tarif ihtiyacından pantry miktarını düşer.
- **Evdekilerden düş:** Kullanıcının seçtiği market satırını pantry miktarından azaltır.
- **Evdekilere ekle:** Satın alınan miktarı pantry’ye ekler.
- **Bitti olarak işaretle:** Pantry miktarını sıfırlar ve markete ekleme önerir.

Kurallar:

- Pantry miktarı ihtiyacı karşılıyorsa eksik miktar sıfır olur.
- Pantry miktarı yetersizse yalnızca eksik miktar markete eklenir.
- İşaretlenmiş market satırları korunur.
- Aynı mutation retry edildiğinde market miktarı iki kez artmaz.
- Uyumsuz birimlerde otomatik çıkarma yapılmaz.
- Plan değişince pantry miktarı kendiliğinden azalmaz.
- Pişirme tamamlanınca stoktan otomatik düşüm V5 ilk sürümünde zorunlu değildir; varsa kullanıcı açıkça etkinleştirir.

## 8. Haftalık plan ve scoring

Pantry, öneri skoruna açıklanabilir bir sinyal olarak eklenebilir.

- Tarif, pantry'deki malzemelerin bir kısmını kullanıyorsa küçük bir avantaj alabilir.
- Son kullanma tarihi yaklaşan bir malzeme yalnız güvenli ve açıkça eşleşen tariflerde sinyal olur.
- Pantry hiçbir zaman `Never Again`, household veto, pişirme süresi veya diğer hard filter kurallarını geçersiz kılmaz.
- Kişisel Meal Memory skorlaması korunur.
- Pantry sinyali kullanıcıya “Evdeki malzemeleri kullanıyor” gibi kısa bir açıklamayla gösterilir.
- Plan yeniden oluşturulunca pantry miktarı düşmez.
- Pantry boşsa mevcut V4.1 planlama davranışı aynen devam eder.

İlk V5 sürümünde pantry otomatik planlama için zorunlu kaynak değildir. Kullanıcı planı pantry kullanmadan da oluşturabilir.

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

- Household üyeliği ve yetki server'da doğrulanır.
- Pantry item validation server'da tekrarlanır.
- Server başka household erişimini reddeder.
- Server conflict response ve version bilgisini döner.
- Idempotency anahtarı aynı mutation'ın iki kez uygulanmasını engeller.
- `Ingredient` sözlüğü server tarafında authoritative kaynaktır.
- Client, yazılan metni `ingredientId` yapmaz. Öneri seçilmezse birebir ve tekil bir ad veya eş anlamlı o kimliğe bağlanır; aksi halde istemci `custom:<uuid>` üretir ve ortak evde bunu `POST /v1/households/:id/ingredients` ile kaydeder. Benzer adlar birleşmez ve LLM eşlemesi yoktur.
- V5'te ingredient sözlüğünün yönetimi admin paneli gerektirmez; başlangıç sözlüğü migration/seed ile gelir ve uygulama içinden kullanıcıya görünmez.

### SwiftData

- Hızlı UI için cache tutar.
- Offline görüntülemeyi sağlar.
- Bekleyen pantry mutation'larını saklar.
- Server state yerine geçmez.

## 10. Offline ve sync

Offline yapılabilen işlemler:

- Daha önce senkronize edilmiş pantry'yi görüntüleme
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

Durumlar:

- `pending`
- `syncing`
- `completed`
- `failed`
- `requiresResolution`

Retry exponential backoff ile yapılır. Bağlantı geri geldiğinde işlemler sırayla gönderilir; aynı işlem yeniden gönderilse de sonucu çoğalmaz.

## 11. Conflict resolution

İki cihaz aynı pantry öğesini değiştirirse server sürümü kazanır. İstemci, kendi pending mutation'ını sessizce silmez; server delta'sını aldıktan sonra işlemi `requiresResolution` durumuna alır veya deterministik merge uygular.

Basit alanlarda:

- Miktar için son server revision'ı geçerli olur.
- Konum için server revision'ı geçerli olur.
- Minimum miktar ve son kullanma tarihi aynı revision ailesinde birlikte değerlendirilir.

Kullanıcıya şu anlama gelen Türkçe mesaj gösterilir:

> “Bu malzeme başka bir cihazda güncellendi.”

Sessiz veri kaybı kabul edilmez.

## 12. API sözleşmesi

V5 yeni API endpoint'leri ve versioned SQL migration gerektirir. Mevcut `0001`–`0011` migration'ları değiştirilmez.

Önerilen endpoint'ler:

```text
GET    /v1/households/:id/pantry
POST   /v1/households/:id/pantry/items
PATCH  /v1/households/:id/pantry/items/:itemId
DELETE /v1/households/:id/pantry/items/:itemId
POST   /v1/households/:id/pantry/reconcile-grocery
GET    /v1/ingredients
```

Endpoint kuralları:

- Access token zorunludur.
- Household üyeliği zorunludur.
- İstemci sahibi request body'den okunmaz.
- API version header V4.1 sözleşmesine uyar.
- Geçersiz miktar, birim ve tarih reddedilir.
- Rate limit ve request size sınırları korunur.
- Hata gövdeleri istemcinin recovery akışını çalıştıracak şekilde sınıflandırılır.

## 13. Veritabanı migration

Yeni migration pantry öğesi, version ve idempotency kayıtlarını ekleyebilir. Migration:

- Önceki migration'ları değiştirmez.
- Geriye dönük uyumsuz client'ı API version ile reddeder.
- Household authorization için gerekli foreign key ve index'leri ekler.
- Aynı household ve ingredient için duplicate davranışını açıkça tanımlar.
- Account deletion sırasında pantry ownership kurallarını uygular.

V5 yerel cache migration'ı, mevcut V1–V4.1 verisini silmez. Pantry yoksa boş başlar; mevcut plan, market, tarif ve Meal Memory korunur.

## 14. Account deletion ve privacy

Kullanıcı hesabını sildiğinde:

- Kişisel pantry varsa kişisel veri olarak silinir.
- Household pantry'si household ownership kuralına göre korunur veya silinir.
- Silinen üyeye ait access ve refresh token'lar geçersiz kalır.
- Başka household üyelerinin verisi export'a karışmaz.
- Pantry item geçmişi kullanıcıya görünmeyen sessiz bir kopya olarak bırakılmaz; saklama kararı ayrıca belgelenir.

## 15. V5 kilitlenen kararlar

V5'in uygulanması sırasında aşağıdaki kararlar yeniden açılmaz:

1. Pantry'nin ana server sahipliği household'dır.
2. Household dışındaki kişisel pantry yalnızca local-only'dir; V5'te ayrı kişisel pantry backend'i yoktur.
3. Ingredient eşleştirmesi görünen isimle değil merkezi `ingredientId` ile yapılır.
4. V5 otomatik malzeme tanıma veya LLM tabanlı ingredient eşleştirmesi yapmaz.
5. `bestBefore` ve `useBy` farklı kavramlardır; sistem kullanıcı adına gıda güvenliği kararı vermez.
6. V5 fiyat, satın alma maliyeti veya bütçe verisi toplamaz.
7. Plan oluşturmak pantry kullanımına bağlı değildir.
8. Planın oluşturulması veya tarifin pişirildi olarak işaretlenmesi pantry miktarını sessizce düşürmez.
9. Pantry → Grocery ve Grocery → Pantry işlemleri kullanıcı tarafından açıkça tetiklenir.
10. V5'in mevcut branch'inde başlayan `0012` migration çalışması, pantry şemasının kanonik migration'ı olarak tamamlanır.

## 15. Uygulama fazları

### Faz 1 — Domain ve kararlar

- Pantry domain modeli
- Ingredient kimliği ve merkezi sözlük
- Eş anlamlı/alternatif görünen ad kuralları
- Birim aileleri ve dönüşüm kuralları
- `bestBefore` / `useBy` tarih ayrımı
- Household ve kişisel pantry ownership
- API sözleşmesi
- Migration tasarımı

### Faz 2 — Server

- CRUD endpoint'leri
- Validation
- Household authorization
- Idempotency
- Conflict response
- Migration ve integration testleri

### Faz 3 — Local cache ve sync

- SwiftData pantry cache
- Pending operation modeli
- Retry ve backoff
- Delta pull
- Conflict recovery

### Faz 4 — Pantry UI

- Liste
- Ekleme ve düzenleme
- Konum seçimi
- Minimum miktar
- Son kullanma tarihi
- Empty, loading, error ve offline durumları

### Faz 5 — Market entegrasyonu

- Eksik miktar hesabı
- Evdekilerden düşme
- Evdekilere ekleme
- İşaretli satır koruması
- Idempotent replay

### Faz 6 — Planner sinyali

- Pantry kullanım sinyali
- Yaklaşan son kullanma tarihi sinyali
- Açıklama metinleri
- V1–V4.1 scoring regresyonu

### Faz 7 — QA ve release

- Server testleri
- iOS unit ve integration testleri
- Offline ve conflict testleri
- V1–V4.1 regression
- Accessibility
- Dynamic Type
- Dark Mode
- Runbook ve release gate

## 16. V5 kabul kapısı

V5 tamamlanmış sayılmadan önce aşağıdakilerin hepsi sağlanır:

- Pantry CRUD testleri geçer.
- Household authorization testleri geçer.
- Başka household erişimi 403 veya tanımlı privacy davranışıyla reddedilir.
- Uyumlu birimler doğru birleşir.
- Uyumsuz birimler karıştırılmaz.
- Aynı ingredient kimliği dışındaki malzemeler yalnız görünen ad benzerliğiyle birleştirilmez.
- `bestBefore` ve `useBy` kullanıcıya farklı anlamlarla gösterilir.
- Eksik miktar hesabı doğru ve idempotent çalışır.
- İşaretlenmiş market satırları korunur.
- Offline queue bağlantı dönüşünde işlemleri çoğaltmadan gönderir.
- Conflict server state ile deterministik çözülür.
- Migration mevcut V1–V4.1 verisini silmez.
- Account deletion pantry ownership kurallarına uyar.
- V1–V4.1 regresyon testleri korunur.
- Loading, empty, error, offline ve conflict metinleri Türkçedir.
- VoiceOver, Dynamic Type ve Dark Mode kontrol edilir.
- API, migration ve local runbook güncellenir.

## 17. V5 sonunda beklenen ürün davranışı

Kullanıcı evdeki malzemeleri görür, miktarı günceller ve ortak markette yalnızca eksik olan miktarı satın alacak şekilde plan yapabilir. Household üyeleri aynı pantry state'ini server üzerinden paylaşır. Offline değişiklikler kaybolmaz ve çakışmalar sessizce veri silmez.

V5, MealRoutine'a stok farkındalığı kazandırır. Pantry fiyat veya bütçe verisi tutmaz. V6 Balanced Nutrition haftalık yemek planının çeşitliliğini ve seçilen beslenme yönünü ele alır; kalori/makro hesapları ve fiyat/bütçe özellikleri bu sürümün kapsamı dışındadır.


## 22. V5.1 Integration Readiness — V6 öncesi kontrol

Bu bölüm V5.0'da var olduğu kanıtlanan özelliklerle daha sonra eklenen ürün kararlarını birbirinden ayırır. Aşağıdaki maddeler kodda uygulanmış sayılmaz; V6'ya geçmeden önce kod ve testlerle kapatılmalıdır.

- [ ] Kullanıcı tarih hatırlatmalarını açıp kapatabilir; tarih değiştiğinde eski bildirim iptal edilir, yeni tarihe göre planlanır; öğe tüketilince veya silinince bildirim iptal edilir.
- [ ] Varsayılan tarih hatırlatması kullanıcı tarafından girilen tarih için 2 gün önce ve tarihin kendisindedir; kullanıcı takvimi değiştirebilir. Bildirim teslim zamanı garanti edilmez.
- [ ] Düşük stok bildirimi isteğe bağlıdır; yalnız eşik üstünden eşik altına geçişte tetiklenir ve aynı düşük stok durumu için tekrarlanmaz.
- [ ] Minimum stok altına düşünce market listesine otomatik ekleme varsayılan olarak kapalıdır. Kullanıcı açarsa işlem idempotenttir ve mevcut market satırını ikinci kez çoğaltmaz.
- [ ] Cooked işaretlemesi tek başına stoku değiştirmez. Kullanıcı tarifin malzemelerini ve stokta mevcut miktarı görür, tüketimi açıkça onaylar. Yalnızca mevcut stoktan düşülür; eksik miktar sessizce markete eklenmez.
- [ ] useBy geçmiş tarihinin metni “Son tüketim tarihi geçti” gibi nötr olmalıdır; güvenli/güvensiz hükmü verilmez. bestBefore ayrı kalite/tazelik açıklaması kullanır.
- [ ] WidgetKit widget bu V5 kapsamına eklenmez. “Bugünün Yemeği” widget'ı V6 kapsamındadır.
- [ ] Bu maddelerin her biri için unit/integration/UI testi vardır; V1–V4.1 regresyonu korunur.
