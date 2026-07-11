# Release screenshot contract

The five committed PNGs are generated from the full Flutter widget tree at a fixed 1440×1000 viewport, a fixed injected clock, and the bundled fictional example family. They are not mockups and contain no real health information.

Required files:

| File | Required state |
| --- | --- |
| `patient.png` | Grandma Rose selected; at least one taken dose and one unresolved amber dose visible. |
| `caregiver.png` | Both people visible; attention section distinguishes unresolved and confirmed missed. |
| `provider.png` | Live Today panel plus the taken/missed/not-marked history legend. |
| `circle.png` | Fictional-family label, people, medications, and schedules visible. |
| `settings.png` | Demo-clock explanation, reset action, and non-medical-device disclaimer visible. |

Regenerate them from `app/` in PowerShell:

```powershell
$env:DOSEKEEPER_CAPTURE_SCREENSHOTS = 'true'
flutter test test/screenshot_capture_test.dart --update-goldens
Remove-Item Env:DOSEKEEPER_CAPTURE_SCREENSHOTS
```

The capture harness loads Flutter's cached Roboto and Material Icons fonts, uses only states the app can produce, and is skipped during the ordinary test suite. After regeneration, inspect all five images and verify the links in the root README.
