# MealRoutine V5 — Smart Pantry

**Roadmap:** V1 Core Meal Planning → V2 Personal Meal Memory → V3 Personal Recipe Collection → V4 Household & Shared Planning → V4.1 Release Hardening → **V5 Smart Pantry** → V6 Meal Budget

**Durum:** Kabul kapısındaki kod ve sunucu testleri kapandı. `MARKETING_VERSION` `5.0.0`. Migration `0012_pantry` (`0001`–`0011` değişmedi). Ayrıntılı kapı: `docs/v5-release-gate.md`. Yerel çalıştırma: `docs/v5-local-runbook.md`.

Apple Sign in, APNs, fiziksel cihaz, TestFlight ve Mac’te iOS test koşusu bu ortamda yok; V5 blokeri değiller. VoiceOver, Dynamic Type ve Dark Mode görsel turu cihazsız doğrulanmadı.

**V4.1 ön koşulu:** V4.1 kod ve otomatik test kapsamı tamamlandı. Apple Developer hesabı, gerçek APNs, iki fiziksel cihaz, TestFlight / App Store ve bazı manuel UX kontrolleri bilinçli olarak ertelendi. Bu karar V5 geliştirmesini engellemez.

## 1. Amaç

V5, evde bulunan malzemeleri haftalık plan ve ortak market listesiyle birleştirir. Kullanıcı stoktaki malzemeyi kolayca ekler, miktarı günceller, tüketir ve gerektiğinde eksik miktarı market listesine taşır.

Pantry, planı sessizce değiştiren bir otomasyon değildir. Kullanıcı hangi malzemenin hesaba katıldığını, ne kadar eksik kaldığını ve hangi işlemin stoktan düşüm yaptığını görebilir.

V5, V1–V4.1 davranışlarını korur. Bütçe ve maliyet hesabı V6 Meal Budget kapsamındadır.

## 2. Ürün sınırı

### V5 kapsamı

- Pantry malzemesi ekleme, düzenleme, tüketme ve silme
- Miktar ve birim yönetimi
- Pantry konumu: kiler, buzdolabı, dondurucu veya diğer
- İsteğe bağlı minimum miktar
- İsteğe bağlı son kullanma tarihi
- Uyumlu birimlerin birleştirilmesi
- Uyumsuz birimlerin ayrı tutulması
- Ortak market listesinde eksik miktar hesabı
- Pantry kullanan tarifler için açıklanabilir öneri sinyali
- Household üyeleri arasında server-authoritative senkronizasyon
- Offline görüntüleme ve bekleyen işlem kuyruğu

### V5 kapsamı dışında

- Barkod tarama
- Fiş veya OCR ile otomatik stok çıkarma
- LLM ile malzeme tanıma
- Tarif sitelerinden otomatik malzeme çıkarma
- Market fiyatı ve bütçe hesabı
- Son kullanma tarihi için dış veri servisi
- Household üye sınırını artırma

## 3. Veri sahipliği

Pantry verisinin sahibi household'dır. Ortak pantry verisi V4.1 mimarisine uygun olarak server-authoritative olur.

Household yokken kullanıcı kişisel, yerel pantry kullanabilir. Household oluşturulduğunda kişisel pantry otomatik olarak ortak veriye karıştırılmaz. Kullanıcıya açık bir aktarım veya kopyalama adımı gösterilir; aktarımın sonucu kullanıcı tarafından onaylanır.

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
  bestBefore?
  createdAt
  updatedAt
  version
```

### Alan kuralları

- `id` server tarafından kalıcı kimlik olarak tanınır; offline oluşturulan öğe için istemci kimliği idempotent biçimde korunur.
- `householdId` istek gövdesinden kabul edilmez; erişim belirtecindeki üyelikten doğrulanır.
- `ingredientId`, mevcut tarif ve market birleştirme sözlüğündeki kimliktir.
- `displayName`, malzemenin Türkçe görünen adıdır; kimlik yerine geçmez.
- `quantity` negatif olamaz.
- `unit` bilinmeyen veya geçersizse kayıt reddedilir ya da kullanıcı açıkça “uyumsuz birim” olarak işaretler.
- `minimumQuantity` boş olabilir; doluysa negatif olamaz ve `quantity` ile aynı birim ailesinde olmalıdır.
- `bestBefore` isteğe bağlıdır. Kullanıcı tarih girmediyse sistem tarih uydurmaz.
- `updatedAt` ve `version` conflict çözümünde kullanılır.

### “Bitti” davranışı

“Bitti” bir pantry öğesini sessizce silmez ve diyalog açılır açılmaz miktarı sıfırlamaz. Önce kullanıcıya:

1. markete ekle,
2. minimum miktara göre eksik hesapla,
3. öğeyi sil

seçenekleri gösterilir. Bir seçenek seçilirse miktar sıfıra çekilir, değişiklik eşitlenir, sonra seçilen işlem yapılır. Diyalog iptal edilirse miktar aynı kalır. “Bitti”, “Düzenle” ve eksi düğmesi değildir.

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
- Son kullanma tarihi varsa tarih
- Eksik veya yaklaşan durum için açık Türkçe etiket

### Boş durum

İlk kullanımda açıklama:

> “Evdeki malzemelerini ekle. Planını ve marketini daha doğru hazırlayalım.”

Household verisi yüklenemediğinde boş liste gösterilmez; hata ve yeniden deneme eylemi gösterilir.

### Düzenleme

Miktar, birim, konum, minimum miktar ve son kullanma tarihi tek düzenleme akışında değiştirilebilir. Kaydetme başarısız olursa yerel değer sessizce kesinleşmiş gibi gösterilmez.

## 7. Market listesi entegrasyonu

Pantry miktarı ortak market satırını otomatik olarak silmez. Market kullanıcının açıkça onayladığı bir satın alma listesidir.

Desteklenen işlemler:

- **Eksik miktarı hesapla:** Tarif ihtiyacından pantry miktarını düşer.
- **Pantry'den düş:** Kullanıcının seçtiği market satırını pantry miktarından azaltır.
- **Pantry'ye ekle:** Satın alınan miktarı pantry'ye ekler.
- **Bitti olarak işaretle:** Kullanıcı bir seçenek seçince pantry miktarını sıfırlar ve markete ekleme önerir. İptal stoku değiştirmez.

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

## 15. Uygulama fazları

### Faz 1 — Domain ve kararlar

- Pantry domain modeli
- Birim aileleri ve dönüşüm kuralları
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
- Pantry'den düşme
- Pantry'ye ekleme
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

Durum `docs/v5-release-gate.md` içindedir. Kod ve sunucu testiyle kapanan maddeler:

- Pantry CRUD testleri geçer.
- Household authorization testleri geçer.
- Başka household erişimi 403 ile reddedilir.
- Uyumlu birimler (g/kg, ml/L) birleşir.
- Uyumsuz birimler otomatik karışmaz; kullanıcı ayrı satırı onaylar. Geçersiz birim reddedilir.
- Eksik miktar hesabı idempotent çalışır. İşaretli market satırları korunur.
- Offline kuyruk bağlantı dönüşünde pantry işlemini aynı idempotency anahtarıyla gönderir.
- Conflict `requiresResolution` olur. Metin: “Bu malzeme başka bir cihazda güncellendi.”
- Migration `0012` ekler; `0001`–`0011` değişmez.
- Hesap silinince kişisel pantry ve idempotency kaydı gider. Son üye evi kapatınca pantry silinir. Partner kalırsa pantry kalır.
- V1–V4.1 sunucu regresyonu korunur.
- Loading, empty, error, offline ve conflict metinleri Türkçedir.
- API, migration ve local runbook güncellendi.

VoiceOver, Dynamic Type ve Dark Mode görsel kontrolü ile iOS XCTest koşusu Mac gerektirir. Bu ortamda koşulmadı. Apple Sign in, APNs ve TestFlight V5 kapısının dışında.

## 17. V5 sonunda beklenen ürün davranışı

Kullanıcı evdeki malzemeleri görür, miktarı günceller ve ortak markette yalnızca eksik olan miktarı satın alacak şekilde plan yapabilir. Household üyeleri aynı pantry state'ini server üzerinden paylaşır. Offline değişiklikler kaybolmaz ve çakışmalar sessizce veri silmez.

V5, MealRoutine'a stok farkındalığı kazandırır. Fiyat, bütçe ve maliyet kararları V6 Meal Budget'a bırakılır.
