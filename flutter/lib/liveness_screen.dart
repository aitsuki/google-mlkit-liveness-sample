import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:liveness/camera/camera_view.dart';
import 'package:liveness/camera/face_analyzer.dart';

class LivenessScreen extends StatefulWidget {
  const LivenessScreen({super.key});

  @override
  State<LivenessScreen> createState() => _LivenessScreenState();
}

class _LivenessScreenState extends State<LivenessScreen>
    with WidgetsBindingObserver {
  late final FaceAnalyzer _faceAnalyzer;
  final _camera = GlobalKey<CameraViewState>();
  final _livenessPictures = <LivenessStep, XFile>{};
  final _guideText = ValueNotifier("");
  final _errorText = ValueNotifier("");
  var _isBusy = false;

  @override
  void initState() {
    super.initState();
    _faceAnalyzer = FaceAnalyzer(
      cameraKey: _camera,
      statusCallback: (step, error) {
        _guideText.value = switch (step) {
          LivenessStep.front =>
            "Please make sure your face is in the center of the screen",
          LivenessStep.smile => "Please smile",
          LivenessStep.side => "Please slowly turn your head left or right",
          LivenessStep.done => "",
        };

        _errorText.value = switch (error) {
          FaceError.notCenter =>
            "Please move your face to the center of the screen",
          FaceError.tooFar => "Please move closer",
          FaceError.tooClose => "Please move farther away",
          FaceError.multipleFaces =>
            "Multiple faces detected, please ensure only one person is in view",
          FaceError.none => "",
        };
      },
      onCapture: (step, bytes) {
        _livenessPictures[step] = bytes;
      },
      onDone: () {
        _popForResult();
      },
    );
  }

  @override
  void dispose() {
    _faceAnalyzer.dispose();
    super.dispose();
  }

  void _popForResult() async {
    if (_livenessPictures.isEmpty) {
      Navigator.pop(context);
      return;
    }

    final result = <Uint8List>[];
    final files = [
      _livenessPictures[LivenessStep.front],
      _livenessPictures[LivenessStep.smile],
      _livenessPictures[LivenessStep.side],
    ].nonNulls;

    for (final file in files) {
      final bytes = await FlutterImageCompress.compressWithFile(
        file.path,
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
          ValueListenableBuilder<String>(
            valueListenable: _errorText,
            builder: (context, value, child) {
              return Container(
                height: 50,
                alignment: Alignment.center,
                child: Text(value, style: TextStyle(color: Colors.red)),
              );
            },
          ),
          Center(
            child: SizedBox(
              width: 220,
              height: 220,
              child: CameraView(
                key: _camera,
                clipBorderRadius: BorderRadiusGeometry.circular(110),
                lensDirection: CameraLensDirection.front,
                imageStream: (cameraImage) async {
                  if (_isBusy) return;
                  _isBusy = true;
                  await _faceAnalyzer.analyze(cameraImage);
                  _isBusy = false;
                },
                resolutionPreset: ResolutionPreset.medium,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
