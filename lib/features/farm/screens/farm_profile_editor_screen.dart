import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_providers.dart';
import '../../../core/models/animal_catalogue.dart';
import '../../../core/theme/app_theme.dart';
import '../../shared/widgets/avera_ui.dart';
import '../../shared/widgets/catalogue_selector.dart';

class FarmProfileEditorScreen extends ConsumerStatefulWidget {
  const FarmProfileEditorScreen({super.key, this.farmId});
  final String? farmId;

  bool get isEditing => farmId != null;

  @override
  ConsumerState<FarmProfileEditorScreen> createState() =>
      _FarmProfileEditorScreenState();
}

class _FarmProfileEditorScreenState
    extends ConsumerState<FarmProfileEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _location = TextEditingController();
  final _owner = TextEditingController();
  final _contact = TextEditingController();
  final _notes = TextEditingController();
  final _speciesIds = <String>{};
  final _breedIdsBySpecies = <String, Set<String>>{};
  String _farmType = 'Mixed';
  bool _loading = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (widget.isEditing) _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _location.dispose();
    _owner.dispose();
    _contact.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final dashboard = await ref
          .read(clinicRepositoryProvider)
          .getFarmDashboard(widget.farmId!);
      if (!mounted || dashboard == null) return;
      final farm = dashboard.farm;
      final speciesIds = _jsonIds(farm.speciesJson);
      final breedIds = _jsonIds(farm.breedJson);
      _name.text = farm.name;
      _location.text = farm.location ?? '';
      _owner.text = farm.ownerOrganization ?? '';
      _contact.text = farm.contactNumber ?? '';
      _notes.text = farm.notes ?? '';
      setState(() {
        _speciesIds
          ..clear()
          ..addAll(speciesIds);
        _breedIdsBySpecies.clear();
        for (final speciesId in speciesIds) {
          _breedIdsBySpecies[speciesId] = breedIds
              .where(
                (id) =>
                    AnimalCatalogue.breedBelongsToSpecies(id, speciesId) ||
                    AnimalCatalogue.resolveLegacyBreed(speciesId, id) != null,
              )
              .toSet();
        }
        _farmType = farm.farmType ?? 'Mixed';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.isEditing ? 'Edit Farm' : 'Add Farm')),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                AveraSpacing.pageHorizontalPadding,
                AveraSpacing.pageTopPadding,
                AveraSpacing.pageHorizontalPadding,
                AveraSpacing.bottomContentClearance,
              ),
              children: [
                _textField(
                  label: 'Farm Name',
                  controller: _name,
                  hint: 'Enter farm name',
                  validator: (value) => (value?.trim().length ?? 0) < 2
                      ? 'Enter the farm name.'
                      : null,
                ),
                _textField(
                  label: 'Location',
                  controller: _location,
                  hint: 'Enter farm location',
                ),
                _textField(
                  label: 'Owner or Organization',
                  controller: _owner,
                  hint: 'Enter owner or organization',
                ),
                _textField(
                  label: 'Contact Number',
                  controller: _contact,
                  hint: 'Enter contact number',
                  keyboardType: TextInputType.phone,
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: AveraSpacing.cardGap),
                  child: AveraLabeledFieldCard(
                    label: 'Species Reared',
                    child: InkWell(
                      key: const Key('farm-species-selector'),
                      onTap: _selectSpecies,
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _speciesSummary,
                              style: _speciesIds.isEmpty
                                  ? averaText(context).fieldPlaceholder
                                  : averaText(context).fieldValue,
                            ),
                          ),
                          const Icon(Icons.chevron_right_rounded),
                        ],
                      ),
                    ),
                  ),
                ),
                for (final speciesId in _orderedSelectedSpecies) ...[
                  _BreedSelector(
                    speciesId: speciesId,
                    selectedIds:
                        _breedIdsBySpecies[speciesId] ?? const <String>{},
                    onTap: () => _selectBreeds(speciesId),
                  ),
                  const SizedBox(height: AveraSpacing.cardGap),
                ],
                AveraLabeledFieldCard(
                  label: 'Farm Type',
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: _farmType,
                      items: const [
                        DropdownMenuItem(
                          value: 'Commercial',
                          child: Text('Commercial'),
                        ),
                        DropdownMenuItem(
                          value: 'Breeding',
                          child: Text('Breeding'),
                        ),
                        DropdownMenuItem(value: 'Dairy', child: Text('Dairy')),
                        DropdownMenuItem(value: 'Mixed', child: Text('Mixed')),
                      ],
                      onChanged: (value) {
                        if (value != null) setState(() => _farmType = value);
                      },
                    ),
                  ),
                ),
                const SizedBox(height: AveraSpacing.cardGap),
                _textField(
                  label: 'Notes',
                  controller: _notes,
                  hint: 'Enter relevant farm information',
                  maxLines: 4,
                ),
                const SizedBox(height: AveraSpacing.sectionGap),
                AveraPrimaryActionButton(
                  label: widget.isEditing ? 'Save Farm' : 'Create Farm',
                  icon: Icons.save_outlined,
                  loading: _saving,
                  onPressed: _saving ? null : _save,
                ),
              ],
            ),
          ),
  );

  Widget _textField({
    required String label,
    required TextEditingController controller,
    required String hint,
    TextInputType? keyboardType,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: AveraSpacing.cardGap),
    child: AveraLabeledFieldCard(
      label: label,
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        maxLines: maxLines,
        validator: validator,
        decoration: InputDecoration(hintText: hint, border: InputBorder.none),
      ),
    ),
  );

  List<String> get _orderedSelectedSpecies =>
      _speciesIds.toList()..sort((a, b) {
        final left = AnimalCatalogue.speciesById(a)?.displayName ?? a;
        final right = AnimalCatalogue.speciesById(b)?.displayName ?? b;
        return left.compareTo(right);
      });

  String get _speciesSummary {
    if (_speciesIds.isEmpty) return 'Select one or more species';
    return _orderedSelectedSpecies
        .map((id) => AnimalCatalogue.speciesById(id)?.displayName ?? id)
        .join(', ');
  }

  Future<void> _selectSpecies() async {
    final selected = await showMultiSearchableCatalogueSelector(
      context: context,
      title: 'Select Farm Species',
      selectedIds: _speciesIds,
      options: animalSpeciesPickerOptions(),
    );
    if (selected == null || !mounted || setEquals(selected, _speciesIds)) {
      return;
    }
    final removed = _speciesIds.difference(selected);
    final removesBreedData = removed.any(
      (id) => _breedIdsBySpecies[id]?.isNotEmpty == true,
    );
    if (removesBreedData) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Remove selected breed data?'),
          content: const Text(
            'Breeds selected for removed species will be discarded.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Keep Species'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Remove'),
            ),
          ],
        ),
      );
      if (discard != true || !mounted) return;
    }
    setState(() {
      _speciesIds
        ..clear()
        ..addAll(selected);
      for (final id in removed) {
        _breedIdsBySpecies.remove(id);
      }
      for (final id in selected) {
        _breedIdsBySpecies.putIfAbsent(id, () => <String>{});
      }
    });
  }

  Future<void> _selectBreeds(String speciesId) async {
    final species = AnimalCatalogue.speciesById(speciesId);
    if (species == null) return;
    final current = _breedIdsBySpecies[speciesId] ?? const <String>{};
    final canonicalIds = AnimalCatalogue.breedsForSpecies(
      speciesId,
    ).map((breed) => breed.id).toSet();
    final selected = await showMultiSearchableCatalogueSelector(
      context: context,
      title: _breedPickerTitle(species),
      selectedIds: current,
      options: [
        ...animalBreedPickerOptions(speciesId),
        for (final id in current.where((id) => !canonicalIds.contains(id)))
          CataloguePickerOption(
            id: id,
            title:
                AnimalCatalogue.resolveLegacyBreed(
                  speciesId,
                  id,
                )?.displayName ??
                AnimalCatalogue.breedDisplayName(id),
            subtitle: AnimalCatalogue.isCustomBreedId(id)
                ? 'Custom breed'
                : 'Saved legacy breed',
          ),
      ],
    );
    if (selected == null || !mounted) return;
    final resolved = {...selected};
    final customPlaceholders = resolved.where(
      (id) =>
          AnimalCatalogue.breedById(id)?.allowsCustomBreed == true &&
          !AnimalCatalogue.isCustomBreedId(id),
    );
    for (final placeholder in customPlaceholders.toList()) {
      resolved.remove(placeholder);
      final customName = await requestCustomBreedName(
        context: context,
        species: species,
      );
      if (!mounted) return;
      if (customName != null) {
        resolved.add(
          AnimalCatalogue.customBreedId(speciesId: speciesId, name: customName),
        );
      }
    }
    setState(() => _breedIdsBySpecies[speciesId] = resolved);
  }

  String _breedPickerTitle(AnimalSpeciesOption species) {
    final label = AnimalCatalogue.breedFieldLabel(species);
    return 'Select ${species.displayName} ${label == 'Breed' ? 'Breeds' : label}';
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_speciesIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select at least one farm species.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final repository = ref.read(clinicRepositoryProvider);
      final session = await ref.read(userSessionProvider.future);
      final breedIds = _breedIdsBySpecies.values
          .expand((items) => items)
          .toList();
      final farm = widget.isEditing
          ? await repository.updateFarm(
              session: session,
              farmId: widget.farmId!,
              name: _name.text,
              location: _location.text,
              ownerOrganization: _owner.text,
              contactNumber: _contact.text,
              farmType: _farmType,
              notes: _notes.text,
              speciesIds: _speciesIds.toList(),
              breedIds: breedIds,
            )
          : await repository.createFarm(
              session: session,
              name: _name.text,
              location: _location.text,
              ownerOrganization: _owner.text,
              contactNumber: _contact.text,
              farmType: _farmType,
              notes: _notes.text,
              speciesIds: _speciesIds.toList(),
              breedIds: breedIds,
            );
      if (!mounted) return;
      context.go('/farm-records/${farm.id}');
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _BreedSelector extends StatelessWidget {
  const _BreedSelector({
    required this.speciesId,
    required this.selectedIds,
    required this.onTap,
  });
  final String speciesId;
  final Set<String> selectedIds;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final species = AnimalCatalogue.speciesById(speciesId);
    final names = selectedIds.map(AnimalCatalogue.breedDisplayName).toList()
      ..sort();
    return AveraLabeledFieldCard(
      label:
          '${species?.displayName ?? speciesId} ${AnimalCatalogue.breedFieldLabel(species)}s',
      child: InkWell(
        key: Key('farm-breed-selector-$speciesId'),
        onTap: onTap,
        child: Row(
          children: [
            Expanded(
              child: Text(
                selectedIds.isEmpty ? 'Select breeds' : names.join(', '),
                style: selectedIds.isEmpty
                    ? averaText(context).fieldPlaceholder
                    : averaText(context).fieldValue,
              ),
            ),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    );
  }
}

Set<String> _jsonIds(String value) {
  try {
    return (jsonDecode(value) as List).map((item) => '$item').toSet();
  } catch (_) {
    return {};
  }
}
