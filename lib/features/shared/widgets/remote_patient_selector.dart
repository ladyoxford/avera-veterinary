import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/remote/cloud_clinical_state.dart';
import '../../../core/remote/clinical_remote_data_source.dart';
import 'avera_ui.dart';

class RemotePatientSelectorSheet extends ConsumerStatefulWidget {
  const RemotePatientSelectorSheet({
    super.key,
    this.selectedId,
    this.ownerId,
    this.excludedIds = const {},
    this.title = 'Select Patient',
  });

  final String? selectedId;
  final String? ownerId;
  final Set<String> excludedIds;
  final String title;

  @override
  ConsumerState<RemotePatientSelectorSheet> createState() =>
      _RemotePatientSelectorSheetState();
}

class _RemotePatientSelectorSheetState
    extends ConsumerState<RemotePatientSelectorSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final directory = ref.watch(remotePatientDirectoryProvider);
    final query = _query.trim().toLowerCase();
    final patients = directory.items
        .where((patient) {
          if (widget.excludedIds.contains(patient.id)) return false;
          if (widget.ownerId != null && patient.ownerId != widget.ownerId) {
            return false;
          }
          if (query.isEmpty) return true;
          return '${patient.name} ${patient.hospitalNumber} ${patient.ownerName} ${patient.ownerPhone}'
              .toLowerCase()
              .contains(query);
        })
        .toList(growable: false);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.title, style: averaText(context).sectionTitle),
            const SizedBox(height: 12),
            TextField(
              autofocus: true,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search_rounded),
                hintText: 'Search patient, hospital number or owner',
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _DirectoryBody(
                state: directory,
                patients: patients,
                hasQuery: query.isNotEmpty,
                selectedId: widget.selectedId,
                onRetry: () =>
                    ref.read(remotePatientDirectoryProvider.notifier).refresh(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DirectoryBody extends StatelessWidget {
  const _DirectoryBody({
    required this.state,
    required this.patients,
    required this.hasQuery,
    required this.selectedId,
    required this.onRetry,
  });

  final RemotePatientDirectoryState state;
  final List<RemotePatient> patients;
  final bool hasQuery;
  final String? selectedId;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (state.isLoading && state.items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.error != null && state.items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Patient records could not be loaded.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }
    if (patients.isEmpty) {
      return Center(
        child: Text(
          hasQuery
              ? 'No active patients match this search.'
              : 'No active patients are registered for this clinic.',
          textAlign: TextAlign.center,
        ),
      );
    }
    return Column(
      children: [
        if (state.fromCache)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                const Icon(Icons.cloud_off_outlined, size: 16),
                const SizedBox(width: 6),
                Text(
                  'Showing saved patients',
                  style: averaText(context).caption,
                ),
              ],
            ),
          ),
        Expanded(
          child: ListView.separated(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            itemCount: patients.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final patient = patients[index];
              final initial = patient.name.trim().isEmpty
                  ? '?'
                  : patient.name.trim()[0].toUpperCase();
              return ListTile(
                leading: CircleAvatar(child: Text(initial)),
                title: Text(
                  patient.name,
                  style: averaText(context).listItemTitle,
                ),
                subtitle: Text(
                  '${patient.hospitalNumber} | ${patient.species}${patient.breed == null ? '' : ' | ${patient.breed}'}\nOwner: ${patient.ownerName}',
                  style: averaText(context).listItemSubtitle,
                ),
                isThreeLine: true,
                trailing: patient.id == selectedId
                    ? const Icon(Icons.check_rounded)
                    : const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.of(context).pop(patient),
              );
            },
          ),
        ),
      ],
    );
  }
}
