import {NavigationContainer} from '@react-navigation/native';
import {createNativeStackNavigator} from '@react-navigation/native-stack';
import {StatusBar} from 'react-native';
import {SafeAreaProvider} from 'react-native-safe-area-context';
import {HomeScreen} from './src/HomeScreen';
import {LivenessScreen} from './src/LivenessScreen';
import type {RootStackParamList} from './src/navigation';

const Stack = createNativeStackNavigator<RootStackParamList>();

function App() {
  return (
    <SafeAreaProvider>
      <StatusBar barStyle="dark-content" backgroundColor="#ffffff" />
      <NavigationContainer>
        <Stack.Navigator
          screenOptions={{
            orientation: 'portrait',
            contentStyle: {backgroundColor: '#ffffff'},
          }}>
          <Stack.Screen
            name="Home"
            component={HomeScreen}
            options={{title: 'Liveness Sample'}}
          />
          <Stack.Screen
            name="Liveness"
            component={LivenessScreen}
            options={{title: 'Liveness'}}
          />
        </Stack.Navigator>
      </NavigationContainer>
    </SafeAreaProvider>
  );
}

export default App;
