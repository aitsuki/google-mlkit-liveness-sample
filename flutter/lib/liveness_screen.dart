import 'dart:developer';
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:liveness/camera/camera_view.dart';
import 'package:liveness/camera/liveness_state_handle.dart';

class LivenessScreen extends StatefulWidget {
  const LivenessScreen({super.key});

  @override
  State<LivenessScreen> createState() => _LivenessScreenState();
}

class _LivenessScreenState extends State<LivenessScreen>
    with WidgetsBindingObserver {
  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableContours: true,
      enableLandmarks: true,
      enableClassification: true,
      minFaceSize: 0.68,
      enableTracking: false,
      performanceMode: FaceDetectorMode.fast,
    ),
  );
  final _camera = GlobalKey<CameraViewState>();

  bool _canProcess = true;
  bool _isBusy = false;
  int _imageWidth = 0;
  int _imageHeight = 0;

  final _livenessStateHandlers = [
    FrontFaceStateHandler(),
    SmileStateHandler(),
    SideFaceStateHandler(),
    MouthOpenStateHandler(),
  ];

  late LivenessStateHandler _currentStateHandler;
  int _fps = 0;
  int _frameCount = 0;
  DateTime? _lastFrameTimestamp;
  int _emptyFaceFrames = 0;
  int _validStateFrames = 0;
  final _livenessPictures = <XFile>[];
  final _guideText = ValueNotifier("");

  void _popForResult() async {
    if (_livenessPictures.isEmpty) {
      Navigator.pop(context);
      return;
    }

    final result = <Uint8List>[];
    for (var picture in _livenessPictures) {
      final bytes = await FlutterImageCompress.compressWithFile(
        picture.path,
        quality: 75,
        autoCorrectionAngle: true,
      );
      if (!mounted) return;
      if (bytes == null) {
        Navigator.pop(context);
        return;
      }
      result.add(bytes);
    }
    Navigator.pop(context, result);
  }

  void _handleImageStream(CameraImage cameraImage) async {
    if (!_canProcess || _isBusy) return;
    _isBusy = true;

    // --- FPS 计算开始 ---
    final now = DateTime.now();
    _frameCount++;
    if (_lastFrameTimestamp != null &&
        now.difference(_lastFrameTimestamp!).inSeconds >= 1) {
      _fps = _frameCount;
      _frameCount = 0;
      _lastFrameTimestamp = now;
      log("FPS: $_fps");
    }
    // --- FPS 计算结束 ---

    final image = _inputImageFromCameraImage(cameraImage);
    if (image == null) {
      _isBusy = false;
      return;
    }

    if (_imageHeight == 0 || _imageHeight == 0) {
      final imageSize = image.metadata.size;
      final rotatiton = image.metadata.rotation;
      switch (rotatiton) {
        case InputImageRotation.rotation180deg:
        case InputImageRotation.rotation0deg:
          _imageWidth = imageSize.width.toInt();
          _imageHeight = imageSize.height.toInt();
          break;
        case InputImageRotation.rotation270deg:
        case InputImageRotation.rotation90deg:
          _imageWidth = imageSize.height.toInt();
          _imageHeight = imageSize.width.toInt();
          break;
      }
    }

    final faces = await _faceDetector.processImage(image);
    if (faces.isEmpty) {
      _emptyFaceFrames++;
      if (_emptyFaceFrames >= 10) {
        _resetStateHandler();
      }
      _isBusy = false;
      return;
    }
    _emptyFaceFrames = 0;

    final face = faces.first;
    final handleResult = _currentStateHandler.onFrame(
      face,
      _imageWidth,
      _imageHeight,
      _validStateFrames,
      _fps.clamp(0, 60),
    );

    if (handleResult is Valid) {
      _validStateFrames++;
    } else {
      _validStateFrames = 0;
    }

    _guideText.value = switch (handleResult) {
      Invalid() => switch (handleResult.reason) {
        InvalidReason.faceNotCenter => "Face not center",
        InvalidReason.faceTooFar => "Too far",
        InvalidReason.faceTooClose => "Too close",
      },
      _ => _currentStateHandler.stateGuideText,
    };

    if (handleResult is Completed) {
      final picture = await _camera.currentState?.takePicture();
      if (mounted && picture != null) {
        _livenessPictures.add(picture);
        final index = _livenessStateHandlers.indexOf(_currentStateHandler);
        final nextHandler = _livenessStateHandlers.elementAtOrNull(index + 1);
        if (nextHandler == null) {
          _canProcess = false;
          _popForResult();
        } else {
          _emptyFaceFrames = 0;
          _validStateFrames = 0;
          _currentStateHandler = nextHandler;
        }
      }
    }

    _isBusy = false;
  }

  void _resetStateHandler() {
    _emptyFaceFrames = 0;
    _validStateFrames = 0;
    _livenessPictures.clear();
    _currentStateHandler = _livenessStateHandlers.first;
  }

  InputImage? _inputImageFromCameraImage(CameraImage image) {
    // get image rotation
    // it is used in android to convert the InputImage from Dart to Java: https://github.com/flutter-ml/google_ml_kit_flutter/blob/master/packages/google_mlkit_commons/android/src/main/java/com/google_mlkit_commons/InputImageConverter.java
    // `rotation` is not used in iOS to convert the InputImage from Dart to Obj-C: https://github.com/flutter-ml/google_ml_kit_flutter/blob/master/packages/google_mlkit_commons/ios/Classes/MLKVisionImage%2BFlutterPlugin.m
    // in both platforms `rotation` and `camera.lensDirection` can be used to compensate `x` and `y` coordinates on a canvas: https://github.com/flutter-ml/google_ml_kit_flutter/blob/master/packages/example/lib/vision_detector_views/painters/coordinates_translator.dart
    final sensorOrientation = _camera.currentState?.sensorOrientation;
    if (sensorOrientation == null) return null;
    InputImageRotation? rotation = InputImageRotationValue.fromRawValue(
      sensorOrientation,
    );
    if (rotation == null) return null;

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
  void initState() {
    super.initState();
    _currentStateHandler = _livenessStateHandlers.first;
  }

  @override
  void dispose() {
    _canProcess = false;
    _faceDetector.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ValueListenableBuilder<String>(
            valueListenable: _guideText,
            builder: (context, value, child) {
              return Container(
                height: 50,
                alignment: Alignment.center,
                child: Text(value),
              );
            },
          ),
          Center(
            child: SizedBox(
              width: 220,
              height: 220,
              child: CameraView(
                key: _camera,
                lensDirection: CameraLensDirection.front,
                imageStream: _handleImageStream,
                resolutionPreset: ResolutionPreset.medium,
                onCameraStart: () {
                  _lastFrameTimestamp = DateTime.now();
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
