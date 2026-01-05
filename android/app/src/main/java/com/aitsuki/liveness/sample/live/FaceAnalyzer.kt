package com.aitsuki.liveness.sample.live

import android.graphics.Rect
import android.util.Log
import androidx.annotation.OptIn
import androidx.camera.core.ExperimentalGetImage
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageCapture
import androidx.camera.core.ImageCaptureException
import androidx.camera.core.ImageProxy
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.face.FaceDetection
import com.google.mlkit.vision.face.FaceDetectorOptions
import java.io.File.createTempFile
import java.util.concurrent.Executor
import kotlin.math.abs

enum class LiveStep {
    FRONT, SMILE, SIDE, DONE
}

enum class FaceError {
    NOT_CENTER, TOO_FAR, TOO_CLOSE, MULTIPLE_FACES, NONE
}

private class LiveController {
    private var currentStep: LiveStep = LiveStep.FRONT
    private var retryCount = 0
    private val maxRetries = 5

    fun reset() {
        currentStep = LiveStep.FRONT
        retryCount = 0
    }

    fun nextStep() {
        retryCount = 0
        currentStep = when (currentStep) {
            LiveStep.FRONT -> LiveStep.SMILE
            LiveStep.SMILE -> LiveStep.SIDE
            LiveStep.SIDE -> LiveStep.DONE
            else -> LiveStep.DONE
        }
    }

    fun onFailedDetection() {
        retryCount++
        if (retryCount > maxRetries) {
            reset()
        }
    }

    fun getStep() = currentStep
}

class FaceAnalyzer(
    private val imageCapture: ImageCapture,
    private val outputDirectory: java.io.File,
    private val executor: Executor,
    private val onImageCaptured: (LiveStep, String) -> Unit,
    private val onStatusUpdate: (LiveStep, FaceError) -> Unit,
    private val onDone: () -> Unit
) : ImageAnalysis.Analyzer {

    private val controller = LiveController()

    @Volatile
    private var isTaking = false

    private val detector by lazy {
        val options = FaceDetectorOptions.Builder()
            .setPerformanceMode(FaceDetectorOptions.PERFORMANCE_MODE_FAST)
            .setClassificationMode(FaceDetectorOptions.CLASSIFICATION_MODE_ALL)
            .setLandmarkMode(FaceDetectorOptions.LANDMARK_MODE_ALL)
            .setMinFaceSize(0.15f)
            .build()
        FaceDetection.getClient(options)
    }

    private var stepSuccessTime = 0L

    private fun takePicture(step: LiveStep, onResult: (Boolean) -> Unit) {
        isTaking = true
        val outputFile = createTempFile("face_${step.name}_", ".jpg", outputDirectory)
        val outputOptions = ImageCapture.OutputFileOptions.Builder(outputFile).build()

        imageCapture.takePicture(
            outputOptions,
            executor,
            object : ImageCapture.OnImageSavedCallback {
                override fun onImageSaved(outputFileResults: ImageCapture.OutputFileResults) {
                    Log.d("Liveness", "Image captured for step $step: ${outputFile.absolutePath}")
                    onImageCaptured(step, outputFile.absolutePath)
                    isTaking = false
                    onResult(true)
                }

                override fun onError(exception: ImageCaptureException) {
                    Log.e("Liveness", "Image capture failed for step $step", exception)
                    isTaking = false
                    onResult(false)
                }
            }
        )
    }


    private fun handleFailure(step: LiveStep, error: FaceError) {
        stepSuccessTime = 0L
        onStatusUpdate(step, error)
        controller.onFailedDetection()
    }

    @OptIn(ExperimentalGetImage::class)
    override fun analyze(imageProxy: ImageProxy) {
        // 如果正在拍照，跳过分析
        if (isTaking) return imageProxy.close()

        val step = controller.getStep()
        if (step == LiveStep.DONE) return imageProxy.close()
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
                val faceRect = clampRect(face.boundingBox, frameW, frameH)

                // 面部位置 & 距离检测
                if (step == LiveStep.FRONT) {
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
                    LiveStep.FRONT -> yaw in -12.0..12.0 && pitch in -8.0..8.0
                    LiveStep.SMILE -> (face.smilingProbability ?: 0f) > 0.3f
                    LiveStep.SIDE -> yaw < -20 || yaw > 20
                }

                if (success) {
                    val currentTime = System.currentTimeMillis()
                    if (stepSuccessTime == 0L) {
                        stepSuccessTime = currentTime
                    } else {
                        // 检查是否已经持续成功足够长时间
                        val elapsedTime = currentTime - stepSuccessTime
                        val delayTime = when (step) {
                            LiveStep.FRONT -> 1000L
                            LiveStep.SMILE -> 500L
                            LiveStep.SIDE -> 250L
                        }
                        if (elapsedTime >= delayTime && !isTaking) {
                            takePicture(step) { success ->
                                if (success) {
                                    // 拍照成功，进入下一步
                                    controller.nextStep()
                                    if (controller.getStep() == LiveStep.DONE) {
                                        onDone()
                                    }
                                } else {
                                    // 拍照失败，重置成功时间，需要重新满足条件后重拍
                                    Log.w("Liveness", "Photo capture failed for step $step, retrying...")
                                }
                                stepSuccessTime = 0L
                            }
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