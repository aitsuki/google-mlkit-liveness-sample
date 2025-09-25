import 'dart:developer';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
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

  int? get sensorOrientation => _controller?.description.sensorOrientation;

  void _initController(CameraDescription camera) async {
    _controller = CameraController(
      camera,
      ResolutionPreset.medium,
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
      if (widget.imageStream != null) {
        _controller!.startImageStream(widget.imageStream!);
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
    _stopLiveFeed().then((_) {
      widget.onCameraStop?.call();
      WakelockPlus.disable();
      WidgetsBinding.instance.removeObserver(this);
    });
    super.dispose();
  }

  Future<void> _stopLiveFeed() async {
    if (_controller != null) {
      if (widget.imageStream != null) {
        await _controller!.stopImageStream();
      }
      await _controller!.dispose();
      _controller = null;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    final CameraController? controller = _controller;
    if (state == AppLifecycleState.inactive) {
      if (controller != null && controller.value.isInitialized) {
        _stopLiveFeed().then((_) {
          widget.onCameraStop?.call();
        });
      }
    } else if (state == AppLifecycleState.resumed) {
      if (_controller == null) {
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
}
