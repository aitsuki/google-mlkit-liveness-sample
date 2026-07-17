# React Native Liveness Sample

Android-only liveness sample built with React Native Community CLI, Vision Camera, Nitro, and Google ML Kit face detection.

## Requirements

- Windows 10/11 or another Android development host
- Node.js 22.11 or newer
- npm
- JDK supported by the React Native 0.86 Android template
- Android SDK 36, Android Build Tools 36, and NDK `27.1.12297006`
- Android emulator or physical device

A physical Android device with a front-facing camera is required to validate the complete liveness flow.

## Install and run

```shell
npm ci
npm start
```

In another terminal:

```shell
npm run android
```

This project intentionally has no iOS project and does not support Expo, Yarn, or pnpm.

## Checks

```shell
npm run lint
npm run typecheck
npm test -- --runInBand

cd android
./gradlew.bat assembleDebug -PreactNativeArchitectures=x86_64
```

## Liveness flow

1. Hold a centered front-facing pose for 1000 ms.
2. Smile for 500 ms.
3. Turn left or right for 250 ms.
4. Return the three captured temporary image paths to the home screen.

Continuous invalid detection for 1500 ms resets the flow. Superseded or abandoned temporary photos are deleted.
