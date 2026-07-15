import 'package:flutter/material.dart';

class CloveryApp extends StatelessWidget {
  const CloveryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Clovery',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFE9B800)),
        useMaterial3: true,
      ),
      home: const Scaffold(
        body: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Clovery'),
                SizedBox(height: 12),
                Text('Initializing secure vault…'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
