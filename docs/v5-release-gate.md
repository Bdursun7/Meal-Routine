# V5 release gate

Spec bölüm 16. Ürün sınırı `docs/v5-smart-pantry.md`. Yerel kurulum `docs/v5-local-runbook.md`.

`MARKETING_VERSION` `5.0.0`. `CURRENT_PROJECT_VERSION` `5`. Migration `0012_pantry`. `0001`–`0011` dosyaları değişmedi.

Bu ortamda `cd server && npm test` ve `npm run typecheck` geçti. Postgres entegrasyonu `DATABASE_URL` olmadan atlanır. iOS XCTest bu ortamda koşmadı; `MealRoutineTests/PantryTests.swift` eklendi. Apple Sign in, APNs, fiziksel cihaz ve TestFlight V5 kapsamı dışında.

## Kapı

| Madde | Durum | Not |
| --- | --- | --- |
| Pantry CRUD | pass | `pantry.test.ts` oluşturma, liste, güncelleme, silme |
| Household authorization | pass | Üye olmayan `GET` ve `POST` 403 |
| Uyumlu birimler | pass | 400 g + 1 kg → 1400 g, tek satır |
| Uyumsuz birimler | pass | Adet, gram satırına karışmaz. `confirmSeparate` ile ayrı satır. `kova` → 400 `invalid_unit` |
| Eksik miktar | pass | 1000 g ihtiyaç, 400 g stok → 600 g. Replay aynı gövde. Stok azalmaz |
| İşaretli market satırı | pass | `checked` satırın miktarı hesapta değişmez |
| Consume / restock idempotency | pass | Aynı anahtar 400 g’yi bir kez düşer, 1 kg’yi bir kez ekler |
| Conflict | pass | Eski `baseRevision` 409 `conflict` ve güncel kayıt döner. İstemci `requiresResolution` bırakır |
| Offline retry | pass (birim) | `SyncDrainer` çevrimdışıyken göndermez, dönüşte bir kez gönderir, conflict’i yeniden uygulamaz. Uçtan uca ağ testi Mac’te |
| Migration | pass | `0012` var. Önceki dosyalarda `pantry_items` yok. `DROP TABLE` yok |
| Account deletion | pass | Tek üye silinince pantry gider. Partner kalırsa pantry kalır. Başka hesabın export’unda yok |
| V1–V4.1 regresyon | pass | Sunucu paketi yeşil. Boş pantry plan cümlesini değiştirmez |
| Türkçe durum metinleri | pass | Yükleniyor, boş, hata, çevrimdışı, conflict cümlesi |
| VoiceOver / Dynamic Type / Dark Mode | manual | Etiketler ve sistem kontrolleri var. Görsel tur cihazsız yapılmadı |
| iOS unit test koşusu | blocked | `PantryTests.swift` yazıldı. Xcode bu ortamda yok |
| Apple / APNs / TestFlight | deferred | V4.1’de ertelendi. V5 blokeri değil |

## Bu fazdan sonra

1. Mac’te MealRoutine testlerini, özellikle `PantryTests`, çalıştır.
2. İstenirse `DATABASE_URL` ile `cd server && npm test`.
3. `npm run migrate` (`0001`–`0012`).
