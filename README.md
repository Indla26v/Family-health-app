# Family Health

A private, offline-first Android app for one family (with a companion web app in [`family-health-web/`](family-health-web/README.md)): lab reports become trend charts, plus medicine reminders, daily BP/sugar logging, appointments and an emergency card. Everything is stored on the phone.

The design follows the "Family Health — Prototype" canvas: 21 screens across Today, Health, Records and Family.

## Run it

```bash
flutter pub get
flutter run            # on a connected Android phone or emulator
flutter run -d chrome  # quick look in a browser (reminders, fingerprint and camera are phone-only)
```

The app starts empty. On first launch a short setup asks for the language, your details (you become the admin on this phone), the family members you look after (each one gets **Simple mode** with big buttons and Telugu, the **Full app**, or **Admin**), and whether to lock the app with a PIN. People can be added or removed later under **Family**, and **Settings → Delete everything on this phone** starts over.

The mock data from the design brief now exists only as a test fixture (`test/support/sample_data.dart`). Data saved by the earlier sample build is discarded on upgrade.

## What works

- **Today (admin):** member switcher, due medicine with Taken/Skip/Undo, missed-dose banner, today's readings, next appointment, and the "reports need review" banner.
- **Today (simple mode):** for parents. One next medicine with a huge Taken button, Log BP and Log Sugar, and the next doctor visit. Telugu labels and large text.
- **Log reading:** BP, sugar (fasting or after a meal), weight and SpO2, using a big keypad. The status pill updates as you type. Reading history shows every home log with date, time, member/type/meal filters and confirmed deletion; open it from Today, Health or Log reading.
- **Health:** condition cards with the latest value, change since the last test and a sparkline. Home sugar logs feed the fasting (FBS) and post-prandial (PPBS) cards and histories alongside confirmed lab results, with their source labelled. BP, weight and SpO2 logs also appear without requiring a tracked condition. The Diabetes screen has the HbA1c chart (reference band and target line), daily sugar averages, combined glucose trends, medicines, check-ups and a descriptive insight. There are also BP and per-test trend screens. Tap a lab point to open its source report.
- **Records:** search, filters, a pinned Needs review section, grouping by year, and failed and empty states.
- **Upload:** pick files or scan with the camera, choose the member, then the report is read on the phone. PDFs with a text layer go through `lib/services/parser.dart`. Confident values are confirmed automatically. Uncertain values, and every value when the patient name doesn't match, wait for review.
- **Review:** shows the original file, highlights low-confidence rows, lets you edit inline, remove a row, add a missing test, set the date, and confirm.
- **Bulk import:** pick many files at once. Progress is shown by year, with pause and resume.
- **Medicines:** grouped Morning, Afternoon and Night, with a stock and refill warning. The add/edit form takes a photo, the food timing and a schedule. Adherence shows a month heatmap, a percentage and the list of missed doses.
- **Reminders:** daily local notifications open a full-screen alarm with Taken, Snooze 10 min and Skip. A Telugu voice reads the reminder when the phone has one.
- **Appointments:** upcoming visits with the report to take along, and past visits with the doctor's notes and prescription.
- **Family:** profiles (BMI, ABHA number, insurance, allergies, family history, conditions, app mode, emergency contacts) and roles.
- **Emergency card:** high contrast with no red, tap-to-call contacts, an offline QR code and a PDF export.
- **Settings:** English or Telugu, large text, appearance, voice, app lock (fingerprint with PIN backup), JSON backup, a summary PDF for doctor visits, who uses this phone, and delete everything.

## Cloud sync (optional)

Sign in on first start (or Settings → Cloud account & sync) to sync with the family's web app (`family-health-web/`, deployed on Vercel + Neon). The phone stays offline-first: everything is stored locally, and changes sync in the background with last-write-wins. See [DEPLOYMENT_NOTES.md](DEPLOYMENT_NOTES.md).

## Not built yet

- **Text recognition for scans and photos.** Images and scanned PDFs are saved and go to Needs review, where the values are entered by hand. On-device OCR (for example ML Kit) would plug into `ImportService.read`.
- **Missed-dose alert to another phone.** Cloud sync now exists (see below), but push notifications to the admin's phone are not built yet.
- **Native home-screen widget.** The emergency screen shows a preview only.
- **Share sheet from WhatsApp or Gmail.** For now, save the file to the phone and pick it with Files.

## Notes

- Each person gets a starter list of check-ups based on the conditions ticked for them. Mark them done from the Health tab.
- The thresholds in `lib/data/catalog.dart` (`VitalRanges`, `labTests`) are placeholders set to match the brief's sample data. Have the family's doctor confirm them.
- Insights describe trends only. The app never gives treatment advice.

## Logo

The logo (a white heart with a heartbeat line on teal) is in `assets/branding/` as SVG and PNG. Launcher icons for Android (adaptive and themed), web and Windows are generated from it with `dart run flutter_launcher_icons`.

## Tests

```bash
flutter test test/logic_test.dart   # empty start, family setup, parser, ranges, adherence, review, persistence
flutter test test/shots_test.dart   # renders every screen (with test data) to build/shots/*.png
```
