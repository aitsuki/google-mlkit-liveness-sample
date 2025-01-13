package com.aitsuki.liveness.sample

import androidx.compose.runtime.Composable
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import kotlinx.serialization.Serializable

object Routes {

    @Serializable
    object Home

    @Serializable
    object Liveness
}

@Composable
fun AppGraph() {
    val navController = rememberNavController()
    NavHost(navController = navController, startDestination = Routes.Home) {
        composable<Routes.Home> { HomeScreen(navController) }
        composable<Routes.Liveness> { LivenessScreen(navController) }
    }
}