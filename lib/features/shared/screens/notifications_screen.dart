import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';
import 'package:intl/intl.dart';

import '../../../core/config/app_providers.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifications = ref.watch(notificationsProvider);
    final date = DateFormat.yMMMd();

    return Scaffold(
      appBar: AppBar(title: const Text('Notification Center')),
      body: notifications.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Unable to load notifications: $error')),
        data: (items) => ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final item = items[index];
            return Card(
              child: ListTile(
                leading: Icon(
                  item.isRead ? Iconsax.notification_bing : Iconsax.notification,
                  color: item.isRead ? null : Theme.of(context).colorScheme.primary,
                ),
                title: Text(item.title),
                subtitle: Text(
                  '${item.type} • ${item.dueDate == null ? date.format(item.createdAt) : date.format(item.dueDate!)}\n${item.message}',
                ),
                isThreeLine: true,
              ),
            );
          },
        ),
      ),
    );
  }
}
