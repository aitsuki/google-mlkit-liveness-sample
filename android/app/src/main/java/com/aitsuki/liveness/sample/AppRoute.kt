package com.aitsuki.liveness.sample

import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.snapshots.SnapshotStateList
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.navigation3.runtime.entryProvider
import androidx.navigation3.ui.NavDisplay

sealed interface AppRoute {
    data object Home : AppRoute
    data object Liveness : AppRoute
}

val LocalBackStack = staticCompositionLocalOf<SnapshotStateList<AppRoute>> {
    error("No ResultEventBus provided")
}

@Composable
fun AppNavDisplay() {

    val resultEventBus = remember { ResultEventBus() }
    val backStack = remember { mutableStateListOf<AppRoute>(AppRoute.Home) }

    CompositionLocalProvider(
        LocalBackStack provides backStack,
        LocalResultEventBus provides resultEventBus,
    ) {
        NavDisplay(
            backStack = backStack,
            onBack = { backStack.removeLastOrNull() },
            entryProvider = entryProvider {
                entry<AppRoute.Home> { HomeScreen() }
                entry<AppRoute.Liveness> { LivenessScreen() }
            }
        )
    }
}