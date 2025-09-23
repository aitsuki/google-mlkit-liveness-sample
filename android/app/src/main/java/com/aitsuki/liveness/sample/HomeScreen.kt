package com.aitsuki.liveness.sample

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.unit.dp
import androidx.navigation.NavController
import coil3.compose.AsyncImage
import com.google.accompanist.permissions.ExperimentalPermissionsApi
import com.google.accompanist.permissions.isGranted
import com.google.accompanist.permissions.rememberPermissionState

@OptIn(ExperimentalPermissionsApi::class)
@Composable
fun HomeScreen(navController: NavController) {
    var images: Array<String> by remember { mutableStateOf(emptyArray()) }
    LaunchedEffect(Unit) {
        navController.currentBackStackEntry?.savedStateHandle?.let { savedStateHandle ->
            images = savedStateHandle.remove<Array<String>>("images") ?: emptyArray()
        }
    }

    Scaffold { innerPadding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding)
                .padding(16.dp)
        ) {
            Column(
                Modifier
                    .fillMaxWidth()
                    .weight(1f)
                    .verticalScroll(rememberScrollState())
            ) {
                for (image in images) {
                    AsyncImage(
                        model = image,
                        contentDescription = null,
                        modifier = Modifier
                            .fillMaxWidth()
                            .aspectRatio(1.77f),
                        contentScale = ContentScale.Crop,
                    )
                }
            }

            val cameraPermissionState = rememberPermissionState(android.Manifest.permission.CAMERA) {
                navController.navigate(Routes.Liveness)
            }
            Button(onClick = {
                if (cameraPermissionState.status.isGranted) {
                    navController.navigate(Routes.Liveness)
                } else {
                    cameraPermissionState.launchPermissionRequest()
                }
            }, modifier = Modifier.fillMaxWidth()) {
                Text("Start Liveness")
            }
        }
    }
}