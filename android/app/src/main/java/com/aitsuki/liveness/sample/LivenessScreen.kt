package com.aitsuki.liveness.sample

import android.util.Log
import androidx.annotation.StringRes
import androidx.camera.compose.CameraXViewfinder
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageCapture
import androidx.camera.core.Preview
import androidx.camera.core.SurfaceRequest
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.lifecycle.awaitInstance
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalResources
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.aitsuki.liveness.sample.live.FaceAnalyzer
import com.aitsuki.liveness.sample.live.FaceError
import com.aitsuki.liveness.sample.live.KeepScreenOn
import com.aitsuki.liveness.sample.live.LiveStep
import com.google.accompanist.permissions.ExperimentalPermissionsApi
import com.google.accompanist.permissions.isGranted
import com.google.accompanist.permissions.rememberPermissionState
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.launch
import java.io.File
import java.util.concurrent.Executors
import kotlin.coroutines.cancellation.CancellationException

// process-lifetime scope; move to an injected application scope if cleanup grows.
private val imageCleanupScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

@OptIn(ExperimentalPermissionsApi::class)
@Composable
fun LivenessScreen() {
    Scaffold { innerPadding ->
        val cameraPermissionState = rememberPermissionState(android.Manifest.permission.CAMERA)
        LaunchedEffect(Unit) {
            if (!cameraPermissionState.status.isGranted) {
                cameraPermissionState.launchPermissionRequest()
            }
        }
        if (cameraPermissionState.status.isGranted) {
            CameraPreviewContent(
                modifier = Modifier.padding(innerPadding),
            )
        }
    }
}

@Composable
private fun CameraPreviewContent(modifier: Modifier = Modifier) {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val resultEventBus = LocalResultEventBus.current
    val backStack = LocalBackStack.current

    var surfaceRequest by remember { mutableStateOf<SurfaceRequest?>(null) }
    var guideText by remember { mutableIntStateOf(R.string.liveness_front) }
    var errorText by remember { mutableIntStateOf(0) }

    val capturedImages = remember { mutableMapOf<LiveStep, String>() }
    val analyzerExecutor = remember { Executors.newSingleThreadExecutor() }


    val imageCaptureUseCase = remember {
        ImageCapture.Builder()
            .setCaptureMode(ImageCapture.CAPTURE_MODE_MINIMIZE_LATENCY)
            .build()
    }

    val previewUseCase = remember {
        Preview.Builder().build().apply {
            setSurfaceProvider { newSurfaceRequest ->
                surfaceRequest = newSurfaceRequest
                Log.d("Liveness", "preview resolution: ${newSurfaceRequest.resolution}")
            }
        }
    }

    val imageAnalysisUseCase = remember { ImageAnalysis.Builder().build() }

    val faceAnalyzer = remember {
        FaceAnalyzer(
            imageCapture = imageCaptureUseCase,
            outputDirectory = context.cacheDir,
            executor = ContextCompat.getMainExecutor(context),
            onImageCaptured = { step, filePath ->
                Log.d("Liveness", "Image captured for step $step: $filePath")
                capturedImages.put(step, filePath)?.let { oldPath ->
                    imageCleanupScope.launch {
                        runCatching { File(oldPath).delete() }
                            .onSuccess { if (!it) Log.w("Liveness", "Failed to delete $oldPath") }
                            .onFailure { Log.w("Liveness", "Failed to delete $oldPath", it) }
                    }
                }
            },
            onStatusUpdate = { step, error ->
                guideText = when (step) {
                    LiveStep.FRONT -> R.string.liveness_front
                    LiveStep.SIDE -> R.string.liveness_side
                    LiveStep.SMILE -> R.string.liveness_smile
                    LiveStep.DONE -> 0
                }
                errorText = when (error) {
                    FaceError.NOT_CENTER -> R.string.err_face_not_center
                    FaceError.TOO_FAR -> R.string.err_face_too_far
                    FaceError.TOO_CLOSE -> R.string.err_face_too_close
                    FaceError.MULTIPLE_FACES -> R.string.err_multiple_faces
                    FaceError.NONE -> 0
                }
            },
            onDone = {
                Log.d("Liveness", "Face detection completed")
                val images = listOfNotNull(
                    capturedImages[LiveStep.FRONT],
                    capturedImages[LiveStep.SMILE],
                    capturedImages[LiveStep.SIDE]
                ).toTypedArray()
                resultEventBus.sendResult(result = images)
                backStack.removeLastOrNull()
            }
        )
    }

    LaunchedEffect(lifecycleOwner) {
        val cameraProvider = ProcessCameraProvider.awaitInstance(context)
        try {
            cameraProvider.bindToLifecycle(
                lifecycleOwner,
                CameraSelector.DEFAULT_FRONT_CAMERA,
                previewUseCase,
                imageAnalysisUseCase,
                imageCaptureUseCase
            )
            imageAnalysisUseCase.setAnalyzer(analyzerExecutor, faceAnalyzer)
            Log.d("Liveness", "Camera bound to lifecycle")
            awaitCancellation()
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            Log.e("Liveness", "Failed to bind camera", e)
        } finally {
            cameraProvider.unbindAll()
            analyzerExecutor.shutdown()
            faceAnalyzer.close()
        }
    }

    KeepScreenOn()

    surfaceRequest?.let { request ->
        Column(
            modifier = modifier.fillMaxSize(),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Spacer(Modifier.weight(0.8f))
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(100.dp)
                    .padding(horizontal = 20.dp),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                Text(safeStringResource(guideText), textAlign = TextAlign.Center)
                Text(
                    safeStringResource(errorText),
                    textAlign = TextAlign.Center,
                    color = Color.Red
                )
            }
            CameraXViewfinder(
                surfaceRequest = request,
                modifier = Modifier
                    .fillMaxWidth(0.8f)
                    .aspectRatio(1f)
                    .clip(RoundedCornerShape(50))
            )
            Spacer(Modifier.weight(1f))
        }
    }
}

@Composable
@ReadOnlyComposable
fun safeStringResource(@StringRes id: Int): String {
    if (id == 0) return ""
    return LocalResources.current.getString(id)
}