# SMS Bulk Sender (Flutter, Android)

Android-only Flutter ilova bo‘lib, fayllardan telefon raqamlarini import qiladi, validatsiya qiladi va bulk SMS yuborishni boshqaradi.

## Asosiy imkoniyatlar

- `.xlsx`, `.xls`, `.csv`, `.txt` fayllardan raqamlarni import qilish
- Telegram va boshqa ilovalardan share qilingan fayllarni qabul qilish
- O‘zbek raqamlarini normalize qilish (`+998...`, `998...`, bo‘sh joyli formatlar)
- Yakuniy valid format: `^998\d{9}$`
- Barcha fayllar bo‘yicha raqamlarni birlashtirish va duplicate raqamlarni olib tashlash
- Foreground service orqali navbatma-navbat SMS yuborish
- Har SMS oralig‘ida 2 soniya kutish (`queue` uslubi)
- Uzun matnlar uchun multipart yuborish
- Progress, sent, failed, remaining holatlarini real vaqtga yaqin ko‘rsatish
- Qurilma restart bo‘lganda yuborilmagan navbatni tiklash va davom ettirish

## Texnologiyalar

- Flutter (Dart, null-safety)
- Android Kotlin native integration (`MethodChannel`)
- `another_telephony`
- `file_picker`
- `receive_sharing_intent`
- `excel`
- `csv`
- Android Foreground Service + WakeLock
- SQLite (native) queue va status persistence

## Arxitektura

`lib/`:
- `models/` - domen modellari (`ImportedFile`, `SmsProgress`, ...)
- `services/` - parser, native bulk SMS channel xizmati
- `pages/` - asosiy UI (`HomePage`)
- `core/` - umumiy matnlar (`AppStrings`)

`android/app/src/main/kotlin/com/example/sms/`:
- `MainActivity.kt` - `sms_native` method channel
- `BulkSmsForegroundService.kt` - background/sleep holatda yuborish
- `BulkSmsRepository.kt` - SQLite orqali campaign/queue holatini saqlash
- `BootCompletedReceiver.kt` - restartdan keyin kampaniyani davom ettirish

## MethodChannel API

Kanal: `sms_native`

- `startBulkSend`
  - input: `numbers: List<String>`, `message: String`
- `stopBulkSend`
  - input: yo‘q
- `getBulkStatus`
  - output: `state`, `total`, `sent`, `failed`, `pending`, `currentIndex`, `currentNumber`, `message`

## Android ruxsatlar

Manifestda quyidagilar ishlatiladi:

- `android.permission.SEND_SMS`
- `android.permission.FOREGROUND_SERVICE`
- `android.permission.WAKE_LOCK`
- `android.permission.RECEIVE_BOOT_COMPLETED`
- `android.permission.POST_NOTIFICATIONS`

## Ishga tushirish

1. Flutter SDK va Android SDK o‘rnatilgan bo‘lishi kerak.
2. Loyihada:
   - `flutter pub get`
3. Qurilma/emulator ulang.
4. Ilovani ishga tushiring:
   - `flutter run`

## Foydalanish oqimi

1. `Телефон рақамлар файлини юклаш` tugmasi orqali fayl(lar) qo‘shing.
2. Import qilingan fayllardagi valid/invalid natijalarni tekshiring.
3. SMS matnini kiriting.
4. `Юбориш` ni bosing.
5. Zarur bo‘lsa `Тўхтатиш` bilan jarayonni to‘xtating.
6. Ilova qayta ochilganda status panel joriy holatni avtomatik tiklaydi.

## Muhim eslatmalar

- Ilova Android platformasi uchun mo‘ljallangan.
- Bulk SMS yuborishda operator va davlat regulyator talablari (anti-spam siyosatlari)ga amal qiling.
- Juda katta hajmda yuborishda qurilma/ROM cheklovlari bo‘lishi mumkin.

## Troubleshooting

- `Inconsistent JVM target` xatolari chiqsa, pluginlar Kotlin/Java targetlari mosligini tekshiring.
- Build cache muammosida `build/` va `android/.gradle/` papkalarini tozalab qayta build qiling.
- SMS yuborilmasa, qurilma ruxsatlari (`SMS`, `Notifications`) berilganini tekshiring.

## Parser yangilanishlari (2026-02-26)

Telefon raqam parseri quyidagicha yaxshilandi:

- Quyidagi formatlar qabul qilinadi va bitta standartga keltiriladi:
  - `+998901075508`
  - `+998 90 107 55 08`
  - `998901075508`
  - `998 90 107 55 08`
  - `90 107 55 08`
  - `90-107-55-08`
  - `(90) 107 55 08`
- Yakuniy format doim `998XXXXXXXXX` (12 ta raqam).
- Validatsiya regex: `^998\d{9}$`.
- 9 xonali lokal formatga avtomatik `998` prefiksi qo'shiladi.
- Barcha non-digit belgilar (`\D`) tozalanadi.
- Oddiy space bilan birga maxsus bo'sh joy belgilar ham tozalanadi: `\u00A0`, `\u2007`, `\u202F`.
- Excel numeric edge-case qo'llab-quvvatlanadi:
  - `... .0` ko'rinishidagi qiymat to'g'ri butun songa aylantiriladi.
  - E-notation qiymatlarda parse bo'lsa butun songa fallback aylantirish ishlaydi.
- Parser oqimida har bir qiymat `toString()` orqali normalizatsiyadan o'tadi.
- Valid raqamlar deduplicate qilinadi (`Set`), invalid qiymatlar alohida sanaladi.
- UI'da valid/invalid sonlari aniq ko'rsatiladi va invalid holatda tushunarli kirillcha izoh chiqadi.
