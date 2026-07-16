import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:liveness/devlog.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class CameraView extends StatefulWidget {
  const CameraView({
    super.key,
    this.flashMode = FlashMode.off,
    this.lensDirection = CameraLensDirection.back,
    this.resolutionPreset = ResolutionPreset.high,
    this.clipBorderRadius = BorderRadius.zero,
    this.imageStream,
    this.onCameraStart,
    this.onCameraStop,
  });

  final CameraLensDirection lensDirection;
  final ResolutionPreset resolutionPreset;
  final FlashMode flashMode;
  final void Function(CameraImage image)? imageStream;
  final VoidCallback? onCameraStart;
  final VoidCallback? onCameraStop;
  final BorderRadiusGeometry clipBorderRadius;

  @override
  State<CameraView> createState() => CameraViewState();
}

class CameraViewState extends State<CameraView> with WidgetsBindingObserver {
  CameraController? _controller;
  Future<void> _cameraTask = Future.value();
  var _wantCamera = true;
  var _didStart = false;
  VoidCallback? _onCameraStop;

  int? get sensorOrientation => _controller?.description.sensorOrientation;

  bool _isCurrent(CameraController controller) =>
      mounted && _wantCamera && identical(_controller, controller);

  Future<void> _initCamera() async {
    CameraController? controller;
    try {
      final cameras = await availableCameras();
      if (!mounted || !_wantCamera) return;

      final camera = cameras.firstWhere(
        (camera) => camera.lensDirection == widget.lensDirection,
      );
      controller = CameraController(
        camera,
        widget.resolutionPreset,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.bgra8888,
      );
      _controller = controller;

      await controller.initialize();
      if (!_isCurrent(controller)) {
        if (identical(_controller, controller)) _controller = null;
        await _disposeController(controller);
        return;
      }

      await controller.setFlashMode(widget.flashMode);
      if (!_isCurrent(controller)) {
        if (identical(_controller, controller)) _controller = null;
        await _disposeController(controller);
        return;
      }

      final imageStream = widget.imageStream;
      if (imageStream != null) await controller.startImageStream(imageStream);

      if (!_isCurrent(controller)) {
        if (identical(_controller, controller)) _controller = null;
        await _disposeController(controller);
        return;
      }

      widget.onCameraStart?.call();
      _didStart = true;
      if (_isCurrent(controller)) setState(() {});
    } catch (e, stackTrace) {
      if (identical(_controller, controller)) _controller = null;
      if (controller != null) await _disposeController(controller);
      if (mounted && _wantCamera) {
        devLog('init camera error', error: e, stackTrace: stackTrace);
      }
    }
  }

  void _scheduleCameraSync() {
    final previousTask = _cameraTask;
    _cameraTask = () async {
      try {
        await previousTask;
        await _syncCamera();
      } catch (e, stackTrace) {
        devLog('camera lifecycle error', error: e, stackTrace: stackTrace);
      }
    }();
  }

  Future<void> _syncCamera() async {
    if (mounted && _wantCamera) {
      if (_controller == null) await _initCamera();
    } else {
      await _stopLiveFeed(rebuild: mounted);
    }
  }

  Future<XFile?> takePicture() async {
    final controller = _controller;
    if (_wantCamera && controller != null && controller.value.isInitialized) {
      if (controller.value.isTakingPicture) return null;
      return controller.takePicture();
    }
    return null;
  }

  @override
  void didUpdateWidget(CameraView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _onCameraStop = widget.onCameraStop;
    final controller = _controller;
    if (_wantCamera &&
        controller != null &&
        controller.value.isInitialized &&
        oldWidget.flashMode != widget.flashMode) {
      unawaited(
        controller.setFlashMode(widget.flashMode).catchError((e, stackTrace) {
          devLog('set flash mode error', error: e, stackTrace: stackTrace);
        }),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    final lifecycleState = WidgetsBinding.instance.lifecycleState;
    _wantCamera =
        lifecycleState == null || lifecycleState == AppLifecycleState.resumed;
    _onCameraStop = widget.onCameraStop;
    unawaited(WakelockPlus.enable());
    WidgetsBinding.instance.addObserver(this);
    _scheduleCameraSync();
  }

  @override
  void dispose() {
    _wantCamera = false;
    _scheduleCameraSync();
    unawaited(WakelockPlus.disable());
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _disposeController(CameraController controller) async {
    try {
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
    } catch (e, stackTrace) {
      devLog('stop camera stream error', error: e, stackTrace: stackTrace);
    }
    try {
      await controller.dispose();
    } catch (e, stackTrace) {
      devLog('dispose camera error', error: e, stackTrace: stackTrace);
    }
  }

  Future<void> _stopLiveFeed({bool rebuild = true}) async {
    final controller = _controller;
    _controller = null;
    final didStart = _didStart;
    _didStart = false;

    if (rebuild && mounted) setState(() {});
    if (controller != null) await _disposeController(controller);
    if (didStart) _onCameraStop?.call();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    final wantCamera = state == AppLifecycleState.resumed;
    if (_wantCamera == wantCamera) return;
    _wantCamera = wantCamera;
    _scheduleCameraSync();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return Container();
    }
    return ClipRRect(
      borderRadius: widget.clipBorderRadius,
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: controller.value.previewSize?.height,
          height: controller.value.previewSize?.width,
          child: CameraPreview(controller),
        ),
      ),
    );
  }
}
