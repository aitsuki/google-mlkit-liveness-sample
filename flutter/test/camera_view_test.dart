import 'dart:async';

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liveness/camera/camera_view.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:wakelock_plus_platform_interface/wakelock_plus_platform_interface.dart';

void main() {
  late CameraPlatform originalCameraPlatform;
  late WakelockPlusPlatformInterface originalWakelockPlatform;
  late _FakeCameraPlatform cameraPlatform;

  setUp(() {
    originalCameraPlatform = CameraPlatform.instance;
    originalWakelockPlatform = wakelockPlusPlatformInstance;
    cameraPlatform = _FakeCameraPlatform();
    CameraPlatform.instance = cameraPlatform;
    wakelockPlusPlatformInstance = _FakeWakelockPlatform();
  });

  tearDown(() {
    CameraPlatform.instance = originalCameraPlatform;
    wakelockPlusPlatformInstance = originalWakelockPlatform;
  });

  testWidgets('disposes a camera whose initialization outlives the widget', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    cameraPlatform.initializeGate = Completer<void>();
    var starts = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: CameraView(
          lensDirection: CameraLensDirection.front,
          onCameraStart: () => starts++,
        ),
      ),
    );
    await _flush(tester);
    expect(cameraPlatform.initializeCalls, 1);

    await tester.pumpWidget(const SizedBox());
    cameraPlatform.initializeGate!.complete();
    await _flush(tester);

    expect(starts, 0);
    expect(cameraPlatform.created, 1);
    expect(cameraPlatform.disposed, 1);
    expect(cameraPlatform.liveCameras, isEmpty);
  });

  testWidgets('waits for disposal before creating a resumed camera', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    var starts = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: CameraView(
          lensDirection: CameraLensDirection.front,
          onCameraStart: () => starts++,
        ),
      ),
    );
    await _flush(tester);
    expect(starts, 1);
    expect(cameraPlatform.created, 1);
    expect(cameraPlatform.liveCameras.length, 1);

    cameraPlatform.disposeGate = Completer<void>();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await _flush(tester);
    expect(cameraPlatform.disposeCalls, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _flush(tester);
    expect(cameraPlatform.created, 1);

    cameraPlatform.disposeGate!.complete();
    cameraPlatform.disposeGate = null;
    await _flush(tester);

    expect(cameraPlatform.created, 2);
    expect(cameraPlatform.maxLiveCameras, 1);
    expect(cameraPlatform.liveCameras.length, 1);

    await tester.pumpWidget(const SizedBox());
    await _flush(tester);
    expect(cameraPlatform.liveCameras, isEmpty);
  });

  testWidgets('does not start streaming after the app is paused', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    cameraPlatform.flashGate = Completer<void>();
    var starts = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: CameraView(
          lensDirection: CameraLensDirection.front,
          imageStream: (_) {},
          onCameraStart: () => starts++,
        ),
      ),
    );
    await _flush(tester);
    expect(cameraPlatform.flashCalls, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    cameraPlatform.flashGate!.complete();
    await _flush(tester);

    expect(starts, 0);
    expect(cameraPlatform.streamListens, 0);
    expect(cameraPlatform.disposed, 1);
    expect(cameraPlatform.liveCameras, isEmpty);
  });
}

Future<void> _flush(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump();
  }
}

class _FakeCameraPlatform extends CameraPlatform {
  static const camera = CameraDescription(
    name: 'front',
    lensDirection: CameraLensDirection.front,
    sensorOrientation: 90,
  );

  final liveCameras = <int>{};
  final _initializedEvents = <int, StreamController<CameraInitializedEvent>>{};
  final _errorEvents = <int, StreamController<CameraErrorEvent>>{};
  final _imageStreams = <int, StreamController<CameraImageData>>{};
  Completer<void>? initializeGate;
  Completer<void>? disposeGate;
  Completer<void>? flashGate;
  var created = 0;
  var disposed = 0;
  var disposeCalls = 0;
  var initializeCalls = 0;
  var maxLiveCameras = 0;
  var flashCalls = 0;
  var streamListens = 0;

  @override
  Future<List<CameraDescription>> availableCameras() async => [camera];

  @override
  Future<int> createCameraWithSettings(
    CameraDescription cameraDescription,
    MediaSettings mediaSettings,
  ) async {
    final id = ++created;
    liveCameras.add(id);
    if (liveCameras.length > maxLiveCameras) {
      maxLiveCameras = liveCameras.length;
    }
    _initializedEvents[id] = StreamController.broadcast();
    _errorEvents[id] = StreamController.broadcast();
    return id;
  }

  @override
  Future<void> initializeCamera(
    int cameraId, {
    ImageFormatGroup imageFormatGroup = ImageFormatGroup.unknown,
  }) async {
    initializeCalls++;
    await initializeGate?.future;
    _initializedEvents[cameraId]!.add(
      CameraInitializedEvent(
        cameraId,
        640,
        480,
        ExposureMode.auto,
        true,
        FocusMode.auto,
        true,
      ),
    );
  }

  @override
  Stream<CameraInitializedEvent> onCameraInitialized(int cameraId) =>
      _initializedEvents[cameraId]!.stream;

  @override
  Stream<CameraErrorEvent> onCameraError(int cameraId) =>
      _errorEvents[cameraId]!.stream;

  @override
  Stream<DeviceOrientationChangedEvent> onDeviceOrientationChanged() =>
      const Stream.empty();

  @override
  bool supportsImageStreaming() => true;

  @override
  Stream<CameraImageData> onStreamedFrameAvailable(
    int cameraId, {
    CameraImageStreamOptions? options,
  }) => (_imageStreams[cameraId] ??= StreamController.broadcast(
    onListen: () => streamListens++,
  )).stream;

  @override
  Future<void> setFlashMode(int cameraId, FlashMode mode) async {
    flashCalls++;
    await flashGate?.future;
  }

  @override
  Widget buildPreview(int cameraId) => const SizedBox();

  @override
  Future<void> dispose(int cameraId) async {
    disposeCalls++;
    await disposeGate?.future;
    liveCameras.remove(cameraId);
    disposed++;
    await _initializedEvents.remove(cameraId)?.close();
    _errorEvents.remove(cameraId);
    await _imageStreams.remove(cameraId)?.close();
  }
}

class _FakeWakelockPlatform extends WakelockPlusPlatformInterface {
  @override
  Future<void> toggle({required bool enable}) async {}

  @override
  Future<bool> get enabled async => false;
}
