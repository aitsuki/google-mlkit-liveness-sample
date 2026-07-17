export type LivenessStep = 'front' | 'smile' | 'side' | 'done';

export type FaceError =
  | 'not_center'
  | 'too_far'
  | 'too_close'
  | 'multiple_faces'
  | 'no_face'
  | 'capture_failed'
  | 'detector_failed'
  | 'none';

export interface FaceSample {
  bounds: {x: number; y: number; width: number; height: number};
  frameWidth: number;
  frameHeight: number;
  yawAngle: number;
  pitchAngle: number;
  smilingProbability?: number;
}

export interface AnalysisResult {
  step: LivenessStep;
  error: FaceError;
  captureStep?: Exclude<LivenessStep, 'done'>;
  didReset: boolean;
}

const STEP_DURATION_MS: Record<Exclude<LivenessStep, 'done'>, number> = {
  front: 1000,
  smile: 500,
  side: 250,
};

const RESET_TIMEOUT_MS = 1500;

export class LivenessController {
  private step: LivenessStep = 'front';
  private failureSince?: number;
  private successSince?: number;
  private awaitingCapture = false;

  process(faces: FaceSample[], now: number): AnalysisResult {
    if (this.step === 'done' || this.awaitingCapture) {
      return this.result('none');
    }

    if (faces.length === 0) {
      return this.fail('no_face', now);
    }
    if (faces.length > 1) {
      return this.fail('multiple_faces', now);
    }

    const face = faces[0];
    if (this.step === 'front') {
      const geometryError = this.validateFrontGeometry(face);
      if (geometryError) {
        return this.fail(geometryError, now);
      }
    }

    this.failureSince = undefined;
    const successful = this.isStepSuccessful(face);
    if (!successful) {
      this.successSince = undefined;
      return this.result('none');
    }

    if (this.successSince === undefined) {
      this.successSince = now;
      return this.result('none');
    }

    const step = this.step as Exclude<LivenessStep, 'done'>;
    if (now - this.successSince < STEP_DURATION_MS[step]) {
      return this.result('none');
    }

    this.awaitingCapture = true;
    return {...this.result('none'), captureStep: step};
  }

  captureSucceeded(step: Exclude<LivenessStep, 'done'>): LivenessStep {
    if (!this.awaitingCapture || this.step !== step) {
      return this.step;
    }

    this.awaitingCapture = false;
    this.successSince = undefined;
    this.failureSince = undefined;
    this.step =
      step === 'front' ? 'smile' : step === 'smile' ? 'side' : 'done';
    return this.step;
  }

  captureFailed(): void {
    this.awaitingCapture = false;
    this.successSince = undefined;
  }

  getStep(): LivenessStep {
    return this.step;
  }

  private fail(error: FaceError, now: number): AnalysisResult {
    this.successSince = undefined;
    if (this.failureSince === undefined) {
      this.failureSince = now;
      return this.result(error);
    }

    if (now - this.failureSince >= RESET_TIMEOUT_MS) {
      this.reset();
      return {...this.result(error), didReset: true};
    }
    return this.result(error);
  }

  private reset(): void {
    this.step = 'front';
    this.failureSince = undefined;
    this.successSince = undefined;
    this.awaitingCapture = false;
  }

  private result(error: FaceError): AnalysisResult {
    return {step: this.step, error, didReset: false};
  }

  private validateFrontGeometry(face: FaceSample): FaceError | undefined {
    const {frameWidth, frameHeight} = face;
    if (frameWidth <= 0 || frameHeight <= 0) {
      return 'not_center';
    }

    const x = Math.max(0, face.bounds.x);
    const y = Math.max(0, face.bounds.y);
    const width = Math.min(face.bounds.width, frameWidth - x);
    const height = Math.min(face.bounds.height, frameHeight - y);
    const faceRatio = (width * height) / (frameWidth * frameHeight);

    if (faceRatio > 0.36) {
      return 'too_close';
    }
    if (faceRatio < 0.12) {
      return 'too_far';
    }

    const dxRatio = (x + width / 2 - frameWidth / 2) / frameWidth;
    const dyRatio = (y + height / 2 - frameHeight / 2) / frameHeight;
    if (Math.abs(dxRatio) > 0.15 || Math.abs(dyRatio) > 0.15) {
      return 'not_center';
    }
    return undefined;
  }

  private isStepSuccessful(face: FaceSample): boolean {
    switch (this.step) {
      case 'front':
        return (
          face.yawAngle >= -12 &&
          face.yawAngle <= 12 &&
          face.pitchAngle >= -8 &&
          face.pitchAngle <= 8
        );
      case 'smile':
        return (face.smilingProbability ?? 0) > 0.3;
      case 'side':
        return face.yawAngle < -20 || face.yawAngle > 20;
      case 'done':
        return false;
    }
  }
}
