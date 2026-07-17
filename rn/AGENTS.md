# AGENTS.md

## Scope

This directory contains the Android-only React Native liveness sample.

## Toolchain constraints

- Use **npm** and commit `package-lock.json`.
- Do not use Yarn, pnpm, Expo, or Expo modules.
- Use `@react-native-community/cli` and the matching React Native template.
- Support Android only. Do not add an `ios/` project, CocoaPods, or iOS scripts.
- Keep the New Architecture and Hermes enabled unless a documented dependency incompatibility requires a change.

## Required commands

Run these before completing a change:

```shell
npm ci
npm run lint
npm run typecheck
npm test -- --runInBand
cd android
./gradlew.bat assembleDebug -PreactNativeArchitectures=x86_64
```

For a release-oriented Android change, also run:

```shell
cd android
./gradlew.bat assembleRelease -PreactNativeArchitectures=arm64-v8a
```

Use `gradlew.bat` when validating from Windows. Do not commit generated build outputs, `.gradle`, `.cxx`, `node_modules`, or `local.properties`.

## Architecture

- Keep liveness decision logic in pure TypeScript under `src/liveness/`.
- Keep camera, filesystem, and navigation APIs out of `LivenessController`.
- Add or update unit tests whenever thresholds, steps, reset behavior, or timing changes.
- Keep the React Native behavior aligned with the native sample in `../android`.
- Current flow is `front -> smile -> side -> done`.
- Current required durations are 1000 ms, 500 ms, and 250 ms.
- Continuous detection failures reset the flow after 1500 ms; a valid detection clears the failure window.

## Camera and files

- The camera is active only while the liveness screen is focused and the app is active.
- Treat Vision Camera, Nitro, face detector, and Worklets packages as one compatibility group when upgrading.
- Do not destructure Nitro Hybrid Objects returned by detector hooks unless the library explicitly allows it.
- Delete superseded and abandoned temporary photos.
- Validate face detection on an arm64 Android physical device; an emulator is only sufficient for build, install, navigation, and basic camera-preview checks.

## Dependency changes

- Prefer exact React Native and `@react-native/*` versions from the official community template.
- Check peer dependencies before changing Vision Camera-related packages.
- Never use `npm audit fix --force` without reviewing and testing every major-version change.
- Do not manually copy Gradle settings from `../android`; use the versions required by the React Native template.
