# FitNEP visual baseline and splash

The original image fill was exported from Figma node `4:994`:
https://www.figma.com/design/LFz2aFEFAJjVBlVjrnEsFW/Untitled?node-id=4-994
The supplied `146:2` link is a separate 100×100 vector, not the auth logo.
The source asset is `assets/images/fitnep_logo.png` (641×615).
`FitNepWordmark` displays the original image with the reference's rounded shape
and aspect ratio on startup, welcome, recovery, and the client header.

The shared baseline uses white surfaces, navy text, orange `#FA6B09` actions,
Inter typography, 13px outlined fields, pill buttons and 16px bordered cards.
Inter is bundled with its OFL license, so startup does not download a font.
`AppTheme.light` and the legacy `lightTheme` name resolve to one shared theme.
Recovery no longer replaces that theme with a private Material configuration.
The app uses the supplied light appearance consistently across phone settings.

Android launch resources include a centered logo before Flutter starts, with
Android 12 safe-area padding. iOS uses the same logo in its launch storyboard.
`scripts/prepare_branding.py` regenerates native bitmap display resources from
the unchanged source image; it requires Python and Pillow.

The Flutter startup view shows the logo while Firebase initializes. Connection
failure remains retryable. No forced delay or splash route is inserted, so cold
recovery links keep their destination after initialization. Native Android 12
splash checks must launch through the launcher; a direct adb activity launch can
skip the system splash.

The Android debug APK was built, installed on Infinix X6817 (Android 12), and the
startup/recovery logo and visual baseline were inspected. Startup and recovery
tests also cover compact screens, enlarged text, retry and cold recovery links.
iOS resources were updated but require macOS/Xcode for device validation.
