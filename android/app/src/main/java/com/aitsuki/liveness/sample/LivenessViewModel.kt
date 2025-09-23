package com.aitsuki.liveness.sample

import android.app.Application
import android.graphics.Bitmap
import android.util.Log
import androidx.camera.core.CameraControl
import androidx.camera.core.CameraSelector.DEFAULT_FRONT_CAMERA
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.Preview
import androidx.camera.core.SurfaceRequest
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.lifecycle.awaitInstance
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.LifecycleOwner
import com.aitsuki.liveness.sample.live.FaceAnalyzer
import com.aitsuki.liveness.sample.live.FaceError
import com.aitsuki.liveness.sample.live.LivenessStep
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.withContext
import java.io.File
import java.util.concurrent.Executors

class LivenessViewModel(application: Application) : AndroidViewModel(application) {

    // Used to set up a link between the Camera and your UI.
    private val _surfaceRequest = MutableStateFlow<SurfaceRequest?>(null)
    val surfaceRequest: StateFlow<SurfaceRequest?> = _surfaceRequest

    private var cameraControl: CameraControl? = null

    private val previewUseCase = Preview.Builder().build().apply {
        setSurfaceProvider { newSurfaceRequest ->
            _surfaceRequest.update { newSurfaceRequest }
            Log.d("Liveness", "preview resolution: ${newSurfaceRequest.resolution}")
        }
    }

    private val imageAnalysisUseCase: ImageAnalysis = ImageAnalysis.Builder().build()

    private val analyzerExecutor = Executors.newSingleThreadExecutor()

    var guideText by mutableIntStateOf( R.string.liveness_front)
        private set
    var errorText by mutableIntStateOf(0)

    private val captureImages = mutableMapOf<LivenessStep, Bitmap>()

    var done by mutableStateOf(false)
        private set

    private val faceAnalyzer = FaceAnalyzer(
        onStatusUpdate = { step, error ->
            guideText = when (step) {
                LivenessStep.FRONT -> R.string.liveness_front
                LivenessStep.SIDE -> R.string.liveness_side
                LivenessStep.SMILE -> R.string.liveness_smile
                LivenessStep.DONE -> 0
            }
            errorText = when (error) {
                FaceError.NOT_CENTER -> R.string.err_face_not_center
                FaceError.TOO_FAR -> R.string.err_face_too_far
                FaceError.TOO_CLOSE -> R.string.err_face_too_close
                FaceError.MULTIPLE_FACES -> R.string.err_multiple_faces
                FaceError.NONE -> 0
            }
        },
        onCapture = { bitmap, step ->
            captureImages[step] = bitmap
        },
        onDone = {
            done = true
        }
    )

    suspend fun bindToCamera(lifecycleOwner: LifecycleOwner) {
        val processCameraProvider = ProcessCameraProvider.awaitInstance(getApplication())
        val camera = processCameraProvider.bindToLifecycle(
            lifecycleOwner,
            DEFAULT_FRONT_CAMERA,
            previewUseCase,
            imageAnalysisUseCase
        )
        cameraControl = camera.cameraControl
        imageAnalysisUseCase.setAnalyzer(
            analyzerExecutor,
            faceAnalyzer
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

    suspend fun getFaceImages(): Array<String> = withContext(Dispatchers.IO) {
        if (!done) return@withContext emptyArray()
        val bitmapList = listOfNotNull(
            captureImages[LivenessStep.FRONT],
            captureImages[LivenessStep.SMILE],
            captureImages[LivenessStep.SIDE],
        )

        bitmapList.map { bitmap ->
            val file = createTempFile()
            file.outputStream().use { out ->
                bitmap.compress(Bitmap.CompressFormat.JPEG, 80, out)
            }
            file.absolutePath
        }.toTypedArray()
    }

    private fun createTempFile(): File {
        return File.createTempFile("face_", ".jpg", getApplication<Application>().cacheDir)
    }

    override fun onCleared() {
        super.onCleared()
        analyzerExecutor.close()
    }
}