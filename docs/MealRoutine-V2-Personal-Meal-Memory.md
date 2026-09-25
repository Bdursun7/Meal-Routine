# MealRoutine V2 — Personal Meal Memory

> **Core differentiation:** Other apps show what you can cook. MealRoutine learns what you actually want to cook.

## 1. V2'nin Ana Amacı

MealRoutine V1, kullanıcının tercihlerini alarak haftalık yemek planı ve otomatik grocery list oluşturur.

V2, **Personal Meal Memory** katmanıyla kullanıcının zaman içindeki gerçek davranışlarını öğrenir:

- Gerçekte pişirdiği yemekler
- Sevdiği ve sevmediği tarifler
- Sürekli değiştirdiği yemekler
- Tekrar seçtiği tarifler
- Gerçek süre ve zorluk tercihleri
- Yeni tarif keşfetme isteği
- Hafta içi ve hafta sonu alışkanlıkları

Amaç, her hafta daha isabetli ve uygulanabilir bir plan sunmaktır.

## 2. Ürün Konumlandırması

### Uzun açıklama

MealRoutine, her gün “Ne yesek?” sorusunu tekrar tekrar düşünme yükünü azaltan kişisel bir yemek rutini uygulamasıdır. Kullanıcının zevkini yalnızca onboarding sırasında sormaz; zaman içinde ne pişirdiğini, hangi yemekleri değiştirdiğini ve hangi tariflere tekrar yöneldiğini öğrenir.

### Kısa açıklama

> MealRoutine, ne pişirebileceğini göstermekten fazlasını yapar; zaman içinde gerçekten ne pişirmek istediğini öğrenir.

### İngilizce konumlandırma

> **Meal planning apps tell you what you can cook. MealRoutine learns what you actually want to cook.**

Bu farklılaşma başlangıçta bir ürün iddiasıdır. Gerçek rekabet avantajına dönüşmesi; daha az replacement, daha fazla pişirilen planlı yemek ve daha yüksek geri dönüş oranıyla doğrulanacaktır.

## 3. V2 Kapsamı

| Konu | Karar |
|---|---|
| Platform | iPhone |
| UI | SwiftUI |
| Persistence | SwiftData |
| Backend | Yok |
| Login | Yok |
| Cloud sync | Yok |
| Ana özellik | Personal Meal Memory |
| Planlama | Davranış tabanlı scoring |
| Feedback | Genişletilmiş |
| Tarif keşfi | Kişiselleştirilmiş |
| Smart replacement | Var |
| Öneri nedeni | Var |
| AI chatbot | Yok |
| LLM planlama | Yok |
| Market entegrasyonu | Yok |
| Sosyal özellikler | Yok |
| Veri yaklaşımı | Local-first |

## 4. V2'de Yapılmayacaklar

- AI chatbot veya serbest sohbet eden AI chef
- Kontrolsüz LLM tabanlı yemek önerileri
- İnternetten otomatik tarif scrape etme
- Instagram/TikTok API entegrasyonu
- Sosyal akış ve kullanıcı takip sistemi
- Market fiyat karşılaştırması veya siparişi
- Kalori, makro veya kilo hedefleri
- Sağlık entegrasyonu
- Zorunlu pantry yönetimi
- Household ortak hesabı
- Android, web veya Watch uygulaması
- Cloud sync
- Karmaşık makine öğrenmesi altyapısı

## 5. V1'den V2'ye Geçiş Kriteri

- [ ] Onboarding çalışıyor.
- [ ] İlk haftalık plan oluşturuluyor.
- [ ] Tek öğün değiştirilebiliyor.
- [ ] Tarif detayları çalışıyor.
- [ ] Yemek pişirildi olarak işaretlenebiliyor.
- [ ] Feedback kaydediliyor.
- [ ] Grocery list oluşturuluyor.
- [ ] Plan değişiklikleri grocery list'e yansıyor.
- [ ] Local data korunuyor.
- [ ] V1 beta tamamlanıyor.
- [ ] Kritik crash veya veri kaybı bulunmuyor.

## 6. Ana Kullanıcı Akışı

```text
V1 kullanımı
    ↓
Pişirme, değiştirme ve feedback kayıtları
    ↓
Meal Memory güncellemesi
    ↓
Kullanıcı profilinin zenginleşmesi
    ↓
Davranış tabanlı yeni haftalık plan
    ↓
Öneri nedeninin gösterilmesi
    ↓
Daha uygun yemeklerin pişirilmesi
    ↓
Yeni feedback ile sistemin gelişmesi
```

## 7. Personal Meal Memory

### Saklanacak sinyaller

- Pişirilen tarifler
- Loved, Okay ve Never again feedback'leri
- Değiştirilen ve atlanan tarifler
- Tekrar seçilen tarifler
- Favoriye eklenen tarifler
- Son pişirme tarihi
- Pişirme ve değiştirme sayıları
- Süre ve zorluk feedback'i
- Yeni tarif keşif geçmişi

### Kurallar

- Veriler local-first tutulur.
- Tek bir davranış kesin tercih olarak kabul edilmez.
- Açık feedback davranışsal sinyalden daha güçlüdür.
- Her sinyalin güven seviyesi bulunur.
- Kullanıcı Meal Memory verilerini sıfırlayabilir.
- Öneri mantığı mümkün olduğunca açıklanır.
- Açıkça reddedilen tercihler korunur.

### Güven seviyeleri

| Davranış | Güven |
|---|---|
| Bir kez değiştirme | Low |
| Aynı tarifi birkaç kez değiştirme | Medium |
| Never again | High |
| Bir tarifi birkaç kez pişirme | Medium |
| Loved feedback | High |

## 8. Genişletilmiş Feedback

V1 seçenekleri korunur:

- Loved it
- It was okay
- Never again

V2 ek seçenekleri:

- Too time-consuming
- Too difficult
- Would make again
- Portion was too small
- Portion was too large
- Missing ingredients
- Too many ingredients

Kurallar:

- Ana feedback zorunludur.
- Ek feedback opsiyoneldir.
- Feedback tek ekranda tamamlanır.
- Kullanıcı uzun anket doldurmak zorunda kalmaz.
- Feedback, Meal Memory ve scoring sistemini günceller.

## 9. Davranışsal Sinyaller

### Pozitif

- Tarifin pişirilmesi
- Loved olarak işaretlenmesi
- Tekrar seçilmesi
- Favoriye eklenmesi
- Benzer tarifin pişirilmesi
- Plan içinde değiştirilmeden kalması

### Negatif

- Plan içinden değiştirilmesi
- Never again olarak işaretlenmesi
- Sürekli atlanması
- Süre veya zorluk nedeniyle reddedilmesi
- Eksik malzeme nedeniyle tamamlanmaması

Bir tarifin bir kez değiştirilmesi, kullanıcının o tarifi kesinlikle sevmediği anlamına gelmez.

## 10. V2 Scoring Sistemi

| Kriter | Puan |
|---|---:|
| Loved tarif | +10 |
| Daha önce tekrar pişirilmiş tarif | +6 |
| Sevilen kategori | +5 |
| Sevilen protein | +5 |
| Benzer tarif daha önce sevilmiş | +4 |
| Normal bulunan tarif | +2 |
| Süre sınırının altında | +2 |
| Sık seçilen mutfak | +3 |
| Daha önce değiştirilmiş tarif | -6 |
| Son 2 gün içinde kullanılmış | -10 |
| Son 3-5 gün içinde kullanılmış | -5 |
| Son 6-10 gün içinde kullanılmış | -2 |
| Too time-consuming | -7 |
| Too difficult | -6 |
| Never again | -100 |

### Yeni tarif keşfi

| Kriter | Puan |
|---|---:|
| Sevilen kategoriye ait yeni tarif | +4 |
| Sevilen proteine ait yeni tarif | +3 |
| Sevilen mutfağa ait yeni tarif | +3 |
| Daha önce denenmemiş kategori | +1 |

Yeni tarif keşfi, açıkça reddedilen tercihleri geçersiz kılamaz.

## 11. Tekrar Yönetimi

- Aynı tarif aynı hafta içinde tekrarlanmaz.
- Loved tarifler en erken 7 gün sonra tekrar önerilebilir.
- Sık pişirilen tarifler için tekrar aralığı artırılabilir.
- Kullanıcı favori tarifini manuel olarak plana ekleyebilir.
- Sık pişirilen tarifler tamamen engellenmez.

### Repeat preference

- Occasionally
- Balanced
- Often

Varsayılan: `Balanced`

## 12. Discovery Level

- Familiar
- Balanced
- Adventurous

Varsayılan: `Balanced`

- Familiar bilinen yemekleri önceliklendirir.
- Balanced tanıdık ve yeni tarifleri dengeler.
- Adventurous yeni kategori ve tariflere daha fazla puan verir.
- Hiçbir seviye Never again veya disliked tercihlerini geçersiz kılamaz.

## 13. Kişiselleştirilmiş Tarif Keşfi

Recipes ekranına eklenecek bölümler:

1. Recommended for you
2. Similar to meals you loved
3. Try something different
4. Quick meals for your routine
5. Your previous favorites

Öneri nedeni örnekleri:

```text
Because you loved creamy chicken recipes
```

```text
Fits your usual cooking time
```

```text
A new recipe from a category you enjoy
```

```text
Similar to a meal you cooked twice
```

Kurallar:

- Sonsuz scroll kullanılmaz.
- Her bölüm sınırlı sayıda tarif gösterir.
- Never again tarifler gösterilmez.
- Disliked malzemeli tarifler gösterilmez.
- Öneriler açıklanabilir olur.

## 14. Smart Replacement

Seçenekler:

- Faster
- Similar to something you loved
- Something completely different
- Use a favorite
- Try a new recipe
- No chicken
- Vegetarian
- Use what I usually like
- Surprise me

Akış:

1. Kullanıcı replacement intent seçer.
2. İlgili filtre uygulanır.
3. Meal Memory puanları hesaplanır.
4. Çeşitlilik ve tekrar kuralları uygulanır.
5. Alternatifler öneri nedeni ile gösterilir.
6. Seçilen tarif plana eklenir.
7. Grocery list yeniden hesaplanır.

## 15. Plan Açıklamaları

Örnekler:

```text
A balanced week with quick weekday meals and two new recipes to explore.
```

```text
This week leans into meals you have enjoyed before, with a little variety.
```

Kurallar:

- Açıklama deterministik template'lerden üretilir.
- LLM kullanılmaz.
- Açıklama gerçek kullanıcı verisine dayanır.
- Aşırı iddialı ifadeler kullanılmaz.

## 16. Meal Memory Ekranı

Profile altında:

```text
Your Meal Memory
```

Bölümler:

### Your favorites

- En çok sevilen tarifler
- En çok pişirilen tarifler
- Son sevilen tarifler

### Your patterns

```text
You usually prefer meals under 30 minutes.
```

```text
You often cook chicken on weekdays.
```

```text
You have enjoyed 4 pasta recipes.
```

### Your avoid list

- Never again tarifler
- Kaçınılan malzemeler
- Too time-consuming tarifler

### Your discovery history

- Denenen yeni tarifler
- İlk kez pişirilen kategoriler
- Yeni tarif feedback'leri

Pattern kuralları:

- En az üç veri noktası olmadan güçlü pattern gösterilmez.
- `You always...` gibi kesin ifadeler kullanılmaz.
- `You often...` ve `You seem to prefer...` gibi temkinli ifadeler kullanılır.
- Kullanıcı pattern'i devre dışı bırakabilir.

## 17. Kullanıcı Kontrollü Kişiselleştirme

### Cooking difficulty preference

- Easy only
- Mostly easy
- Open to medium

Varsayılan: `Mostly easy`

### Weekday planning style

- Mostly quick
- Balanced
- More variety

Varsayılan: `Mostly quick`

Kurallar:

- Ayarlar Profile ekranından değiştirilir.
- Yeni ayarlar bir sonraki plan üretiminde kullanılır.
- Mevcut plan otomatik olarak silinmez.
- Kullanıcı mevcut haftada tek öğünü değiştirebilir.

## 18. V2 UI Güncellemeleri

### This Week

- Plan explanation card
- Personal recommendation reason
- Familiar / New meal badge
- Smart replacement suggestions
- Meal Memory insight widget

### Recipes

- Recommended for you
- Similar to your favorites
- Try something new
- Frequently cooked meals

### Profile

- Your Meal Memory
- Discovery preference
- Repetition preference
- Cooking difficulty preference
- Weekday planning style

### Recipe Detail

- Cooked X times
- Last cooked date
- Similar recipes
- Why this recipe fits you

Yeterli veri yoksa kişiselleştirme widget'ları gösterilmez.

## 19. Veri Modelleri

### MealMemory

- Recipe ID
- Times cooked
- Times replaced
- Times skipped
- Last cooked date
- Last selected date
- Loved count
- Okay count
- Never again flag
- Time concern count
- Difficulty concern count
- Portion concern count
- Discovery status
- Confidence level

### MealBehaviorEvent

```swift
enum MealBehaviorEventType: String, Codable {
    case viewed
    case selected
    case cooked
    case replaced
    case skipped
    case loved
    case okay
    case neverAgain
    case favorited
}
```

Alanlar:

- ID
- Recipe ID
- Event type
- Date
- Meal plan ID
- Planned meal ID
- Replacement reason

### RecipeMemoryScore

- Preference score
- Behavior score
- Variety score
- Repetition penalty
- Discovery score
- Final score

Score değerleri gerektiğinde hesaplanabilir; zorunlu olarak kalıcı saklanmaz.

## 20. Gizlilik ve Local-first

- Meal Memory cihaz üzerinde tutulur.
- Kullanıcı hesabı gerekmez.
- Veriler dışarıya gönderilmez.
- Kullanıcı tüm Meal Memory verisini sıfırlayabilir.
- Analytics event'leri ham Meal Memory verisinin tamamını içermez.
- Temel kişiselleştirme internet olmadan çalışır.

### Reset Meal Memory

Silinir:

- Cooking history
- Feedback kayıtları
- Davranışsal sinyaller
- Öğrenilmiş tercih skorları

Korunur:

- Sabit onboarding tercihleri

### Reset all app data

- Tüm yerel verileri siler.
- Kullanıcıyı onboarding'e geri götürür.
- Onay ekranı gösterir.

## 21. V2 Planlama Algoritması

### Girdiler

- UserPreference
- Recipe catalog
- MealMemory
- Previous meal plans
- Recent cooked recipes
- Discovery preference
- Repetition preference
- Current week constraints

### İşlem sırası

1. Never again tarifleri çıkar.
2. Disliked malzemeli tarifleri çıkar.
3. Süre ve zorluk filtrelerini uygula.
4. Son kullanılan tarifleri belirle.
5. Favori tarifleri belirle.
6. Yeni keşif adaylarını belirle.
7. Preference score hesapla.
8. Behavior score hesapla.
9. Variety score hesapla.
10. Repetition penalty uygula.
11. Discovery score uygula.
12. Haftalık çeşitlilik kurallarını uygula.
13. Planı oluştur.
14. Plan açıklamasını üret.
15. Planı kaydet.

### Pseudocode

```text
candidates = recipes
    .filter(notNeverAgain)
    .filter(notContainsDislikedIngredients)
    .filter(matchesTimePreference)
    .filter(matchesDifficultyPreference)

for recipe in candidates:
    score = 0
    score += preferenceScore(recipe)
    score += behaviorScore(recipe)
    score += familiarityScore(recipe)
    score += discoveryScore(recipe)
    score += varietyScore(recipe)
    score -= repetitionPenalty(recipe)

plan = selectMealsWithWeeklyConstraints(candidates)

return plan
```

## 22. Analytics Event'leri

V1 event'leri korunur.

Yeni event'ler:

```text
meal_memory_updated
personalized_recommendation_viewed
personalized_recommendation_selected
recommendation_reason_viewed
discovery_preference_changed
repetition_preference_changed
meal_pattern_viewed
meal_memory_reset
smart_replacement_used
new_recipe_cooked
familiar_recipe_cooked
```

## 23. Test Planı

### Meal Memory

- [ ] Pişirilen tarif sayısı doğru artıyor.
- [ ] Değiştirilen tarif sayısı doğru artıyor.
- [ ] Loved feedback kaydediliyor.
- [ ] Never again doğru kaydediliyor.
- [ ] Son pişirme tarihi güncelleniyor.
- [ ] Confidence level doğru hesaplanıyor.
- [ ] Tek olay kesin tercih oluşturmuyor.
- [ ] Reset tüm Meal Memory kayıtlarını temizliyor.

### Scoring

- [ ] Loved tarifler doğru puanı alıyor.
- [ ] Sık değiştirilen tarifler cezalandırılıyor.
- [ ] Discovery score çalışıyor.
- [ ] Repetition preference uygulanıyor.
- [ ] Discovery level uygulanıyor.
- [ ] Never again tarifler seçilmiyor.
- [ ] Aynı tarif aynı hafta içinde tekrarlanmıyor.
- [ ] Plan açıklaması gerçek veriye dayanıyor.

### UI

- [ ] Öneri nedeni doğru gösteriliyor.
- [ ] Yeterli veri yoksa widget gizleniyor.
- [ ] Kullanıcı ayarlarını değiştirebiliyor.
- [ ] Kullanıcı verisini sıfırlayabiliyor.
- [ ] Familiar ve New etiketleri doğru gösteriliyor.
- [ ] Dynamic Type ile UI bozulmuyor.
- [ ] Empty state ekranları hazırlanıyor.

## 24. V2 Beta Planı

- Süre: 21 gün
- Kullanıcı sayısı: En az 30
- 15 mevcut V1 kullanıcısı
- 15 yeni kullanıcı

Beta görevleri:

- [ ] En az iki haftalık plan oluşturma
- [ ] En az dört yemek pişirme
- [ ] En az iki yemek değiştirme
- [ ] En az bir yeni tarif deneme
- [ ] Meal Memory ekranını inceleme
- [ ] Discovery preference değiştirme
- [ ] Smart replacement kullanma
- [ ] Öneri nedenleri hakkında geri bildirim verme

## 25. V2 Başarı Metrikleri

| Metrik | Hedef |
|---|---:|
| Haftalık meal replacement | V1'e göre en az %20 azalma |
| Planlanan yemeklerden pişirilen oran | V1'e göre artış |
| Kullanıcı başına haftalık feedback | En az 2 |
| Kişiselleştirilmiş öneriden tarif seçme | En az %25 |
| Yeni önerilen tariflerden en az birini deneme | En az %40 |
| İkinci haftada geri dönüş | V1'e göre artış |
| Smart replacement kabul oranı | En az %40 |
| Meal Memory ekranını yararlı bulanlar | En az %60 |

V1 baseline'ı ölçülmeden kesin ürün etkisi iddia edilmez.

## 26. Definition of Done

- [ ] Meal Memory modeli çalışıyor.
- [ ] Pişirme, değiştirme ve feedback davranışları kaydediliyor.
- [ ] Davranışsal sinyaller scoring'e yansıyor.
- [ ] Never again önceliği korunuyor.
- [ ] Tekrar yönetimi çalışıyor.
- [ ] Yeni tarif keşfi çalışıyor.
- [ ] Smart replacement kişiselleşiyor.
- [ ] Öneri nedenleri gösteriliyor.
- [ ] Meal Memory ekranı çalışıyor.
- [ ] Kullanıcı ayarları değiştirilebiliyor.
- [ ] Meal Memory reset çalışıyor.
- [ ] Scoring testleri tamamlanıyor.
- [ ] Grocery list regresyona uğramıyor.
- [ ] V1 akışı korunuyor.
- [ ] En az 30 kullanıcıyla beta yapılıyor.
- [ ] V1 ve V2 metrikleri karşılaştırılıyor.

## 27. Geliştirme Sırası

### Faz 1 — Veri modeli ve event altyapısı

- [ ] MealMemory modelini oluştur.
- [ ] MealBehaviorEvent modelini oluştur.
- [ ] Feedback geçmişini genişlet.
- [ ] Replacement event kayıtlarını ekle.
- [ ] Confidence level hesaplamasını ekle.

Commit:

```text
feat: add personal meal memory models
```

### Faz 2 — Behavioral tracking

- [ ] Cooked event kaydet.
- [ ] Replaced event kaydet.
- [ ] Skipped event kaydet.
- [ ] Loved event kaydet.
- [ ] Never again event kaydet.
- [ ] Favorited event kaydet.
- [ ] Meal Memory servislerini oluştur.

Commit:

```text
feat: track meal behavior signals
```

### Faz 3 — V2 scoring

- [ ] Preference score'u ayır.
- [ ] Behavior score'u ekle.
- [ ] Discovery score'u ekle.
- [ ] Repetition penalty'yi geliştir.
- [ ] Confidence ağırlıklandırmasını ekle.
- [ ] Plan açıklaması üretimini ekle.
- [ ] Unit testleri yaz.

Commit:

```text
feat: add behavior-based meal scoring
```

### Faz 4 — Smart replacement

- [ ] Replacement intent modelini oluştur.
- [ ] Faster filtresini ekle.
- [ ] Similar to loved filtresini ekle.
- [ ] Use a favorite filtresini ekle.
- [ ] Try a new recipe filtresini ekle.
- [ ] Öneri nedenlerini oluştur.
- [ ] Replacement ekranını güncelle.

Commit:

```text
feat: add personalized meal replacement
```

### Faz 5 — Meal Memory UI

- [ ] Meal Memory ekranını oluştur.
- [ ] Favori özetini ekle.
- [ ] Pattern kartlarını ekle.
- [ ] Avoid listesini ekle.
- [ ] Discovery history ekle.
- [ ] Reset Meal Memory aksiyonunu ekle.

Commit:

```text
feat: add meal memory insights
```

### Faz 6 — Discovery

- [ ] Recommended for you bölümünü ekle.
- [ ] Similar to favorites bölümünü ekle.
- [ ] Try something different bölümünü ekle.
- [ ] Familiarity badge'lerini ekle.
- [ ] Discovery level ayarını ekle.
- [ ] Repetition preference ayarını ekle.

Commit:

```text
feat: add personalized recipe discovery
```

### Faz 7 — Test ve beta

- [ ] Scoring testlerini tamamla.
- [ ] Meal Memory reset testini tamamla.
- [ ] UI regression testlerini tamamla.
- [ ] V1 akışını tekrar test et.
- [ ] Analytics event'lerini doğrula.
- [ ] 30 kullanıcıyla beta başlat.
- [ ] V1 ve V2 metriklerini karşılaştır.

Commit:

```text
chore: prepare MealRoutine V2 beta
```

## 28. V2 Dosya Yapısı

```text
Core/
├── Models/
│   ├── MealMemory.swift
│   ├── MealBehaviorEvent.swift
│   ├── RecipeMemoryScore.swift
│   └── UserDiscoveryPreference.swift
│
├── Services/
│   ├── MealMemoryService.swift
│   ├── BehaviorTrackingService.swift
│   ├── PersonalizedScoringService.swift
│   ├── RecommendationReasonService.swift
│   └── MealPatternService.swift
│
└── Utilities/
    └── ConfidenceCalculator.swift

Features/
├── MealMemory/
│   ├── MealMemoryView.swift
│   ├── MealMemoryViewModel.swift
│   ├── MealPatternCard.swift
│   └── MealHistoryView.swift
│
├── Discovery/
│   ├── PersonalizedDiscoveryView.swift
│   ├── RecommendationCard.swift
│   └── DiscoveryViewModel.swift
│
└── MealPlanning/
    ├── SmartReplacementView.swift
    ├── ReplacementIntent.swift
    └── RecommendationReasonView.swift
```

## 29. V2 Riskleri

### Aşırı kişiselleştirme

Geçmiş davranışlara fazla bağlanmak yeni tarif keşfini azaltabilir.

Çözüm:

- Discovery level
- Kontrollü yeni tarif puanı
- Haftalık çeşitlilik

### Yanlış çıkarım

Bir tarifi değiştirmek, o tarifin kesinlikle sevilmediği anlamına gelmez.

Çözüm:

- Confidence level
- Açık feedback'e daha yüksek öncelik
- Tek davranıştan kesin sonuç çıkarmama

### Tekrara düşme

Kullanıcı sevdiği yemekleri görmek ister ancak her hafta aynı yemekleri görmek istemeyebilir.

Çözüm:

- Repeat preference
- Minimum tekrar aralığı
- Haftalık çeşitlilik

### Sahte kişiselleştirme

Uygulama yalnızca “Sana özel” etiketi gösterip gerçekte anlamlı fark yaratmazsa kullanıcı güveni düşer.

Çözüm:

- Her önerinin gerçek bir sinyale dayanması
- Öneri nedeninin doğru olması
- Feedback ve replacement davranışlarının scoring'e gerçekten yansıması
- Beta sırasında öneri kalitesinin ölçülmesi

## 30. V2 Ürün Kararlarının Özeti

MealRoutine V2:

- V1'in üzerine inşa edilir.
- Ana özellik Personal Meal Memory'dir.
- Kullanıcı davranışları planlama sistemine yansır.
- Açık feedback davranışsal sinyallerden daha güçlüdür.
- Never again tarifler önerilmez.
- Sevilen tarifler kontrollü biçimde tekrar gösterilir.
- Yeni tarif keşfi korunur.
- Öneri nedenleri gösterilir.
- Smart replacement kişiselleştirilir.
- Meal Memory ekranı eklenir.
- Discovery ve repetition tercihleri kullanıcı tarafından kontrol edilir.
- Kişiselleştirme local-first çalışır.
- AI chatbot veya LLM tabanlı planlama kullanılmaz.
- V1 akışı bozulmadan geliştirilir.
- Başarı, daha fazla özellik ile değil; daha uygun planlar ve daha yüksek gerçek pişirme oranıyla ölçülür.

## 31. V3'e Geçiş Kriteri

- [ ] Kişiselleştirilmiş önerilerin kullanıldığı doğrulanır.
- [ ] Meal replacement oranında iyileşme ölçülür.
- [ ] Yeni tarif keşfinin kullanıcı deneyimini bozmadığı görülür.
- [ ] Meal Memory ekranının kullanıldığı doğrulanır.
- [ ] Kullanıcıların öneri nedenlerini anladığı ölçülür.
- [ ] Kritik scoring hatası bulunmaz.
- [ ] Local data ve reset davranışı güvenilir olur.
- [ ] V3 kapsamı beta verileriyle belirlenir.

### V3 planlanan konu

```text
Share Sheet Recipe Import
```
