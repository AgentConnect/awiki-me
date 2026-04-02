# AWiki Me Flutter App

AWiki Me is a Flutter messaging client extracted into a standalone Flutter repository layout.

## Requirements

- Flutter 3.24.0 or newer
- Dart 3.5.0 or newer

## Getting Started

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

## Project Structure

- `lib/`: application code
- `assets/`: bundled images and SVG assets
- `test/`: widget and unit tests
- `android/`, `ios/`, `web/`: platform runners

## Regenerate App Icons

```bash
dart run flutter_launcher_icons
```

The icon source lives at `assets/branding/awiki-me-logo.png`.

## Regenerate Splash Screen

```bash
dart run flutter_native_splash:create
```

The splash image source also lives at `assets/branding/awiki-me-logo.png`.
