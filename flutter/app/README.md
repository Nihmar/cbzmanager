# CBZ Manager — Flutter app

Flutter front-end for CBZ Manager (Android, Linux, Windows). See the port plan
in [`../PLAN.md`](../PLAN.md), the architecture in [`../TARGET.md`](../TARGET.md)
and the parity checklist in [`../PARITY.md`](../PARITY.md).

## Layout

```
lib/
  main.dart                     app shell, theming, i18n wiring
  l10n/                         ARB sources + generated AppLocalizations
  src/
    engine/                     pure-Dart core (zip, image edit, merge, comicinfo,
                                image search, page model) + engine facade
    vfs/                        byte-oriented VFS (local, memory, SMB) + workspace
    jobs/                       job controller + monitor
    features/
      browser/                  archive grid, thumbnails, preview
      validate/ convert/ merge/ cbr/ comicinfo/
      page_editor/ batch_edit/ image_search/
      settings/                 persistent settings
```

## Run / test

```bash
flutter pub get
flutter run -d linux        # or: flutter run  (Android device/emulator)
flutter test                # 118 unit/widget tests
flutter analyze
```

SMB integration tests are opt-in and need a Samba server:

```bash
docker run -d --name cbz-smb -p 445:445 -v /tmp/smb:/share \
  dperson/samba -u "test;testpass" -s "books;/share;yes;no;no;test;test;test"
CBZ_SMB_TEST=1 LD_LIBRARY_PATH=build/linux/x64/debug/bundle/lib \
  flutter test test/smb/
```

## Headless CLI

```bash
dart run bin/cbzmanager.dart --help
dart run bin/cbzmanager.dart validate <dir> [--threads N]
dart run bin/cbzmanager.dart convert-webp <dir> [--delete] [--threads N]
dart run bin/cbzmanager.dart merge <dir> [--delete] [--force] [--chapters N1,N2] [--chapters-per-volume N] [--threads N]
dart run bin/cbzmanager.dart cbr-to-cbz <dir> [--delete] [--threads N]
```

Runs under plain `dart run` (the engine/services are Flutter-free); exit codes
0/1/2 mirror the reference CLI.

## Release

```bash
../scripts/build_release.sh
```

Builds `build/linux/x64/release/bundle` (and, on hosts with an Android SDK, an
APK/AAB). Windows/macOS hosts build their native target.

## Notes

- All archive operations are in RAM; only the final output and optional
  `_OLD.cbz` backup touch storage (local or SMB).
- CBR (RAR) reading needs libarchive, loaded dynamically; the UI degrades
  gracefully when it is missing. On Android the library must be bundled per ABI
  (still pending).
- The engine is pure Dart; only libarchive (CBR) and libsmb2 (SMB) are native.
