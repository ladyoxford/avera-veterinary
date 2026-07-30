import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/config/app_providers.dart';
import '../../../core/database/app_database.dart' as local_db show Notification;
import '../../../core/models/alert_destination.dart';
import '../../../core/repositories/clinic_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../widgets/avera_ui.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(userSessionProvider).valueOrNull;
    final notifications = ref.watch(notificationsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notification Center'),
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/');
            }
          },
        ),
        actions: [
          notifications.when(
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
            data: (items) => items.isEmpty || session == null
                ? const SizedBox.shrink()
                : TextButton(
                    onPressed: () =>
                        _confirmClearAll(context, ref, session, items),
                    child: const Text('Clear All'),
                  ),
          ),
        ],
      ),
      body: notifications.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) =>
            const Center(child: Text('Unable to load notifications.')),
        data: (items) {
          if (items.isEmpty) {
            return const Center(child: _EmptyNotifications());
          }
          if (session == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(
              20,
              20,
              20,
              AveraSpacing.bottomContentClearance,
            ),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) => _NotificationCard(
              item: items[index],
              onTap: () =>
                  _showNotificationDetails(context, ref, session, items[index]),
              onLongPress: () =>
                  _showManageSheet(context, ref, session, items[index]),
            ),
          );
        },
      ),
    );
  }

  Future<void> _openNotification(
    BuildContext context,
    WidgetRef ref,
    UserSession session,
    local_db.Notification item,
  ) async {
    final repository = ref.read(clinicRepositoryProvider);
    final status = InAppNotificationStatusStorage.fromStorage(
      item.status,
      isRead: item.isRead,
    );
    if (status == InAppNotificationStatus.unread) {
      await repository.markNotificationRead(
        session: session,
        notificationId: item.id,
      );
    }
    if (!context.mounted) return;
    _openDestination(context, item);
  }

  Future<void> _showNotificationDetails(
    BuildContext context,
    WidgetRef ref,
    UserSession session,
    local_db.Notification item,
  ) async {
    final status = InAppNotificationStatusStorage.fromStorage(
      item.status,
      isRead: item.isRead,
    );
    if (status == InAppNotificationStatus.unread) {
      await ref
          .read(clinicRepositoryProvider)
          .markNotificationRead(session: session, notificationId: item.id);
    }
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => _NotificationDetailsSheet(
        item: item,
        onOpenRelated: () {
          Navigator.of(sheetContext).pop();
          _openDestination(context, item);
        },
        onReview: () async {
          Navigator.of(sheetContext).pop();
          await ref
              .read(clinicRepositoryProvider)
              .markNotificationReviewed(
                session: session,
                notificationId: item.id,
              );
        },
        onDismiss: () async {
          Navigator.of(sheetContext).pop();
          await ref
              .read(clinicRepositoryProvider)
              .dismissNotification(session: session, notificationId: item.id);
        },
      ),
    );
  }

  Future<void> _confirmClearAll(
    BuildContext context,
    WidgetRef ref,
    UserSession session,
    List<local_db.Notification> items,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear all notifications?'),
        content: const Text(
          'This will remove notifications from your Notification Center and Android notification tray. Related patients, vaccinations, appointments and inventory records will not be deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Clear Notifications'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref
        .read(clinicRepositoryProvider)
        .dismissAllNotifications(session: session);
    final service = ref.read(appointmentNotificationServiceProvider);
    for (final item in items) {
      final systemId = item.systemNotificationId;
      if (systemId != null) await service.cancelReminder(systemId);
    }
  }

  Future<void> _showManageSheet(
    BuildContext context,
    WidgetRef ref,
    UserSession session,
    local_db.Notification item,
  ) async {
    HapticFeedback.selectionClick();
    final status = InAppNotificationStatusStorage.fromStorage(
      item.status,
      isRead: item.isRead,
    );
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Manage Notification',
                style: averaText(sheetContext).pageTitle,
              ),
              const SizedBox(height: 16),
              _ManageHeader(item: item, status: status),
              const SizedBox(height: 16),
              _SheetAction(
                icon: Icons.open_in_new_rounded,
                title: 'Open Related Record',
                subtitle: 'Open the record connected to this alert.',
                onTap: () {
                  Navigator.pop(sheetContext);
                  _openNotification(context, ref, session, item);
                },
              ),
              if (status == InAppNotificationStatus.unread ||
                  status == InAppNotificationStatus.read)
                _SheetAction(
                  icon: Icons.task_alt_rounded,
                  title: 'Mark as reviewed',
                  subtitle: 'Confirm that you have reviewed this alert.',
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    await ref
                        .read(clinicRepositoryProvider)
                        .markNotificationReviewed(
                          session: session,
                          notificationId: item.id,
                        );
                  },
                ),
              if (status == InAppNotificationStatus.read ||
                  status == InAppNotificationStatus.reviewed)
                _SheetAction(
                  icon: Icons.mark_email_unread_rounded,
                  title: 'Mark as unread',
                  subtitle: 'Return this alert to the unread inbox.',
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    await ref
                        .read(clinicRepositoryProvider)
                        .markNotificationUnread(
                          session: session,
                          notificationId: item.id,
                        );
                  },
                ),
              _SheetAction(
                icon: Icons.notifications_off_rounded,
                title: 'Dismiss Notification',
                subtitle:
                    'Remove this notification. The related record remains unchanged.',
                destructive: true,
                onTap: () async {
                  Navigator.pop(sheetContext);
                  await ref
                      .read(clinicRepositoryProvider)
                      .dismissNotification(
                        session: session,
                        notificationId: item.id,
                      );
                  final systemId = item.systemNotificationId;
                  if (systemId != null) {
                    await ref
                        .read(appointmentNotificationServiceProvider)
                        .cancelReminder(systemId);
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void _openDestination(BuildContext context, local_db.Notification item) {
  final destination = AlertDestinationTypeStorage.fromStorage(
    item.destinationType,
  );
  final entityId = item.destinationEntityId;
  switch (destination) {
    case AlertDestinationType.vaccinationRecord when entityId != null:
      context.push('/vaccinations/$entityId');
    case AlertDestinationType.appointmentDetail when entityId != null:
      context.push('/appointments/$entityId');
    case AlertDestinationType.patientDetail when entityId != null:
      context.push('/animals/$entityId');
    case AlertDestinationType.consultationDetail when entityId != null:
      context.push('/consultations/$entityId');
    case AlertDestinationType.inventoryFilteredList:
      context.push('/inventory');
    case AlertDestinationType.vaccineScheduleFilteredList:
      context.push('/vaccinations?filter=due-now');
    default:
      return;
  }
}

class _NotificationDetailsSheet extends StatelessWidget {
  const _NotificationDetailsSheet({
    required this.item,
    required this.onOpenRelated,
    required this.onReview,
    required this.onDismiss,
  });

  final local_db.Notification item;
  final VoidCallback onOpenRelated;
  final VoidCallback onReview;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final status = InAppNotificationStatusStorage.fromStorage(
      item.status,
      isRead: item.isRead,
    );
    final date = DateFormat.yMMMd().add_jm();
    final hasRelatedRecord =
        AlertDestinationTypeStorage.fromStorage(item.destinationType) !=
        AlertDestinationType.none;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Notification Details', style: averaText(context).pageTitle),
            const SizedBox(height: 18),
            AveraSurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.notifications_outlined),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          item.title,
                          style: averaText(context).listItemTitle,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    item.message,
                    style: averaText(context).listItemSubtitle,
                  ),
                  const SizedBox(height: 12),
                  Text('Type: ${item.type}', style: averaText(context).caption),
                  Text(
                    'Generated: ${date.format(item.createdAt)}',
                    style: averaText(context).caption,
                  ),
                  if (item.dueDate != null)
                    Text(
                      'Due: ${date.format(item.dueDate!)}',
                      style: averaText(context).caption,
                    ),
                  Text(
                    'Status: ${status.name}',
                    style: averaText(context).caption,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (hasRelatedRecord)
              FilledButton.icon(
                onPressed: onOpenRelated,
                icon: const Icon(Icons.open_in_new_rounded),
                label: const Text('Open Related Record'),
              ),
            if (status == InAppNotificationStatus.unread ||
                status == InAppNotificationStatus.read) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: onReview,
                icon: const Icon(Icons.task_alt_rounded),
                label: const Text('Mark as Reviewed'),
              ),
            ],
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: onDismiss,
              icon: const Icon(Icons.notifications_off_rounded),
              label: const Text('Dismiss Notification'),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({
    required this.item,
    required this.onTap,
    required this.onLongPress,
  });

  final local_db.Notification item;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final status = InAppNotificationStatusStorage.fromStorage(
      item.status,
      isRead: item.isRead,
    );
    final color = switch (status) {
      InAppNotificationStatus.unread => Theme.of(context).colorScheme.primary,
      InAppNotificationStatus.read => Theme.of(context).colorScheme.outline,
      InAppNotificationStatus.reviewed => Theme.of(
        context,
      ).colorScheme.tertiary,
      InAppNotificationStatus.dismissed => Theme.of(
        context,
      ).colorScheme.outline,
    };
    final date = DateFormat.yMMMd().format(item.dueDate ?? item.createdAt);
    return Semantics(
      button: true,
      label: '${item.title}, ${status.name}',
      child: AveraSurfaceCard(
        child: InkWell(
          borderRadius: BorderRadius.circular(AveraSpacing.cardRadius),
          onTap: onTap,
          onLongPress: onLongPress,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.notifications_outlined, color: color),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.title,
                            style: averaText(context).listItemTitle,
                          ),
                        ),
                        _StatusChip(status: status),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$date - ${item.type}',
                      style: averaText(context).caption,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.message,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: averaText(context).listItemSubtitle,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final InAppNotificationStatus status;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      status.name[0].toUpperCase() + status.name.substring(1),
      style: averaText(context).caption,
    ),
  );
}

class _ManageHeader extends StatelessWidget {
  const _ManageHeader({required this.item, required this.status});
  final local_db.Notification item;
  final InAppNotificationStatus status;

  @override
  Widget build(BuildContext context) => AveraSurfaceCard(
    child: Row(
      children: [
        const Icon(Icons.notifications_outlined),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.title, style: averaText(context).listItemTitle),
              Text(
                '${item.type} - ${DateFormat.yMMMd().format(item.createdAt)}',
                style: averaText(context).caption,
              ),
              Text(
                status.name[0].toUpperCase() + status.name.substring(1),
                style: averaText(context).caption,
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _SheetAction extends StatelessWidget {
  const _SheetAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.destructive = false,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? Theme.of(context).colorScheme.error : null;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: color),
      title: Text(
        title,
        style: averaText(context).listItemTitle.copyWith(color: color),
      ),
      subtitle: Text(subtitle, style: averaText(context).listItemSubtitle),
      onTap: onTap,
    );
  }
}

class _EmptyNotifications extends StatelessWidget {
  const _EmptyNotifications();

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const Icon(Icons.notifications_off_outlined, size: 40),
      const SizedBox(height: 12),
      Text(
        'No notifications require attention.',
        style: averaText(context).listItemTitle,
      ),
    ],
  );
}
