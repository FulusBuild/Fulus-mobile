# Fulus Web / Visual QA Target

The web target exists to support browser-based UI inspection without building or
installing an Android APK.

The production Android entrypoint remains `lib/main.dart`.

For visual QA, use the dedicated web entrypoint when it is available:

```bash
flutter run -d chrome -t lib/main_web.dart
```

This target is for UI inspection and automated browser verification only. It
must not be treated as a replacement for Android validation of device,
printing, camera, background-sync, or other platform-specific behavior.
