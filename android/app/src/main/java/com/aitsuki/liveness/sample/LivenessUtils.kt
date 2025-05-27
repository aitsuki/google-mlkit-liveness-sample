package com.aitsuki.liveness.sample

import android.graphics.PointF
import com.google.mlkit.vision.face.Face
import com.google.mlkit.vision.face.FaceContour
import com.google.mlkit.vision.face.FaceLandmark
import kotlin.math.abs
import kotlin.math.acos
import kotlin.math.sqrt


object LivenessUtils {

    private const val YAW_THRESHOLD = 12f
    private const val PITCH_THRESHOLD = 8f
    private const val ROLL_THRESHOLD = 8f
    private const val SIDE_FACE_YAW_THRESHOLD = 20f

    fun isFrontFace(face: Face): Boolean {
        val yaw = face.headEulerAngleY // 左右摇头角度
        val pitch = face.headEulerAngleX // 上下点头角度
        val roll = face.headEulerAngleZ // 旋转角度
        return yaw < YAW_THRESHOLD && yaw > -YAW_THRESHOLD
                && pitch < PITCH_THRESHOLD && pitch > -PITCH_THRESHOLD
                && roll < ROLL_THRESHOLD && roll > -ROLL_THRESHOLD
    }

    fun isSideFace(face: Face): Boolean {
        val yaw = face.headEulerAngleY // 左右摇头角度
        val pitch = face.headEulerAngleX // 上下点头角度
        val roll = face.headEulerAngleZ // 旋转角度
        return (yaw > SIDE_FACE_YAW_THRESHOLD || yaw < -SIDE_FACE_YAW_THRESHOLD)
                && pitch < PITCH_THRESHOLD && pitch > -PITCH_THRESHOLD
                && roll < ROLL_THRESHOLD && roll > -ROLL_THRESHOLD
    }

    fun isMouthOpened(face: Face): Boolean {
        val left = face.getLandmark(FaceLandmark.MOUTH_LEFT)?.position ?: return false
        val right = face.getLandmark(FaceLandmark.MOUTH_RIGHT)?.position ?: return false
        val bottom = face.getLandmark(FaceLandmark.MOUTH_BOTTOM)?.position ?: return false

        // Square of lengths be a2, b2, c2
        val a2 = lengthSquare(right, bottom)
        val b2 = lengthSquare(left, bottom)
        val c2 = lengthSquare(left, right)

        // length of sides be a, b, c
        val a = sqrt(a2)
        val b = sqrt(b2)

        // From Cosine law
        val gamma = acos((a2 + b2 - c2) / (2 * a * b))

        // Converting to degrees
        val gammaDeg = gamma * 180 / Math.PI
        return gammaDeg < 115f
    }

    private fun lengthSquare(a: PointF, b: PointF): Float {
        val x = a.x - b.x
        val y = a.y - b.y
        return x * x + y * y
    }

    /**
     * 远近检测
     * -1: tooClose
     * 0: perfect
     * 1: tooFar
     */
    fun isFaceTooFarOrClose(face: Face, imageWidth: Int, imageHeight: Int): Int {
        val boundingBox = face.boundingBox
        val contours = face.getContour(FaceContour.FACE)
        val top = contours?.points?.getOrNull(0)?.y?.toInt() ?: boundingBox.top
        val bottom = contours?.points?.getOrNull(18)?.y?.toInt() ?: boundingBox.bottom
        val left = contours?.points?.getOrNull(27)?.x?.toInt() ?: boundingBox.left
        val right = contours?.points?.getOrNull(9)?.x?.toInt() ?: boundingBox.right
        val height = bottom - top
        val width = right - left
        val widthPercent = width.toFloat() / imageWidth
        val heightPercent = height.toFloat() / imageHeight
        if (widthPercent > 0.8f || heightPercent > 0.8f) {
            return -1
        } else if (widthPercent < 0.3f || heightPercent < 0.3f) {
            return 1
        }
        return 0
    }

    /**
     * 居中检测
     */
    fun isFaceInCenter(face: Face, imageWidth: Int, imageHeight: Int): Boolean {
        val boundingBox = face.boundingBox
        val contours = face.getContour(FaceContour.FACE)
        val top = contours?.points?.getOrNull(0)?.y?.toInt() ?: boundingBox.top
        val bottom = contours?.points?.getOrNull(18)?.y?.toInt() ?: boundingBox.bottom
        val left = contours?.points?.getOrNull(27)?.x?.toInt() ?: boundingBox.left
        val right = contours?.points?.getOrNull(9)?.x?.toInt() ?: boundingBox.right
        val topMargin = top.coerceAtLeast(1)
        val bottomMargin = (imageHeight - bottom).coerceAtLeast(1)
        val leftMargin = left.coerceAtLeast(1)
        val rightMargin = (imageWidth - right).coerceAtLeast(1)
        val dh = abs(rightMargin - leftMargin)
        val dv = abs(bottomMargin - topMargin)
        return !(dh > imageWidth * 0.2f || dv > imageHeight * 0.2f)
    }
}