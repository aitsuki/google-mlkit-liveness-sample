import 'dart:math';

import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

const double _yawThreshold = 12.0;
const double _pitchThreshold = 8.0;
const double _rollThreshold = 8.0;
const double _sideFaceYawThreshold = 20.0;

class LivenessUtils {
  LivenessUtils._();

  static bool isFrontFace(Face face) {
    final yaw = face.headEulerAngleY!; // 左右摇头角度
    final pitch = face.headEulerAngleX!; // 上下点头角度
    final roll = face.headEulerAngleZ!; // 旋转角度
    return yaw.abs() < _yawThreshold &&
        pitch.abs() < _pitchThreshold &&
        roll.abs() < _rollThreshold;
  }

  static bool isSideFace(Face face) {
    final yaw = face.headEulerAngleY!; // 左右摇头角度
    final pitch = face.headEulerAngleX!; // 上下点头角度
    final roll = face.headEulerAngleZ!; // 旋转角度
    return (yaw > _sideFaceYawThreshold || yaw < -_sideFaceYawThreshold) &&
        pitch.abs() < _pitchThreshold &&
        roll.abs() < _rollThreshold;
  }

  static bool isMouthOpened(Face face) {
    final left = face.landmarks[FaceLandmarkType.leftMouth]?.position;
    final right = face.landmarks[FaceLandmarkType.rightMouth]?.position;
    final bottom = face.landmarks[FaceLandmarkType.bottomMouth]?.position;

    if (left == null || right == null || bottom == null) {
      return false;
    }
    int a2 = right.squaredDistanceTo(bottom);
    int b2 = left.squaredDistanceTo(bottom);
    int c2 = left.squaredDistanceTo(right);
    double a = sqrt(a2);
    double b = sqrt(b2);
    double gamma = acos((a2 + b2 - c2) / (2 * a * b));
    double gammaDeg = gamma * 180 / pi;
    return gammaDeg < 115;
  }

  /// 远近检测
  /// -1: tooClose
  /// 0: perfect
  /// 1: tooFar
  static int isFaceTooFarOrClose(Face face, int imageWidth, int imageHeight) {
    final boundingBox = face.boundingBox;
    final contours = face.contours[FaceContourType.face];
    final top = contours?.points[0].y ?? boundingBox.top.toInt();
    final bottom = contours?.points[18].y ?? boundingBox.bottom.toInt();
    final left = contours?.points[27].x ?? boundingBox.left.toInt();
    final right = contours?.points[9].x ?? boundingBox.right.toInt();
    final height = bottom - top;
    final width = right - left;
    final widthPercent = width / imageWidth;
    final heightPercent = height / imageHeight;

    if (widthPercent > 0.9 || heightPercent > 0.9) {
      return -1; // too close
    } else if (widthPercent < 0.3 || heightPercent < 0.3) {
      return 1; // too far
    }
    return 0; // perfect
  }

  /// 居中检测
  static bool isFaceInCenter(Face face, int imageWidth, int imageHeight) {
    final boundingBox = face.boundingBox;
    final contours = face.contours[FaceContourType.face];
    final top = contours?.points[0].y ?? boundingBox.top.toInt();
    final bottom = contours?.points[18].y ?? boundingBox.bottom.toInt();
    final left = contours?.points[27].x ?? boundingBox.left.toInt();
    final right = contours?.points[9].x ?? boundingBox.right.toInt();
    final topMargin = max(top, 1);
    final bottomMargin = max(imageHeight - bottom, 1);
    final leftMargin = max(left, 1);
    final rightMargin = max(imageWidth - right, 1);
    final dh = (rightMargin - leftMargin).abs();
    final dv = (bottomMargin - topMargin).abs();
    return !(dh > imageWidth * 0.2 || dv > imageHeight * 0.2);
  }
}
