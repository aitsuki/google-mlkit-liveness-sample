package com.aitsuki.liveness.sample

import android.app.Application
import android.util.Log
import androidx.annotation.OptIn
import androidx.camera.core.CameraControl
import androidx.camera.core.CameraSelector.DEFAULT_FRONT_CAMERA
import androidx.camera.core.ExperimentalGetImage
import androidx.camera.core.FocusMeteringAction
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageCapture
import androidx.camera.core.ImageCapture.OnImageSavedCallback
import androidx.camera.core.ImageCaptureException
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import androidx.camera.core.SurfaceOrientedMeteringPointFactory
import androidx.camera.core.SurfaceRequest
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.lifecycle.awaitInstance
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.geometry.Offset
import androidx.core.content.ContextCompat
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.LifecycleOwner
import com.google.mlkit.common.MlKitException
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.face.Face
import com.google.mlkit.vision.face.FaceDetection
import com.google.mlkit.vision.face.FaceDetectorOptions
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import java.io.File
import java.util.Timer
import java.util.TimerTask

class LivenessViewModel(application: Application) : AndroidViewModel(application) {

    var guideText by mutableStateOf("")
        private set

    // Used to set up a link between the Camera and your UI.
    private val _surfaceRequest = MutableStateFlow<SurfaceRequest?>(null)
    val surfaceRequest: StateFlow<SurfaceRequest?> = _surfaceRequest
    private var surfaceMeteringPointFactory: SurfaceOrientedMeteringPointFactory? = null
    private var cameraControl: CameraControl? = null

    private val previewUseCase = Preview.Builder().build().apply {
        setSurfaceProvider { newSurfaceRequest ->
            _surfaceRequest.update { newSurfaceRequest }
            Log.d("Liveness", "preview resolution: ${newSurfaceRequest.resolution}")
            surfaceMeteringPointFactory = SurfaceOrientedMeteringPointFactory(
                newSurfaceRequest.resolution.width.toFloat(),
                newSurfaceRequest.resolution.height.toFloat()
            )
        }
    }

    private val imageCaptureUseCase: ImageCapture = ImageCapture.Builder().build()
    private val imageAnalysisUseCase: ImageAnalysis = ImageAnalysis.Builder().build()

    private val faceDetector = FaceDetection.getClient(
        FaceDetectorOptions.Builder()
            .setPerformanceMode(FaceDetectorOptions.PERFORMANCE_MODE_FAST)
            .setClassificationMode(FaceDetectorOptions.CLASSIFICATION_MODE_ALL)
            .setLandmarkMode(FaceDetectorOptions.LANDMARK_MODE_ALL)
            .setMinFaceSize(0.3f)
            .build()
    )
    private var faceImageWidth = 0
    private var faceImageHeight = 0
    private var needUpdateFaceImageInfo = true
    private var livenessStateHandlers = listOf(
        FrontFaceStateHandler(),
        SmileStateHandler(),
        SideFaceStateHandler(),
        MouthOpenStateHandler()
    )
    private var currentStateHandler: LivenessStateHandler = livenessStateHandlers.first()
    var isLivenessCompleted by mutableStateOf(false)
        private set
    private var isTakingPicture = false
    private val livenessPictures = mutableListOf<String>()
    val completedLivenessPictures: List<String> = livenessPictures
    private val fpsTimer = Timer()
    private var frameProcessedInOneSecondInterval = 0
    private var framesPerSecond = 0
    private var validStateFrames = 0
    private var emptyFaceFrames = 0

    suspend fun bindToCamera(lifecycleOwner: LifecycleOwner) {
        val processCameraProvider = ProcessCameraProvider.awaitInstance(getApplication())
        val camera = processCameraProvider.bindToLifecycle(
            lifecycleOwner,
            DEFAULT_FRONT_CAMERA,
            previewUseCase,
            imageCaptureUseCase,
            imageAnalysisUseCase
        )
        cameraControl = camera.cameraControl
        imageAnalysisUseCase.setAnalyzer(
            ContextCompat.getMainExecutor(getApplication()),
            ::analyzeImage
        )
        fpsTimer.schedule(
            object : TimerTask() {
                override fun run() {
                    framesPerSecond = frameProcessedInOneSecondInterval
                    frameProcessedInOneSecondInterval = 0
                    Log.d("Liveness", "FPS: $framesPerSecond")
                }
            },
            0,
            1000
        )

        // Cancellation signals we're done with the camera
        try {
            awaitCancellation()
        } finally {
            Log.d("Liveness", "bindToCamera: awaitCancellation")
            processCameraProvider.unbindAll()
            cameraControl = null
        }
    }

    @OptIn(ExperimentalGetImage::class)
    private fun analyzeImage(imageProxy: ImageProxy) {
        if (needUpdateFaceImageInfo) {
            updateFaceImageInfo(imageProxy)
            needUpdateFaceImageInfo = false
        }
        try {
            val mediaImage = imageProxy.image
            if (mediaImage != null) {
                val image = InputImage.fromMediaImage(
                    mediaImage,
                    imageProxy.imageInfo.rotationDegrees
                )
                faceDetector.process(image)
                    .addOnSuccessListener { faces ->
                        frameProcessedInOneSecondInterval++
                        if (!isLivenessCompleted) {
                            liveness(faces)
                        }
                    }
                    .addOnFailureListener { e ->
                        liveness(emptyList())
                        Log.e(
                            "Liveness",
                            "Failed to detect image. Error: " + e.localizedMessage
                        )
                    }
                    .addOnCompleteListener {
                        imageProxy.close()
                    }
            }
        } catch (e: MlKitException) {
            liveness(emptyList())
            Log.e(
                "Liveness",
                "Failed to process image. Error: " + e.localizedMessage
            )
        }
    }

    private fun liveness(faces: List<Face>) {
        if (isTakingPicture) return
        if (faces.isEmpty()) {
            emptyFaceFrames++
            if (emptyFaceFrames >= 10) {
                resetStateHandler()
            }
            return
        }
        emptyFaceFrames = 0

        val face = faces.first()
        val handleResult = currentStateHandler.onFrame(
            face = face,
            imageWidth = faceImageWidth,
            imageHeight = faceImageHeight,
            validFrames = validStateFrames,
            framesPerSecond = framesPerSecond
        )
        when (handleResult) {
            FrameHandleResult.Valid -> validStateFrames++
            else -> {
                validStateFrames = 0
            }
        }

        guideText = when (handleResult) {
            FrameHandleResult.Invalid.FaceNotCenter -> "Please make sure your face is in the center of the screen"
            FrameHandleResult.Invalid.FaceTooFar -> "Too far"
            FrameHandleResult.Invalid.FaceTooClose -> "Too close"
            else -> currentStateHandler.stateGuideText
        }

        if (handleResult == FrameHandleResult.Completed) {
            takePicture()
        }
    }

    private fun resetStateHandler() {
        emptyFaceFrames = 0
        validStateFrames = 0
        livenessPictures.clear()
        currentStateHandler = livenessStateHandlers.first()
    }

    private fun updateStateHandler(stateHandler: LivenessStateHandler) {
        emptyFaceFrames = 0
        validStateFrames = 0
        currentStateHandler = stateHandler
    }

    private fun updateFaceImageInfo(imageProxy: ImageProxy) {
        val rotation = imageProxy.imageInfo.rotationDegrees
        if (rotation == 0 || rotation == 180) {
            faceImageWidth = imageProxy.width
            faceImageHeight = imageProxy.height
        } else {
            faceImageWidth = imageProxy.height
            faceImageHeight = imageProxy.width
        }
    }

    private fun takePicture() {
        isTakingPicture = true
        val cacheDir = getApplication<Application>().cacheDir
        val imageFile = File.createTempFile("liveness", ".jpg", cacheDir)
        val outputFileOptions = ImageCapture.OutputFileOptions.Builder(imageFile).build()
        imageCaptureUseCase.takePicture(
            outputFileOptions,
            ContextCompat.getMainExecutor(getApplication()),
            object : OnImageSavedCallback {
                override fun onImageSaved(outputFileResults: ImageCapture.OutputFileResults) {
                    livenessPictures.add(imageFile.absolutePath)
                    val currentStateHandlerIndex =
                        livenessStateHandlers.indexOf(currentStateHandler)
                    val nextStateHandler =
                        livenessStateHandlers.getOrNull(currentStateHandlerIndex + 1)
                    if (nextStateHandler == null) {
                        isLivenessCompleted = true
                    } else {
                        updateStateHandler(nextStateHandler)
                    }
                    isTakingPicture = false
                }

                override fun onError(exception: ImageCaptureException) {
                    isTakingPicture = false
                    Log.d("Liveness", "Failed to take picture", exception)
                }
            })
    }

    fun tapToFocus(tapCoords: Offset) {
        val point = surfaceMeteringPointFactory?.createPoint(tapCoords.x, tapCoords.y)
        if (point != null) {
            val meteringAction = FocusMeteringAction.Builder(point).build()
            cameraControl?.startFocusAndMetering(meteringAction)
        }
    }
}