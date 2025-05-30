import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:liveness/camera/camera_view.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  final _flashMode = ValueNotifier(FlashMode.off);
  final _image = ValueNotifier<XFile?>(null);
  final _camera = GlobalKey<CameraViewState>();

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black,
      child: Column(
        children: [
          Expanded(
            child: Row(
              children: [
                const SizedBox(width: 16),
                Expanded(
                  child: AspectRatio(
                    aspectRatio: 0.63,
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(
                          width: 4,
                          color: Colors.white,
                          strokeAlign: BorderSide.strokeAlignOutside,
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: ListenableBuilder(
                          listenable: Listenable.merge([_flashMode, _image]),
                          builder: (context, _) {
                            final image = _image.value;
                            if (image != null) {
                              return Image.file(
                                File(image.path),
                                fit: BoxFit.cover,
                              );
                            }
                            return CameraView(
                              key: _camera,
                              flashMode: _flashMode.value,
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.only(left: 8, right: 12),
                  child: const RotatedBox(
                    quarterTurns: 1,
                    child: Text(
                      "请确保证件在方框内",
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(
            color: Colors.white60,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                ValueListenableBuilder(
                  valueListenable: _image,
                  builder: (context, image, _) {
                    return IconButton(
                      onPressed: () {
                        if (image == null) {
                          Navigator.pop(context);
                        } else {
                          _image.value = null;
                        }
                      },
                      icon: image == null
                          ? Icon(Icons.arrow_back_ios)
                          : Icon(Icons.close),
                    );
                  },
                ),
                ValueListenableBuilder(
                  valueListenable: _image,
                  builder: (context, image, _) {
                    return IconButton(
                      onPressed: () async {
                        if (image == null) {
                          _image.value = await _camera.currentState
                              ?.takePicture();
                        } else {
                          final bytes =
                              await FlutterImageCompress.compressWithFile(
                                image.path,
                                minWidth: 1080,
                                minHeight: 1080,
                                quality: 75,
                                rotate: -90,
                                autoCorrectionAngle: true,
                              );
                          if (context.mounted && bytes != null) {
                            Navigator.pop(context, bytes);
                          }
                        }
                      },
                      icon: image == null
                          ? Icon(Icons.camera)
                          : Icon(Icons.check),
                    );
                  },
                ),
                ValueListenableBuilder(
                  valueListenable: _flashMode,
                  builder: (context, flashMode, _) {
                    return IconButton(
                      onPressed: () {
                        if (flashMode == FlashMode.off) {
                          _flashMode.value = FlashMode.always;
                        } else {
                          _flashMode.value = FlashMode.off;
                        }
                      },
                      icon: flashMode == FlashMode.off
                          ? Icon(Icons.flash_off)
                          : Icon(Icons.flash_on),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
