import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_providers.dart';
import '../../../core/remote/api_client.dart';
import '../../../core/models/animal_search_result.dart';
import '../../../core/repositories/clinic_repository.dart';
import '../../../core/services/animal_age_service.dart';
import '../../../core/theme/app_theme.dart';
import 'cloud_patient_screens.dart';

class AnimalSearchScreen extends ConsumerWidget {
  const AnimalSearchScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (BackendConfiguration.isConfigured) {
      return const CloudPatientListScreen();
    }
    final results = ref.watch(animalSearchProvider);
    final filter = ref.watch(animalStatusFilterProvider);
    final theme = Theme.of(context);

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        tooltip: 'Register Pet',
        icon: const Icon(Icons.add_rounded),
        label: const Text('Register pet'),
        onPressed: () => context.push('/animals/new'),
      ),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              sliver: SliverToBoxAdapter(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1120),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Registered Pets',
                        style: theme.extension<AveraTextStyles>()!.pageTitle,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Search and manage your clinic patient records',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ),
            SliverPersistentHeader(
              pinned: true,
              delegate: _PatientToolbarDelegate(
                filter: filter,
                onFilterChanged: (value) =>
                    ref.read(animalStatusFilterProvider.notifier).state = value,
                onSearchChanged: (value) =>
                    ref.read(animalSearchQueryProvider.notifier).state = value,
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 96),
              sliver: results.when(
                loading: () => const _PatientListSkeleton(),
                error: (error, _) => SliverFillRemaining(
                  hasScrollBody: false,
                  child: _ErrorState(
                    message: 'We could not load patient records.\n$error',
                  ),
                ),
                data: (animals) {
                  if (animals.isEmpty) {
                    return SliverFillRemaining(
                      hasScrollBody: false,
                      child: _EmptyPatientState(
                        filter: filter,
                        onRegister: () => context.push('/animals/new'),
                      ),
                    );
                  }
                  return SliverToBoxAdapter(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1120),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 220),
                          child: _PatientList(
                            key: ValueKey(filter),
                            animals: animals,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PatientToolbarDelegate extends SliverPersistentHeaderDelegate {
  const _PatientToolbarDelegate({
    required this.filter,
    required this.onFilterChanged,
    required this.onSearchChanged,
  });

  final AnimalStatusFilter filter;
  final ValueChanged<AnimalStatusFilter> onFilterChanged;
  final ValueChanged<String> onSearchChanged;

  @override
  double get minExtent => 132;

  @override
  double get maxExtent => 132;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final theme = Theme.of(context);
    return ColoredBox(
      color: theme.scaffoldBackgroundColor,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1160),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: 42,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: AnimalStatusFilter.values.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final item = AnimalStatusFilter.values[index];
                      return ChoiceChip(
                        label: Text(item.label),
                        selected: item == filter,
                        onSelected: (_) => onFilterChanged(item),
                        avatar: item == filter
                            ? const Icon(Icons.check_rounded, size: 16)
                            : null,
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 56,
                  child: SearchBar(
                    elevation: const WidgetStatePropertyAll(0),
                    shape: const WidgetStatePropertyAll(
                      RoundedRectangleBorder(
                        borderRadius: BorderRadius.all(Radius.circular(24)),
                      ),
                    ),
                    padding: const WidgetStatePropertyAll(
                      EdgeInsets.symmetric(horizontal: 16),
                    ),
                    leading: const Icon(Icons.search_rounded),
                    trailing: const [Icon(Icons.tune_rounded, size: 20)],
                    hintText:
                        'Search name, hospital number, owner, phone, species, breed or microchip',
                    onChanged: onSearchChanged,
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _PatientToolbarDelegate oldDelegate) =>
      filter != oldDelegate.filter;
}

class _PatientList extends StatelessWidget {
  const _PatientList({super.key, required this.animals});

  final List<AnimalSearchResult> animals;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      shrinkWrap: true,
      primary: false,
      itemCount: animals.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) => _AnimalSearchCard(animal: animals[index])
          .animate()
          .fadeIn(
            delay: Duration(milliseconds: 25 * index),
            duration: 180.ms,
          )
          .slideY(begin: .03, end: 0, duration: 180.ms),
    );
  }
}

class _AnimalSearchCard extends ConsumerWidget {
  const _AnimalSearchCard({required this.animal});

  final AnimalSearchResult animal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isArchived = animal.status != AnimalStatuses.active;
    final subtitleColor = theme.colorScheme.onSurfaceVariant;
    final isLargeLayout = MediaQuery.sizeOf(context).width >= 600;

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AveraSpacing.cardRadius),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(AveraSpacing.cardRadius),
        onTap: () => context.push('/animals/${animal.animalId}'),
        onLongPress: isArchived ? null : () => _showStatusSheet(context, ref),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _PatientAvatar(animal: animal),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            animal.animalName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontSize: isLargeLayout ? 18 : 17,
                              height: 1.18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (isArchived) ...[
                          const SizedBox(width: 8),
                          _StatusBadge(status: animal.status),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      animal.hospitalNumber,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontSize: 13,
                        height: 1.25,
                        fontWeight: FontWeight.w500,
                        color: subtitleColor,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _signalment(
                        animal,
                        ref.watch(animalAgeReferenceDateProvider),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontSize: 13,
                        height: 1.3,
                        fontWeight: FontWeight.w400,
                        color: subtitleColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${animal.ownerName}  •  ${animal.ownerPhone}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontSize: 13,
                        height: 1.25,
                        fontWeight: FontWeight.w400,
                        color: subtitleColor,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right_rounded, color: subtitleColor),
            ],
          ),
        ),
      ),
    );
  }

  String _signalment(AnimalSearchResult animal, DateTime referenceDate) => [
    animal.species,
    if (animal.breed?.trim().isNotEmpty ?? false) animal.breed!,
    if (animal.sex?.trim().isNotEmpty ?? false) animal.sex!,
    if (animal.dateOfBirth != null)
      AnimalAgeService.displayAge(
        birthDate: animal.dateOfBirth!,
        referenceDate: referenceDate,
        estimated: animal.isDateOfBirthEstimated,
        compact: true,
      ),
  ].join('  •  ');

  Future<void> _showStatusSheet(BuildContext context, WidgetRef ref) async {
    final session = await ref.read(userSessionProvider.future);
    if (!session.can('Manage Animal Status')) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'You do not have permission to manage animal status.',
            ),
          ),
        );
      }
      return;
    }

    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                leading: const Icon(Icons.heart_broken_rounded),
                title: const Text('Mark as Deceased'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _confirmStatus(context, ref, AnimalStatuses.deceased);
                },
              ),
              ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                leading: const Icon(Icons.location_on_outlined),
                title: const Text('Mark as Relocated'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _confirmStatus(context, ref, AnimalStatuses.relocated);
                },
              ),
              ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                leading: const Icon(Icons.close_rounded),
                title: const Text('Cancel'),
                onTap: () => Navigator.of(sheetContext).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmStatus(
    BuildContext context,
    WidgetRef ref,
    String status,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Mark ${animal.animalName} as $status?'),
        content: const Text(
          'The complete medical, billing, vaccination, and consultation history will remain available.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final session = await ref.read(userSessionProvider.future);
    await ref
        .read(clinicRepositoryProvider)
        .updateAnimalStatus(
          animalId: animal.animalId,
          newStatus: status,
          session: session,
          notes: 'Changed from active patient list.',
        );
    ref
      ..invalidate(animalSearchProvider)
      ..invalidate(archivedAnimalsProvider)
      ..invalidate(dashboardStatsProvider);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${animal.animalName} marked as $status.')),
      );
    }
  }
}

class _PatientAvatar extends StatelessWidget {
  const _PatientAvatar({required this.animal});

  final AnimalSearchResult animal;

  @override
  Widget build(BuildContext context) {
    final initials = animal.animalName
        .trim()
        .split(RegExp(r'\s+'))
        .take(2)
        .map((part) => part[0])
        .join();
    final color = _avatarColors[animal.animalId.abs() % _avatarColors.length];
    final imagePath = animal.photo;

    return Semantics(
      label: '${animal.animalName} patient photo',
      child: SizedBox(
        width: 56,
        height: 56,
        child: ClipOval(
          child: imagePath == null || imagePath.isEmpty
              ? _InitialAvatar(initials: initials, color: color)
              : Image.file(
                  File(imagePath),
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      _InitialAvatar(initials: initials, color: color),
                  frameBuilder:
                      (context, child, frame, wasSynchronouslyLoaded) =>
                          wasSynchronouslyLoaded
                          ? child
                          : child.animate().fadeIn(duration: 180.ms),
                ),
        ),
      ),
    );
  }
}

class _InitialAvatar extends StatelessWidget {
  const _InitialAvatar({required this.initials, required this.color});

  final String initials;
  final Color color;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: color,
    child: Center(
      child: Text(
        initials.toUpperCase(),
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final semantic = Theme.of(context).extension<AppSemanticColors>()!;
    final color = switch (status) {
      AnimalStatuses.deceased => semantic.danger,
      AnimalStatuses.relocated => semantic.warning,
      _ => semantic.success,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        status,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }
}

class _PatientListSkeleton extends StatelessWidget {
  const _PatientListSkeleton();

  @override
  Widget build(BuildContext context) => SliverList.builder(
    itemCount: 6,
    itemBuilder: (context, index) => const Padding(
      padding: EdgeInsets.only(bottom: 12),
      child: _SkeletonCard(),
    ),
  );
}

class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard();

  @override
  Widget build(BuildContext context) {
    final shade = Theme.of(
      context,
    ).colorScheme.surfaceContainerHighest.withValues(alpha: .55);
    return Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AveraSpacing.cardRadius),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                CircleAvatar(radius: 30, backgroundColor: shade),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SkeletonLine(width: 150, color: shade),
                      const SizedBox(height: 10),
                      _SkeletonLine(width: 96, color: shade),
                      const SizedBox(height: 14),
                      _SkeletonLine(width: double.infinity, color: shade),
                      const SizedBox(height: 8),
                      _SkeletonLine(width: 180, color: shade),
                    ],
                  ),
                ),
              ],
            ),
          ),
        )
        .animate(onPlay: (controller) => controller.repeat())
        .shimmer(duration: 1200.ms);
  }
}

class _SkeletonLine extends StatelessWidget {
  const _SkeletonLine({required this.width, required this.color});
  final double width;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: 12,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(8),
    ),
  );
}

class _EmptyPatientState extends StatelessWidget {
  const _EmptyPatientState({required this.filter, required this.onRegister});
  final AnimalStatusFilter filter;
  final VoidCallback onRegister;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.pets_outlined,
            size: 52,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text(
            'No ${filter.label.toLowerCase()} patients found.',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            'Try a different search or register a new patient.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: onRegister,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Register pet'),
          ),
        ],
      ),
    ),
  );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Text(message, textAlign: TextAlign.center),
    ),
  );
}

const _avatarColors = [
  Color(0xFF2878B5),
  Color(0xFF4A8B69),
  Color(0xFF8A6093),
  Color(0xFFC1784E),
  Color(0xFF397D83),
  Color(0xFF8A6C38),
];
