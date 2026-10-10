> **Repo kopyası.** Bu dosya hizalama adım 1 ile `docs/v5-alignment-execution-order.md` olarak eklendi. Kaynak, `V5-Alignment-Audit` (`1f07663`) üzerinde uygulanan yönergedir. Belge bir talimattır; uygulama kodunu değiştirmez. Adım 5 bu turda çalıştırılmaz.

# MealRoutine — V5.0 Karşılaştırma Sonrası Güncelleme Yönergeleri

**Belge türü:** Uygulama ve doküman hizalama talimatı  
**İncelenen kod tabanı:** `Bdursun7/Meal-Routine`, `V5.0` dalı  
**Hedef:** Mevcut V5.0 davranışını kaynak kabul ederek V5 dokümanını, globalleşme hazırlık belgesini ve sürümler arası denetim sürecini birbiriyle tutarlı hale getirmek.  
**Önemli:** Bu belge bir değişiklik talimatıdır; tek başına kodun değiştirilmiş veya bütün testlerin geçmiş olduğu anlamına gelmez.

---

## 1. Karar özeti

V5.0 için baştan yazım veya yalnızca numaralandırma amacıyla yeni bir sürüm açılması önerilmiyor. Önce aşağıdaki belge ve davranış uyuşmazlıkları kapatılmalı, sonra V1–V5 çapraz sürüm denetimi gerçek kod ve veritabanı şeması üzerinden yürütülmelidir.

1. **Gıda güvenliği metnini düzelt:** Geçmiş `useBy` tarihi için “Güvenlik uyarısı” gibi ürünün güvenli/güvensiz olduğuna karar veriyormuş izlenimi veren ifadeler kullanma. Kullanıcıya yalnızca kaydettiği tarih türünü ve tarihin geçmiş olduğunu nötr biçimde göster.
2. **V5 dokümanını V5.0 kapsamına hizala:** Minimum stoktan otomatik market listesi oluşturma, düşük stok bildirimi, tarih hatırlatmaları ve pişirme sonrası otomatik stok düşümü V5.0’da gerçekten uygulanmış değilse bunları mevcut özellikmiş gibi yazma. V5.0 için stok değişikliklerinin açık kullanıcı eylemiyle gerçekleştiğini belirt.
3. **Yol haritasını düzelt:** `V6 Meal Budget` ifadelerini `V6 Balanced Nutrition` ile değiştir. Sayısal kalori/makro hesaplarını sonraya bırak. `V7 Globalization & Localization`, çok dilli kullanıcı arayüzü ve bölgesel/global lansman sürümüdür.
4. **V5 durumunu kanıta dayalı yaz:** “Tamamlandı” veya “testler geçti” ifadelerini yalnızca ilgili kontrol listesi ve gerçek test kanıtı mevcutsa kullan. Kodda uygulanmış olmak, kabul kapısının kapandığını tek başına kanıtlamaz.
5. **Önce belge düzeltmeleri, sonra denetim, sonra V6:** Çapraz sürüm denetiminde P0/P1 engel bulunursa V6’ya geçmeden düzelt. Yalnızca numara olsun diye V5.1 açma.

---

## 2. V5 Smart Pantry dokümanında yapılacak değişiklikler

Hedef belge: `MealRoutine_V5_Smart_Pantry_Updated.md` (kullanılan en güncel V5 kopyası).  
Kod referansı: GitHub `V5.0` dalı. Değişiklikleri doğrudan ana dala uygulama; önce ayrı bir doküman/entegrasyon dalında düzenle ve diff incele.

### 2.1 Yol haritası ve V6 kapsamı

Dokümandaki tüm eski `V6 Meal Budget` referanslarını şu kararla hizala:

- **V6 — Balanced Nutrition:** Kullanıcı tarafından seçilen yemek örüntüsü tercihleri ve haftalık çeşitlilik.
- İlk plan modları: `balanced`, `vegetableForward`, `proteinForward`, `plantForward`.
- Modlar tercih sinyalidir; açıkça girilmiş alerji, `Never Again`, malzeme dışlama ve ev halkı vetosu gibi sert kısıtları geçersiz kılamaz.
- İlk V6 kapsamı kalori, makro, klinik beslenme önerisi, sağlık iddiası, market fiyatı veya bütçe optimizasyonu içermez.
- **V7 — Globalization & Localization:** Çok dilli arayüz, bölgesel varsayımlar, yerelleştirilmiş içerik ve global lansman.

Dokümanın başındaki roadmap, V5 kapsamı, “out of scope”, kabul kriterleri ve son bölümdeki sonraki sürüm listesi aynı ifadeleri kullanmalı.

### 2.2 Tarih etiketleri ve gıda güvenliği sınırı

**Mevcut çelişki:** Bir bölüm, geçmiş `useBy` tarihi için “Güvenlik uyarısı” derken başka bölümler sistemin gıda güvenliği kararı vermediğini söylüyor.

Gerekli değişiklik:

- “Güvenlik uyarısı”, “bu ürün yenmez”, “güvenlidir/güvenli değildir” gibi hüküm veren metinleri kaldır.
- Tarih türünü (`bestBefore` / `useBy`) ve kullanıcının girdiği tarihin geçmiş olduğunu tarafsız biçimde göster.
- Tarih, malzemenin gerçekten bozulduğunu veya tüketilmesinin güvenli olduğunu kanıtlayan bir veri gibi kullanılmamalı.
- Geçmiş `useBy` tarihi, tarif öneri puanını artıran olumlu bir stok sinyali olarak kullanılmamalı. Tarih bilgisi planlama kararında kullanılıyorsa davranış açıkça tanımlanmalı ve güvenlik kararı gibi sunulmamalı.
- Testler, doğru tarih türü ve nötr metnin gösterildiğini; tarihin otomatik olarak üretilmediğini doğrulamalı.

### 2.3 V5.0’da bulunmayan otomasyonları mevcut özellik gibi yazma

V5.0 kodunda gerçekten bulunup test edilmedikçe aşağıdakileri V5.0’ın tamamlanmış özellikleri olarak belgelemeyin:

- Minimum stok eşiği geçilince market listesine otomatik ekleme.
- Düşük stok bildirimi.
- `bestBefore` / `useBy` için otomatik tarih hatırlatmaları ve hatırlatma takvimi.
- Yemek pişirildikten sonra otomatik stok düşümü.

V5.0 için belge açıkça şunları söylemeli:

- Pantry → Grocery ve Grocery → Pantry değişiklikleri kullanıcı tarafından açıkça başlatılır.
- Plan değişikliği stok miktarını sessizce düşürmez.
- “Pişirdim” eylemi V5.0’da stoktan otomatik miktar düşürmüyorsa, doküman da böyle bir davranış vaat etmez.
- Otomasyonlar ileride eklenecekse bunlar ayrı bir kapsam kararı, ayar varsayılanı, idempotency kuralı, bildirim davranışı ve test seti gerektirir. Bu belge, bu otomasyonları kendiliğinden V5.0’a ekleme izni vermez.

### 2.4 Şema ve migration kuralları

Doküman, gerçek V5.0 veritabanı ve API modeliyle karşılaştırılmalı; özellikle `0012_pantry` migration’ı ve pantry alanlarının kanonik isimleri kontrol edilmeli.

Kontrol edilecekler:

- `ingredientId` kimlik alanı; `displayName` yalnızca görüntüleme metnidir.
- `quantity` sayısal, `unit` yapılandırılmış birimdir; miktar ve birim gösterim metninden türetilmez.
- `dateType` yalnızca desteklenen değerleri (`bestBefore`, `useBy`) kabul eder; `dateValue` takvim tarihi olarak saklanır ve saat dilimi dönüşümüyle bir gün ileri/geri kaymaz.
- Kiler kaydının sahipliği, household kileri ile cihazda kalan kişisel kiler arasında açıkça ayrıdır.
- Ortak household kileri için sunucu/veritabanı otoritesi, yetkilendirme, offline kuyruk ve conflict çözümü belgede kodla aynı şekilde anlatılır.
- Migration tekrar çalıştırma, mevcut kayıtları koruma, API uyumluluğu ve rollback/onarım yaklaşımı test edilir.
- Gerçek şemada olmayan alan veya davranış dokümana eklenmez; dokümandaki alan adı kodda yoksa kod ve migration kanıtına göre tek kanonik ad belirlenir.

Bu karşılaştırma tamamlanmadan `0012_pantry` için “uyumlu” veya “tamamlandı” denmemeli.

### 2.5 Eski kilit kararları koru

V5 dokümanında ayrı bir “Locked Decisions / Kilitli Kararlar” bölümü bulunmalı. En az şu kararlar burada tek yerde toplanmalı:

1. Ingredient kimliği olarak `ingredientId` kullanılır; çevrilmiş/görünen isim kimlik değildir.
2. Birim dönüşümü yalnızca desteklenen ve aynı birim ailesindeki dönüşümlerde yapılır.
3. Plan oluşturmak veya planı değiştirmek kiler stokunu sessizce değiştirmez.
4. Kullanıcı açıkça onaylamadıkça pişirme akışı stok düşmez.
5. Kullanıcının girdiği tarih uydurulmaz; tarih tek başına gıda güvenliği kararı üretmez.
6. V5’te fiyat, bütçe, fiyat geçmişi veya market sağlayıcı entegrasyonu yoktur.
7. Kişisel kiler, household kilerine otomatik ve sessizce birleştirilmez.
8. Stok ve market güncellemeleri tekrar denendiğinde çift kayıt/çift düşüm üretmeyecek şekilde idempotent olmalıdır.
9. V5.0 kapsamı dışında kalan otomasyonlar uygulanmış özellik gibi gösterilmez.

### 2.6 Durum ve kabul kapısı

Dokümanın durum paragrafı şu ayrımı net tutmalı:

- “Kodda uygulanmış”
- “Otomatik testle doğrulanmış”
- “Xcode/iOS cihazında doğrulanmış”
- “Ürün kabul kapısı kapandı”

Bu dört durum birbirinin yerine kullanılamaz. Mevcut V5.0 için belgede bulunan release gate kayıtları referans gösterilebilir; ancak Xcode derlemesi, `PantryTests` ve cihaz üzerinde VoiceOver / Dynamic Type / Dark Mode doğrulamaları yapılmadıysa tamamlandı olarak işaretlenmemeli.

Önerilen durum metni:

> V5.0 pantry işlevleri uygulanmış durumda; V5 kabul kapısının kapanması için doküman-kod uyumu, geçmiş `useBy` tarihindeki nötr metin ve platforma özgü iOS kontrolleri doğrulanmalıdır. Bu belgede test sonucu olarak yalnızca gerçek komut çıktısı veya CI kanıtı bulunan kontroller işaretlenir.

---

## 3. Globalization Readiness V1–V6 dokümanında yapılacak değişiklikler

Hedef belge: `MealRoutine_Globalization_Readiness_V1-V6.md` ve kullanılan güncel kopyası.

### 3.1 Roadmap tekilleştirme

Tüm bölümlerde aynı sıra kullanılmalı:

`V1 Core Meal Planning → V2 Personal Meal Memory → V3 Personal Recipe Collection → V4 Household & Shared Planning → V4.1 Release Hardening → V5 Smart Pantry → V6 Balanced Nutrition → V7 Globalization & Localization`

`V6 Meal Budget` referanslarını kaldır. Fiyat ve bütçe özelliğini V6’ya aitmiş gibi gösterme.

### 3.2 Global-ready ile localized/global launch ayrımı

- V1–V6: veri modeli, ID’ler, birimler, tarihler, saat dilimleri ve iş mantığı globalleşmeye hazır tutulur.
- V7: kullanıcıya görünen çok dilli arayüz, bölgesel deneyim, içerik, mağaza sayfası, destek ve global lansman.
- V1–V6’da Türkçe arayüz bulunması kabul edilebilir; ancak Türkçe metin, ülke, para birimi veya metrik sistem iş mantığında sabit varsayım haline getirilmez.

### 3.3 Bölgesel alanların birbirinden ayrılması

`locale`, `countryCode`, `currencyCode`, `measurementSystem` ve `timezone` farklı kavramlardır. Birbirinden otomatik çıkarılmamalı.

- `locale`: dil ve sayı/tarih biçimlendirmesi.
- `countryCode`: kullanıcının/household’un işletim bölgesi.
- `currencyCode`: ISO para birimi kodu; V6’da fiyat özelliği yoksa yalnız altyapı alanıdır.
- `measurementSystem`: açık tercih veya tanımlı bölgesel ayar.
- `timezone`: haftalık plan sınırları ve yerel hatırlatma zamanı.

`TR`, `TRY`, `metric`, `tr-TR` yalnızca geçiş için gerekirse kullanılan varsayılanlardır; kullanıcının açık ayarını ezemez.

### 3.4 V5 global-ready kontrolü

- Ingredient ID sabit kalır; adlar locale’e göre sunum katmanında çözülür.
- `bestBefore` / `useBy` tarihleri date-only semantiğini korur.
- Hatırlatma otomasyonu V5.0’da yoksa global readiness belgesi onu uygulanmış özellik gibi tarif etmez. İleride eklenirse household timezone ve cihaz bildirim izinleri açıkça ele alınır.
- Birimler yalnız desteklenen kurallarla dönüştürülür; dil veya ülke tek başına birim dönüşüm kuralı sayılmaz.
- Kullanıcı tarafından yazılmış tarif adı, notu ve talimatlar otomatik çevrilmez.

### 3.5 V6 beslenme sınırları

V6 için bu belge şu kapsamı sabitlemeli:

- Yemek örüntüsü ve tarif metadata’sına dayalı tercih modları.
- Güvenilir metadata yoksa sebze/protein/bitki ağırlıklı sınıflandırma uydurulmaz.
- Kalori, makro, sağlık/klinik iddialar ve besin veri tabanı bağımlılığı V6 başlangıç kapsamına dahil değildir.
- Nicel beslenme verisi daha sonraki ayrı bir sürüm/karar için ertelenir; kaynak lisansı, ülke kapsamı, çiğ/pişmiş ölçü, porsiyon normalizasyonu, eksik veri ve güncelleme politikası önceden kararlaştırılmalıdır.

### 3.6 Checklist’in kanıt standardı

Belgede yer alan maddeler “mimari hedef / denetim maddesi” olarak kalmalı; kod ve test kanıtı yoksa “tamamlandı” olarak işaretlenmemeli. Denetim bulguları ayrı `V1-V5 Cross-Version Audit Report` belgesine yazılmalı.

---

## 4. V1–V5 Cross-Version Audit için uygulanacak yöntem

Denetim, doküman okumakla sınırlı kalmamalı. Her bulgu için kaynak dosya, gerçek davranış, beklenen davranış, önem seviyesi, test ve karar kaydedilmeli.

### 4.1 Denetim kapsamı

1. V1: tarif/ingredient kimlikleri, birim modeli, planlama ve grocery toplama.
2. V2: Meal Memory sinyalleri, `Never Again`, puanlama ve kullanıcı geri bildirimi.
3. V3: manuel tarif oluşturma, eksik Quick Save ile planlanabilir tarif ayrımı; URL scraping varsayımı olmaması.
4. V4: household sahipliği, veto, üyelik, yetkilendirme, timezone ve senkronizasyon.
5. V4.1: hesap yaşam döngüsü, silme/export, API sürümleme, migration, retry/idempotency, offline/conflict.
6. V5: pantry ownership, ingredientId, birimler, tarihler, grocery etkileşimi, sessiz stok değişimi olmaması ve release gate.
7. Ortak: localization varsayımları, erişilebilirlik, hata/boş/offline durumları, veri kaybı ve regressions.

### 4.2 Önem seviyeleri

- **P0 — Release blocker:** veri kaybı, yetkisiz veri erişimi, yanlış ingredient kimliği veya kullanıcı onayı olmadan kritik veri değişikliği.
- **P1 — V6 öncesi blocker:** migration/şema uyumsuzluğu, lokalize görünen adların kimlik olarak kullanılması, yanlış tarih/birim semantiği, V1–V5 temel akışını bozan hata.
- **P2 — Sonraya alınabilir:** işlevsel doğruluğu etkilemeyen localization polish veya V7’ye ait UI genişletmeleri.

P0/P1 bulgular kapatılmadan V6 geliştirmesine başlanmaz.

### 4.3 Her bulgu için zorunlu kayıt

| Alan | İçerik |
|---|---|
| ID | Örn. `AUD-V5-001` |
| Sürüm/alan | V1–V5 ve alt sistem |
| Beklenen davranış | İlgili sürüm dokümanından kesin kural |
| Gerçek davranış | Dosya/satır, API, SQL veya test çıktısı |
| Sonuç | Pass / Fail / Not verified |
| Öncelik | P0 / P1 / P2 |
| Düzeltme | Dosya ve davranış düzeyinde kesin işlem |
| Test | Tekrarlanabilir test senaryosu/komutu |
| Durum | Open / Fixed / Verified |

“Not verified” sonucu “Pass” değildir.

---

## 5. Bu repoda özellikle doğrulanması gereken konular

Aşağıdakiler kod düzeyinde kesin kapatılması gereken hedefli kontrollerdir; denetim yapılmadan hepsinin hata olduğu varsayılmamalıdır.

### 5.1 Geçmiş `useBy` etiketi

- `V5.0` UI’da “Güvenlik uyarısı” veya aynı anlamdaki metni bul.
- Bunu “Girilen tarih geçti” benzeri nötr bir yerelleştirme anahtarıyla değiştir.
- Aynı metnin pantry listesi, detay ekranı, bildirim, widget ve planner açıklamalarında başka kopyası olup olmadığını ara.
- Test: `bestBefore` ve `useBy` için tarih geçmiş/bugün/gelecek senaryolarında UI gıda güvenliği hükmü vermemeli.

### 5.2 `0012_pantry` ve veri modeli

- Migration dosyasını ve sıralamasını belirle; gerçek schema dump veya test DB ile doğrula.
- iOS model, API DTO, server model ve SQL sütunlarının alan isimlerini ve nullability’lerini karşılaştır.
- Eski kayıtlar için migration testi ekle; mevcut ingredient identity, miktar, birim ve tarih kaybı olmamalı.
- Household ID/owner kapsamı ve kişisel kilerin cihazda kalması kuralını API authorization testleriyle doğrula.

### 5.3 Otomasyonların yanlışlıkla vaat edilmesi

- V5 dokümanında otomatik grocery ekleme, düşük stok bildirimi, tarih hatırlatması veya pişirme sonrası düşüm var mı kontrol et.
- Kodda ve release gate’te yoksa bunları V5.0’ın aktif özellikleri olarak tanımlama.
- Kodda varsa gerçek implementasyon ve test kanıtını bul; o zaman kapsamı ve ayar varsayılanlarını belgeyle hizala. Doküman tek başına yeni otomasyon eklenmesine gerekçe değildir.

### 5.4 V5 test ve kabul durumu

- `docs/v5-release-gate.md` maddelerini tek tek çalıştır veya CI kanıtıyla doğrula.
- Xcode/iOS gerektiren maddeleri platform gereksinimi nedeniyle “Not verified” olarak bırak; başarılı varsayma.
- Her kontrolün komutunu, sonucu ve mümkünse CI run/commit referansını audit report’a yaz.

---

## 6. Uygulama sırası — hangi belge ne zaman uygulanacak?

Aşağıdaki sıra zorunlu sıradır. Bir aşama tamamlanmadan sonraki aşamaya geçme.

### Adım 1 — Bu yönerge belgesini sabitle

Bu dosyayı proje dokümanlarına ekle. Bu belge uygulama talimatıdır; V5 kodunu doğrudan değiştirmez.

**Çıkış kriteri:** ekip/uygulama ajanı değişiklik kapsamını, V5.0 referans dalını ve P0/P1/P2 kurallarını kabul etmiş olmalı.

### Adım 2 — V5 Smart Pantry dokümanını güncelle

Hedef: `MealRoutine_V5_Smart_Pantry_Updated.md`.

Uygula: Bölüm 2’deki roadmap, tarih güvenliği dili, V5.0’da bulunmayan otomasyonların kapsam dışı tutulması, schema/migration kontrol notları, kilitli kararlar ve kanıta dayalı durum paragrafı.

**Çıkış kriteri:** V5 dokümanı V5.0’ın gerçek kapsamını anlatmalı; uygulanmamış özellikleri vaat etmemeli; tüm V6 referansları Balanced Nutrition olmalı.

### Adım 3 — Globalization Readiness belgesini güncelle

Hedef: `MealRoutine_Globalization_Readiness_V1-V6.md`.

Uygula: Bölüm 3’teki roadmap tekilleştirmesi, global-ready/global launch ayrımı, bölgesel alanlar, V5 tarih/birim/kimlik kontrolleri, V6 beslenme sınırları ve kanıt standardı.

**Çıkış kriteri:** belge V1–V6’nın global-ready altyapısını, V7’nin gerçek localization/global launch kapsamını anlatmalı; V6 Meal Budget kalıntısı kalmamalı.

### Adım 4 — V1–V5 Cross-Version Audit yönergesini çalıştır

Hedefler: `MealRoutine_V1-V5_Cross_Version_Audit.md` ve `MealRoutine_V1-V5_Cross_Version_Audit_Report.md`.

- Audit yönergesi test edilecek alanları ve komutları tanımlar.
- Audit report her bulgunun gerçek kanıtını, sonucunu ve önemini kaydeder.
- Dokümanla çelişen kodu, kodla çelişen dokümanı ve test edilmeyen alanları ayrı sınıflandır.

**Çıkış kriteri:** V1–V5 maddelerinin her biri Pass / Fail / Not verified olarak kayıtlı olmalı; P0/P1 bulgular listelenmiş olmalı.

### Adım 5 — Karara göre V5.1 düzeltme dalı aç veya açma

- P0/P1 bulgu varsa `V5.1_Integration_Readiness_Fixes` gibi açık kapsamlı bir düzeltme dalı/spec’i oluştur. Yalnızca audit bulgularındaki düzeltmeleri yap; V6 özellikleri ekleme.
- P0/P1 bulgu yoksa sırf sürüm numarası olsun diye V5.1 oluşturma.
- P2 maddeleri V7 veya ilgili sonraki sürüm backlog’una taşı; kararını audit report’a yaz.

**Çıkış kriteri:** tüm P0/P1 bulgular Fixed + Verified olmalı; ilgili regresyon testleri geçmeli.

### Adım 6 — V6 Balanced Nutrition belgesini son kez hizala ve V6’ya başla

Hedef: `MealRoutine_V6_Balanced_Nutrition.md`.

V6 ancak Adım 4–5 çıkış kriterleri sağlandığında başlar. V6’da yemek örüntüsü modları ve Today’s Meal widget’ı kapsam dahilindedir; nicel beslenme verileri, market fiyatları ve bütçe özellikleri dahil değildir.

**Çıkış kriteri:** V6 gereksinimleri V1–V5 davranışlarıyla çelişmiyor; hard constraints, eksik metadata ve household veto testleri tanımlı.

### Adım 7 — V7 Globalization & Localization planını ayrı tut

V7’ye kadar çok dilli UI veya global lansmanı V5/V6 kapsamına sokma. V7’de locale kaynakları, bölgesel içerik, formatlama, ölçü tercihleri, App Store metadata, privacy/legal review ve locale bazlı QA ayrı kabul kriterleriyle planlanır.

---

## 7. Nihai kontrol listesi

- [ ] V5 dokümanında `V6 Meal Budget` kalmadı.
- [ ] Geçmiş `useBy` tarihi için güvenlik hükmü veren metin kaldırıldı veya kaldırılacağı açıkça kaydedildi.
- [ ] V5.0’da bulunmayan otomasyonlar aktif özellik gibi anlatılmıyor.
- [ ] `0012_pantry`, iOS model, API DTO ve SQL alanları karşılaştırıldı.
- [ ] V5 kilitli kararları tek bölümde korunuyor.
- [ ] Globalization Readiness belgesinde V1–V6 global-ready, V7 global localization ayrımı açık.
- [ ] V6 nicel kalori/makro ve bütçe/fiyat kapsamı dışında.
- [ ] V1–V5 audit report’ta her madde Pass / Fail / Not verified.
- [ ] P0/P1 bulgular V6 başlamadan kapatıldı.
- [ ] Test kanıtı olmayan hiçbir madde “passed” veya “complete” olarak işaretlenmedi.

**Son karar:** Önce V5 dokümanı, ardından Globalization Readiness belgesi, sonra çapraz sürüm audit; audit sonucuna göre gerekiyorsa V5.1 düzeltmeleri; ancak bundan sonra V6 Balanced Nutrition.
