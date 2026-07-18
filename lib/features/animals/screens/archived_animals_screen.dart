import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/config/app_providers.dart';
import '../../../core/models/animal_search_result.dart';
import '../../../core/repositories/clinic_repository.dart';

class ArchivedAnimalsScreen extends ConsumerWidget {
  const ArchivedAnimalsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(userSessionProvider);

    return session.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Scaffold(
        appBar: AppBar(title: const Text('Archived Animals')),
        body: Center(child: Text('Unable to load permissions: $error')),
      ),
      data: (data) {
        if (!data.can('Manage Animal Status')) {
          return Scaffold(
            appBar: AppBar(title: const Text('Archived Animals')),
            body: const Center(
              child: Text('You do not have permission to view archived animals.'),
            ),
          );
        }

        return const DefaultTabController(
          length: 2,
          child: Scaffold(
            appBar: _ArchivedAnimalsAppBar(),
            body: TabBarView(
              children: [
                _ArchivedAnimalsList(status: AnimalStatuses.deceased),
                _ArchivedAnimalsList(status: AnimalStatuses.relocated),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ArchivedAnimalsAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _ArchivedAnimalsAppBar();

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight + 48);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: const Text('Archived Animals'),
      bottom: const TabBar(
        tabs: [
          Tab(text: 'Deceased'),
          Tab(text: 'Relocated'),
        ],
      ),
    );
  }
}

class _ArchivedAnimalsList extends ConsumerWidget {
  const _ArchivedAnimalsList({required this.status});

  final String status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final animals = ref.watch(archivedAnimalsProvider(status));

    return animals.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('Unable to load archived animals: $error')),
      data: (items) {
        if (items.isEmpty) {
          return Center(child: Text('No $status animals archived.'));
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) => _ArchivedAnimalCard(animal: items[index]),
        );
      },
    );
  }
}

class _ArchivedAnimalCard extends ConsumerWidget {
  const _ArchivedAnimalCard({required this.animal});

  final AnimalSearchResult animal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final date = DateFormat.yMMMd();
    final registered = animal.dateRegistered == null
        ? '-'
        : date.format(animal.dateRegistered!);
    final marked = animal.statusUpdatedAt == null
        ? '-'
        : date.add_jm().format(animal.statusUpdatedAt!);

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push('/animals/${animal.animalId}'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    child: Text(animal.animalName.characters.first.toUpperCase()),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          animal.animalName,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          animal.hospitalNumber,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                  Chip(label: Text(animal.status)),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 16,
                runSpacing: 8,
                children: [
                  _Detail(label: 'Species', value: animal.species),
                  _Detail(label: 'Breed', value: animal.breed ?? '-'),
                  _Detail(label: 'Sex', value: animal.sex ?? '-'),
                  _Detail(label: 'Owner', value: animal.ownerName),
                  _Detail(label: 'Phone', value: animal.ownerPhone),
                  _Detail(label: 'Registered', value: registered),
                  _Detail(label: 'Marked', value: marked),
                ],
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton.icon(
                  onPressed: () => _restore(context, ref),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Restore'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _restore(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Restore ${animal.animalName}?'),
        content: const Text('This will return the animal to the active Registered Pets list.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final session = await ref.read(userSessionProvider.future);
    await ref.read(clinicRepositoryProvider).restoreAnimal(
          animalId: animal.animalId,
          session: session,
        );
    ref
      ..invalidate(animalSearchProvider)
      ..invalidate(archivedAnimalsProvider)
      ..invalidate(dashboardStatsProvider);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${animal.animalName} restored to active pets.')),
      );
    }
  }
}

class _Detail extends StatelessWidget {
  const _Detail({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 180,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          Text(value, maxLines: 2, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}
