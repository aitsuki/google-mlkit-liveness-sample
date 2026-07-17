import {useEffect, useMemo, useRef, useState} from 'react';
import {Button, Image, ScrollView, StyleSheet, Text, View} from 'react-native';
import {FileSystem} from 'react-native-file-access';
import {SafeAreaView} from 'react-native-safe-area-context';
import {useCameraPermission} from 'react-native-vision-camera';
import type {RootScreenProps} from './navigation';

async function removePhotos(paths: string[]): Promise<void> {
  await Promise.all(
    paths.map(path => FileSystem.unlink(path).catch(() => undefined)),
  );
}

export function HomeScreen({navigation, route}: RootScreenProps<'Home'>) {
  const photoPaths = useMemo(
    () => route.params?.photoPaths ?? [],
    [route.params?.photoPaths],
  );
  const previousPaths = useRef<string[]>([]);
  const [permissionError, setPermissionError] = useState('');
  const {hasPermission, requestPermission} = useCameraPermission();

  useEffect(() => {
    const obsoletePaths = previousPaths.current.filter(
      path => !photoPaths.includes(path),
    );
    previousPaths.current = photoPaths;
    removePhotos(obsoletePaths).catch(() => undefined);
  }, [photoPaths]);

  const startLiveness = async () => {
    if (hasPermission || (await requestPermission())) {
      setPermissionError('');
      navigation.push('Liveness');
    } else {
      setPermissionError('Camera permission is required');
    }
  };

  return (
    <SafeAreaView style={styles.container} edges={['bottom']}>
      <ScrollView contentContainerStyle={styles.photos}>
        {photoPaths.map(path => (
          <Image
            key={path}
            source={{uri: `file://${path}`}}
            style={styles.photo}
          />
        ))}
      </ScrollView>
      {permissionError ? (
        <Text style={styles.error}>{permissionError}</Text>
      ) : null}
      <View style={styles.button}>
        <Button title="Start Liveness" onPress={startLiveness} />
      </View>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: {flex: 1},
  photos: {padding: 16, gap: 12},
  photo: {width: '100%', aspectRatio: 1.77, resizeMode: 'cover'},
  button: {padding: 16},
  error: {color: '#c62828', textAlign: 'center'},
});
