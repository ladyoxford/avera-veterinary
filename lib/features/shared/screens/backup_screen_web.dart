import 'package:flutter/material.dart';

class BackupScreen extends StatelessWidget {
  const BackupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Backup and restore')),
      body: const SafeArea(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Card(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text(
                  'Database backup and restore is available in the Android and desktop app. Web data is synchronized through the AVERA server.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
