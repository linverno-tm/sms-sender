# SMS Bulk Sender (Flutter, Android)

Android uchun Flutter ilova: fayldan telefon raqamlarni import qiladi, tekshiradi va navbat bilan SMS yuboradi.

## Asosiy imkoniyatlar

- `.xlsx`, `.csv`, `.txt` dan raqam import qilish
- Boshqa ilovalardan share qilingan fayllarni qabul qilish
- Raqamlarni normalize qilish va deduplicate qilish
- Native foreground service orqali bulk SMS yuborish
- Real-time status: `sent`, `failed`, `remaining`, `percent`
- Qurilma qayta yuklanganda kampaniyani tiklash

## Qo'llab-quvvatlanadigan raqam formatlari

Quyidagi formatlar qabul qilinadi:

- `XX XXX XX XX`
- `+998 XX XXX XX XX`
- `998XXXXXXXXX`
- `XXXXXXXXX`

Yakuniy ichki format: `998XXXXXXXXX` (regex: `^998\d{9}$`).

## Texnologiyalar

- Flutter (Dart)
- Android Kotlin (`MethodChannel`)
- `another_telephony`
- `file_picker`
- `receive_sharing_intent`
- `excel`
- `csv`
- `archive`
- `xml`
- Android Foreground Service + WakeLock
- SQLite (native)

## Arxitektura

`lib/`:
- `core/` - matnlar va global error reporting
- `models/` - `ImportedFile`, `SmsProgress`, `ParseResult`
- `services/` - parserlar, normalizer, native bridge
- `pages/` - asosiy UI (`HomePage`)

`android/app/src/main/kotlin/com/example/sms/`:
- `MainActivity.kt` - `sms_native` kanal
- `BulkSmsForegroundService.kt` - yuborish servisi
- `BulkSmsRepository.kt` - SQLite status/queue
- `BootCompletedReceiver.kt` - rebootdan keyin tiklash

## MethodChannel API

Kanal: `sms_native`

- `startBulkSend`
  - input: `numbers: List<String>`, `message: String`
- `stopBulkSend`
- `getBulkStatus`
  - output: `state`, `total`, `sent`, `failed`, `pending`, `currentIndex`, `currentNumber`, `message`

## Android ruxsatlar

- `android.permission.SEND_SMS`
- `android.permission.FOREGROUND_SERVICE`
- `android.permission.WAKE_LOCK`
- `android.permission.RECEIVE_BOOT_COMPLETED`
- `android.permission.POST_NOTIFICATIONS`

## Ishga tushirish

1. `flutter pub get`
2. Emulator yoki qurilma ulang
3. `flutter run`

## Oxirgi yangilanishlar (2026-02-26)

1. Excel import mustahkamlandi:
- `.xlsx` uchun 2 bosqichli parsing: avval `excel`, yiqilsa ZIP/XML fallback (`archive` + `xml`).
- Noto'g'ri/parolli/buzilgan fayllar uchun aniq `FormatException` xabarlari.
- `.xls` format alohida rad etiladi (faqat `.xlsx` tavsiya qilinadi).

2. File picker oqimi yaxshilandi:
- `withData: false` qilindi.
- Fayl avval `path`dan o'qiladi (Android cache faylidan), kerak bo'lsa memory bytes fallback ishlaydi.

3. Telefon normalizer kengaytirildi:
- Bo'sh joy, maxsus space belgilar, `+998`, `998`, 9 xonali lokal formatlar qamrab olindi.
- `00` bilan boshlanuvchi xalqaro prefiks (`00998...`) ham normalize qilinadi.

4. Global xato monitoring qo'shildi:
- `FlutterError`, `PlatformDispatcher`, `runZonedGuarded` ushlanadi.
- Xatolar logga `[APP_ERROR][context] ...` ko'rinishida chiqadi.
- UI'da global error banner ko'rsatiladi.

5. Native SQLite resource leak tuzatildi:
- `BulkSmsRepository`ga `close()` qo'shildi.
- `MainActivity` va `BulkSmsForegroundService` lifecycle'da repository yopiladi.

## Eslatma

- Ilova Android uchun mo'ljallangan.
- Bulk SMS yuborishda operator va qonunchilik talablariga amal qiling.
