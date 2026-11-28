# FitNEP visual baseline and splash

The original image fill was exported from Figma node `4:994`:
https://www.figma.com/design/LFz2aFEFAJjVBlVjrnEsFW/Untitled?node-id=4-994
The supplied `146:2` link is a separate 100×100 vector, not the auth logo.
The source asset is `lib/shared/assets/images/fitnep_logo.png` (641×615).
`FitNepWordmark` displays the original symbol and FitNEP name with the
**Your Health Partner** tagline on startup, welcome, recovery, and the client
header.

The light theme pairs cool ivory surfaces and slate text with muted lavender
actions. The dark theme uses charcoal surfaces, soft lavender, and muted sage.
The FitNEP mark uses deep lavender on pearl in light mode and pale lavender on
charcoal in dark mode.
Inter is bundled with its OFL license, so startup does not download a font.
`AppTheme.light` and the legacy `lightTheme` name resolve to one shared theme.

The Android and iOS launch screens use the device appearance to select the
light or dark FitNEP wordmark and matching background. Regenerate the native
logo bitmaps from the Flutter wordmark with
`flutter test scripts/prepare_branding_test.dart`. If the scaffold background
colors change, update the Android `launch_background` colors and the iOS
`LaunchBackground` color asset.

The Flutter startup view shows the logo while Firebase initializes. Connection
failure remains retryable. No forced delay or splash route is inserted, so cold
recovery links keep their destination after initialization. Native Android 12
splash checks must launch through the launcher; a direct adb activity launch can
skip the system splash.

The Android debug APK was built, installed on Infinix X6817 (Android 12), and the
startup/recovery logo and visual baseline were inspected. Startup and recovery
tests also cover compact screens, enlarged text, retry and cold recovery links.
iOS resources were updated but require macOS/Xcode for device validation.
