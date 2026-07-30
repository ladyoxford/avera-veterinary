import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/config/app_providers.dart';

class VaccinationProtocolsScreen extends ConsumerWidget {
  const VaccinationProtocolsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final protocols = ref.watch(vaccinationProtocolsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Vaccination Protocols')),
      body: protocols.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) =>
            Center(child: Text('Unable to load protocols: $error')),
        data: (items) => ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final protocol = items[index];
            return Card(
              child: ExpansionTile(
                leading: const Icon(Iconsax.shield_tick),
                title: Text('${protocol.species} • ${protocol.vaccine}'),
                subtitle: Text(
                  '${protocol.recommendedAge} • ${protocol.route ?? 'Route not set'}',
                ),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: [
                  _Line('Protects', protocol.diseasesProtectedAgainst),
                  _Line('Dose', protocol.dose),
                  _Line('Storage', protocol.storageRequirements),
                  _Line('Booster', protocol.boosterSchedule),
                  _Line('Contraindications', protocol.contraindications),
                  _Line('Adverse Effects', protocol.possibleAdverseEffects),
                  _Line('Precautions', protocol.precautions),
                  _Line('References', protocol.references),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.label, this.value);

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(label, style: Theme.of(context).textTheme.labelLarge),
          ),
          Expanded(child: Text(value ?? '-')),
        ],
      ),
    );
  }
}
