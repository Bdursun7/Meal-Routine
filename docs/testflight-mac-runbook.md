# TestFlight Mac kurulum rehberi

Dal: `V5.1-TestFlight`. Uygulama sürümü **5.1.0 (6)**. Bu sayfa sahibin Mac’inde ve Apple web sitelerinde yapılacak işleri anlatır. Sunucu kodu repodadır; `.p8` ve `server/.env` repoya girmez.

Ek maliyet 0 $. Quick tunnel adresi her yeniden başlatmada değişir. Birden fazla testçi olduğu için uygulama önce elle adresi, sonra son iyi adresi, sonra Gist JSON’unu, sonra derleme adresini, sonra Local şemada localhost’u kullanır.

## 1. Postgres

Konteyner yoksa:

```bash
docker run --name mealroutine-postgres \
  --restart unless-stopped \
  -e POSTGRES_USER=mealroutine \
  -e POSTGRES_PASSWORD=mealroutine \
  -e POSTGRES_DB=mealroutine \
  -p 5433:5432 \
  -d postgres:16
```

Konteyner varsa:

```bash
docker update --restart unless-stopped mealroutine-postgres
docker start mealroutine-postgres
```

Docker Desktop’ın oturum açınca başlamasını aç. 5433 yönlendiricide yayınlanmaz.

## 2. `server/.env`

```bash
cd server
cp .env.example .env
chmod 600 .env
```

Doldur:

```bash
DATABASE_URL=postgres://mealroutine:mealroutine@localhost:5433/mealroutine
JWT_SECRET=EN_AZ_32_KARAKTER_RASTGELE
GOOGLE_CLIENT_ID_IOS=
APPLE_BUNDLE_ID=com.berkaydursun.mealroutine.app
PORT=8080
NODE_ENV=development

APNS_KEY_ID=9SM8YS7B5H
APNS_TEAM_ID=L99MZR5MXZ
APNS_BUNDLE_ID=com.berkaydursun.mealroutine.app
APNS_KEY_PATH=/Users/OWNER/.config/mealroutine/AuthKey_9SM8YS7B5H.p8
APNS_PRODUCTION=true
```

`JWT_SECRET` en az 32 karakter, repoda olmayan bir metin olsun. `NODE_ENV` burada `development` kalsa da LaunchAgent onu `production` yapar ve `.env` kabukta duran değişkeni ezmez. Elle `npm start` ile denecekse bu satırı `production` yap. Production’da `APPLE_BUNDLE_ID` boşsa veya `com.mealroutine.app` ise süreç açılmaz. `POST /v1/auth/dev` production’da 404 döner.

`GOOGLE_CLIENT_ID_IOS` bu betada boş kalır. Release arşivi boş Google uyarısını göstermez.

## 3. APNs `.p8`

Dosyayı sohbete yapıştırma. Repo dışında tut:

```bash
mkdir -p ~/.config/mealroutine
mv /indirdigin/yol/AuthKey_9SM8YS7B5H.p8 ~/.config/mealroutine/
chmod 600 ~/.config/mealroutine/AuthKey_9SM8YS7B5H.p8
```

`APNS_KEY_PATH` bu mutlak yol olsun. `*.p8` gitignore’dadır. TestFlight production APNs kullanır; `APNS_PRODUCTION=true` `https://api.push.apple.com` adresine gider. Xcode’dan development kurulumuyla bu sürece push denemesi yapma; o jeton sandbox’tır.

## 4. Şema ve ilk kontrol

```bash
cd server
npm install
npm run migrate
NODE_ENV=production npm start
```

Başka bir terminalde:

```bash
curl -sS http://localhost:8080/health
curl -sS http://localhost:8080/ready
curl -sS -o /dev/null -w "%{http_code}\n" -X POST http://localhost:8080/v1/auth/dev \
  -H 'content-type: application/json' \
  -d '{"subject":"dev-beta","displayName":"Yerel"}'
```

Beklenen: `/health` içinde `"ok":true`, `/ready` 200, dev girişi **404**. Sonra bu elle süreci durdur; asıl süreç launchd olacak.

## 5. LaunchAgent

`Tools/launchd/` içindeki üç plist şablondur. Kopyalayıp yolları değiştir:

- `/ABSOLUTE/Meal-Routine` → bu klonun yolu
- `/ABSOLUTE/node` → `which node`
- `/Users/OWNER` → `$HOME`
- `cloudflared` Intel Mac’te `/usr/local/bin/cloudflared` olabilir

API plist’i `caffeinate -s` ile node’u prizde uyanık tutar. Tünel plist’i stdout ve stderr’i aynı günlüğe yazar ki quick tunnel adresi orada kalsın.

```bash
cp Tools/launchd/com.berkaydursun.mealroutine.api.plist ~/Library/LaunchAgents/
cp Tools/launchd/com.berkaydursun.mealroutine.tunnel.plist ~/Library/LaunchAgents/
cp Tools/launchd/com.berkaydursun.mealroutine.backup.plist ~/Library/LaunchAgents/
# yolları düzenle, sonra:
launchctl bootout gui/$UID/com.berkaydursun.mealroutine.api 2>/dev/null || true
launchctl bootstrap gui/$UID ~/Library/LaunchAgents/com.berkaydursun.mealroutine.api.plist
launchctl bootstrap gui/$UID ~/Library/LaunchAgents/com.berkaydursun.mealroutine.tunnel.plist
launchctl bootstrap gui/$UID ~/Library/LaunchAgents/com.berkaydursun.mealroutine.backup.plist
```

Yedek her gece 03:15’te `Tools/backup_postgres.sh` ile `~/Backups/mealroutine/` altına `pg_dump` yazar ve 7 kopya tutar. `PGPASSWORD` yedek plist’indedir; bu dosya repoya geri kopyalanmaz.

Uyku: Sistem Ayarları → Enerji, prize takılıyken uyku kapalı, kapak açık. `pmset -a disablesleep 1` kullanma.

Kontrol:

```bash
curl -sS http://localhost:8080/health
curl -sS http://localhost:8080/ready
grep -oE 'https://[A-Za-z0-9-]+\.trycloudflare\.com' ~/Library/Logs/mealroutine-tunnel.log | tail -n 1
```

## 6. Herkese açık Gist

Tünel adresi Gist’in içindedir. Gist’in kendi URL’si sabittir ve uygulamaya derleme ayarı olarak girer.

```bash
printf '%s\n' '{"apiBaseURL":"https://placeholder.trycloudflare.com"}' > /tmp/server.json
gh auth status
gh gist create --public /tmp/server.json --desc "MealRoutine server address"
```

Çıkan gist kimliğini sakla. Ham adres şöyledir:

```text
https://gist.githubusercontent.com/SAHIP/GIST_ID/raw/server.json
```

Bunu iki dosyada placeholder’ın yerine yaz:

- `Config/App.xcconfig` → `MEALROUTINE_REMOTE_CONFIG_URL`
- Local şema aynı dosyayı `#include` eder

Bu URL tünel sırrı değildir; commit edilebilir. Asıl tünel adresi Gist içeriğindedir.

Tünel her yeniden başlayınca:

```bash
MEALROUTINE_GIST_ID=GIST_ID Tools/update_tunnel_gist.sh
```

Betik `~/Library/Logs/mealroutine-tunnel.log` içindeki son `https://….trycloudflare.com` satırını `gh gist edit` ile `server.json` dosyasına yazar. `gh auth status` bu Mac’te başarılı olmalıdır.

Telefonlar elle adres yoksa son iyi adresi kullanır, o da yoksa bu JSON’u okur. Elle adres her zaman kazanır. JSON okunamazsa son iyi adres durur.

## 7. Telefonda adres

Profil’in en altındaki sürüm satırına 2 saniye içinde 7 kez dokun. Sayfa etkin adresi, kaynağını ve uzak yapılandırma URL’sini gösterir.

- Kaydet: yapıştırılan `https://….trycloudflare.com` elle adres olur.
- Elle adresi sil: Gist / son iyi adres devreye girer.
- Uzak adresi yenile: Gist’i hemen okur.
- Bağlantıyı dene: `GET /health`.

Oturum jetonu host’a bağlı değildir. Aynı Mac ve aynı `JWT_SECRET` arkasında adres değişince yeniden giriş gerekmez. Adres yokken ev halkı CloudKit’e düşmez; ekranda `sunucu adresi yok` yazar.

Test modunu kapalı bırak. Açıkken ev halkı sahte sunucudadır.

## 8. Apple portal

Takım `L99MZR5MXZ`.

1. Identifiers → App ID `com.berkaydursun.mealroutine.app`: Sign in with Apple, Push Notifications, App Groups.
2. App ID `com.berkaydursun.mealroutine.app.share`: App Groups.
3. App Group kimliği kodda durduğu gibi **`group.com.berkaydursun.mealroutine.app`**. İki App ID’ye de ekle. Yeniden adlandırma.
4. APNs anahtarını yeniden oluşturma. Key ID `9SM8YS7B5H` yeter.
5. Release arşivi iCloud kabı istemez. `MealRoutine.Release.entitlements` içinde CloudKit yok. `aps-environment` production’dır. Debug dosyası development’ta kalır.

## 9. App Store Connect ve arşiv

1. Yeni iOS uygulaması. Ad MealRoutine, dil Türkçe, bundle `com.berkaydursun.mealroutine.app`, SKU `mealroutine-ios`.
2. Gizlilik etiketi: ad, e-posta, ürün etkileşimi, çökme verisi, diğer kullanıcı içeriği, aygıt kimliği (APNs jetonu). İzleme yok, satış yok. Ayrıntı `MealRoutine/PrivacyInfo.xcprivacy` ve `docs/gizlilik-politikasi.md`.
3. Şifreleme: proje `ITSAppUsesNonExemptEncryption = NO` taşır. Soru çıkarsa cevap muaf HTTPS’tir.
4. Xcode şeması **MealRoutine** (Local değil). Any iOS Device. Product → Archive. Sürüm 5.1.0, build 6. Organizer’da `MealRoutineShare.appex` arşivin içinde olsun.
5. Distribute App → App Store Connect → Upload. Otomatik imza, takım `L99MZR5MXZ`.
6. İşlenince iç test grubuna aç. İç test Beta App Review istemez.
7. Dış testçiden önce `docs/gizlilik-politikasi.md` içindeki iletişim satırını doldur ve herkese açık bir URL’ye koy (GitHub Pages olur). Beta inceleme bu URL’yi, bir telefon ve bir e-posta ister. İnceleme boyunca tünel ve Gist ayakta olmalıdır. İnceleyen kendi Apple kimliğiyle girer; demo şifresi yoktur. Plan hesapsız açılır, ev halkı Sign in with Apple ister.

Sonraki yüklemede build numarasını 6’nın üstüne çıkar. Aynı build iki kez yüklenmez.

## 10. İlk telefon turu

1. TestFlight’tan kur.
2. Sürüm satırı `5.1.0 (6)` olsun. Yedi dokunuşta adres sayfası açılsın.
3. Gist güncel değilse tünel URL’sini kaydet. Bağlantıyı dene.
4. Apple ile giriş. Uygulamayı öldürüp aç; oturum durmalı.
5. İkinci telefon aynı adrese bağlansın, davet koduyla eve katılsın.
6. Bir telefonda veto veya plan değişikliği diğerinde APNs ile gelsin. Aynı olay için ikinci bir yerel kopya gelmemeli. Kiler tarih anımsatıcıları bu telefonda yerel kalır.
7. Paylaşım sayfasından bir bağlantı gönder. App Group portalda kayıtlıysa ana uygulama bir sonraki açılışta onu alır.
