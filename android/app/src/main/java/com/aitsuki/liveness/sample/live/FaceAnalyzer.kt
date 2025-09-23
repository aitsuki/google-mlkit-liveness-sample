package com.aitsuki.liveness.sample.live

import android.graphics.Bitmap
import android.graphics.Matrix
import android.graphics.Rect
import androidx.annotation.OptIn
import androidx.camera.core.ExperimentalGetImage
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.face.FaceDetection
import com.google.mlkit.vision.face.FaceDetectorOptions
import kotlin.math.abs

enum class LivenessStep {
    FRONT, SMILE, SIDE, DONE
}

enum class FaceError {
    NOT_CENTER, TOO_FAR, TOO_CLOSE, MULTIPLE_FACES, NONE
}

private class LivenessController {
    private var currentStep: LivenessStep = LivenessStep.FRONT
    private var retryCount = 0
    private val maxRetries = 5

    fun reset() {
        currentStep = LivenessStep.FRONT
        retryCount = 0
    }

    fun nextStep() {
        retryCount = 0
        currentStep = when (currentStep) {
            LivenessStep.FRONT -> LivenessStep.SMILE
            LivenessStep.SMILE -> LivenessStep.SIDE
            LivenessStep.SIDE -> LivenessStep.DONE
            else -> LivenessStep.DONE
        }
    }

    fun onFailedDetection(): Boolean {
        retryCount++
        return if (retryCount > maxRetries) {
            reset()
            true
        } else false
    }

    fun getStep() = currentStep
}

class FaceAnalyzer(
    private val onCapture: (Bitmap, LivenessStep) -> Unit,
    private val onStatusUpdate: (LivenessStep, FaceError) -> Unit,
    private val onDone: () -> Unit
) : ImageAnalysis.Analyzer {

    private val controller = LivenessController()

    private val detector by lazy {
        val options = FaceDetectorOptions.Builder()
            .setPerformanceMode(FaceDetectorOptions.PERFORMANCE_MODE_FAST)
            .setClassificationMode(FaceDetectorOptions.CLASSIFICATION_MODE_ALL)
            .setLandmarkMode(FaceDetectorOptions.LANDMARK_MODE_ALL)
            .setMinFaceSize(0.7f)
            .build()
        FaceDetection.getClient(options)
    }

    private var stepSuccessTime = 0L

    private fun handleFailure(step: LivenessStep,  error: FaceError) {
        stepSuccessTime = 0L
        onStatusUpdate(step, error)
        controller.onFailedDetection()
    }

    @OptIn(ExperimentalGetImage::class)
    override fun analyze(imageProxy: ImageProxy) {
        val step = controller.getStep()
        if (step == LivenessStep.DONE) return imageProxy.close()
        val mediaImage = imageProxy.image ?: return imageProxy.close()
        val rotation = imageProxy.imageInfo.rotationDegrees
        val reverseWH = rotation == 90 || rotation == 270
        val inputImage = InputImage.fromMediaImage(mediaImage, rotation)
        val frameW = if (reverseWH) inputImage.height else inputImage.width
        val frameH = if (reverseWH) inputImage.width else inputImage.height

        detector.process(inputImage)
            .addOnSuccessListener { faces ->
                // 多人脸 / 无人脸
                if (faces.isEmpty()) {
                    handleFailure(step, FaceError.NONE)
                    return@addOnSuccessListener
                } else if (faces.size > 1) {
                    handleFailure(step, FaceError.MULTIPLE_FACES)
                    return@addOnSuccessListener
                }

                val face = faces[0]
                val faceRect = clampRect(face.boundingBox, frameW, frameH).insetPercent(0.1f)

                // 面部位置 & 距离检测
                if (step == LivenessStep.FRONT) {
                    val faceDistance = computeFrontFaceDistance(faceRect, frameW, frameH)
                    if (faceDistance == FaceDistance.TOO_FAR) {
                        handleFailure(step, FaceError.TOO_FAR)
                        return@addOnSuccessListener
                    } else if (faceDistance == FaceDistance.TOO_CLOSE) {
                        handleFailure(step, FaceError.TOO_CLOSE)
                        return@addOnSuccessListener
                    }

                    val facePosition = computeFrontFacePosition(faceRect, frameW, frameH)
                    if (facePosition != FacePosition.CENTERED) {
                        handleFailure(step, FaceError.NOT_CENTER)
                        return@addOnSuccessListener
                    }
                }

                onStatusUpdate(step, FaceError.NONE)

                val yaw = face.headEulerAngleY // 左右摇头角度
                val pitch = face.headEulerAngleX // 上下点头角度

                val success = when (step) {
                    LivenessStep.FRONT -> yaw in -12.0..12.0 && pitch in -8.0..8.0
                    LivenessStep.SMILE -> (face.smilingProbability ?: 0f) > 0.3f
                    LivenessStep.SIDE -> yaw < -20 || yaw > 20
                    else -> false
                }

                if (success) {
                    val currentTime = System.currentTimeMillis()
                    if (stepSuccessTime == 0L) {
                        stepSuccessTime = currentTime
                    } else {
                        // 检查是否已经持续成功足够长时间
                        val elapsedTime = currentTime - stepSuccessTime
                        val delayTime = when (step) {
                            LivenessStep.FRONT -> 1000L
                            LivenessStep.SMILE -> 500L
                            LivenessStep.SIDE -> 250L
                            else -> 0L
                        }
                        if (elapsedTime >= delayTime) {
                            val bitmap = imageProxy.toRotatedBitmap()
                            onCapture(bitmap, step)
                            controller.nextStep()
                            if (controller.getStep() == LivenessStep.DONE) {
                                onDone()
                            }
                            stepSuccessTime = 0L
                        }
                    }
                } else {
                    stepSuccessTime = 0L
                }
            }
            .addOnFailureListener { controller.onFailedDetection() }
            .addOnCompleteListener { imageProxy.close() }
    }
}

fun ImageProxy.toRotatedBitmap(): Bitmap {
    val bitmap = this.toBitmap()
    val rotationDegrees = this.imageInfo.rotationDegrees
    if (rotationDegrees == 0) return bitmap
    val matrix = Matrix().apply { postRotate(rotationDegrees.toFloat()) }
    return Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
}

private fun Rect.insetPercent(p: Float): Rect {
    val dx = (width() * p).toInt()
    val dy = (height() * p).toInt()
    return Rect(left + dx, top + dy, right - dx, bottom - dy)
}

private fun clampRect(r: Rect, maxW: Int, maxH: Int): Rect {
    val l = r.left.coerceIn(0, maxW)
    val t = r.top.coerceIn(0, maxH)
    val rr = r.right.coerceIn(0, maxW)
    val bb = r.bottom.coerceIn(0, maxH)
    return Rect(l, t, rr, bb)
}

private enum class FaceDistance {
    TOO_CLOSE, OK, TOO_FAR
}

private fun computeFrontFaceDistance(faceRect: Rect, frameW: Int, frameH: Int): FaceDistance {
    // 面积检测（远近检测）, 经测试，正脸面对屏幕时，面积大于0.36表示摄像机太近，小于0.12表示摄像头过远
    val tooCloseRatio = 0.36f
    val tooFarRatio = 0.12f
    val faceRatio = (faceRect.width().toFloat() * faceRect.height()) / (frameW.toFloat() * frameH)
    return if (faceRatio > tooCloseRatio) {
        FaceDistance.TOO_CLOSE
    } else if (faceRatio < tooFarRatio) {
        FaceDistance.TOO_FAR
    } else {
        FaceDistance.OK
    }
}

private enum class FacePosition {
    TOP_LEFT, TOP_RIGHT, BOTTOM_LEFT, BOTTOM_RIGHT, CENTERED
}

private fun computeFrontFacePosition(faceRect: Rect, frameW: Int, frameH: Int): FacePosition {
    // 经测试，正脸面对屏幕时，人脸贴近边缘时的值大概是0.15f
    val centerToleranceX = 0.15f
    val centerToleranceY = 0.15f

    val cx = faceRect.centerX().toFloat()
    val cy = faceRect.centerY().toFloat()
    val dxRatio = (cx - frameW / 2f) / frameW
    val dyRatio = (cy - frameH / 2f) / frameH

    val position = if (abs(dxRatio) <= centerToleranceX && abs(dyRatio) <= centerToleranceY) {
        FacePosition.CENTERED
    } else if (dxRatio < 0 && dyRatio < 0) {
        FacePosition.TOP_LEFT
    } else if (dxRatio > 0 && dyRatio < 0) {
        FacePosition.TOP_RIGHT
    } else if (dxRatio < 0 && dyRatio > 0) {
        FacePosition.BOTTOM_LEFT
    } else {
        FacePosition.BOTTOM_RIGHT
    }
    return position
}