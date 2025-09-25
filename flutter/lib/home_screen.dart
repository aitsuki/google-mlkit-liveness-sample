import 'dart:typed_data';

import 'package:flutter/material.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Uint8List> images = [];

  Future<void> _handleLiveness() async {
    final result = await Navigator.pushNamed(context, "/liveness");
    if (mounted && result != null) {
      setState(() {
        images = result as List<Uint8List>;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                itemCount: images.length,
                itemBuilder: (context, index) {
                  final image = images[index];
                  return Image.memory(image);
                },
              ),
            ),
            Container(
              padding: EdgeInsets.all(16.0),
              width: double.infinity,
              child: FilledButton(
                onPressed: _handleLiveness,
                child: Text("Liveness"),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
