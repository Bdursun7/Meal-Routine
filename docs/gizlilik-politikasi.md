# Gizlilik politikası (taslak)

Bu metin MealRoutine için App Store öncesi taslaktır. Yayınlamadan önce köşeli parantezli iletişim satırını kendi adresinle değiştir. Uygulama bu metni henüz uygulama içinde yasal sözleşme olarak göstermez; hesap ekranındaki kısa açıklama onun özetidir.

Son güncelleme: 6 Ekim 2026.

## Kimden

MealRoutine, yemek planı ve ev içi ortak plan için çalışan bir iOS uygulamasıdır. Sorumlu: **[sahibin adı ve e-posta adresi]**.

## Ne toplanır

Hesap açmadan plan, puanlar, market listesi ve kaydettiğin tarifler telefonda kalır.

Apple veya Google ile giriş yaptığında sunucu şunları saklar:

- Ad ve görünen ad
- Sağlayıcının verdiği e-posta, varsa gizli aktarım (Hide My Email) işareti
- Kişisel tarifler, yemek hafızası, favoriler, pişirme geçmişi, geri bildirim ve plan tercihleri
- Bildirim tercihleri ve cihazın anlık bildirim jetonu
- Üye olduğun ev halkının kimliği, adı ve rolün

Ortak evde partnerin gördüğü veri ortak plandır: haftalık plan, yemek tepkileri, market işaretleri ve planlama için gereken kısa sinyaller. Partnerinin kişisel tarifleri, yemek hafızası ve giriş bilgileri senin dışa aktarımına girmez. Senin kişisel hafızan da ona kopyalanmaz.

Konum istenmez. Reklam kimliği toplanmaz. Veri satılmaz ve reklam ağlarıyla paylaşılmaz.

## Jetonlar

Erişim ve yenileme jetonları yalnızca bu cihazın anahtar zincirinde durur (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`). Kullanıcı varsayılanlarına yazılmaz. Sunucu ve uygulama günlükleri jeton, e-posta ve ad alanlarını maskeler.

## Saklama ve silme

Hesap ekranından **Verilerimi indir** kendi verinin JSON kopyasını verir. Ortak evin içeriği bu dosyada yoktur; yalnızca evin kimliği, adı ve rolün vardır.

**Hesabımı sil** onayından sonra sunucu:

- bütün yenileme jetonlarını ve cihaz jetonlarını geçersiz kılar
- kişisel tarifleri, yemek hafızasını, favorileri, geçmişi, tercihleri ve giriş kimliklerini siler
- adını boşaltır ve hesabı kapatır

Ev halkı: senden başka üye varsa ev ona kalır ve sahiplik devredilir. Son üyeysen ev kapatılır. Telefondaki yerel plan, bu silmeyle kendiliğinden gitmez; onu ayrı yerel sıfırlama kaldırır.

## İletişim

Silme, dışa aktarma veya bu taslak için: **[sahibin adı ve e-posta adresi]**.
