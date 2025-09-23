package com.aitsuki.liveness.sample

import android.util.Log
import androidx.annotation.StringRes
import androidx.camera.compose.CameraXViewfinder
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
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalResources
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.NavController
import com.google.accompanist.permissions.ExperimentalPermissionsApi
import com.google.accompanist.permissions.isGranted
import com.google.accompanist.permissions.rememberPermissionState

@OptIn(ExperimentalPermissionsApi::class)
@Composable
fun LivenessScreen(
    navController: NavController,
    viewModel: LivenessViewModel = viewModel()
) {
    LaunchedEffect(viewModel.done) {
        if (viewModel.done) {
            val faceImages = viewModel.getFaceImages()
            navController.previousBackStackEntry?.savedStateHandle?.let { savedStateHandle ->
                savedStateHandle["images"] = faceImages
            }
            navController.popBackStack()
        }
    }
    Scaffold { innerPadding ->
        val cameraPermissionState = rememberPermissionState(android.Manifest.permission.CAMERA)
        if (cameraPermissionState.status.isGranted) {
            CameraPreviewContent(
                viewModel = viewModel,
                modifier = Modifier.padding(innerPadding)
            )
        }
    }
}

@Composable
private fun CameraPreviewContent(
    viewModel: LivenessViewModel,
    modifier: Modifier = Modifier,
    lifecycleOwner: LifecycleOwner = LocalLifecycleOwner.current
) {
    val surfaceRequest by viewModel.surfaceRequest.collectAsStateWithLifecycle()
    val view = LocalView.current
    DisposableEffect(view) {
        view.keepScreenOn = true
        onDispose {
            view.keepScreenOn = false
        }
    }
    LaunchedEffect(lifecycleOwner) {
        Log.d("Liveness", "bindToCamera: $lifecycleOwner")
        viewModel.bindToCamera(lifecycleOwner)
    }

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
                Text(safeStringResource(viewModel.guideText), textAlign = TextAlign.Center)
                Text(
                    safeStringResource(viewModel.errorText),
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