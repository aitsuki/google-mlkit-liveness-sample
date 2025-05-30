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

  void _handleImageStream(InputImage image) async {
    if (!_canProcess || _isBusy) return;
    _isBusy = true;
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
      _camera.currentState?.fps ?? 0,
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
              return Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(value, textAlign: TextAlign.center),
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
              ),
            ),
          ),
        ],
      ),
    );
  }
}
