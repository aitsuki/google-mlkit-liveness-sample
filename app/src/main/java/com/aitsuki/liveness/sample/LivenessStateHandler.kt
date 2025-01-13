package com.aitsuki.liveness.sample

import com.google.mlkit.vision.face.Face

sealed interface FrameHandleResult {
    enum class Invalid : FrameHandleResult {
        FaceNotCenter,
        FaceTooFar,
        FaceTooClose,
    }

    data object Valid : FrameHandleResult
    data object Completed : FrameHandleResult
}

interface LivenessStateHandler {
    val stateGuideText: String

    fun onFrame(
        face: Face,
        imageWidth: Int,
        imageHeight: Int,
        validFrames: Int,
        framesPerSecond: Int,
    ): FrameHandleResult
}

class FrontFaceStateHandler(override val stateGuideText: String = "Please make sure your face is in the center of the screen") :
    LivenessStateHandler {
    override fun onFrame(
        face: Face,
        imageWidth: Int,
        imageHeight: Int,
        validFrames: Int,
        framesPerSecond: Int
    ): FrameHandleResult {
        val farOrClose = LivenessUtils.isFaceTooFarOrClose(face, imageWidth, imageHeight)
        if (farOrClose == -1) {
            return FrameHandleResult.Invalid.FaceTooClose
        } else if (farOrClose == 1) {
            return FrameHandleResult.Invalid.FaceTooFar
        }

        if (!LivenessUtils.isFaceInCenter(face, imageWidth, imageHeight)) {
            return FrameHandleResult.Invalid.FaceNotCenter
        }

        val validSeconds = (validFrames / framesPerSecond.coerceAtLeast(1))
        if (LivenessUtils.isFrontFace(face) && validSeconds >= 2) {
            return FrameHandleResult.Completed
        }
        return FrameHandleResult.Valid
    }
}

class SmileStateHandler(override val stateGuideText: String = "Please smile") :
    LivenessStateHandler {
    override fun onFrame(
        face: Face,
        imageWidth: Int,
        imageHeight: Int,
        validFrames: Int,
        framesPerSecond: Int
    ): FrameHandleResult {
        val farOrClose = LivenessUtils.isFaceTooFarOrClose(face, imageWidth, imageHeight)
        if (farOrClose == -1) {
            return FrameHandleResult.Invalid.FaceTooClose
        } else if (farOrClose == 1) {
            return FrameHandleResult.Invalid.FaceTooFar
        }

        if (!LivenessUtils.isFaceInCenter(face, imageWidth, imageHeight)) {
            return FrameHandleResult.Invalid.FaceNotCenter
        }

        val validSeconds = (validFrames / framesPerSecond.coerceAtLeast(1))
        val smilingProbability = face.smilingProbability ?: 0f
        if (smilingProbability > 0.3f && validFrames > validSeconds) {
            return FrameHandleResult.Completed
        }
        return FrameHandleResult.Valid
    }
}

class SideFaceStateHandler(override val stateGuideText: String = "Please slowly turn your head left or right") :
    LivenessStateHandler {
    override fun onFrame(
        face: Face,
        imageWidth: Int,
        imageHeight: Int,
        validFrames: Int,
        framesPerSecond: Int
    ): FrameHandleResult {
        if (LivenessUtils.isSideFace(face) && validFrames > 2) {
            return FrameHandleResult.Completed
        }
        return FrameHandleResult.Valid
    }
}

class MouthOpenStateHandler(override val stateGuideText: String = "Please open your mouth") :
    LivenessStateHandler {
    override fun onFrame(
        face: Face,
        imageWidth: Int,
        imageHeight: Int,
        validFrames: Int,
        framesPerSecond: Int
    ): FrameHandleResult {
        val farOrClose = LivenessUtils.isFaceTooFarOrClose(face, imageWidth, imageHeight)
        if (farOrClose == -1) {
            return FrameHandleResult.Invalid.FaceTooClose
        } else if (farOrClose == 1) {
            return FrameHandleResult.Invalid.FaceTooFar
        }

        val validSeconds = (validFrames / framesPerSecond.coerceAtLeast(1))
        if (LivenessUtils.isMouthOpened(face) && validSeconds > 1) {
            return FrameHandleResult.Completed
        }
        return FrameHandleResult.Valid
    }
}
