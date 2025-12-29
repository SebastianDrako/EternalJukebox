# Infinite Jukebox Local

A Flutter project that generates infinite loops of audio files locally on Android.

## Prerequisites

- [Flutter SDK](https://flutter.dev/docs/get-started/install) installed and in your PATH.
- Android Studio / Android SDK command-line tools.

## Setup

1.  Initialize the project platform files (since this repo only contains source code):
    ```bash
    flutter create . --platforms android
    ```
    *Note: This will generate the `android/` directory structure properly with Gradle wrappers.*

2.  Install dependencies:
    ```bash
    flutter pub get
    ```

## Permissions

The `AndroidManifest.xml` is already configured for background audio playback permissions.

## Building

To build the APK:

```bash
flutter build apk --release
```

The output APK will be located at `build/app/outputs/flutter-apk/app-release.apk`.

## Running

To run on a connected device:

```bash
flutter run
```
