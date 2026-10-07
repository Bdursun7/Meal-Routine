# V5 yerel çalıştırma

V4.1 adımları `docs/v4.1-local-runbook.md` içindedir. V5 aynı sunucuyu kullanır ve şemaya `0012_pantry.sql` ekler. `0001`–`0011` değişmez.

## Şema

```bash
cd server
npm install
npm run migrate
npm test
npm run typecheck
```

`npm run migrate` `0001`–`0012` uygular. `0012` üç tablo kurar:

- `ingredients`: merkezi sözlük. Seed satırları (`household_id` boş) `server/db/ingredients.v1.json` ile aynıdır. Ev halkının eklediği `custom:<uuid>` satırları o eve bağlıdır.
- `pantry_items`: household pantry. `ingredient_id` sözlüğe bağlıdır; `date_type` (`bestBefore` | `useBy`) ve `date_value` ya ikisi birden vardır ya hiçbiri. `version` her yazımda artar.
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

`pantry.integration.test.ts` boş bir şemaya `0001`–`0011` uygular, V4.1 verisi yazar, `0012`’yi uygular ve hiçbir satırın kaybolmadığını, kısıtların veritabanında da tuttuğunu doğrular.

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
- Pantry gövdesi: `ingredientId`, `displayName`, `quantity`, `unit`, `location`, `minimumQuantity`, `dateType`, `dateValue` (`YYYY-MM-DD`). Şema strict; eski `bestBefore` alanı reddedilir.
- Uyumlu birim aynı `ingredientId` satırına eklenir (g/kg, ml/L). Uyumsuz birim 409 `pantry_unit_choice`; `confirmSeparate: true` ayrı satır açar. Bilinmeyen birim 400.
- Eski `baseVersion` 409 `conflict` ve gövdede `current` (sunucudaki satır) döner.
- `reconcile-grocery`: `operation` (`compute-missing`, `consume`, `restock`) ve `lines`. `compute-missing` stoktan düşmez. İşaretli satır aynen kalır. Uyumsuz birim otomatik düşülmez.
- Pantry hatalarında gövde `recovery` taşır: `resolve`, `choose-unit`, `fix-input`, `new-key`, `refresh-household`, `retry-later`, `reauthenticate`. Uygulama `fix-input`, `new-key` ve `refresh-household` hatalarını yeniden göndermez; satırı “gönderilemedi” olarak gösterir.

## Uygulama

`MARKETING_VERSION` `5.0.0`. Evdekiler, Profil’den açılır.

- Malzeme adı serbest yazılır. Öneriler sözlük adı, eş anlamlı ve evin özel malzemeleridir. Öneriye basılmazsa tekil birebir eşleşme bağlanır; yoksa `custom:<uuid>` oluşur. İkinci onay yoktur. “Domates” ile “Cherry domates” birleşmez.
- Tarih isteğe bağlıdır. “Son tüketim tarihi (STT)” geçince güvenlik uyarısı, “Tavsiye edilen tüketim tarihi (TETT)” geçince tazelik uyarısı görünür.
- Market’te “Eksik miktarı hesapla”, satırda “Evdekilerden düş” ve “Evdekilere ekle” vardır. Plan kurmak ve “Pişirdim” stoğu değiştirmez.
- “Bitti” seçenek ister; seçilmeden ya da İptal ile stok değişmez.
- Household yazımları önce telefona yazılır, sonra kuyruktan gönderilir. Çevrimdışıyken satırda “Eşitlenmeyi bekliyor” görünür. Çakışmada “Bu malzeme başka bir cihazda güncellendi.” ve iki seçenek çıkar.
- Kişisel pantry, ev kurulunca kendiliğinden karışmaz. Aktar, kopyala veya ayrı tut onayı istenir; satırlar yalnız aynı sözlük kimliğinde birleşir.

## iOS testleri

Mac’te Xcode ile `MealRoutineTests` koş. Pantry hedefleri:

- `PantryDomainTests.swift`: sözlük, tarih türleri, satır sunumu, birim, market hesabı, planner sinyali, sync gövdeleri. Yalnız Foundation.
- `PantryTests.swift`: SwiftData cache, outbox, conflict çözümü, transfer, gizlilik, plan ve pişirmenin stoğa dokunmaması.

Mac olmadan domain testleri Linux’ta da koşar (Swift 5.9+ ve XCTest):

```bash
Tools/run_pantry_domain_tests.sh
```

`Tools/run_*_checks.sh` betikleri aynı Foundation dosyalarını derler ve Xcode gerektirmez.
