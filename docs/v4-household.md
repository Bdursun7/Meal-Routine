# MealRoutine V4 — Ev halkı

V4, iki kişinin aynı haftanın yemeklerine birlikte karar vermesini sağlar. Sohbet, sosyal akış veya aile yönetimi değildir. Ev halkı en fazla **2** kişidir.

## Mimari

**Sign in with Apple + CloudKit.** Ayrı bir ücretli backend yok.

```text
SwiftUI
  → HouseholdSession
  → SwiftData (HouseholdCacheBox, yerel önbellek)
  → CloudKit
       özel bölge: MealRoutineHousehold / HouseholdBoard
       CKShare: ikinci üye aynı kaydı okur ve yazar
       public lookup: davet kodu → share URL
```

Sunucu çakışmada kazanır. İki kişi farklı akşamları değiştirdiyse, her yemeğin kendi revizyonu birleşir. Aynı yemeği ikisi de değiştirdiyse sunucudaki satır kalır ve ekran yenilenir.

Kişisel yemek hafızası (`MealMemory`) cihazda kalır. Ev halkına yalnızca planlama için gereken kısa sinyaller gider: sevdim, olur, bir daha asla, favori, pişirme sayısı, sevmediğin malzeme kimlikleri. Bu bir kopyalama veya taşıma değildir.

Container: `iCloud.com.mealroutine.app`.

## Tek başına ve ev halkı

Ev halkı yokken Bu Hafta, önceki sürümdeki kişisel planla çalışır. Giriş zorunlu değildir.

Ev halkı kurulunca Bu Hafta ortak plana bakar. Plan henüz yoksa kişisel hafta ortak planmış gibi gösterilmez; “Ortak planı kur” boş durumu çıkar. Market listesi ortak planın akşamlarından üretilir. Biri bir malzemeyi işaretleyince revizyon diğer telefona gider.

## Davet

1. Ev sahibi Apple ile girer, ev halkını adlandırır.
2. **Partnerini davet et** altı haneli kod ve `mealroutine://household/join?code=XXXXXX` bağlantısı üretir.
3. Kod, CloudKit public veritabanındaki `HouseholdInviteLookup` kaydıdır. Bağlantı, evin `CKShare` adresini taşır.
4. Partner kendi Apple hesabıyla kodu veya bağlantıyı açar. Ev doluysa (2), süresi dolduysa veya davet geri alındıysa katılım olmaz.
5. V4’te bir kişi tek ev halkındadır.

iCloud hesabı yoksa kod telefonda durur; paylaşım bağlantısı hesap açılınca yazılır.

## Veto ve Bir daha asla

| | Bir daha asla | Veto |
| --- | --- | --- |
| Ne | Kişisel, kalıcı hafıza | Yalnızca bu haftanın ortak planı |
| Nerede durur | `MealMemory.neverAgain` | `MealReaction.veto` |
| Etki | Önerilerden tamamen çıkar | Bu hafta o yemeği durdurur, “Karar gerekiyor” açar |

Veto, Bir daha asla yazmaz. Bu haftanın veto ettiği tarif, geçmişte ikisi de sevmiş olsa bile bu planın önerilerinden çıkar.

Tepkiler: İstiyorum, Olur, Bu hafta olmaz. Çakışma gizlenmez.

## Öneri sırası

1. Bir daha asla
2. Bu haftanın ev veto’su
3. Güçlü kişisel kaçınma (sevmediğin malzeme veya tekrar tekrar değiştirilen yemek)
4. Ev uyumu
5. Kişisel hafıza
6. Ev hafızası (birlikte pişirme, ortak beğeni, eski veto)
7. Çeşit
8. Keşif

Yerine koyma: İkiniz de seversiniz, Daha hızlı, Bir favori kullan, Bundan farklı, Tavuksuz, Mantarsız, Bizi şaşırt.

## Tarifler

Kişisel tarif ortak plana girebilir. Karşı taraf başlığı ve planlama alanlarını görür. Tarif, eşin kişisel koleksiyonuna kopyalanmaz; sahiplik `ownerUserId` alanında kalır.

## Bildirim

Yalnızca şunlar: plan incelemesi, veto, yerine koyma, planın netleşmesi. İstiyorum, Olur ve market işareti bildirim açmaz. İşlemi yapan kişiye bildirim gitmez.

## Apple portal

Xcode’da MealRoutine hedefine şunlar eklenmeli (entitlements dosyası bunları ister):

1. Sign in with Apple
2. iCloud → CloudKit, container `iCloud.com.mealroutine.app`
3. Push Notifications (development)
4. Background Modes → Remote notifications

İki hesapla denemek: iki simülatör veya cihaz, ikisi de iCloud ve Apple kimliğiyle girişli. Ev sahibi davet eder, partner kodu Profil → Birlikte planla altına yapıştırır. CloudKit şeması ilk çalıştırmada `HouseholdBoard` ve `HouseholdInviteLookup` kayıt türlerini geliştirme ortamında oluşturur; production’a ayrıca taşımak gerekir.

Abonelik, kiler, bütçe ve web istemcisi bu sürümde yoktur.

## Test modu

Ücretli Apple Developer hesabı olmadan ev halkını **tek simülatörde** veya ücretsiz kişisel ekiple denemek için. Test modu açıkken Sign in with Apple, CloudKit ve push çağrılmaz. Aynı `HouseholdSyncTransport` soyutlamasının sahte uygulaması (`FakeHouseholdBackend`) panoyu bellekte tutar; SwiftData yalnızca bu telefonun önbelleğidir.

Açmak:

1. Profil → Birlikte planla → **Test modu**
2. **Test olarak gir** (Apple kimliği yok)
3. Ev halkı kur, **Partnerini davet et** (kod ve `mealroutine://` bağlantısı görünür)
4. **Test Partner katılsın**
5. Ortak haftayı kur. Bu Hafta kartında ve ev ekranında Test Partner adına İstiyorum / Olur / Bu hafta olmaz denir. Veto **Karar gerekiyor** açar. **Partner yerine koysun** bu haftanın vetosunu eleyen bir yemek seçer. Market’te **Test Partner işaretlesin** ortak işareti yazar. Kararlar listesi ve uygulama içi bildirim şeridi aynı telefonda durur.

**Test verisini sıfırla** test evini, partneri ve bildirim günlüğünü siler. Test modu kapalıyken gerçek CloudKit yolu değişmez. Tek başına plan da değişmez.

UI testi `-HouseholdTestMode` ile açılır.

### Ücretsiz imza

`MealRoutine Local` şeması `Debug-Local` derlemesini kullanır. Ayarlar `Config/Debug-Local.xcconfig` içindedir.

| | Debug / Release | Debug-Local |
| --- | --- | --- |
| Entitlements | `MealRoutine.entitlements` (Apple ile giriş, iCloud, Push, App Group) | `MealRoutine.Local.entitlements` (boş) |
| Share extension | App Group | boş entitlements |
| Info.plist | remote-notification | `Info-Local.plist`, arka plan bildirimi yok |
| Swift | `DEBUG` | `DEBUG HOUSEHOLD_LOCAL` |

Simülatör: şemayı **MealRoutine Local** seç, bir iOS 18 simülatörü seç, çalıştır. Ücretli takım gerekmez. Ücretsiz kişisel ekipte de aynı şema imzalanır; Sign in with Apple, iCloud ve Push bu derlemede yoktur. Paylaşım uzantısının App Group’u da bu şemada yoktur; tarif ekleme uygulama içinden sürer.

Test modu şunları **kanıtlamaz**: iki cihaz arasında gerçek CloudKit eşitlemesi, `CKShare`, public davet kaydı, sessiz push veya production şeması. Onlar için ücretli hesap ve normal **MealRoutine** şeması gerekir.
