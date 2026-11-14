# SIMOVE

**SIMOVE** is a standalone, offline-first Android earnings tracker for Angkas riders.
It watches the Angkas booking screen with Android's own screen-capture API and
Google ML Kit OCR, reads the displayed **Total Earnings**, **Fare To Collect** and
payment method, and saves each ride as a local transaction — while keeping the
fare, platform earnings and tips strictly separate.

SIMOVE never accepts or rejects rides, never taps Angkas controls, and never
stores passenger names, phone numbers or addresses.

---

## Status of this build

| Item | Status |
|---|---|
| Flutter UI, SQLite storage, manual entry, tips, expenses, reports | Implemented and unit-tested on this machine |
| Booking state machine, OCR parser, duplicate prevention | Implemented; 47 automated tests pass |
| Android screen capture + ML Kit OCR + foreground-app gating | Implemented; emulator + real-device (TECNO LJ6) validation |
| Live Angkas OCR accuracy on a real phone | **Verified on hardware** — TECNO LJ6 (Android 16 / API 36), Angkas package `com.angkas.drivernew` |
| Debug APK | `build/app/outputs/flutter-apk/app-debug.apk` |
| Release APK | `build/app/outputs/flutter-apk/app-release.apk` (v1.0.2 — published) |

### Release v1.0.2

- Published on GitHub: <https://github.com/crldnglsn-dev/simove/releases/tag/v1.0.2>
- Contains the release APK (`app-release.apk`) for other riders to download.
- The release uses the **remove-background logo mark** (`assets/logo/`), the plain-language monitoring/income UI, quick add booking/expense, Reports date + month pickers, and payment methods limited to **Cash / E-wallet / Card**.

Built by **Carl John Dinglasan**.

Validated on the real phone (TECNO LJ6, Android 16, Angkas package
`com.angkas.drivernew`) on 2026-11-14:

- Auto-accepted booking panel read correctly: `Proceed to Pickup`, `Total
  Earnings ₱75.00`, `Fare To Collect ₱95.00`, payment `Cash`.
- The same ride's trip-details screen (later) was recognised via `Total Payment`
  / `Collected Payment` and the `Biker Cancelled` status chip, updating the open
  booking instead of creating a new one.
- Exactly one transaction was stored: `SMV-20261114-001`, platform ₱55.90
  / fare collected ₱76.00, Cash, status `bookingEnded` — with no passenger data.
- OCR history-tab false positives (bare `Earnings`, `NET EARNINGS` summaries) were
  fixed and the parser was extended to accept the real labels.
- A later auto-accepted booking was missed because the TECNO's `Usf_Hiber` power
  manager froze the app process; the app is now device-idle whitelisted and given
  background execution permission, and the UI/health flow can detect and surface
  capture stops.


The release APK is currently signed with the local **debug keystore** so it can be
installed and tested. Replace the signing config in
`android/app/build.gradle.kts` with a private keystore before distributing it.

---

## Features

- **Automatic booking detection** – recognises the Angkas accepted-booking screen
  and creates one pending transaction.
- **Pending bookings survive app switches and restarts** – a booking is kept in
  SQLite while Maps or Waze is in front, and while SIMOVE is closed.
- **Earnings recognition** – Total Earnings / Total Payment, Fare To Collect and
  payment method, read only when their labels are visible; payment methods are
  limited to Cash, E-wallet or Card.
- **Duplicate prevention** – state machine, salted screen-signature hash, salted
  booking-panel fingerprint, two-frame confirmation for weak new-booking signals,
  and a manual-edit lock so corrected values are never overwritten by OCR.
- **Manual entry and correction** – when OCR fails or misreads, edit the existing
  booking instead of creating a second one.
- **Tips** – cash, digital or other, with a switch for tips already included in
  Total Earnings to avoid double counting.
- **Expenses** – gasoline, maintenance, parking, food and other; net income is
  recorded earnings minus expenses.
- **Dashboard** – today, week, month, tips, fare collected, expenses, net income
  and pending detections; plain-language monitoring status with a health check.
- **Quick add** – add a booking or an expense from the Dashboard and from the
  Transactions tab.
- **Reports** – daily bars, payment-method breakdown, expense breakdown, date and
  month pickers, CSV and JSON export through the Android share sheet.
- **Floating tracker** – optional movable overlay with today's earnings and the
  latest booking.
- **Dark navy / cyan financial UI**, four tabs, offline-only.

---

## Calculation rules

```
Recorded Earnings = Platform Total Earnings + Tips not already included
Net Earnings      = Recorded Earnings - Recorded Expenses
```

`Fare To Collect` is what the passenger pays the rider; it is stored and shown
for reference but **never added to income**. No commission is guessed or
subtracted. Money is stored as integer centavos to avoid rounding errors.

---

## Requirements

- Android 8.0 (API 26) or newer.
- The Angkas rider app installed (this build was validated against
  `com.angkas.drivernew`).
- Permissions used:
  - **Usage access** – required so OCR runs only while Angkas is in front.
  - **Screen capture** – Android asks for consent every time monitoring starts.
  - **Notifications** – required foreground-service notification.
  - **Display over other apps** – only for the optional floating tracker.
  - **Notification access** – optional hint source; never the only booking source.
  - **Battery optimisation exemption** – optional, for long shifts.

SIMOVE cannot read Angkas while Maps or Waze covers the screen. In that case the
current pending booking is preserved and OCR resumes when Angkas is visible again.

---

## Install

1. Copy `app-release.apk` (or `app-debug.apk`) to the phone and install it.
   Android may ask you to allow installing from unknown sources.
2. Open **SIMOVE**.
3. Tap **Set up automatic detection** (or **Start** on the dashboard):
   - allow **usage access**;
   - allow **notifications**;
   - tap **Start** and accept Android's screen-capture dialog.
4. Open Angkas and go online. The first ride is detected automatically.
5. Slide the Angkas panel up when convenient so Total Earnings and Fare To
   Collect are visible; SIMOVE fills in the pending transaction.
6. Add a tip from the dashboard or transaction detail if the passenger tipped.

### Using it during a shift

- Switching to Maps/Waze does not lose the booking.
- Returning to Angkas resumes detection on the same transaction ID.
- When a genuinely new ride appears, a new transaction is created.
- Review anything marked **Needs review** and correct it while safely stopped.
- The red **Stop** button on the dashboard (or the notification action) stops
  monitoring at any time.

---

## Privacy

- OCR runs **on the device** with Google ML Kit.
- Screenshots/frames are processed in memory and **never uploaded or saved**.
- Only transaction fields (amounts, payment method, timestamps, optional notes)
  are stored.
- Deduplication uses SHA-256 hashes with a random per-install salt. Readable
  screen text is not written to SQLite.
- Passenger names, phone numbers and addresses are never persisted.
- SIMOVE has no internet permission and no server component.

---

## How detection works

```
MediaProjection frame
        │
        ▼
UsageStatsManager: is Angkas foreground? ──no──► keep pending booking, wait
        │ yes
        ▼
ML Kit OCR (lines + bounding boxes, in memory)
        │
        ▼
Dart AngkasOcrParser: label-anchored field extraction
        │
        ▼
BookingStateMachine: IDLE → BOOKING_DETECTED → WAITING_FOR_EARNINGS
                     → EARNINGS_DETECTED/RECORDED → BOOKING_ENDED
        │
        ▼
SQLite transaction + dashboard/overlay refresh
```

Key safeguards:

- Amounts are accepted only next to their own label; bare integers, distances
  and clock times are rejected.
- Earnings above ₱5,000 for one ride, or Total Earnings above Fare To Collect,
  lower confidence and route the record to review.
- An incomplete read is saved as pending / needs review, not as a completed fare.
- The same booking screen seen repeatedly does not create duplicates.
- A partial or blurry frame cannot un-record an already verified booking; only a
  frame that proposes different values moves it back to review.
- Manual corrections set `isManuallyEdited` and are preserved.
- A pending record older than 45 minutes is closed for review before a new ride
  is created.

Implementation notes:

- MediaProjection delivers `RGBA_8888` frames, which ML Kit cannot consume
  directly. The service copies each frame into an ARGB bitmap (trimming row
  padding) before OCR and recycles it afterwards.
- Android 14+ is asked for whole-display capture explicitly
  (`MediaProjectionConfig.createConfigForDefaultDisplay()`), so the consent
  dialog defaults to **Share entire screen**.
- The foreground check looks back two minutes of `UsageStatsManager` events and
  falls back to aggregated usage stats, because event writes can be batched.
- The native OCR payload is flat (`type`, `timestamp`, `packageName`, `lines`);
  the Dart event decoder accepts both that shape and a nested `observation`.


---

## Build from source

Toolchain used: Flutter 3.47.7, Dart 3.13.5, Android SDK 36, JDK 17 target
(Android Studio JBR).

```powershell
C:\flutter\bin\flutter.bat pub get
C:\flutter\bin\flutter.bat analyze
C:\flutter\bin\flutter.bat test
C:\flutter\bin\flutter.bat build apk --debug
C:\flutter\bin\flutter.bat build apk --release
```

`kotlin.incremental=false` is set in `android/gradle.properties`. Without it,
Kotlin's incremental cache fails on this machine because the pub cache and the
project live on different drives.

---

## Automated tests

```powershell
C:\flutter\bin\flutter.bat test
```

47 tests cover the acceptance criteria:

| Area | Tests |
|---|---|
| New booking creates one pending record | `booking_state_machine_test.dart` |
| Earnings are not invented before the panel expands | `booking_state_machine_test.dart` |
| Expanded panel records ₱75.00 / ₱95.00 / Cash | `ocr_parser_test.dart`, state machine |
| App switching keeps the same transaction | `booking_state_machine_test.dart` |
| Repeated screens do not duplicate | `booking_state_machine_test.dart` |
| A partial frame cannot un-record a verified booking | `booking_state_machine_test.dart` |
| A low-confidence frame with different values needs review | `booking_state_machine_test.dart` |
| New ride creates a separate transaction | `booking_state_machine_test.dart` |
| ₱20 tip updates ₱75 → ₱95 without double counting | state machine + summary tests |
| Incomplete OCR stays pending / needs review | parser + state machine |
| Pending booking survives an app restart | `database_test.dart` (real SQLite via FFI) |
| Daily summary excludes fare and duplicate tips | `database_test.dart` |
| OCR fingerprint changes only for a new ride | `ocr_parser_test.dart` |
| Native OCR event payload is decoded into an observation | `monitoring_event_test.dart` |
| App shell, onboarding, package dialog and summary UI | `app_smoke_test.dart` |

The tests use synthetic OCR observations, not recorded Angkas screens. Real
accuracy depends on the phone's resolution, font scale and Angkas version.

### What was not testable here

- Live capture and OCR against the real Angkas app.
- The real Android permission dialogs and overlay compatibility on a physical
  device.
- Different screen sizes / Android skins.

These need a physical Android phone with Angkas installed. Use the Diagnostics
panel in **Settings → Detection** to see the last OCR reason and signals — OCR
events alone update the reason, so it keeps showing the last decision even
while monitoring waits for Angkas.

---

## Project structure

```
lib/
  core/            theme, money and date helpers
  data/            SQLite database, models, repositories
  domain/
    detection/     booking state machine / duplicate prevention
    ocr/           OCR models and Angkas field parser
    summary/       earnings aggregation and reports
  screens/         dashboard, transactions, reports, settings, setup
  services/        Flutter ↔ Android bridge, CSV/JSON export
  state/           settings, earnings and monitoring providers
  widgets/         shared UI components
assets/
  logo/            generated SIMOVE logo PNGs (1024 / 512 / adaptive)
android/app/src/main/kotlin/com/simove/app/
  MainActivity.kt                    channels, permissions, capture consent
  capture/ScreenCaptureService.kt    MediaProjection + ML Kit + foreground gating
  overlay/OverlayService.kt          floating earnings tracker
  notifications/…                    optional coarse notification hints
  PermissionHelper.kt                permission snapshot
  ForegroundAppDetector.kt           UsageStatsManager helper
```

---

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| “Permission needed” | Grant **usage access** in Android settings, then tap Start again. |
| Screen-capture dialog does not appear | Android requires the consent dialog every session; start monitoring again from SIMOVE. |
| Nothing detected while Angkas is open | Check Settings → Detection → last reason/signals. Make sure the Angkas package matches `com.angkas.rider` (Settings → Angkas app package), the screen is on, and Angkas is the foreground app. |
| Booking stays pending | The earnings panel was not visible long enough, or confidence was below the threshold. Open the panel or enter values manually. |
| Tip counted twice | Toggle **Already included in Total Earnings** on the tip. |
| Monitoring stops after a while | Exempt SIMOVE from battery optimisation (Settings → Battery optimisation). |
| Overlay does not show | Grant **Display over other apps**, then enable the tracker again. |
| Monitoring shows “off” / nothing is detected while Angkas is open | Tap **Fix** on the dashboard. Grant **battery → Unrestricted** and **Auto-start** in the Angkas-adjacent app info screen (TECNO/Infinix/itel). If the OEM still freezes the process, whitelist with `adb shell cmd deviceidle whitelist +com.simove.app`. |

---

## Known limitations

- OCR only sees the **visible** screen. Angkas behind Maps/Waze is unreadable.
- Angkas UI changes can rename labels; the parser is conservative and will leave
  the booking pending for manual entry rather than guess.
- Notification access is an optional hint only, never a guaranteed booking source.
- SIMOVE is a tracker, not an automation tool: it does not accept rides, reject
  rides, or press Angkas buttons.
- The bundled release APK is debug-signed for testing.
