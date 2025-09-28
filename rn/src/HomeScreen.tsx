import { Button, Image, ScrollView, StyleSheet, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useCameraPermission } from 'react-native-vision-camera';
import { RootScreenProps } from './App';

export function HomeScreen({ navigation, route }: RootScreenProps<'Home'>) {
  const { hasPermission, requestPermission } = useCameraPermission();
  const photoFiles = route.params?.photoFiles;

  const handleLiveness = async () => {
    if (hasPermission || (await requestPermission())) {
      navigation.push('Liveness');
    }
  };

  return (
    <SafeAreaView style={styles.container} edges={['bottom']}>
      <ScrollView style={styles.scrollContainer}>
        <View>
          {photoFiles &&
            photoFiles.map((file, index) => (
              <Image
                key={index}
                source={{ uri: 'file://' + file.path }}
                style={styles.imageStyle}
              />
            ))}
        </View>
      </ScrollView>
      <Button title="Liveness" onPress={handleLiveness} />
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  scrollContainer: {
    flex: 1,
  },
  imageStyle: {
    width: 300,
    height: 300,
  },
});
