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

`npm run migrate` `0001`–`0012` uygular. `pantry_items` household’a bağlıdır. `pantry_idempotency` hesap silinince temizlenir.

`DATABASE_URL` yoksa Postgres entegrasyon testleri atlanır. Bellek deposundaki pantry testleri yine çalışır.

## API

```text
GET    /v1/households/:id/pantry
POST   /v1/households/:id/pantry/items
PATCH  /v1/households/:id/pantry/items/:itemId
DELETE /v1/households/:id/pantry/items/:itemId
POST   /v1/households/:id/pantry/reconcile-grocery
```

`reconcile-grocery` gövdesi `operation` (`compute-missing`, `consume`, `restock`) ve `lines` taşır. `Idempotency-Key` aynı isteğin pantry miktarını iki kez değiştirmesini engeller. `compute-missing` stoktan düşmez. İşaretli satır aynen kalır. g/kg ve ml/L birleşir. Adet ile gram otomatik düşülmez.

## Uygulama

`MARKETING_VERSION` `5.0.0`. Pantry, Profil’den açılır. Market’te “Eksik miktarı hesapla”, satırda “Pantry’den düş” ve “Pantry’ye ekle” vardır. “Bitti” miktarı sıfırlar ve markete ekleme, minimuma göre eksik hesaplama veya silme seçeneklerini gösterir.

Kişisel pantry, ev kurulunca kendiliğinden karışmaz. Aktar, kopyala veya ayrı tut onayı istenir.

iOS testleri Xcode’da `MealRoutineTests/PantryTests.swift` içindedir. Bu belgeyi üreten ortamda Mac olmadığı için o hedef koşulmadı.
