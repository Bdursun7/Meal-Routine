# V5 yerel çalıştırma

V4.1 adımları `docs/v4.1-local-runbook.md` içindedir. V5 aynı sunucuyu kullanır ve şemaya `0012_pantry.sql` ekler. V5.1 `0013_pantry_auto_add.sql` ile `pantry_items.auto_add_to_grocery` kolonunu ekler (`BOOLEAN NOT NULL DEFAULT false`). `0001`–`0012` dosyaları yeniden yazılmaz. Household saat dilimi kolonu yoktur.

## Şema

```bash
cd server
npm install
npm run migrate
npm test
npm run typecheck
```

`npm run migrate` `0001`–`0013` uygular. `0012` üç tablo kurar:

- `ingredients`: merkezi sözlük. Seed satırları (`household_id` boş) `server/db/ingredients.v1.json` ile aynıdır. Ev halkının eklediği `custom:<uuid>` satırları o eve bağlıdır.
- `pantry_items`: household pantry. `ingredient_id` sözlüğe bağlıdır; `date_type` (`bestBefore` | `useBy`) ve `date_value` ya ikisi birden vardır ya hiçbiri. `version` her yazımda artar. `0013` `auto_add_to_grocery` ekler; varsayılan kapalıdır.
- `pantry_idempotency`: aynı `Idempotency-Key` ile gelen isteğin ilk cevabı. Hesap silinince o hesabın satırları silinir.

Kişisel pantry sunucuya hiç gitmez; yalnız telefondaki SwiftData’dadır.

### Taslak `0012` uygulanmış geliştirme veritabanı

Kapı öncesi `V5.0` dalındaki taslak `0012_pantry` sözlüksüz bir `pantry_items` kurmuştu. O taslağı uygulamış yerel bir veritabanında `schema_migrations` dosyayı uygulanmış sayar. Yalnız geliştirme veritabanında:

```sql
DROP TABLE IF EXISTS pantry_idempotency;
DROP TABLE IF EXISTS pantry_items;
DELETE FROM schema_migrations WHERE version = '0012_pantry';
```

Sonra `npm run migrate`. Yayınlanmış bir ortamda taslak hiç uygulanmadı.

### Testler

`DATABASE_URL` yoksa Postgres entegrasyon testleri atlanır; bellek deposundaki pantry testleri yine çalışır. Postgres ile:

```bash
DATABASE_URL=postgres://kullanici:sifre@localhost:5433/mealroutine npm test
```

`pantry.integration.test.ts` boş bir şemaya `0001`–`0011` uygular, V4.1 verisi yazar, `0012` ve `0013`’ü uygular ve hiçbir satırın kaybolmadığını, kısıtların veritabanında da tuttuğunu doğrular.

## Ingredient sözlüğü

Sözlük `Tools/build_ingredient_dictionary.py` ile katalogdan üretilir ve iki kopyası aynıdır:

```bash
python3 Tools/build_ingredient_dictionary.py
```

Çıktı `MealRoutine/Recipes/ingredients.v1.json` (uygulama paketi) ve `server/db/ingredients.v1.json` (seed). Birleştirmeler betikteki açık listeden gelir (`tomatoes` → `tomato` gibi); benzer görünen adlar kendiliğinden birleşmez. Bir ad iki girdiye aitse eşleme anahtarı olmaz. Sözlük değişirse ikisini birlikte commit et; `migrations.test.ts` iki dosyanın ve seed’in aynı olduğunu kontrol eder.

Eşleme sırası: sözlük `id`, katalog `sourceIds`, tek anlamlı seed adı, `custom:<uuid>`. Çözülemeyen kimlik hiçbir şeyle eşleşmez.

## API

```text
GET    /v1/ingredients?householdId=&q=&limit=
POST   /v1/households/:id/ingredients
GET    /v1/households/:id/pantry
POST   /v1/households/:id/pantry/items
PATCH  /v1/households/:id/pantry/items/:itemId?baseVersion=
DELETE /v1/households/:id/pantry/items/:itemId?baseVersion=
POST   /v1/households/:id/pantry/reconcile-grocery
```

Yazımlar `Idempotency-Key` (8–200 karakter) ister. Aynı anahtar aynı gövdeyle ilk cevabı döner, farklı gövdeyle 409 verir.

- `GET /v1/ingredients`: seed sözlük ve `householdId` verilirse o evin malzemeleri. `scope` `dictionary` veya `household`.
- `POST …/ingredients`: `{ id: "custom:<uuid>", displayName }`. İstemci, yazılan ad tek bir sözlük veya ev malzemesiyle birebir örtüşmezse bu kimliği üretir ve ortak evde kaydeder. Aynı id ikinci kez gelirse mevcut satır döner. Kişisel evdekilerde özel malzeme yalnız telefonda durur.
- Pantry gövdesi: `ingredientId`, `displayName`, `quantity`, `unit`, `location`, `minimumQuantity`, `autoAddToGrocery`, `dateType`, `dateValue` (`YYYY-MM-DD`). Şema strict; eski `bestBefore` alanı reddedilir. `autoAddToGrocery` yoksa create `false` yazar, patch mevcut değeri bırakır. İstemci bu günü `calendarDay` stringi olarak saklar. Saat dilimi değişince gün kaymaz. Eski kişisel satırda tarih hâlâ `Date` ise V5.1 açılışında o satır bir kez silinir (proje sahibi, 2026-10-10). Tarihsiz kişisel satır kalır. Ortak satır silinmez; sunucudan gelen `YYYY-MM-DD` yazılır.
- Uyumlu birim aynı `ingredientId` satırına eklenir (g/kg, ml/L). Uyumsuz birim 409 `pantry_unit_choice`; `confirmSeparate: true` ayrı satır açar. Bilinmeyen birim 400.
- Eski `baseVersion` 409 `conflict` ve gövdede `current` (sunucudaki satır) döner.
- `reconcile-grocery`: `operation` (`compute-missing`, `consume`, `restock`) ve `lines`. `compute-missing` stoktan düşmez. İşaretli satır aynen kalır. Uyumsuz birim otomatik düşülmez.
- Pantry hatalarında gövde `recovery` taşır: `resolve`, `choose-unit`, `fix-input`, `new-key`, `refresh-household`, `retry-later`, `reauthenticate`. Uygulama `fix-input`, `new-key` ve `refresh-household` hatalarını yeniden göndermez; satırı “gönderilemedi” olarak gösterir.

## Uygulama

`MARKETING_VERSION` `5.0.0`. Evdekiler, Profil’den açılır.

- Malzeme adı serbest yazılır. Öneriler sözlük adı, eş anlamlı ve evin özel malzemeleridir. Öneriye basılmazsa tekil birebir eşleşme bağlanır; yoksa `custom:<uuid>` oluşur. İkinci onay yoktur. “Domates” ile “Cherry domates” birleşmez.
- Tarih isteğe bağlıdır. “Son tüketim tarihi (STT)” geçince “Girilen son tüketim tarihi geçti”, “Tavsiye edilen tüketim tarihi (TETT)” geçince “Girilen tavsiye edilen tüketim tarihi geçti” görünür. Bu satırlar paketteki türü ve tarihin geçmiş olduğunu söyler; gıdanın güvenli olup olmadığına karar vermez.
- Market’te “Eksik miktarı hesapla”, satırda “Evdekilerden düş” ve “Evdekilere ekle” vardır. Plan kurmak, plan satırını açmak veya işaretlemek ve “Pişirdim” tek başına stoğu değiştirmez. Puan kaydedilince “Evdekilerden düşülsün mü?” sayfası açılır. “Stoktan düşme” stoku bırakır. “Stoktan düş” yalnız aynı malzeme kimliği ve çevrilebilir birimde, eldeki miktarı aşmadan düşer. Eksik, `autoAddToGrocery` kapalıysa kendiliğinden markete yazılmaz; “Eksik miktarı markete ekle” ayrı durur.
- Eşik market satırı yalnız `autoAddToGrocery` açıkken ve miktar minimumun üstünden minimuma veya altına ilk inince yazılır. Anahtar `pantry-auto:<ingredientId>|<birim>`. Ortak listede gövde `mode: "set"` mutlak miktar yazar; iki telefon aynı eksiği ikinci satır yapmaz. İşaretli satır durur. Miktar `0008` tamsayısıdır (`1`–`999`).
- Evdekiler’de “Düşük stok bildirimi” ve “Tarih hatırlatması” anahtarları cihazdadır, sunucu şeması değildir. Hatırlatma, girilen `YYYY-MM-DD` gününde cihazın saat dilimiyle 09:00’a konur. `bestBefore` 2 gün önce ve o gün, `useBy` 1 gün önce ve o gündür. İzin yoksa pantry yine çalışır. Uzak push V6 sonrasına bırakıldı. Household saat dilimi V7’dedir.
- “Bitti” seçenek ister; seçilmeden ya da İptal ile stok değişmez.
- Household yazımları önce telefona yazılır, sonra kuyruktan gönderilir. Çevrimdışıyken satırda “Eşitlenmeyi bekliyor” görünür. Çakışmada “Bu malzeme başka bir cihazda güncellendi.” ve iki seçenek çıkar.
- Kişisel pantry, ev kurulunca kendiliğinden karışmaz. Aktar, kopyala veya ayrı tut onayı istenir; satırlar yalnız aynı sözlük kimliğinde birleşir.

## iOS testleri

Mac’te Xcode ile `MealRoutineTests` koş. Pantry hedefleri:

- `PantryDomainTests.swift`: sözlük, tarih türleri, satır sunumu, birim, market hesabı, planner sinyali, sync gövdeleri. Yalnız Foundation.
- `PantryTests.swift`: SwiftData cache, outbox, conflict çözümü, transfer, gizlilik, plan ve pişirmenin tek başına stoğa dokunmaması. Onaylı düşüm, bildirim ve hatırlatma kararı `PantryDomainTests` içindedir; ekran ve `UNUserNotificationCenter` Xcode ister.

Mac olmadan domain testleri Linux’ta da koşar (Swift 5.9+ ve XCTest):

```bash
Tools/run_pantry_domain_tests.sh
```

`Tools/run_*_checks.sh` betikleri aynı Foundation dosyalarını derler ve Xcode gerektirmez.
