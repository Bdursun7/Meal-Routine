# Özgün Türkçe akşam tarifleri

UniTools kataloğu duruyor. Yanına MealRoutine’un yazdığı akşam paketi eklendi. UniTools satırları silinmedi, değiştirilmedi ve CC BY-SA atıfları yerinde.

## Sayı

- UniTools: 125 tarif (`source.provider` = `unitools`)
- Özgün paket: 100 tarif (`source.provider` = `mealroutine`)
- Katalog toplamı: 225
- `curation.originalPack.id`: `mealroutine-tr-aksam-v1`

## Metin

Başlık, malzeme ve adımlar bu paket için yazıldı. Tarif sitelerinden, kitaplardan veya ticari sayfalardan metin ya da fotoğraf alınmadı. İngilizce alan da özgün metindir; UniTools satırlarındaki gibi bir kaynak çevirisi değildir.

## Atlanan tekrarlar

Katalogda zaten duran UniTools yemekleri yeniden eklenmedi: Menemen, Mercimek çorbası, İskender kebap, Lahmacun, Mantı. Lübnan kibbe satırı arayüzde “Çiğ köfte” diye durduğu için ayrı bir çiğ köfte açılmadı. Yakın görünenler ayrı tabaktır: yeşil mercimek çorbası, etli ve zeytinyağlı yaprak sarması, ev usulü tavuk döner (İskender sosu yok).

## Fotoğraf

Özgün tariflerde `photo` yok. Uygulamadaki çatal-bıçak yer tutucusu kalır. UniTools fotoğrafları ve yazar/lisans satırları olduğu gibi durur.

## Seed

`schemaVersion` 1 olarak kaldı. SwiftData kapısı dosya baytlarının parmak izidir (`schemaVersion` + FNV-1a). Paket eklenince bayt değişir, bir sonraki açılış kataloğu yeniden alır. Özgün satırlar `MealRoutine original` lisansını taşır; detay ekranı UniTools cümlesini yalnız `unitools` sağlayıcısında gösterir.
