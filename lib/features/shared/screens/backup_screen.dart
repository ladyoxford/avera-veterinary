import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/config/app_providers.dart';

class BackupScreen extends ConsumerWidget {
  const BackupScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Backup & Restore')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Iconsax.archive_book),
              title: const Text('Export SQLite Database'),
              subtitle: const Text('Create a timestamped backup file'),
              trailing: const Icon(Iconsax.arrow_right_3),
              onTap: () async {
                final file = await ref.read(clinicRepositoryProvider).exportDatabaseBackup();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Backup saved: ${file.path}')));
                }
              },
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Iconsax.import_1),
              title: const Text('Select Backup to Restore'),
              subtitle: const Text('Picker is configured; restore is guarded for production review'),
              trailing: const Icon(Iconsax.arrow_right_3),
              onTap: () async {
                final result = await FilePicker.pickFiles(type: FileType.any);
                if (context.mounted && result != null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Selected ${result.files.single.name}. Close the app before replacing the live database.')),
                  );
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}
