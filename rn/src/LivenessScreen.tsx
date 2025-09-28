import { useEffect, useRef, useState } from 'react';
import { AppState, AppStateStatus, StyleSheet, Text, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import {
  Camera,
  runAsync,
  useCameraDevice,
  useFrameProcessor,
} from 'react-native-vision-camera';
import {
  Face,
  useFaceDetector,
} from 'react-native-vision-camera-face-detector';
import { Worklets } from 'react-native-worklets-core';
import { FaceAnalyzer, FaceError, LivenessStep } from './FaceAnalyzer';
import { RootScreenProps } from './App';

const guideTextMap: Record<LivenessStep, string> = {
  front: 'Please make sure your face is in the center of the screen',
  smile: 'Please smile',
  side: 'Please slowly turn your head left or right',
  done: '',
};

const errorTextMap: Record<FaceError, string> = {
  not_center: 'Please move your face to the center of the screen',
  too_far: 'Please move closer',
  too_close: 'Please move farther away',
  multiple_faces:
    'Multiple faces detected, please ensure only one person is in view',
  none: '',
};

export function LivenessScreen({ navigation }: RootScreenProps<'Liveness'>) {
  const cameraRef = useRef<Camera>(null);
  const device = useCameraDevice('front');

  const [guideText, setGuideText] = useState('');
  const [errorText, setErrorText] = useState('');
  const [done, setDone] = useState(false);

  const [appState, setAppState] = useState(AppState.currentState);
  useEffect(() => {
    const handleAppState = (nextAppState: AppStateStatus) => {
      setAppState(nextAppState);
    };

    const subscription = AppState.addEventListener('change', handleAppState);
    return () => subscription.remove();
  }, []);

  const faceAnalyzer = useRef<FaceAnalyzer | null>(null);
  if (!faceAnalyzer.current) {
    faceAnalyzer.current = new FaceAnalyzer(
      cameraRef,
      (step, error) => {
        setGuideText(guideTextMap[step]);
        setErrorText(errorTextMap[error]);
        console.log('step', step, 'error', error);
      },
      files => {
        setDone(true);
        console.log('Liveness done, photos taken:', files);
        navigation.popTo('Home', { photoFiles: files });
      },
    );
  }

  const { detectFaces } = useFaceDetector(
    faceAnalyzer.current.faceDetectionOptions,
  );

  const handleDetectedFaces = Worklets.createRunOnJS(
    (faces: Face[], frameW: number, frameH: number) => {
      faceAnalyzer.current?.analyze(faces, frameW, frameH);
    },
  );

  const frameProcessor = useFrameProcessor(
    frame => {
      'worklet';
      runAsync(frame, () => {
        'worklet';
        const reverseWH =
          frame.orientation === 'landscape-left' ||
          frame.orientation === 'landscape-right';
        const frameW = reverseWH ? frame.height : frame.width;
        const frameH = reverseWH ? frame.width : frame.height;
        const faces = detectFaces(frame);
        handleDetectedFaces(faces, frameW, frameH);
      });
    },
    [handleDetectedFaces],
  );

  return (
    <SafeAreaView style={styles.container}>
      <View style={styles.textContainer}>
        <Text>{guideText}</Text>
        <Text style={styles.errorText}>{errorText}</Text>
      </View>
      {device && (
        <View style={styles.cameraContainer}>
          <Camera
            style={StyleSheet.absoluteFill}
            ref={cameraRef}
            device={device}
            isActive={!done && appState === 'active'}
            frameProcessor={frameProcessor}
          />
        </View>
      )}
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  textContainer: {
    height: 100,
    justifyContent: 'center',
    alignItems: 'center',
  },
  errorText: {
    color: '#F00',
    fontWeight: 'semibold',
  },
  cameraContainer: {
    height: 220,
    width: 220,
    alignSelf: 'center',
    borderRadius: 110,
    overflow: 'hidden',
  },
});
