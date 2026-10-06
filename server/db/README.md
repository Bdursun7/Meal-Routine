# MealRoutine veritabanı

Sunucu Postgres kullanır. Barındırılan bir veritabanı gerekmez. Şema `migrations/` altındaki dosyalardadır. `npm run migrate` her dosyayı bir kez uygular ve adını `schema_migrations` tablosuna yazar. Dosyalar `IF NOT EXISTS` kullandığı için aynı dosyayı elle ikinci kez çalıştırmak da tabloyu bozmaz. `0001`–`0011` değişmez. Ürün istatistikleri ve çökme özetleri `0011_observability.sql` dosyasındadır. V5 pantry satırları ve idempotency kayıtları `0012_pantry.sql` dosyasındadır. Hesap silinince o hesabın idempotency satırı silinir; household pantry’si yalnız ev kapanınca silinir. Gözlem satırları 30 gün sonra yeni kayıt sırasında silinir.

Postgres 14 veya daha yeni olmalı.

Komutları repo kökünden değil, `server/` klasöründen çalıştır.

## 1. Postgres (Docker, port 5433)

5432 dolu olabilir. Bu komut veritabanını 5433’te açar:

```bash
docker run --name mealroutine-postgres \
  -e POSTGRES_USER=mealroutine \
  -e POSTGRES_PASSWORD=mealroutine \
  -e POSTGRES_DB=mealroutine \
  -p 5433:5432 \
  -d postgres:16
```

Durmuş bir konteyneri yeniden açmak için: `docker start mealroutine-postgres`

## 2. Postgres (Docker olmadan)

Kendi kurduğun Postgres’te:

```bash
createdb -h localhost -p 5433 mealroutine
```

Kümenin portu 5432 ise komuttan `-p 5433` kısmını çıkar ve aşağıdaki `DATABASE_URL` içindeki portu 5432 yap.

## 3. Ayar dosyası

```bash
cd server
cp .env.example .env
```

`.env` içinde `JWT_SECRET` değerini en az 32 karakterlik rastgele bir metinle değiştir. Sunucu bu sırrı kodun içine gömmez; boşsa açılmaz. `GOOGLE_CLIENT_ID_IOS` boş kalabilir; Google ile giriş ancak bu kimlik doluyken çalışır. `APPLE_BUNDLE_ID` `com.mealroutine.app` olarak kalır. `CORS_ORIGIN` iOS uygulaması için boş kalır. Tarayıcıdan çağrı varsa tam bir origin yaz; `*` kabul edilmez.

## 4. Şemayı kur

```bash
cd server
npm install
npm run migrate
```

Elle uygulamak istersen (migrate ile aynı iş):

```bash
cd server
set -a
source .env
set +a
for f in db/migrations/*.sql; do
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f "$f"
  version=$(basename "$f" .sql)
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "INSERT INTO schema_migrations (version) VALUES ('$version') ON CONFLICT DO NOTHING;"
done
```

Kontrol:

```bash
psql "$DATABASE_URL" -c "\dt"
psql "$DATABASE_URL" -c "SELECT version FROM schema_migrations ORDER BY version;"
```

## 5. Sunucuyu başlat

```bash
cd server
npm start
```

Adres: `http://localhost:8080`. Sağlık kontrolü: `curl http://localhost:8080/health`

`NODE_ENV=development` iken `POST /v1/auth/dev` açıktır. Bunu production ortamında `NODE_ENV=production` yap. Ücretsiz **MealRoutine Local** şemasındaki “Yerel test girişi” bu uca gider.

## 6. Test

```bash
cd server
npm test
```

`DATABASE_URL` yoksa Postgres testi atlanır. Varsa o veritabanında geçici bir şema açar ve bitince siler.

## Google iOS istemci kimliği

Ücretli bir Apple hesabı gerekmez. Google Cloud Console’da bir proje aç, OAuth consent screen’i test kullanıcısıyla doldur, kimlik bilgisi türü **iOS** olan bir OAuth client oluştur. Bundle id `com.mealroutine.app` olsun. Çıkan istemci kimliğini iki yere yaz:

- `server/.env` → `GOOGLE_CLIENT_ID_IOS`
- Xcode’da `Config/Debug-Local.xcconfig` → `GOOGLE_IOS_CLIENT_ID` ve `GOOGLE_REVERSED_CLIENT_ID`

Ters kimlik, istemci kimliğinin ters çevrilmiş halidir. Örnek: `123-abc.apps.googleusercontent.com` için `com.googleusercontent.apps.123-abc`.
