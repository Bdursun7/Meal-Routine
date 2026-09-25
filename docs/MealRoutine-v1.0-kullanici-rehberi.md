# MealRoutine — Kullanıcı Rehberi (v1.0)

Bu rehber, uygulamayı telefonunda kullanan sen içindir. Nerede neye basacağını, ekranda ne göreceğini ve bir işlemden sonra başka nelerin değişeceğini anlatır.

---

## Bu uygulama ne yapar

MealRoutine, akşam yemeklerini haftalık planlayan kişisel bir yardımcıdır. Tarifler ve planın telefonunda kalır; hesap açmazsın, buluta bağlanmaz. Arayüz Türkçedir. Kurulumda evini, akşam sayını, süre sınırını ve sevmediğin malzemeleri söylersin; uygulama buna göre haftanı doldurur. Pişirdikçe verdiğin puanlar sonraki haftaların seçimini şekillendirir.

---

## İlk açılış (onboarding)

İlk açılışta tarif kataloğu yüklenir (“Tarifler yükleniyor…”). Ardından kurulum ekranları gelir. Geri ile bir önceki adıma dönebilirsin; Ev’den itibaren üstte 1/4 … 4/4 ilerleme çubuğu görünür.

### Welcome

Başlık: **Haftan, önceden planlı.** Altında akşam kararını kısalttığı, tariflerin telefonda durduğu ve hesabın gerekmediği yazılır. Üç madde özetler: haftada en fazla 5 akşam; tek yemeği Değiştir ile değiştirebilirsin (tüm hafta silinmez); pişirme + puanlar sonraki haftaları etkiler, market plandan birleşir. Alttaki **Kuruluma başla** ile devam edersin.

### Slogan

Uygulama ikonu ve sabit metin: *Diğer uygulamalar neler pişirebileceğini gösterir. MealRoutine ise gerçekten ne pişirmek istediğini öğrenir.* CTA: **Devam**.

### Ev

Soru: kaç kişisiniz, haftada kaç akşam, en fazla kaç dakika?

- **Ev halkı:** 1–8 kişi (stepper).
- **Akşam sayısı:** 1–5 (ör. “3 akşam” chip’leri).
- **En fazla pişirme:** 30 / 45 / 60 / 90 dakika; varsayılan **60**.

**Devam** ile sonraki adıma geçersin.

### Sevmediğin malzemeler

En sık geçen malzemeler chip olarak listelenir. İşaretlediklerin bu haftanın seçimine girmez. Seçmeden de **Devam** edebilirsin. **Yumurta** chip’i yumurta ile ilgili tüm eşleşmeleri kapsar (tek yumurta / çoğul ayrımı seni ilgilendirmez).

### Tat (isteğe bağlı)

En fazla 8 tarif gösterilir. Her biri için **Sevdim** / **İdare eder** / **Bir daha asla** seçebilirsin; hepsini işaretlemek zorunda değilsin. **Devam** veya **Atla** ile özet ekranına geçersin.

### Özet → Haftamı oluştur

Ev, sevmediğin malzemeler ve tat tercihlerine bir bakış; her satırda **Düzenle** ile ilgili adıma dönüp düzeltirsin. Alttaki **Haftamı oluştur** basınca:

1. Tercihlerin kaydedilir.
2. İlk haftanın akşamları oluşturulur.
3. Market listesi bu plana göre doldurulur.
4. Kurulum biter; altta dört sekme açılır.

Plan kurulamazsa (ör. süre çok kısıtlı veya çok fazla malzeme dışlandıysa) ekranda uyarı görürsün; süre sınırını yükseltmek veya dislikes’ı azaltmak yeni tarifler açar.

---

## Dört sekme özeti

- **Bu Hafta** — Bu Pazartesi’den başlayan haftanın akşam planı; pişirme ve Değiştir buradan.
- **Tarifler** — Katalogda ara, filtrele, favorile; tarif detayına bak (pişirme çubuğu yok).
- **Market** — Haftanın malzemeleri birleşik listede; işaretle, ara, elle ekle.
- **Profil** — Ev ayarları, geçmiş / sevilen / asla, görünüm, gizlilik, yerel sıfırlama.

---

## Bu Hafta

Sekmeyi açtığında uygulama o haftanın planını kontrol eder. Plan yoksa ve kurulum bitmişse (ör. yeni Pazartesi) hafta otomatik kurulur; market de yenilenir. Üstte **Haftalık ilerleme** (kaç yemek pişirildi), öne çıkan akşam kartı ve **Haftanın akşamları** listesi vardır. İlerleme kartından **Market listesi** ile Market sekmesine atlayabilirsin.

### Gün kartları / planlı yemekler

Her akşam kendi kartında: gün adı (Pazartesi…), tarih (“Bugün” veya kısa tarih), tarif adı, süre ve kişilik. Pişirilmişse yeşil onay ve “Pişti” görünür. Kartın tarif alanına veya öne çıkan karttaki **Tarifi aç**a basınca tarif detayı açılır.

### Tarif detayı (Bu Hafta’dan)

Fotoğraf, özet, süre / kişilik / zorluk, porsiyon stepper’ı, malzemeler (işaretlenebilir) ve adımlar. Üstte kalp ile favoriye ekleyebilirsin (pişirmeden de). **Önemli:** Altındaki **Bunu pişirdim** çubuğu yalnızca Bu Hafta’dan açılan, bu haftaya ait bir akşamda görünür. Tarifler veya Profil geçmişinden aynı tarifi açarsan bu çubuk yoktur.

### Değiştir

Karttaki **Değiştir** yalnızca o akşamı değiştirir; diğer günler aynı kalır. Açılan sayfada “Bunun yerine ne istersin?” ve filtre chip’leri vardır (daha hızlı, farklı, tavuksuz, vejetaryen, sevdiğin, sürpriz vb.). Bir alternatif seçince o akşamın tarifi değişir, pişirme durumu sıfırlanır, market listesi yeni malzemelere göre yeniden kurulur. Uygun alternatif yoksa uyarı görürsün.

### Haftayı yeniden kur

Liste boşsa **Planı yeniden kur** görünür. Profil’de de **Bu haftayı yeniden kur** vardır. Her ikisi de mevcut haftayı silip tercihlerinle yeni bir plan üretir; market yeniden oluşur. Eski haftadaki yemekler “geçmişte görüldü” bilgisini taşır, böylece aynı tarifler hemen tekrar peş peşe gelmez.

### Porsiyon / Porsiyonu kaydet

Detayda **Porsiyon** bölümünde stepper ile kişilik ayarlarsın. Bu Hafta’dan açtıysan etiket genelde “Bu akşam: N kişi”dir. **Porsiyonu kaydet** basınca:

- Yalnızca o akşamın kişiliği güncellenir (ev halkı sayısı değişmez).
- Malzeme miktarları yeni kişiliğe göre ölçeklenir.
- Market listesindeki ilgili satırlar güncellenir.
- Miktar artınca daha önce “tamam” sayılan bazı işaretler düşebilir (artık o miktarı karşılamıyorsa).

### Bunu pişirdim / Sevdim / İdare eder / Bir daha asla

Alt çubukta **Bunu pişirdim** (pişmişse **Pişirildi**, tekrar basılmaz). Basınca soru: **Bu yemek nasıldı?** Seçenekler: **Sevdim**, **İdare eder**, **Bir daha asla**. **Vazgeç** dersen ne pişirme ne puan kaydedilir.

Kayıt sonrası:

- O akşam “pişti” olur; haftalık ilerleme artar.
- Puan sonraki hafta önerilerini etkiler (Sevdim güçlendirir; Bir daha asla bir daha önerilmez).
- Pişirme, **o planlı akşama** bağlıdır. Aynı tarif gelecek hafta yeniden plana girerse “Bunu pişirdim” yine aktif olur; geçen hafta pişirmiş olman yeni haftadaki düğmeyi kapatmaz.

Mevcut puan varsa detayda görürsün; **Puanı değiştir** ile yeniden seçebilirsin.

### Market’e yan etkiler

Plan, Değiştir, porsiyon kaydı veya (Bu Hafta detayından) malzeme işaretleri değişince Market listesi yeniden hesaplanır: miktarlar birleşir, işaretler güncellenir, kısmi “kaldı” miktarları görünebilir. Elle eklediğin satırlar mümkün olduğunca korunur.

---

## Tarifler

Tüm katalog burada. Arama kutusu ile isim, ülke veya etiketlere bakarsın. Filtreler: kategori (tavuk, et, balık, vejetaryen, makarna, pilav, hızlı, fırın…), süre (herhangi / ≤30 / 45 / 60 / 90 dk), yalnızca favoriler. Kalp ile Sevdiklerime ekler veya çıkarırsın.

Bir tarife basınca aynı detay ekranı açılır — porsiyon, malzemeler, adımlar. **Buradan “Bunu pişirdim” çubuğu gelmez.** Malzeme kutularını işaretleyebilirsin; bu işaretler **yalnızca tarif ekranına** aittir ve Market listesini **etkilemez**. Market’in güncellenmesi için işaretin Bu Hafta’daki planlı bir akşamdan gelmesi gerekir.

Porsiyonu buradan kaydedersen ev halkı sayısını ve açık haftadaki akşamların kişiliğini birlikte güncelleyebilir; Market buna göre yeniden kurulur (detaydaki açıklama satırı bunu söyler).

---

## Market

Haftanın planlı akşamlarından gelen malzemeler tek listede birleşir. Bölümler kabaca: sebze ve meyve, protein, süt ve yumurta, kiler, baharat ve soslar, diğer. Alınanlar ayrı grupta toplanır.

- **Malzeme ara:** İsim veya reyon başlığıyla süz. Eşleşme yoksa boş durum (ör. “Sonuç yok”) görürsün.
- **İşaretle:** Satırı tikleyince alındı sayılır. Aynı malzeme birden fazla yemekten geliyorsa miktarlar birleşir; birimde çakışma varsa satırlar ayrı kalabilir.
- **Elle ekle:** Listede olmayan bir şeyi (birim seçerek) ekleyebilir, silebilir, miktarını düzenleyebilirsin.
- **Birim birleştirme:** Gram/kg veya ml/l gibi aynı ailedeki birimler toplanır; karışık birimler ayrı satır olabilir.
- **Porsiyon etkisi:** Bu Hafta’da kişilik artınca Market miktarları artar; bazı işaretler düşebilir.

Liste, hafta planı değiştikçe (yeni hafta, Değiştir, porsiyon, ilgili malzeme işaretleri) yeniden kurulur. Plan yoksa veya kurulum bitmemişse liste boş kalabilir.

---

## Profil

### Ev ve tercihler

Ev halkı, akşam sayısı, pişirme süresi burada da ayarlanır. **Porsiyonu kaydet** ile tercihleri yazar; **Bu haftayı yeniden kur** ile mevcut haftayı tercihlerinle baştan üretir. Sevmediğin malzemeleri görür, **Kurulumu tekrar aç** ile onboarding’e dönebilirsin.

### Geçmiş / sevilen / asla

Pişirme geçmişi (tarih + puan), Sevdiklerim ve Bir daha asla listeleri burada. Bu listelerden tarif açınca pişirme çubuğu yoktur.

### Görünüm

**Sistem / Açık / Koyu** — telefonunun veya senin seçtiğin tema.

### Gizlilik

Hesap ve bulut yok; konum istenmez; fotoğraflar gerekirse indirilip telefonda önbelleğe alınır; kullanım kayıtları yerelde kalır. Sıfırlamanın kapsamı da burada özetlenir.

### Yerel veriyi sıfırla

Hafta planın, market listen, pişirme puanların, favorilerin ve kurulum tercihlerin silinir; uygulama ilk kurulum gibi davranır. **Tarif kataloğu telefonunda kalır** — tarifleri yeniden indirmene gerek yoktur; sadece senin planın ve geri bildirimlerin temizlenir.

### Hakkında

Kaynak atıfı, sürüm bilgisi ve fotoğraf notları.

---

## Yeni hafta nasıl oluşur (Pazartesi)

Bu bölüm özellikle önemlidir.

**Haftalar Pazartesi başlar.** Takvim yeni bir Pazartesi’ye geçtiğinde ve o hafta için henüz plan yoksa — kurulum daha önce tamamlanmışsa — uygulama haftayı **kendiliğinden** oluşturur. Senin Pazartesi sabahı ekstra bir düğmeye basman gerekmez; uygulamayı açtığında veya Bu Hafta ekranı göründüğünde kontrol yapılır ve gerekirse yeni plan yazılır.

Yeni hafta şöyle kurulur:

1. Tercihlerin (ev halkı, akşam sayısı, süre, sevmediğin malzemeler) kullanılır.
2. Son günlerdeki pişirme / plan geçmişi ve verdiğin puanlar dikkate alınır (yaklaşık son üç haftalık pencere).
3. Çeşitlilik için aynı mutfak, benzer protein veya aynı tariflerin peş peşe gelmesi azaltılır.
4. Hepsi **telefonda**, sabit kurallarla yapılır; bulut yapay zekâ veya internet planı yoktur.

Eski haftanın yemekleri “görüldü” diye kayda geçer, sonra eski plan kaldırılır; Market listesi **yeni haftaya** göre baştan kurulur. Elle **Planı yeniden kur** / **Bu haftayı yeniden kur** aynı yolu kullanır (mevcut haftayı silip yenisini üretir).

Aynı tarif yeni haftada yeniden plana girerse **Bunu pişirdim** yine basılabilir — pişirme her planlı akşam için ayrıdır.

---

## Ne neyi etkiler

| Sen ne yapınca | Ne olur |
|----------------|---------|
| Onboarding’de Sevdim / İdare / Asla | Sonraki hafta seçiminde ağırlık (Asla = önerilmez) |
| Sevmediğin malzeme işaretlemek | O malzemeli tarifler plana girmez |
| Haftamı oluştur / otomatik Pazartesi / yeniden kur | Yeni akşam planı + Market yeniden |
| Değiştir | Yalnız o akşam değişir; Market güncellenir |
| Porsiyonu kaydet (Bu Hafta akşamı) | O akşamın miktarları + Market; gerekirse işaretler düşer |
| Porsiyonu kaydet (Tarifler / ev halkı) | Ev halkı + açık haftanın akşamları + Market |
| Bunu pişirdim + puan | O akşam pişti; puan gelecek haftaları etkiler |
| Malzeme tik (Bu Hafta detayı) | Market’teki ilgili satır da güncellenir |
| Malzeme tik (yalnız Tarifler) | Market **değişmez** |
| Market’te satır tiklemek | Alındı sayılır; planlı katkıların işaretleri uyumlanır |
| Favori kalp | Sevdiklerime ekler / çıkarır (pişirmeden de) |
| Yerel sıfırla | Plan, market, puan, tercihler gider; katalog kalır |

---

## V1’de olmayanlar

- Hesap, giriş veya şifre yok.
- Telefonlar / iCloud arası senkron yok; her şey bu cihazda.
- Kendi tarifini ekleme veya düzenleme yok; katalog hazır gelir.
- Kahvaltı / öğle planı yok — yalnızca akşam.
- Reklam, abonelik duvarı veya bulut sohbet / yapay zekâ planı yok.
- Widget, bildirim veya İngilizce arayüz seçeneği bu sürümde yok.

Kısaca: MealRoutine v1.0, telefonda kalan, Türkçe, akşam odaklı bir haftalık plan ve market yardımcısıdır. Pazartesi geldiğinde haftayı senin için kurar; pişirdikçe zevkini öğrenir.

---

*MealRoutine v1.0 kullanıcı rehberi — telefonda kullanan kişi için.*
