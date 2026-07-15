package com.aitsuki.liveness.sample

import com.aitsuki.liveness.sample.live.LiveController
import com.aitsuki.liveness.sample.live.LiveStep
import org.junit.Assert.assertEquals
import org.junit.Test

class ExampleUnitTest {
    @Test
    fun onlyContinuousFailuresResetTheFlow() {
        val controller = LiveController().apply { nextStep() }

        controller.onFailedDetection(1_000L)
        controller.onValidDetection()
        controller.onFailedDetection(4_000L)
        controller.onFailedDetection(5_499L)
        assertEquals(LiveStep.SMILE, controller.getStep())

        controller.onFailedDetection(5_500L)
        assertEquals(LiveStep.FRONT, controller.getStep())
    }
}
