import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:liveness/home_screen.dart';
import 'package:liveness/liveness_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      initialRoute: "/",
      routes: {
        '/': (context) => const HomeScreen(),
        '/liveness': (context) => const LivenessScreen(),
      },
    );
  }
}
