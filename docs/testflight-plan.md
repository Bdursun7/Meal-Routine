# TestFlight planı — V5-Alignment-Audit

Kaynak: `e84a525` (`V5.1’i kapat ve MealRoutineUITests duman akışlarını ekle`). Tarih: 12 Ekim 2026.

Bu belge özellik kodu içermez. V6.0 durdurulmuştur; ona dokunulmaz. V5.0’a da dokunulmaz. Bütün iş `V5-Alignment-Audit` üzerindedir.

Hedef: kullanıcının her zaman açık Mac’indeki sunucuya, ücretsiz Cloudflare quick tunnel (`cloudflared tunnel --url http://localhost:8080`) üzerinden bağlanan bir TestFlight betası. `trycloudflare.com` adresi süreç her yeniden başlayınca değişir. Apple takımı `L99MZR5MXZ`, bundle `com.berkaydursun.mealroutine.app`, APNs Key ID `9SM8YS7B5H`. `.p8` kullanıcıda durur; repoya ve bu belgeye yazılmaz. Sign in with Apple ve APNs bu beta için bağlanır.

Ek maliyet hedefi 0 $. Ücretli Apple Developer üyeliği zaten vardır.

## Kısa karar

| Konu | Karar |
| --- | --- |
| Google ile giriş | Kod var, Release’te kapalı. Bu betaya alınmaz. |
| Sunucu adresi | Elle 7 dokunuş birincil. Birden fazla testçi varsa sabit bir Gist JSON yedek keşif. |
| Apple girişi | İstemci ve sunucu doğrulaması yazılmış. Portal yetkisi, doğru `APPLE_BUNDLE_ID` ve Release arşivi kaldı. |
| APNs | Sunucu gönderici yazılmış. TestFlight production APNs ister. Entitlement hâlâ `development`. `.p8` repoda yok. |
| Paylaşım uzantısı | Release App Group entitlement’ı dosyada var. Portal kaydı kullanıcıda. |
| İlk dağıtım | İç testçi (Beta App Review yok). Dış testçi tünel ayakta ve gizlilik URL’si hazır olunca. |

## 1. Google Sign-In

Google ile giriş kodda var. Bu beta için yeni bir sağlayıcı yazmaya gerek yok. Release / TestFlight derlemesinde istemci kimliği boş olduğu için düğme çalışmaz.

İstemci:

- Swift Package: `GoogleSignIn-iOS`, alt sınır 10.0.0 (`MealRoutine.xcodeproj` ve `project.yml`).
- `MealRoutine/Auth/GoogleSignInCoordinator.swift` `GIDSignIn` çağırır, `idToken` alır.
- `MealRoutine/App/MealRoutineApp.swift` dönüş URL’sini `GIDSignIn`’e verir ve açılışta `configureIfNeeded()` çağırır.
- `MealRoutine/Auth/APIClient.swift` `POST /v1/auth/google` yapar.
- `MealRoutine/Auth/AuthSession.swift` girişi, bağlamayı ve `link_required` durumunda ikinci hesap açmamayı yönetir.
- `MealRoutine/Features/Profile/AccountView.swift` “Google ile giriş” ve “Google bağla” gösterir. `GIDClientID` boşsa düğme yerine geliştirici metni durur (`MealRoutineConfig.googleClientMissingMessage`).
- `MealRoutine/Info.plist` ve `MealRoutine/Info-Local.plist`: `GIDClientID` = `$(GOOGLE_IOS_CLIENT_ID)`, URL şeması `$(GOOGLE_REVERSED_CLIENT_ID)`.

Sunucu:

- `POST /v1/auth/google` (`server/src/app.ts`).
- `server/src/jwks.ts` Google JWKS (`https://www.googleapis.com/oauth2/v3/certs`) ile doğrular. `GOOGLE_CLIENT_ID_IOS` boşsa `google_not_configured` / 503.
- Aynı doğrulanmış e-posta başka sağlayıcıda varsa `link_required` / 409; ikinci hesap açılmaz (`server/src/authService.ts`).
- `server/.env.example` içinde `GOOGLE_CLIENT_ID_IOS=` boş.

Yapılandırma boşluğu:

- `GOOGLE_IOS_CLIENT_ID` ve `GOOGLE_REVERSED_CLIENT_ID` yalnız `Config/Debug-Local.xcconfig` içindedir ve ikisi de boştur.
- Debug ve Release hedef ayarlarında bu iki anahtar yoktur. TestFlight arşivi Release kullanır; `MealRoutineConfig` `$(` içeren değeri boş sayar. Google düğmesi beta kullanıcısına geliştirici uyarısı olarak görünür.
- `docs/v4.1-local-runbook.md` Google bundle’ını `com.mealroutine.app` diye yazar. Güncel Xcode bundle’ı ve `server/db/README.md` `com.berkaydursun.mealroutine.app` der. İleride Google açılırsa istemci bu ikinci kimlikle oluşturulur.

Bu betada Google açılmaz. Sign in with Apple tek giriş yolu olarak yeter; Apple’ın “başka sosyal giriş varsa Apple da olsun” kuralı, yalnız Apple sunulunca da sağlanır. Google Cloud OAuth iOS istemcisi, onay ekranı ve Release build ayarı ayrı bir iştir, 0 $’dır, bu betayı bekletmez.

Beta arşivinde boş kimlik uyarısını gizlemek küçük bir arayüz işidir (aşağıdaki PR1). Sağlayıcıyı etkinleştirmez.

## 2. Çalışırken değişen sunucu adresi

Bugün adres derlemeye gömülüdür.

`MealRoutine/Auth/MealRoutineConfig.swift`:

1. Info.plist `MealRoutineAPIBaseURL` dolu ve `http`/`https` ise onu kullanır.
2. `HOUSEHOLD_LOCAL` ise `http://localhost:8080`.
3. Aksi halde `nil`.

`Config/Debug-Local.xcconfig` Local şemaya `http://localhost:8080` yazar. Debug ve Release’te `MEALROUTINE_API_BASE_URL` yoktur. Release `Info.plist` ATS istisnası da içermez (`NSAppTransportSecurity` yalnız `Info-Local.plist` içindedir, `NSAllowsLocalNetworking`).

Sonuç: MealRoutine şemasıyla alınan Release arşivinde `apiBaseURL` nil’dir. `HouseholdSyncRouting` (`MealRoutine/Household/HouseholdBackend.swift`) test modu kapalı ve adres nil iken CloudKit’e düşer (`iCloud.com.mealroutine.app`). Hesap çağrıları `AuthSession.repository()` içinde `http://127.0.0.1:8080` yedeğine gider; telefonun kendisidir ve Release ATS düz HTTP’yi keser. TestFlight bu haliyle Mac sunucusuna ulaşmaz.

`trycloudflare.com` adresi her `cloudflared` yeniden başlayınca değişir. Her değişiklikte yeni arşiv, TestFlight’ı durdurur. Adres çalışma anında okunmalıdır.

### Seçenekler

**A. Profilde gizli ayar.** `ProfileView` zaten `Sürüm 5.0.0 (5)` satırını gösterir (`CFBundleShortVersionString` + `CFBundleVersion`). Bu satıra 7 kez dokununca bir sayfa açılır: etkin adres, kaynağı, metin alanı, Kaydet, Temizle, `/health` dene. Elle yazılan değer `UserDefaults`’ta durur ve plist’ten önce gelir. Local şema `HOUSEHOLD_LOCAL` yedeğini korur; simülatör davranışı değişmez.

Tek kişi ve sahibiyle aynı odadaki iç beta için en kısa yol budur. Tünel düşünce sahip yeni `https://….trycloudflare.com` adresini yapıştırır. Başka testçi varsa herkese mesaj gerekir. Yeni derleme gerekmez.

**B. Sabit GitHub raw / Gist JSON.** Uygulama açılışta tek bir HTTPS adresinden `{ "apiBaseURL": "https://….trycloudflare.com" }` okur, son iyi adresi önbelleğe yazar. Sahip tünel yeniden başlayınca Gist’i günceller; yüklü betalar bir sonraki açılışta yeni adresi alır. `raw.githubusercontent.com` birkaç dakika önbelleğe alabilir. Gist herkese açıksa tünel adresi de açıktır. Gizli Gist, tokensiz raw ile okunamaz; uygulamaya GitHub token koymak bu iş için uygun değildir. Adresi ana dala commit etmek her yeniden başlatmada git geçmişine yazar; Gist bundan daha dar bir yüzeydir.

**C. Release xcconfig’e adresi gömmek.** `docs/v4.1-local-runbook.md` bunu Local şema için söyler. TestFlight’ta her tünel yeniden başlatması yeni arşiv ve dış testte yeni inceleme demektir. Bu beta için uygun değil.

**Öneri.** İç betada A yeter. İkinci bir testçi eklenince B, A’nın üstüne konur. Öncelik:

1. Elle yazılmış geçerli adres.
2. Son başarılı uzak JSON önbelleği.
3. Yeni uzak JSON (zaman aşımı kısa, arayüzü bekletmez; elle adres varken yönlendirme onu kullanmaya devam eder).
4. Info.plist `MealRoutineAPIBaseURL` (Local şema).
5. `HOUSEHOLD_LOCAL` için `http://localhost:8080`.
6. Hiçbiri yoksa bu betada CloudKit’e düşmek yerine “sunucu adresi yok” ve çevrimdışı household. Bu son madde mevcut `HouseholdSyncRouting` yorumuyla çelişir; uygulamadan önce aşağıdaki soru listesi cevaplanır.

Kabul kuralları: şema `https`, host dolu, kullanıcı bilgisi yok, yol ve sorgu atılır, sonda `/` yok. `http` yalnız `localhost` ve `127.0.0.1` için, yani Local şema. Release’e `NSAllowsArbitraryLoads` eklenmez. Quick tunnel sertifikası ATS’i karşılar. Tailscale’in düz `http://100.x:8080` adresi Local ATS ile çalışır; Release Info.plist’te yerel ağ istisnası yoktur, TestFlight telefonunda kesilir.

Deneme ucu: `GET /health` → `{ "ok": true }`. Kimlik istemez. `GET /ready` veritabanını da yoklar.

### Jetonlar adres değişince

Erişim jetonu host’a bağlı değildir. `server/src/tokens.ts` issuer `mealroutine`, audience `mealroutine-ios`, imza `JWT_SECRET` (HS256). Yenileme jetonu `mr1.` ile rasgele bir değerdir; Postgres’te özeti durur. Anahtar zinciri (`KeychainTokenStore`, servis `com.mealroutine.app.auth`) adresi saklamaz.

Aynı Mac, aynı Postgres ve aynı `JWT_SECRET` arkasında adres değişince oturum durur. Adres değişince anahtar zinciri silinmez. `APIClient`, `HouseholdLifecycleAPI` ve `NotificationSync.liveClient()` her çağrıda `MealRoutineConfig.apiBaseURL` okur. Yeni adres bir sonraki istekle kullanılır. Yeni host başka bir veritabanı veya başka bir sırsa `/v1/auth/me` veya refresh 401 döner; mevcut `sessionExpired` yolu oturumu kapatır. Ulaşılmayan host taşıma hatasıdır; oturumu düşürmez (`AuthSession.restore`).

`JWT_SECRET` değişince mevcut erişim jetonları geçersiz olur. Yenileme jetonu sırdan bağımsız olduğu için refresh yeni erişim jetonu üretebilir. Beta sırasında sır döndürülmez.

### Ev halkı eşitlemesi

`HouseholdSession.activeTransport()` her işlemde `HouseholdSyncRouting.makeTransport` çağırır. Adres varsa taşıma `HTTPHouseholdTransport` olur. Kuyruk SwiftData’da durur, host’a yazılmaz. Adres iki çağrı arasında değişirse bitmiş istek eski hosta gitmiş olabilir; sonraki boşaltma yeni hostu kullanır. Kuyruk adres değişiminde silinmez.

Bütün testçiler aynı tünele, yani aynı Mac Postgres’ine bağlanır. Biri eski tünelde, biri yenisinde kalırsa iki ayrı dünyadır. Elle adres ve önbellek bunu tek kaynakta tutmalıdır. Geçici boş adreste CloudKit’e düşmek aynı evin bir parçasını iCloud’a yazardı. Önbellekteki son iyi adres, uzak JSON başarısız olsa da HTTP’de kalır.

Test modu (`HouseholdTestMode`) sahte sunucudadır ve Apple hizmetlerini kapatır. TestFlight’ta test modu kapalı kalır; açıkken Mac sunucusu kullanılmaz.

## 3. Mac’te production sunucu

Sunucu `server/src/index.ts` ile `0.0.0.0:8080` dinler. Quick tunnel `http://localhost:8080` adresine bağlanır; 8080 yönlendiricide açılmaz. Postgres 5433’te yalnız localhost’tadır.

`NODE_ENV=production` iken `POST /v1/auth/dev` 404 döner (`server/src/app.ts` ve `authService.signInDev`). Local şemadaki “Yerel test girişi” bu uca gider ve production’da kaybolmalıdır. Beta telefonu bu ucu çağırmaz (`HOUSEHOLD_LOCAL` Release’te yoktur).

Apple doğrulaması `APPLE_BUNDLE_ID` audience’ıdır. `server/.env.example` doğru değeri taşır: `com.berkaydursun.mealroutine.app`. `server/src/config.ts` değişken boşsa `com.mealroutine.app` yazar. Bu yedek gerçek Apple jetonunu reddeder. Production `.env` değişkeni açıkça doğru bundle olmalıdır. Sonraki sunucu PR’si, production’da değer boşsa veya `com.mealroutine.app` ise açılışı durdurur.

`JWT_SECRET` en az 32 karakter, repoda olmayan rasgele bir metin. `assertRuntimeConfig` kısaysa süreci açmaz. `CORS_ORIGIN` iOS için boş kalır; `*` reddedilir. `SENTRY_DSN` boş kalabilir.

Postgres (konteyner yoksa):

```bash
docker run --name mealroutine-postgres \
  --restart unless-stopped \
  -e POSTGRES_USER=mealroutine \
  -e POSTGRES_PASSWORD=mealroutine \
  -e POSTGRES_DB=mealroutine \
  -p 5433:5432 \
  -d postgres:16
```

Konteyner varsa: `docker update --restart unless-stopped mealroutine-postgres`. Docker’ın oturum açınca başlaması kullanıcı ayarıdır. Şema: `cd server && npm run migrate`. `npm start` geliştirme içindir; launchd doğrudan `node` ve `tsx` kullanır ki bir kabuk profili gerekmesin. `server/package.json` `node` sürümünü `>=20` ister.

Örnek `~/Library/LaunchAgents/com.berkaydursun.mealroutine.api.plist` (yollar Mac’teki gerçek yollarla değişir; bu dosya repoya konmaz, içinde sır vardır):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.berkaydursun.mealroutine.api</string>
  <key>WorkingDirectory</key>
  <string>/ABSOLUTE/Meal-Routine/server</string>
  <key>ProgramArguments</key>
  <array>
    <string>/ABSOLUTE/node</string>
    <string>/ABSOLUTE/Meal-Routine/server/node_modules/tsx/dist/cli.mjs</string>
    <string>src/index.ts</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>NODE_ENV</key>
    <string>production</string>
    <key>HOME</key>
    <string>/Users/OWNER</string>
  </dict>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>ThrottleInterval</key>
  <integer>10</integer>
  <key>StandardOutPath</key>
  <string>/Users/OWNER/Library/Logs/mealroutine-api.log</string>
  <key>StandardErrorPath</key>
  <string>/Users/OWNER/Library/Logs/mealroutine-api.err.log</string>
</dict>
</plist>
```

`loadEnvFile` `server/.env` okur ve kabukta zaten duran değişkeni ezmez. `NODE_ENV` plist’te production olduğu için `.env` içindeki `development` onu geri almaz. Diğer anahtarlar `.env`’den gelir.

Tünel ajanı, API ayakta olduktan sonra:

```xml
<key>ProgramArguments</key>
<array>
  <string>/opt/homebrew/bin/cloudflared</string>
  <string>tunnel</string>
  <string>--url</string>
  <string>http://localhost:8080</string>
  <string>--no-autoupdate</string>
</array>
```

Aynı `RunAtLoad` / `KeepAlive`. stdout/stderr `~/Library/Logs/mealroutine-tunnel.log`. Yeni `https://….trycloudflare.com` satırı bu günlükte belirir; sahip onu gizli ayara veya Gist’e yazar. `launchctl bootstrap gui/$UID ~/Library/LaunchAgents/….plist`.

Uyku: prizdeki Mac için Enerji ayarında uyku kapatılır ve launchd API programının önüne `caffeinate -s` konabilir (`-s` sistemi prizde uyanık tutar). Kapak kapanınca birçok dizüstü yine uyur. Kapak açık, prizde, ekran kararabilir. `pmset -a disablesleep 1` ısı ve fan üretir; bu beta için önerilmez. Uyku, tüneli ve quick tunnel adresini düşürür.

Yedek: Postgres portu tünelin arkasında değildir. Günlük `pg_dump -h localhost -p 5433 -Fc -d mealroutine` çıktısı `~/Backups/mealroutine/` altında durur, 7 kopya tutulur, repoya girmez. Ayrı bir LaunchAgent yeter. `PGPASSWORD` plist’te yerel bir sırdır.

Kontrol: `curl -sS http://localhost:8080/health` ve `curl -sS http://localhost:8080/ready`. Production’da `POST /v1/auth/dev` 404 olmalıdır.

## 4. Sign in with Apple

İstemci yazılmış durumda.

- `AccountView` `SignInWithAppleButton` gösterir. İstek kapsamı ad ve e-posta. Tamamlama `AuthSession.completeApple`.
- Düğme `HouseholdTestLaunch.allowsAppleServices` true iken görünür. Bu, `HOUSEHOLD_LOCAL` olmayan Debug ve Release’te true’dur. Local şema ve test modu düğmeyi gizler.
- Kimlik jetonu `POST /v1/auth/apple` ile gider; ilk girişteki ad gövdeye yazılır. Sunucu jeton doğruladıktan sonra boşsa bu adı kullanır.
- Bağlama `POST /v1/auth/link`. Aynı e-posta `link_required` dönerse bekleyen Google jetonu varsa Apple girişinden sonra bağlanır. Google bu betada kapalı olduğundan bu kol çalışmaz.
- Çıkış, hesap silme ve yenileme vardır. Yenileme 30 gün, erişim 15 dakika (`config.ts` varsayılanları).

Sunucu doğrulaması yazılmış durumda. `createJwksVerifier` Apple JWKS `https://appleid.apple.com/auth/keys`, issuer `https://appleid.apple.com`, audience `config.appleBundleId`. Yerel iOS uygulaması için Services ID gerekmez; audience bundle’dır.

Entitlement dosyaları:

| Dosya | Kullanan | İçerik |
| --- | --- | --- |
| `MealRoutine/MealRoutine.entitlements` | Debug ve Release | Sign in with Apple `Default`, iCloud `iCloud.com.mealroutine.app`, CloudKit, `aps-environment` = `development`, App Group `group.com.mealroutine.app` |
| `MealRoutine/MealRoutine.Local.entitlements` | Debug-Local | Sign in with Apple `Default`, `aps-environment` = `development`. App Group yok. Belgelerdeki “boş entitlements” cümlesi bu dosyayla uyuşmuyor. |
| `ShareExtension/ShareExtension.entitlements` | Share Debug ve Release | Yalnız `group.com.mealroutine.app` |
| `ShareExtension/ShareExtension.Local.entitlements` | Share Debug-Local | Boş |

Release şeması `MealRoutine.xcscheme`: Run Debug, Archive Release. Takım her yapılandırmada `L99MZR5MXZ`. Bundle `com.berkaydursun.mealroutine.app`. Sürüm `5.0.0`, build `5`. Local şemanın Archive eylemi de Release’tir; arşiv yine Release entitlement’ını alır. Arşiv yine de **MealRoutine** şemasından alınır.

Kalan iş kullanıcı portalı ve Mac `.env`’idir. Uygulama kimliği `com.berkaydursun.mealroutine.app` üzerinde Sign in with Apple açıktır. İlk gerçek cihazda bir kez Apple ile giriş, adın saklanması, uygulamayı öldürüp açınca sessiz yenileme ve çıkış denenir. Private relay e-postası hesap ekranında “Gizli e-posta” olarak görünür.

`project.yml` hâlâ `PRODUCT_BUNDLE_IDENTIFIER = com.mealroutine.app` ve `bundleIdPrefix: com.mealroutine` yazar. Açılan proje `MealRoutine.xcodeproj` içindeki `com.berkaydursun.mealroutine.app` değeridir. XcodeGen bu spec ile çalıştırılırsa bundle geriye döner. Bu betada spec çalıştırılmaz.

## 5. APNs

İki ayrı bildirim yolu vardır.

`HouseholdNotifier` (`MealRoutine/Household/HouseholdSession.swift`) uzak push değildir. `UNUserNotificationCenter` ile bu telefonda yerel bildirim kurar. `HOUSEHOLD_LOCAL` derlemesinde gövde boştur. Release’te çalışır. Sunucu APNs’i partner cihazına gider; yerel yol oturumdaki hesabın etkinliklerini bu cihazda gösterir. İkisi birlikte çift bildirim üretebilir. Karar soru listesindedir.

Uzak kayıt yazılmış durumda.

- `MealRoutine/App/MealRoutineApp.swift` aygıt jetonunu hex’e çevirip `NotificationSync.registerToken` çağırır. Kayıt hatası uygulamayı düşürmez.
- `NotificationSync` `POST /v1/notifications/tokens` ve tercih uçlarını kullanır. Adres veya erişim jetonu yoksa yerel tercihte kalır.
- `UIBackgroundModes` → `remote-notification` (`MealRoutine/Info.plist`).
- Sunucu `server/src/notifications.ts`: `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_BUNDLE_ID` ve `APNS_KEY_P8` veya `APNS_KEY_PATH` birlikte yoksa gönderici `log` olur, Apple’a istek gitmez. Dördü de varsa `createApnsSender` HTTP/2 ile gider. `APNS_PRODUCTION=true` ise `https://api.push.apple.com`, değilse `https://api.sandbox.push.apple.com`. Konu başlığı `apns-topic` = `APNS_BUNDLE_ID`. JWT ES256, `kid` = Key ID, `iss` = Team ID. `.p8` süreç açılışında okunur.
- `server/.env.example` bu anahtarları henüz listelemez. `.gitignore` `server/.env` tutar, `*.p8` tutmaz.
- FCM göndericisi arayüz olarak durur ve istek atmaz.

TestFlight production APNs kullanır. Geliştirme kurulumu (Xcode Run, development profili) sandbox jetonu alır. İkisi karışınca Apple `BadDeviceToken` döner. Beta sunucusu `APNS_PRODUCTION=true` olur. Xcode’dan telefona development kurulumla aynı sunucuya push denemesi yapılmaz; o deneme ayrı bir sandbox süreç ister. Bu betada sunucu production’dır.

Entitlement çelişkisi: Debug ve Release aynı dosyada `aps-environment` = `development`. App Store / TestFlight dağıtım profili production bekler. Release için ayrı bir entitlement dosyası `production` taşır; Debug `development` kalır. Otomatik imza, dosyadaki değer profille çakışırsa arşivi reddeder.

`.p8` işlemi (kullanıcı Mac’i, sır sohbete yazılmaz):

- Dosya repo dışında, örneğin `~/.config/mealroutine/AuthKey_9SM8YS7B5H.p8`, mod `600`.
- `.env`: `APNS_KEY_ID=9SM8YS7B5H`, `APNS_TEAM_ID=L99MZR5MXZ`, `APNS_BUNDLE_ID=com.berkaydursun.mealroutine.app`, `APNS_KEY_PATH` mutlak yol, `APNS_PRODUCTION=true`.
- `APNS_KEY_P8` ile dosya içeriğini değişkene yapıştırmak da kodda vardır; yol tercih edilir, süreç listesinde daha az görünür.
- Sonraki PR `.gitignore`’a `*.p8` ve `AuthKey_*.p8` ekler. Dosya commit edilmez.

Gönderim boşluğu: `enqueue` hemen `dispatch` çağırır, `dueBatches` ise penceresi 2 dakikayı (`GROUP_WINDOW_MS`) doldurmuş kayıtları seçer. İkinci bir olay gelmezse kayıt `pending` kalır. `POST /v1/notifications/dispatch` kimlik ister ve dışarıdan cron için bir hesap jetonu gerektirir. Production süreç içinde yaklaşık 30 saniyede bir `dispatch` gerekir. Bu küçük sunucu işi PR3’tedir. Kiler anımsatıcıları bu kuyruğa girmez; onlar cihazdaki `UNUserNotificationCenter` kayıtlarıdır.

Push türleri: davet, haftalık plan, veto, yemek değişikliği, planın kesinleşmesi. Gövde yemek adı taşımaz.

## 6. App Store Connect

Sıra kullanıcıdadır. Hepsi 0 $.

1. developer.apple.com, takım `L99MZR5MXZ`.
   - App ID `com.berkaydursun.mealroutine.app`: Sign in with Apple, Push Notifications, App Groups.
   - App ID `com.berkaydursun.mealroutine.app.share`: App Groups.
   - Grup kimliği kodda `group.com.mealroutine.app`. Bundle önekiyle aynı değil; portalda bu kimlik oluşturulur ve iki App ID’ye eklenir. Yeniden adlandırmak paylaşım dosyalarını ve `RecipeCaptureStore.appGroupID` değerini değiştirir. Bu betada kimlik korunur.
   - iCloud kabı `iCloud.com.mealroutine.app` Release entitlement’ta duruyor. Soru listesi “kalsın” derse kap da açılır. “Kalksın” derse Release dosyasından çıkarılır ve kap açılmaz.
   - APNs anahtarı yeniden oluşturulmaz. Key ID `9SM8YS7B5H` yeter. `.p8` bir kez iner.
2. App Store Connect’te yeni iOS uygulaması. Ad MealRoutine, birincil dil Türkçe, bundle yukarıdaki App ID, SKU `mealroutine-ios`.
3. Gizlilik besin etiketleri, `MealRoutine/PrivacyInfo.xcprivacy` ve `docs/gizlilik-politikasi.md` ile aynı çizgide. İzleme yok, satış yok.
   - Ad: bağlı, uygulama işlevi.
   - E-posta: bağlı, uygulama işlevi (gizli aktarım dahil).
   - Ürün etkileşimi: bağlı, analitik. Profilde kapatılabilir.
   - Çökme verisi: bağlı, uygulama işlevi. Kapalı başlar; toplanabildiği için beyan edilir. Yığın izi gitmez.
   - Diğer kullanıcı içeriği: tarif, yemek hafızası, ev planı; bağlı, uygulama işlevi.
   - Aygıt kimliği: gizlilik manifestosunda yok. Sunucu APNs jetonunu `device_push_tokens` tablosunda tutar. Formda aygıt kimliği, bağlı, uygulama işlevi, izleme değil olarak işaretlenir. Manifestoyu aynı hizaya getirmek ayrı küçük bir PR olabilir.
   - Konum, reklam kimliği ve kişi listesi yok.
4. Dışa aktarma / şifreleme. Debug, Release ve Debug-Local `INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO` taşır. Uygulama standart HTTPS kullanır. Yükleme sorusu bu anahtarla atlanır. Connect hâlâ sorarsa cevap, muaf şifreleme (yalnızca HTTPS) olur. ERN belgesi gerekmez.
5. Beta inceleme bilgisi dış testçiden önce dolar. İç test inceleme istemez.
   - İletişim e-postası ve telefon.
   - Gizlilik politikası URL’si. `docs/gizlilik-politikasi.md` taslaktır; köşeli parantezdeki iletişim satırı dolar ve sayfa herkese açık bir URL’de durur (GitHub Pages 0 $). Uygulama içi yasal sözleşme olarak gösterilmez.
   - İnceleme notu: plan hesapsız da açılır; ev halkı ve hesap Sign in with Apple ister. Demo şifresi yoktur. İnceleyen kendi Apple kimliğini kullanır. Sunucu bu Mac’tedir; inceleme süresince tünel ve keşif adresi ayakta olmalıdır. Quick tunnel inceleme ağından düşerse dış inceleme başarısız olur. Bu yüzden ilk hedef iç testtir.
6. İç testçi: Connect kullanıcısı, en fazla 100 kişi, inceleme yok. İşleme bitince (genelde bir saat içinde) iç gruba açılır.
   Dış testçi: ilk derleme Beta App Review ister. İç kurulum oturmuşken açılır.
7. Arşiv ve yükleme, kullanıcının Mac’inde, Xcode.
   - Şema **MealRoutine**. Hedef Any iOS Device. Simülatör arşivi olmaz.
   - Product → Archive. Organizer’da sürüm 5.0.0, build 5 görünür. PlugIns içinde `MealRoutineShare.appex` aranır. Yoksa uzantı hedefini şemanın Archive eylemine eklemek gerekir; hedef bağımlılığı ve Embed Foundation Extensions normalde onu içeri alır.
   - Distribute App → App Store Connect → Upload. Otomatik imza, takım `L99MZR5MXZ`.
   - Sonraki yükleme `CURRENT_PROJECT_VERSION` artırır. `MARKETING_VERSION` kullanıcıya görünen sürüm değişince artar. Aynı build numarası ikinci kez yüklenmez.
8. İşlenen derlemede dışa aktarma eksik uyarısı plist anahtarıyla gelmemelidir. İç grupta TestFlight’ı aç, telefona kur, Apple ile giriş, `/health` adresinin tünel olduğunu gizli sayfadan doğrula.

## 7. Paylaşım uzantısı ve App Group

Release’te uzantı arşive girer.

- Hedef `MealRoutineShare`, ürün `MealRoutineShare.appex`, bundle `com.berkaydursun.mealroutine.app.share`.
- Uygulama hedefi onu Embed Foundation Extensions ile gömer ve target dependency olarak bağlar.
- Release ve Debug entitlement: `group.com.mealroutine.app`.
- Debug-Local entitlement boştur. Local şemada paylaşım sayfası App Group’suz kalır; tarif uygulama içinden eklenir. TestFlight Local şema değildir.
- `ShareViewController` URL, metin ve görüntüyü App Group dosyasına yazar ve kapanır. Sayfa indirimez, API çağırmaz. Ana uygulama bir sonraki açılışta SwiftData’ya kopyalar (`RecipeCaptureStore`, `group.com.mealroutine.app`).
- Uzantı ailesi yalnız iPhone (`TARGETED_DEVICE_FAMILY = 1`). Uygulama iPhone ve iPad’dir. iPad paylaşım sayfasında uzantı görünmez. iPhone betası için yeter.
- Uzantının kendi gizlilik manifestosu yoktur. App Group dosyası kullanır.

Portal kaydı (bölüm 6) yapılmadan imza, App Group olmayan bir profil üretebilir ve paylaşım sayfası dosyayı yazamaz. Ana uygulama onsuz da açılır.

## 8. Sıralı işler

Her adım bir öncekinin üstüne biner. Maliyet satırı 0 $; alan adı ancak adlandırılmış tünele geçilirse ve elde alan adı yoksa ortaya çıkar. Bu planda adlandırılmış tünel şart değildir.

| Sıra | İş | Sahip | Kod |
| --- | --- | --- | --- |
| 0 | Bu belge | Ajan | Yalnız `docs/testflight-plan.md` |
| 1 | Çalışırken adres: 7 dokunuş, https kuralı, `/health`, son iyi adres önbelleği. Boş Google istemcisinde geliştirici metnini gizle. Uzak JSON sabiti boş bırakılır; kullanıcı Gist ham URL’sini verince tek satır dolar. CloudKit düşüşü soru 1 cevaplanmadan değişmez. | Ajan | İstemci |
| 2 | Release entitlement `aps-environment` = `production`. Debug `development` kalır. Local dosyalara dokunulmaz. | Ajan | Entitlement |
| 3 | Production’da yanlış `APPLE_BUNDLE_ID` ile açılmayı reddet. `.env.example` içine boş `APNS_*` yorumları. `.gitignore` `*.p8`. Süreç içi `dispatch` (yaklaşık 30 sn) ki 2 dakikalık pencere ikinci olayı beklemesin. | Ajan | Sunucu |
| 4 | Docker `--restart unless-stopped`, `.env` production, `APPLE_BUNDLE_ID`, `JWT_SECRET`, APNs yolu ve `APNS_PRODUCTION=true`. `.p8` repo dışında. launchd API + cloudflared. Uyku ve `pg_dump`. Gist veya 7 dokunuşa yeni tünel adresi. | Kullanıcı Mac | Yok |
| 5 | Portal: App ID yetkileri, App Group, isteğe göre iCloud kabı. Connect kaydı, besin etiketi, şifreleme cevabı. MealRoutine şemasıyla arşiv ve yükleme. İç testçi. | Kullanıcı web + Mac | Yok |
| 6 | Gizlilik taslağındaki iletişim satırı ve herkese açık URL. Dış testçi ve Beta App Review ancak tünel inceleme boyunca ayaktaysa. | Kullanıcı web | Yok |
| 7 | Google OAuth iOS istemcisi, bundle `com.berkaydursun.mealroutine.app`, Release `GOOGLE_IOS_CLIENT_ID` ve ters şema, `GOOGLE_CLIENT_ID_IOS`. | Sonra | Bu betada yok |

PR1’den önce soru 1 ve 3 cevaplanırsa keşif ve CloudKit aynı PR’da biter. Cevap gelmezse PR1 yalnız elle adresi ekler; adres yokken bugünkü CloudKit düşüşü durur. TestFlight telefonu adresi bir kez yapıştırmadan Mac’e gitmez.

### Quick tunnel riski

`cloudflared tunnel --url` quick tunnel’dir. Ücreti yoktur. Adres her yeniden başlatmada değişir. Hizmet düzeyi yoktur; Cloudflare tüneli haber vermeden kesebilir. Hız sınırları belgelenmemiştir ve üretim trafiği için tasarlanmamıştır. Cloudflare’in kendi tarifi, quick tunnel’i kalıcı barındırma olarak kullanmamaktır. `trycloudflare.com` adresi herkese açıktır: gören kişi API’ye ulaşır. Veri uçları jeton ister, `/health` açık, auth uçları dakikada 30 istekle sınırlıdır (`RATE_LIMIT_AUTH_MAX`). Adresi herkese açık Gist’e yazmak bu yüzeyi büyütür. Apple inceleme ağı adrese erişemeyebilir.

Adlandırılmış tünel (`cloudflared tunnel create`, ingress `http://localhost:8080`) Cloudflare Zero Trust ücretsiz plandadır ve adres yeniden başlatmada durur. Bunun için Cloudflare DNS’te bir alan adı gerekir. Alan adı zaten varsa ek maliyet 0 $. Yeni alan adı bu planın 0 $ sınırının dışındadır. İç beta quick tunnel ile başlar. Dış inceleme quick tunnel’de takılırsa adlandırılmış tünel, eldeki bir alan adıyla ikinci adımdır.

Tailscale `100.x` adresi sahibin kendi telefonu için `docs/v4.1-local-runbook.md` içinde durur. Release ATS düz HTTP’yi keser. Her testçiye Tailscale kurdurmak bu betanın yolu değildir.

## Dur ve sor

Aşağıdakiler mevcut yapıyla çelişir veya bir kimliği değiştirir. Cevap gelmeden o parçanın kodu yazılmaz.

1. Adres yokken household CloudKit’e düşüyor (`HouseholdSyncRouting`). Bu betada adres yoksa çevrimdışı kalınsın mı? Öneri: evet, CloudKit’e düşülmesin. Son iyi HTTP adresi duruyorsa o kullanılır.
2. Release entitlement’taki iCloud / CloudKit (`iCloud.com.mealroutine.app`) kalsın mı? Öneri: bu beta Mac sunucusuna gidecekse Release dosyasından çıksın. Böylece imza o kabı istemez. `CloudKitHouseholdSync.swift` silinmez; Release yetkisinden çıkar.
3. Kaç testçi var? Yalnız sahip ise 7 dokunuş yeter, Gist açılmaz. Birden fazlaysa herkese açık Gist tünel adresini yayınlar; veri uçları jetonlu kalır.
4. Görünen sürüm `5.0.0` (build `5`). Bu dalda V5.1 kiler var. TestFlight etiketi `5.0.0` kalsın mı, `5.1.0` mı olsun? Build 5 ilk yüklemede kullanılabilir; sonraki yükleme build’i artırır.
5. `project.yml` bundle’ı `com.mealroutine.app`. Xcode projesi `com.berkaydursun.mealroutine.app`. Öneri: proje esas alınır, XcodeGen çalıştırılmaz. Onaylanırsa spec ayrı bir temizlik PR’sinde düzeltilir, bu betada değil.
6. APNs açılınca `HouseholdNotifier` yerel ev bildirimi de çalsın mı? Öneri: uzak push gelen olayda yerel kopya susturulur; kiler anımsatıcıları yerel kalır.

Bunların dışında Local entitlement dosyasının belgelerden farklı olarak Sign in with Apple ve `aps-environment` = `development` taşıması bilinir. TestFlight Local şema kullanmadığı için bu beta o dosyayı değiştirmez.
