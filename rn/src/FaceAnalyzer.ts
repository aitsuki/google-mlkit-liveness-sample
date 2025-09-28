import { Camera, PhotoFile } from 'react-native-vision-camera';
import {
  Bounds,
  Face,
  FaceDetectionOptions,
} from 'react-native-vision-camera-face-detector';

export type LivenessStep = 'front' | 'smile' | 'side' | 'done';
export type FaceError =
  | 'not_center'
  | 'too_far'
  | 'too_close'
  | 'multiple_faces'
  | 'none';

class LivenessController {
  private currentStep: LivenessStep = 'front';
  private retryCount: number = 0;
  private maxRetries: number = 5;

  private reset() {
    this.currentStep = 'front';
    this.retryCount = 0;
  }

  nextStep() {
    this.retryCount = 0;
    if (this.currentStep === 'front') {
      this.currentStep = 'smile';
    } else if (this.currentStep === 'smile') {
      this.currentStep = 'side';
    } else if (this.currentStep === 'side') {
      this.currentStep = 'done';
    }
  }

  public onFailedDetection() {
    this.retryCount++;
    if (this.retryCount > this.maxRetries) {
      this.reset();
    }
  }

  public getStep(): LivenessStep {
    return this.currentStep;
  }
}

export class FaceAnalyzer {
  private camera: React.RefObject<Camera | null>;
  private statusCallback: (step: LivenessStep, error: FaceError) => void;
  private onDone: (files: PhotoFile[]) => void;

  constructor(
    camera: React.RefObject<Camera | null>,
    statusCallback: (step: LivenessStep, error: FaceError) => void,
    onDone: (files: PhotoFile[]) => void,
  ) {
    this.camera = camera;
    this.statusCallback = statusCallback;
    this.onDone = onDone;
  }

  public faceDetectionOptions: FaceDetectionOptions = {
    cameraFacing: 'front',
    classificationMode: 'all',
    performanceMode: 'fast',
    contourMode: 'none',
    landmarkMode: 'none',
    minFaceSize: 0.15,
    trackingEnabled: false,
  };
  private controller = new LivenessController();
  private stepSuccessTime = 0;
  private isBusy = false;

  private stepDuration: Record<LivenessStep, number> = {
    front: 500,
    smile: 100,
    side: 100,
    done: 0,
  };

  private stepFiles: Partial<Record<LivenessStep, PhotoFile>> = {};

  private handleFailure(step: LivenessStep, error: FaceError) {
    this.stepSuccessTime = 0;
    this.statusCallback(step, error);
    this.controller.onFailedDetection();
  }

  public async analyze(faces: Face[], frameW: number, frameH: number) {
    const step = this.controller.getStep();
    console.log('step', step, 'isBusy', this.isBusy);
    if (this.isBusy || step === 'done') return;
    this.isBusy = true;

    try {
      if (faces.length === 0) {
        this.handleFailure(step, 'none');
        return;
      } else if (faces.length > 1) {
        this.handleFailure(step, 'multiple_faces');
        return;
      }

      const face = faces[0];
      const faceBounds = this.clampBounds(face, frameW, frameH);

      // 面部位置 & 距离检测
      if (step === 'front') {
        const distanceError = this.detectFaceDistance(
          faceBounds,
          frameW,
          frameH,
        );
        if (distanceError) {
          this.handleFailure(step, distanceError);
          return;
        }
        const positionError = this.detectFacePosition(
          faceBounds,
          frameW,
          frameH,
        );
        if (positionError) {
          this.handleFailure(step, positionError);
          return;
        }
      }

      this.statusCallback(step, 'none');

      const yaw = face.yawAngle;
      const pitch = face.pitchAngle;
      let success = false;
      if (step === 'front') {
        success = yaw >= -12 && yaw <= 12 && pitch >= -8 && pitch <= 8;
      } else if (step === 'smile') {
        success = face.smilingProbability > 0.3;
      } else if (step === 'side') {
        success = yaw < -20.0 || yaw > 20.0;
      }
      console.log(step, 'success', success);

      if (success) {
        const now = Date.now();
        if (this.stepSuccessTime === 0) {
          this.stepSuccessTime = now;
        } else {
          const elapsedTime = now - this.stepSuccessTime;
          if (elapsedTime >= this.stepDuration[step]) {
            this.stepSuccessTime = 0;
            const file = await this.camera.current?.takeSnapshot();
            if (file) {
              this.stepFiles[step] = file;
              this.controller.nextStep();
              if (this.controller.getStep() === 'done') {
                const files = [
                  this.stepFiles.front,
                  this.stepFiles.smile,
                  this.stepFiles.side,
                ] as PhotoFile[];
                this.onDone(files);
              }
            }
          }
        }
      } else {
        this.stepSuccessTime = 0;
      }
    } catch (e) {
      console.log('error', e);
    } finally {
      this.isBusy = false;
    }
  }

  private detectFaceDistance(
    faceBounds: Bounds,
    frameW: number,
    frameH: number,
  ): FaceError | null {
    const faceRatio =
      (faceBounds.width * faceBounds.height) / (frameW * frameH);
    const tooCloseRatio = 0.36;
    const tooFarRatio = 0.12;
    if (faceRatio > tooCloseRatio) {
      return 'too_close';
    } else if (faceRatio < tooFarRatio) {
      return 'too_far';
    }
    return null;
  }

  private detectFacePosition(
    faceBounds: Bounds,
    frameW: number,
    frameH: number,
  ): FaceError | null {
    const centerTolerance = 0.15;
    const centerX = faceBounds.x + faceBounds.width / 2;
    const centerY = faceBounds.y + faceBounds.height / 2;
    const dxRatio = (centerX - frameW / 2) / frameW;
    const dyRatio = (centerY - frameH / 2) / frameH;
    if (
      Math.abs(dxRatio) > centerTolerance ||
      Math.abs(dyRatio) > centerTolerance
    ) {
      return 'not_center';
    }
    return null;
  }

  private clampBounds(face: Face, frameW: number, frameH: number) {
    const bounds = face.bounds;
    const x = Math.max(0, bounds.x);
    const y = Math.max(0, bounds.y);
    const w = Math.min(bounds.width, frameW - x);
    const h = Math.min(bounds.height, frameH - y);
    return { x, y, width: w, height: h };
  }
}
