import {memo, useCallback, useEffect, useMemo, useRef, useState} from 'react';
import {
  AppState,
  type AppStateStatus,
  StyleSheet,
  Text,
  View,
} from 'react-native';
import {FileSystem} from 'react-native-file-access';
import {useIsFocused} from '@react-navigation/native';
import {SafeAreaView} from 'react-native-safe-area-context';
import {
  Camera,
  type CameraDevice,
  type CameraPhotoOutput,
  useCameraDevice,
  usePhotoOutput,
} from 'react-native-vision-camera';
import {
  type Face,
  useFaceDetectorOutput,
} from 'react-native-vision-camera-face-detector';
import type {RootScreenProps} from './navigation';
import {
  type FaceError,
  type FaceSample,
  LivenessController,
  type LivenessStep,
} from './liveness/LivenessController';

const guideText: Record<LivenessStep, string> = {
  front: 'Keep your face centered and look straight ahead',
  smile: 'Please smile',
  side: 'Slowly turn your head left or right',
  done: '',
};

const errorText: Record<FaceError, string> = {
  not_center: 'Move your face to the center',
  too_far: 'Move closer',
  too_close: 'Move farther away',
  multiple_faces: 'Make sure only one person is visible',
  no_face: '',
  capture_failed: 'Photo capture failed. Please try again',
  detector_failed: 'Face detection failed. Please try again',
  none: '',
};

type CaptureStep = Exclude<LivenessStep, 'done'>;
type CapturedPhotos = Partial<Record<CaptureStep, string>>;

async function removePhotos(paths: string[]): Promise<void> {
  await Promise.all(
    paths.map(path => FileSystem.unlink(path).catch(() => undefined)),
  );
}

interface FaceCameraProps {
  device: CameraDevice;
  isActive: boolean;
  photoOutput: CameraPhotoOutput;
  onFacesDetected: (faces: Face[]) => void;
  onError: (error: Error) => void;
}

const FaceCamera = memo(function FaceCameraComponent({
  device,
  isActive,
  photoOutput,
  onFacesDetected,
  onError,
}: FaceCameraProps) {
  const detectorOutput = useFaceDetectorOutput({
    cameraFacing: 'front',
    outputResolution: 'preview',
    performanceMode: 'fast',
    runClassifications: true,
    runContours: false,
    runLandmarks: false,
    minFaceSize: 0.15,
    trackingEnabled: false,
    onFacesDetected,
    onError,
  });
  const outputs = useMemo(
    () => [detectorOutput, photoOutput],
    [detectorOutput, photoOutput],
  );

  return (
    <Camera
      style={StyleSheet.absoluteFill}
      device={device}
      isActive={isActive}
      outputs={outputs}
      onError={onError}
    />
  );
});

export function LivenessScreen({navigation}: RootScreenProps<'Liveness'>) {
  const device = useCameraDevice('front');
  const photoOutput = usePhotoOutput({qualityPrioritization: 'speed'});
  const isFocused = useIsFocused();
  const [appState, setAppState] = useState(AppState.currentState);
  const [status, setStatus] = useState<{
    step: LivenessStep;
    error: FaceError;
  }>({step: 'front', error: 'none'});

  const controller = useRef(new LivenessController());
  const capturedPhotos = useRef<CapturedPhotos>({});
  const mounted = useRef(true);
  const transferredPhotos = useRef(false);

  useEffect(() => {
    const onAppStateChange = (nextState: AppStateStatus) =>
      setAppState(nextState);
    const subscription = AppState.addEventListener('change', onAppStateChange);
    return () => subscription.remove();
  }, []);

  useEffect(() => {
    return () => {
      mounted.current = false;
      if (!transferredPhotos.current) {
        removePhotos(Object.values(capturedPhotos.current)).catch(
          () => undefined,
        );
      }
    };
  }, []);

  const updateStatus = useCallback((step: LivenessStep, error: FaceError) => {
    if (!mounted.current) {
      return;
    }
    setStatus(current =>
      current.step === step && current.error === error
        ? current
        : {step, error},
    );
  }, []);

  const handleDetectorError = useCallback(
    (error: Error) => {
      console.warn('Face detector error', error);
      updateStatus(controller.current.getStep(), 'detector_failed');
    },
    [updateStatus],
  );

  const handleFacesDetected = useCallback(
    async (faces: Face[]) => {
      const samples: FaceSample[] = faces.map(face => ({
        bounds: face.bounds,
        frameWidth: face.frameWidth,
        frameHeight: face.frameHeight,
        yawAngle: face.yawAngle,
        pitchAngle: face.pitchAngle,
        smilingProbability: face.smilingProbability,
      }));
      const result = controller.current.process(samples, Date.now());
      updateStatus(result.step, result.error);

      if (result.didReset) {
        const obsoletePaths = Object.values(capturedPhotos.current);
        capturedPhotos.current = {};
        removePhotos(obsoletePaths).catch(() => undefined);
      }
      if (!result.captureStep) {
        return;
      }

      const captureStep = result.captureStep;
      try {
        const photo = await photoOutput.capturePhotoToFile(
          {enableShutterSound: false},
          {},
        );
        if (!mounted.current) {
          await removePhotos([photo.filePath]);
          return;
        }

        const oldPath = capturedPhotos.current[captureStep];
        capturedPhotos.current[captureStep] = photo.filePath;
        if (oldPath) {
          removePhotos([oldPath]).catch(() => undefined);
        }

        const nextStep = controller.current.captureSucceeded(captureStep);
        updateStatus(nextStep, 'none');
        if (nextStep === 'done') {
          const paths = [
            capturedPhotos.current.front,
            capturedPhotos.current.smile,
            capturedPhotos.current.side,
          ].filter((path): path is string => Boolean(path));
          if (paths.length === 3) {
            transferredPhotos.current = true;
            navigation.popTo('Home', {photoPaths: paths});
          }
        }
      } catch (error) {
        console.warn('Photo capture failed', error);
        controller.current.captureFailed();
        updateStatus(controller.current.getStep(), 'capture_failed');
      }
    },
    [navigation, photoOutput, updateStatus],
  );

  const isActive = isFocused && appState === 'active';

  return (
    <SafeAreaView style={styles.container}>
      <View style={styles.textContainer}>
        <Text style={styles.guide}>{guideText[status.step]}</Text>
        <Text style={styles.error}>{errorText[status.error]}</Text>
      </View>
      <View style={styles.cameraContainer}>
        {device ? (
          <FaceCamera
            device={device}
            isActive={isActive}
            photoOutput={photoOutput}
            onFacesDetected={handleFacesDetected}
            onError={handleDetectorError}
          />
        ) : (
          <Text style={styles.error}>Front camera is unavailable</Text>
        )}
      </View>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: {flex: 1, alignItems: 'center'},
  textContainer: {
    height: 120,
    paddingHorizontal: 20,
    justifyContent: 'center',
    alignItems: 'center',
  },
  guide: {textAlign: 'center'},
  error: {color: '#c62828', textAlign: 'center', fontWeight: '600'},
  cameraContainer: {
    width: '80%',
    aspectRatio: 1,
    borderRadius: 999,
    overflow: 'hidden',
    justifyContent: 'center',
  },
});
