import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:liveness/camera/liveness_utils.dart';

enum InvalidReason { faceNotCenter, faceTooFar, faceTooClose }

sealed class FrameHandleResult {
  const FrameHandleResult();
}

class Invalid extends FrameHandleResult {
  final InvalidReason reason;
  const Invalid(this.reason);
}

class Valid extends FrameHandleResult {
  const Valid();
}

class Completed extends FrameHandleResult {
  const Completed();
}

abstract class LivenessStateHandler {
  String get stateGuideText;

  FrameHandleResult onFrame(
    Face face,
    int imageWidth,
    int imageHeight,
    int validFrames,
    int framesPerSecond,
  );
}

/// 正面人脸状态处理器
class FrontFaceStateHandler implements LivenessStateHandler {
  @override
  final String stateGuideText;

  FrontFaceStateHandler([
    this.stateGuideText =
        "Please make sure your face is in the center of the screen",
  ]);

  @override
  FrameHandleResult onFrame(
    Face face,
    int imageWidth,
    int imageHeight,
    int validFrames,
    int framesPerSecond,
  ) {
    final farOrClose = LivenessUtils.isFaceTooFarOrClose(
      face,
      imageWidth,
      imageHeight,
    );
    if (farOrClose == -1) {
      return Invalid(InvalidReason.faceTooClose);
    } else if (farOrClose == 1) {
      return Invalid(InvalidReason.faceTooFar);
    }

    if (!LivenessUtils.isFaceInCenter(face, imageWidth, imageHeight)) {
      return Invalid(InvalidReason.faceNotCenter);
    }

    if (LivenessUtils.isFrontFace(face) && validFrames >= 1) {
      return const Completed();
    }
    return const Valid();
  }
}

/// 微笑状态处理器
class SmileStateHandler implements LivenessStateHandler {
  @override
  final String stateGuideText;

  SmileStateHandler([this.stateGuideText = "Please smile"]);

  @override
  FrameHandleResult onFrame(
    Face face,
    int imageWidth,
    int imageHeight,
    int validFrames,
    int framesPerSecond,
  ) {
    final farOrClose = LivenessUtils.isFaceTooFarOrClose(
      face,
      imageWidth,
      imageHeight,
    );
    if (farOrClose == -1) {
      return Invalid(InvalidReason.faceTooClose);
    } else if (farOrClose == 1) {
      return Invalid(InvalidReason.faceTooFar);
    }

    if (!LivenessUtils.isFaceInCenter(face, imageWidth, imageHeight)) {
      return Invalid(InvalidReason.faceNotCenter);
    }

    final smilingProbability = face.smilingProbability ?? 0.0;
    if (smilingProbability > 0.3 && validFrames >= 1) {
      return const Completed();
    }
    return const Valid();
  }
}

/// 侧脸状态处理器
class SideFaceStateHandler implements LivenessStateHandler {
  @override
  final String stateGuideText;

  SideFaceStateHandler([
    this.stateGuideText = "Please slowly turn your head left or right",
  ]);

  @override
  FrameHandleResult onFrame(
    Face face,
    int imageWidth,
    int imageHeight,
    int validFrames,
    int framesPerSecond,
  ) {
    if (LivenessUtils.isSideFace(face) && validFrames >= 1) {
      return const Completed();
    }
    return const Valid();
  }
}

/// 张嘴状态处理器
class MouthOpenStateHandler implements LivenessStateHandler {
  @override
  final String stateGuideText;

  MouthOpenStateHandler([this.stateGuideText = "Please open your mouth"]);

  @override
  FrameHandleResult onFrame(
    Face face,
    int imageWidth,
    int imageHeight,
    int validFrames,
    int framesPerSecond,
  ) {
    final farOrClose = LivenessUtils.isFaceTooFarOrClose(
      face,
      imageWidth,
      imageHeight,
    );
    if (farOrClose == -1) {
      return Invalid(InvalidReason.faceTooClose);
    } else if (farOrClose == 1) {
      return Invalid(InvalidReason.faceTooFar);
    }

    if (LivenessUtils.isMouthOpened(face) && validFrames >= 1) {
      return const Completed();
    }
    return const Valid();
  }
}
