import 'dart:developer';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class CameraView extends StatefulWidget {
  const CameraView({
    super.key,
    this.flashMode = FlashMode.off,
    this.lensDirection = CameraLensDirection.back,
    this.imageStream,
    this.onCameraStart,
    this.onCameraStop,
  });

  final CameraLensDirection lensDirection;
  final FlashMode flashMode;
  final void Function(InputImage image)? imageStream;
  final VoidCallback? onCameraStart;
  final VoidCallback? onCameraStop;

  @override
  State<CameraView> createState() => CameraViewState();
}

class CameraViewState extends State<CameraView> with WidgetsBindingObserver {
  CameraController? _controller;
  int _fps = 0;
  int _frameCount = 0;
  DateTime? _lastTimestamp;

  int get fps => _fps;

  void _initController(CameraDescription camera) async {
    _controller = CameraController(
      camera,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.nv21
          : ImageFormatGroup.bgra8888,
    );
    try {
      await _controller!.initialize();
      if (!mounted) return;
      widget.onCameraStart?.call();
      _controller!.setFlashMode(widget.flashMode);
      _lastTimestamp = DateTime.now();
      if (widget.imageStream != null) {
        _controller!.startImageStream((image) {
          // --- FPS 计算开始 ---
          final now = DateTime.now();
          _frameCount++;
          if (_lastTimestamp != null &&
              now.difference(_lastTimestamp!).inSeconds >= 1) {
            _fps = _frameCount;
            _frameCount = 0;
            _lastTimestamp = now;
            log("FPS: $_fps");
          }
          // --- FPS 计算结束 ---

          final inputImage = _inputImageFromCameraImage(image);
          if (inputImage != null) {
            widget.imageStream!(inputImage);
          }
        });
      }
      setState(() {});
    } catch (e) {
      log("init controller error", error: e);
    }
  }

  void _initCamera() async {
    try {
      final cameras = await availableCameras();
      final camera = cameras.firstWhere(
        (camera) => camera.lensDirection == widget.lensDirection,
      );
      _initController(camera);
    } catch (e) {
      log("init camera error", error: e);
    }
  }

  Future<XFile?> takePicture() async {
    final controller = _controller;
    if (controller != null && controller.value.isInitialized) {
      if (controller.value.isTakingPicture) {
        return null;
      }
      return controller.takePicture();
    }
    return null;
  }

  InputImage? _inputImageFromCameraImage(CameraImage image) {
    if (_controller == null) return null;

    // get image rotation
    // it is used in android to convert the InputImage from Dart to Java: https://github.com/flutter-ml/google_ml_kit_flutter/blob/master/packages/google_mlkit_commons/android/src/main/java/com/google_mlkit_commons/InputImageConverter.java
    // `rotation` is not used in iOS to convert the InputImage from Dart to Obj-C: https://github.com/flutter-ml/google_ml_kit_flutter/blob/master/packages/google_mlkit_commons/ios/Classes/MLKVisionImage%2BFlutterPlugin.m
    // in both platforms `rotation` and `camera.lensDirection` can be used to compensate `x` and `y` coordinates on a canvas: https://github.com/flutter-ml/google_ml_kit_flutter/blob/master/packages/example/lib/vision_detector_views/painters/coordinates_translator.dart
    final camera = _controller!.description;
    final sensorOrientation = camera.sensorOrientation;
    // print(
    //     'lensDirection: ${camera.lensDirection}, sensorOrientation: $sensorOrientation, ${_controller?.value.deviceOrientation} ${_controller?.value.lockedCaptureOrientation} ${_controller?.value.isCaptureOrientationLocked}');
    InputImageRotation? rotation;
    if (Platform.isIOS) {
      rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
    } else if (Platform.isAndroid) {
      var rotationCompensation = switch (_controller!.value.deviceOrientation) {
        DeviceOrientation.portraitUp => 0,
        DeviceOrientation.landscapeLeft => 90,
        DeviceOrientation.portraitDown => 180,
        DeviceOrientation.landscapeRight => 270,
      };

      if (camera.lensDirection == CameraLensDirection.front) {
        // front-facing
        rotationCompensation = (sensorOrientation + rotationCompensation) % 360;
      } else {
        // back-facing
        rotationCompensation =
            (sensorOrientation - rotationCompensation + 360) % 360;
      }
      rotation = InputImageRotationValue.fromRawValue(rotationCompensation);
      // print('rotationCompensation: $rotationCompensation');
    }
    if (rotation == null) return null;
    // print('final rotation: $rotation');

    // get image format
    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    // validate format depending on platform
    // only supported formats:
    // * nv21 for Android
    // * bgra8888 for iOS
    if (format == null ||
        (Platform.isAndroid && format != InputImageFormat.nv21) ||
        (Platform.isIOS && format != InputImageFormat.bgra8888)) {
      return null;
    }

    // since format is constraint to nv21 or bgra8888, both only have one plane
    if (image.planes.length != 1) return null;
    final plane = image.planes.first;

    // compose InputImage using bytes
    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation, // used only in Android
        format: format, // used only in iOS
        bytesPerRow: plane.bytesPerRow, // used only in iOS
      ),
    );
  }

  @override
  void didUpdateWidget(CameraView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final controller = _controller;
    if (controller != null && controller.value.isInitialized) {
      if (oldWidget.flashMode != widget.flashMode) {
        controller.setFlashMode(oldWidget.flashMode);
      }
    }
  }

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
  }

  @override
  void dispose() {
    _stopLiveFeed();
    widget.onCameraStop?.call();
    WakelockPlus.disable();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _stopLiveFeed() async {
    if (widget.imageStream != null) {
      await _controller?.stopImageStream();
    }
    await _controller?.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    final CameraController? controller = _controller;
    if (state == AppLifecycleState.inactive) {
      if (controller != null && controller.value.isInitialized) {
        _stopLiveFeed();
        widget.onCameraStop?.call();
      }
    } else if (state == AppLifecycleState.resumed) {
      if (_controller == null || !_controller!.value.isInitialized) {
        _initCamera();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final CameraController? controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return Container();
    } else {
      return ClipRect(
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
}
