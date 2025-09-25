import 'dart:developer';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:liveness/camera/camera_view.dart';
import 'package:liveness/camera/nv21.dart';

enum LivenessStep { front, smile, side, done }

enum FaceError { notCenter, tooFar, tooClose, multipleFaces, none }

class _LivenessController {
  var _currentStep = LivenessStep.front;
  var _retryCount = 0;
  final _maxRetries = 5;

  LivenessStep get step => _currentStep;

  void reset() {
    _currentStep = LivenessStep.front;
    _retryCount = 0;
  }

  void nextStep() {
    _retryCount = 0;
    _currentStep = switch (_currentStep) {
      LivenessStep.front => LivenessStep.smile,
      LivenessStep.smile => LivenessStep.side,
      LivenessStep.side => LivenessStep.done,
      LivenessStep.done => LivenessStep.done,
    };
  }

  void onFailedDetection() {
    _retryCount++;
    if (_retryCount > _maxRetries) {
      reset();
    }
  }
}

class FaceAnalyzer {
  final Function(LivenessStep step, FaceError error) statusCallback;
  final Function(LivenessStep step, XFile file) onCapture;
  final VoidCallback onDone;

  final _controller = _LivenessController();
  final GlobalKey<CameraViewState> cameraKey;

  final _dector = FaceDetector(
    options: FaceDetectorOptions(
      enableContours: false,
      enableLandmarks: false,
      enableClassification: true,
      minFaceSize: 0.15,
      enableTracking: false,
      performanceMode: FaceDetectorMode.fast,
    ),
  );

  FaceAnalyzer({
    required this.cameraKey,
    required this.statusCallback,
    required this.onCapture,
    required this.onDone,
  });

  var _stepSuccessTime = 0;

  void handleFailure(LivenessStep step, FaceError error) {
    _stepSuccessTime = 0;
    statusCallback(step, error);
    _controller.onFailedDetection();
  }

  Future<void> analyze(CameraImage cameraImage) async {
    final step = _controller.step;
    if (step == LivenessStep.done) return;
    final inputImage = _inputImageFromCameraImage(cameraImage);
    if (inputImage == null) {
      handleFailure(step, FaceError.none);
      return;
    }

    final faces = await _dector.processImage(inputImage);
    if (faces.isEmpty) {
      handleFailure(step, FaceError.none);
      return;
    } else if (faces.length > 1) {
      handleFailure(step, FaceError.multipleFaces);
      return;
    }

    final rotation = inputImage.metadata.rotation;
    final imageSize = inputImage.metadata.size;
    final reverseWH =
        rotation == InputImageRotation.rotation90deg ||
        rotation == InputImageRotation.rotation270deg;
    final frameW = reverseWH ? imageSize.height : imageSize.width;
    final frameH = reverseWH ? imageSize.width : imageSize.height;

    final face = faces.first;
    final faceRect = clampRect(face.boundingBox, frameH, frameH);

    // 面部位置 & 距离检测
    if (step == LivenessStep.front) {
      final distanceError = _detectFaceDistance(faceRect, frameW, frameH);
      if (distanceError != FaceError.none) {
        handleFailure(step, distanceError);
        return;
      }

      final positionError = _detectFacePosition(faceRect, frameW, frameH);
      if (positionError != FaceError.none) {
        handleFailure(step, positionError);
        return;
      }
    }

    statusCallback(step, FaceError.none);

    final yaw = face.headEulerAngleY ?? 0.0;
    final pitch = face.headEulerAngleZ ?? 0.0;

    final success = switch (step) {
      LivenessStep.front =>
        yaw >= -12.0 && yaw <= 12.0 && pitch >= -8.0 && pitch <= 8.0,
      LivenessStep.smile => (face.smilingProbability ?? 0.0) > 0.3,
      LivenessStep.side => yaw < -20.0 || yaw > 20.0,
      LivenessStep.done => false,
    };

    if (success) {
      final now = DateTime.now().millisecondsSinceEpoch;
      if (_stepSuccessTime == 0) {
        _stepSuccessTime = now;
      } else {
        final elapsedTime = now - _stepSuccessTime;
        final delayTime = switch (step) {
          LivenessStep.front => 800,
          LivenessStep.smile => 300,
          LivenessStep.side => 100,
          LivenessStep.done => 0,
        };
        if (elapsedTime >= delayTime) {
          _stepSuccessTime = 0;
          final file = await _capturePhoto();
          if (file == null) return;
          onCapture(step, file);
          _controller.nextStep();
          if (_controller.step == LivenessStep.done) {
            onDone();
          }
        }
      }
    } else {
      _stepSuccessTime = 0;
    }
  }

  Future<XFile?> _capturePhoto() async {
    try {
      return cameraKey.currentState?.takePicture();
    } catch (e) {
      log('Error capturing photo', error: e);
    }
    return null;
  }

  void dispose() {
    _dector.close();
  }

  FaceError _detectFaceDistance(Rect faceRect, double frameW, double frameH) {
    final faceRatio = (faceRect.width * faceRect.height) / (frameW * frameH);
    final tooCloseRatio = 0.36;
    final tooFarRatio = 0.12;
    if (faceRatio > tooCloseRatio) {
      return FaceError.tooClose;
    } else if (faceRatio < tooFarRatio) {
      return FaceError.tooFar;
    }
    return FaceError.none;
  }

  FaceError _detectFacePosition(Rect faceRect, double frameW, double frameH) {
    final centerTolerance = 0.15;
    final center = faceRect.center;
    final dxRatio = (center.dx - frameW / 2) / frameW;
    final dyRatio = (center.dy - frameH / 2) / frameH;
    if (dxRatio.abs() > centerTolerance || dyRatio.abs() > centerTolerance) {
      return FaceError.notCenter;
    }
    return FaceError.none;
  }

  Rect clampRect(Rect r, double frameW, double frameH) {
    final l = r.left.clamp(0, frameW).toDouble();
    final t = r.top.clamp(0, frameH).toDouble();
    final rr = r.right.clamp(0, frameW).toDouble();
    final bb = r.bottom.clamp(0, frameH).toDouble();
    return Rect.fromLTRB(l, t, rr, bb);
  }

  InputImage? _inputImageFromCameraImage(CameraImage image) {
    // get image rotation
    // it is used in android to convert the InputImage from Dart to Java: https://github.com/flutter-ml/google_ml_kit_flutter/blob/master/packages/google_mlkit_commons/android/src/main/java/com/google_mlkit_commons/InputImageConverter.java
    // `rotation` is not used in iOS to convert the InputImage from Dart to Obj-C: https://github.com/flutter-ml/google_ml_kit_flutter/blob/master/packages/google_mlkit_commons/ios/Classes/MLKVisionImage%2BFlutterPlugin.m
    // in both platforms `rotation` and `camera.lensDirection` can be used to compensate `x` and `y` coordinates on a canvas: https://github.com/flutter-ml/google_ml_kit_flutter/blob/master/packages/example/lib/vision_detector_views/painters/coordinates_translator.dart
    final sensorOrientation = cameraKey.currentState?.sensorOrientation;
    if (sensorOrientation == null) return null;
    InputImageRotation? rotation = InputImageRotationValue.fromRawValue(
      sensorOrientation,
    );
    if (rotation == null) return null;

    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null) return null;

    Uint8List? bytes;
    if (format == InputImageFormat.yuv420 ||
        format == InputImageFormat.yuv_420_888) {
      if (image.planes.length != 3) return null;
      bytes = image.getNv21Uint8List();
    } else if (format == InputImageFormat.nv21 ||
        format == InputImageFormat.bgra8888) {
      bytes = image.planes.first.bytes;
    }

    if (bytes == null) return null;
    // compose InputImage using bytes
    return InputImage.fromBytes(
      bytes: bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation, // used only in Android
        format: format, // used only in iOS
        bytesPerRow: image.planes.first.bytesPerRow, // used only in iOS
      ),
    );
  }
}
