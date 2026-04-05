# Moaner (moan)

## Project
Flutter app - shake or slap your phone to trigger moaning sounds. Bundle ID: `com.moan.moan`

## TestFlight Deploy

Two steps to build and upload:

```bash
# 1. Build IPA (increment build number manually)
cd /Users/predator/moan && flutter build ipa --release --build-number=<next_number>

# 2. Upload to TestFlight
cd /Users/predator/moan/ios && FASTLANE_APPLE_APPLICATION_SPECIFIC_PASSWORD="bujn-waty-wgnm-vhte" fastlane beta
```

Note: fastlane only handles upload because CocoaPods breaks under fastlane's Ruby environment.
Current build number: 4

Apple ID: ahto.altmets@gmail.com
Team ID: WZK4HS38QW

## Structure
- `lib/main.dart` — main app (single file)
- `assets/audio/moan/` — 60 sound files (0.mp3 - 59.mp3)
- `ios/fastlane/` — Fastfile and Appfile for TestFlight deployment
