import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';
import 'package:intl/intl.dart';

import '../../../core/config/app_providers.dart';

class AppointmentsScreen extends ConsumerWidget {
  const AppointmentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final animals = ref.watch(clinicRepositoryProvider).watchAnimals();
    final date = DateFormat.yMMMd().add_jm();

    return Scaffold(
      appBar: AppBar(title: const Text('Schedule')),
      body: StreamBuilder(
        stream: animals,
        builder: (context, snapshot) {
          final list = snapshot.data ?? [];
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: ListTile(
                  leading: const Icon(Iconsax.calendar),
                  title: const Text('Schedule calendar'),
                  subtitle: Text('${list.length} active patients available for scheduling'),
                ),
              ),
              for (final animal in list.take(10))
                Card(
                  child: ListTile(
                    leading: const Icon(Iconsax.pet),
                    title: Text(animal.animalName),
                    subtitle: Text('${animal.hospitalNumber} • ${date.format(DateTime.now().add(const Duration(days: 1)))}'),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
