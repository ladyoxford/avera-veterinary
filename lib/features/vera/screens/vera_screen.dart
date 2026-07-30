import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_providers.dart';
import '../../../core/services/feature_gate_service.dart';
import '../../../core/theme/app_theme.dart';

class VeraScreen extends ConsumerStatefulWidget {
  const VeraScreen({super.key, this.patientId, this.patientName});

  final int? patientId;
  final String? patientName;

  @override
  ConsumerState<VeraScreen> createState() => _VeraScreenState();
}

class _VeraScreenState extends ConsumerState<VeraScreen> {
  final _question = TextEditingController();

  @override
  void dispose() {
    _question.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final session = ref.watch(userSessionProvider).valueOrNull;
    final scope = session == null
        ? 'local:anonymous'
        : '${session.clinic.clinicId}:${session.user.userId}';
    final conversations = ref.watch(veraConversationsProvider(scope));
    final firstName = (session?.user.fullName ?? 'there').split(' ').first;
    final plan = SubscriptionPlan.fromStorage(
      session?.clinic.subscriptionPlan ?? SubscriptionPlan.starter.label,
    );

    return Scaffold(
      endDrawer: _VeraHistoryDrawer(
        conversations: conversations,
        onPin: (conversation) => ref
            .read(veraConversationsProvider(scope).notifier)
            .togglePinned(conversation.id),
      ),
      appBar: AppBar(
        titleSpacing: 16,
        title: const Row(
          children: [
            VeraMark(size: 32),
            SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Vera'),
                Text(
                  'Veterinary Clinical Intelligence',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ],
        ),
        actions: [
          Builder(
            builder: (context) => IconButton(
              tooltip: 'Vera history',
              onPressed: () => Scaffold.of(context).openEndDrawer(),
              icon: const Icon(Icons.history_rounded),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 36),
        children: [
          Text('Hello $firstName', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text(
            'How can I assist today?',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 18),
          _VeraSubscriptionBanner(plan: plan),
          if (widget.patientName != null) ...[
            const SizedBox(height: 18),
            _PatientContextBanner(name: widget.patientName!),
          ],
          const SizedBox(height: 22),
          _PromptCard(controller: _question, onSubmit: () => _submit(scope)),
          const SizedBox(height: 28),
          Text('Clinical tools', style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            'Choose a starting point for your clinical question.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 680 ? 4 : 2;
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _quickActions.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: columns == 2 ? 1.42 : 1.28,
                ),
                itemBuilder: (context, index) => _QuickActionCard(
                  action: _quickActions[index],
                  plan: plan,
                  onTap: () {
                    final action = _quickActions[index];
                    if (plan.index < action.minimumPlan.index) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            '${action.title} requires ${action.minimumPlan.label}.',
                          ),
                        ),
                      );
                      return;
                    }
                    setState(() => _question.text = action.prompt);
                  },
                ),
              );
            },
          ),
          if (conversations.isNotEmpty) ...[
            const SizedBox(height: 30),
            Text('This session', style: theme.textTheme.titleLarge),
            const SizedBox(height: 10),
            for (final conversation in conversations.take(3))
              _ConversationPreview(conversation: conversation),
          ],
          const SizedBox(height: 30),
          _ClinicalSafetyNotice(),
        ],
      ),
    );
  }

  void _submit(String scope) {
    final question = _question.text.trim();
    if (question.isEmpty) return;
    final session = ref.read(userSessionProvider).valueOrNull;
    ref
        .read(veraConversationsProvider(scope).notifier)
        .add(
          title: question,
          clinicId: session?.clinic.clinicId ?? 'local',
          userId: session?.user.userId ?? 'anonymous',
          patientId: widget.patientId,
        );
    _question.clear();
    FocusScope.of(context).unfocus();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Vera clinical responses are coming soon. Your question was saved to this session.',
        ),
      ),
    );
  }
}

class VeraMark extends StatelessWidget {
  const VeraMark({super.key, this.size = 48});
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: CustomPaint(painter: _VeraMarkPainter()),
  );
}

class _VeraMarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()
      ..shader = const LinearGradient(
        colors: [AppTheme.primary, AppTheme.secondary],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(Offset.zero & size)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * .11
      ..strokeCap = StrokeCap.round;
    final path = Path()
      ..moveTo(size.width * .2, size.height * .72)
      ..lineTo(size.width * .5, size.height * .18)
      ..lineTo(size.width * .8, size.height * .72);
    canvas.drawPath(path, paint);
    canvas.drawLine(
      Offset(size.width * .34, size.height * .52),
      Offset(size.width * .66, size.height * .52),
      paint,
    );
    final node = Paint()..color = AppTheme.accent;
    for (final point in [
      Offset(size.width * .3, size.height * .72),
      Offset(size.width * .5, size.height * .18),
      Offset(size.width * .7, size.height * .72),
    ]) {
      canvas.drawCircle(point, size.width * .065, node);
    }
    canvas.drawCircle(center, size.width * .07, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _PromptCard extends StatelessWidget {
  const _PromptCard({required this.controller, required this.onSubmit});
  final TextEditingController controller;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Row(
        children: [
          const VeraMark(size: 36),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSubmit(),
              decoration: const InputDecoration(
                border: InputBorder.none,
                hintText: 'Ask Vera anything...',
              ),
            ),
          ),
          IconButton.filled(
            tooltip: 'Ask Vera',
            onPressed: onSubmit,
            icon: const Icon(Icons.arrow_upward_rounded),
          ),
        ],
      ),
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({
    required this.action,
    required this.plan,
    required this.onTap,
  });
  final _VeraQuickAction action;
  final SubscriptionPlan plan;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final locked = plan.index < action.minimumPlan.index;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: colors.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  locked ? Icons.lock_outline_rounded : action.icon,
                  size: 20,
                  color: colors.onPrimaryContainer,
                ),
              ),
              const Spacer(),
              Text(
                action.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  locked
                      ? 'Requires ${action.minimumPlan.label}'
                      : 'Coming Soon',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VeraSubscriptionBanner extends StatelessWidget {
  const _VeraSubscriptionBanner({required this.plan});
  final SubscriptionPlan plan;

  @override
  Widget build(BuildContext context) {
    final definition = FeatureGateService.plan(plan);
    final detail = switch (plan) {
      SubscriptionPlan.starter =>
        'General veterinary assistance without patient context.',
      SubscriptionPlan.professional =>
        'Patient-aware clinical support, subject to veterinary review.',
      SubscriptionPlan.enterprise =>
        'Organisation-wide clinical, operational, and predictive intelligence.',
    };
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const VeraMark(size: 38),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  definition.veraLevel,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 3),
                Text(
                  '$detail Coming Soon.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ClinicalSafetyNotice extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.secondaryContainer,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.verified_user_outlined,
            color: colors.onSecondaryContainer,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Clinical decisions remain the responsibility of the attending veterinarian. Vera will present recommendations with confidence, supporting evidence, references and clinical notes when its response service is enabled.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colors.onSecondaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PatientContextBanner extends StatelessWidget {
  const _PatientContextBanner({required this.name});
  final String name;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.tertiaryContainer,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(
      children: [
        Icon(
          Icons.pets_rounded,
          color: Theme.of(context).colorScheme.onTertiaryContainer,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'Patient context ready: $name',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.onTertiaryContainer,
            ),
          ),
        ),
      ],
    ),
  );
}

class _ConversationPreview extends StatelessWidget {
  const _ConversationPreview({required this.conversation});
  final VeraConversation conversation;
  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: const VeraMark(size: 34),
      title: Text(
        conversation.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text('Saved question - responses coming soon'),
      trailing: conversation.pinned ? const Icon(Icons.push_pin_rounded) : null,
    ),
  );
}

class _VeraHistoryDrawer extends StatefulWidget {
  const _VeraHistoryDrawer({required this.conversations, required this.onPin});
  final List<VeraConversation> conversations;
  final ValueChanged<VeraConversation> onPin;
  @override
  State<_VeraHistoryDrawer> createState() => _VeraHistoryDrawerState();
}

class _VeraHistoryDrawerState extends State<_VeraHistoryDrawer> {
  String query = '';
  @override
  Widget build(BuildContext context) {
    final filtered = widget.conversations
        .where((item) => item.title.toLowerCase().contains(query.toLowerCase()))
        .toList();
    return Drawer(
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Vera history',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 14),
              TextField(
                onChanged: (value) => setState(() => query = value),
                decoration: const InputDecoration(
                  hintText: 'Search conversations',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
              ),
              const SizedBox(height: 14),
              Expanded(
                child: filtered.isEmpty
                    ? const Center(child: Text('No Vera conversations yet.'))
                    : ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final item = filtered[index];
                          return ListTile(
                            leading: const VeraMark(size: 30),
                            title: Text(
                              item.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              item.createdAt.toLocal().toString().substring(
                                0,
                                16,
                              ),
                            ),
                            trailing: IconButton(
                              tooltip: item.pinned
                                  ? 'Unpin conversation'
                                  : 'Pin conversation',
                              onPressed: () => widget.onPin(item),
                              icon: Icon(
                                item.pinned
                                    ? Icons.push_pin_rounded
                                    : Icons.push_pin_outlined,
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class VeraConversation {
  const VeraConversation({
    required this.id,
    required this.title,
    required this.clinicId,
    required this.userId,
    required this.createdAt,
    this.patientId,
    this.pinned = false,
  });
  final String id;
  final String title;
  final String clinicId;
  final String userId;
  final int? patientId;
  final DateTime createdAt;
  final bool pinned;
  VeraConversation copyWith({bool? pinned}) => VeraConversation(
    id: id,
    title: title,
    clinicId: clinicId,
    userId: userId,
    patientId: patientId,
    createdAt: createdAt,
    pinned: pinned ?? this.pinned,
  );
}

class VeraConversationsController
    extends StateNotifier<List<VeraConversation>> {
  VeraConversationsController() : super(const []);
  void add({
    required String title,
    required String clinicId,
    required String userId,
    int? patientId,
  }) {
    final conversation = VeraConversation(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: title,
      clinicId: clinicId,
      userId: userId,
      patientId: patientId,
      createdAt: DateTime.now(),
    );
    state = [conversation, ...state];
  }

  void togglePinned(String id) => state = [
    for (final item in state)
      item.id == id ? item.copyWith(pinned: !item.pinned) : item,
  ];
}

final veraConversationsProvider =
    StateNotifierProvider.family<
      VeraConversationsController,
      List<VeraConversation>,
      String
    >((ref, scope) => VeraConversationsController());

class _VeraQuickAction {
  const _VeraQuickAction(
    this.title,
    this.icon,
    this.prompt, {
    this.minimumPlan = SubscriptionPlan.starter,
  });
  final String title;
  final IconData icon;
  final String prompt;
  final SubscriptionPlan minimumPlan;
}

const _quickActions = <_VeraQuickAction>[
  _VeraQuickAction(
    'Clinical Diagnosis',
    Icons.health_and_safety_outlined,
    'Help me structure differentials for this case.',
    minimumPlan: SubscriptionPlan.professional,
  ),
  _VeraQuickAction(
    'Drug Safety',
    Icons.medication_outlined,
    'Review drug safety considerations for this treatment.',
    minimumPlan: SubscriptionPlan.professional,
  ),
  _VeraQuickAction(
    'Treatment Planner',
    Icons.assignment_turned_in_outlined,
    'Help me draft a treatment plan.',
    minimumPlan: SubscriptionPlan.professional,
  ),
  _VeraQuickAction(
    'Laboratory Interpretation',
    Icons.science_outlined,
    'Help me interpret these laboratory results.',
    minimumPlan: SubscriptionPlan.professional,
  ),
  _VeraQuickAction(
    'Radiology Assistant',
    Icons.image_search_outlined,
    'Help me structure a radiology review.',
    minimumPlan: SubscriptionPlan.enterprise,
  ),
  _VeraQuickAction(
    'Fluid Calculator',
    Icons.water_drop_outlined,
    'Help me calculate fluid therapy.',
  ),
  _VeraQuickAction(
    'Dose Calculator',
    Icons.calculate_outlined,
    'Help me calculate a medication dose.',
  ),
  _VeraQuickAction(
    'SOAP Notes',
    Icons.note_alt_outlined,
    'Help me draft SOAP notes.',
    minimumPlan: SubscriptionPlan.professional,
  ),
  _VeraQuickAction(
    'Clinical Guidelines',
    Icons.menu_book_outlined,
    'Find clinical guidance for this case.',
  ),
  _VeraQuickAction(
    'Differential Diagnosis',
    Icons.account_tree_outlined,
    'Generate a differential diagnosis framework.',
    minimumPlan: SubscriptionPlan.professional,
  ),
  _VeraQuickAction(
    'Hospitalization Review',
    Icons.local_hospital_outlined,
    'Review this hospitalization plan.',
    minimumPlan: SubscriptionPlan.professional,
  ),
  _VeraQuickAction(
    'Vaccination Advisor',
    Icons.vaccines_outlined,
    'Review this vaccination schedule.',
  ),
  _VeraQuickAction(
    'Patient Summary',
    Icons.summarize_outlined,
    'Summarize this patient record.',
    minimumPlan: SubscriptionPlan.professional,
  ),
  _VeraQuickAction(
    'Inventory Assistant',
    Icons.inventory_2_outlined,
    'Review inventory considerations.',
  ),
  _VeraQuickAction(
    'Research Assistant',
    Icons.travel_explore_outlined,
    'Help me frame a veterinary research question.',
  ),
];
