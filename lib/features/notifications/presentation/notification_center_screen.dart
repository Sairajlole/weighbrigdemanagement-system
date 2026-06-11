import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:weighbridgemanagement/shared/providers/app_version_provider.dart';
import 'package:weighbridgemanagement/shared/providers/firestore_path_provider.dart';
import 'package:weighbridgemanagement/shared/providers/notifications_provider.dart';

/// Notification center — full history (read + unread), grouped by day, with
/// category icons, tap-to-open (deep-link), swipe-to-dismiss, and mark-all-read.
class NotificationCenterScreen extends ConsumerWidget {
  const NotificationCenterScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final async = ref.watch(allNotificationsProvider);
    final paths = ref.read(firestorePathsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          TextButton.icon(
            onPressed: () => markAllNotificationsRead(paths),
            icon: const Icon(Icons.done_all_rounded, size: 18),
            label: const Text('Mark all read'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load notifications.\n$e', textAlign: TextAlign.center)),
        data: (items) {
          if (items.isEmpty) return _empty(scheme);
          final groups = _groupByDay(items);
          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: groups.length,
            itemBuilder: (_, gi) {
              final g = groups[gi];
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
                    child: Text(g.label,
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1, color: scheme.onSurfaceVariant)),
                  ),
                  ...g.items.map((n) => _tile(context, ref, paths, n, scheme)),
                ],
              );
            },
          );
        },
      ),
      bottomNavigationBar: _versionFooter(ref, scheme),
    );
  }

  Widget _versionFooter(WidgetRef ref, ColorScheme scheme) {
    final v = ref.watch(appVersionProvider).valueOrNull;
    if (v == null || v.isEmpty) return const SizedBox.shrink();
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(v, textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant.withValues(alpha: 0.55))),
      ),
    );
  }

  Widget _empty(ColorScheme scheme) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.notifications_none_rounded, size: 56, color: scheme.onSurfaceVariant.withValues(alpha: 0.4)),
            const SizedBox(height: 12),
            Text("You're all caught up", style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant)),
            const SizedBox(height: 4),
            Text('New alerts will show up here.', style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant.withValues(alpha: 0.7))),
          ],
        ),
      );

  Widget _tile(BuildContext context, WidgetRef ref, FirestorePaths paths, Map<String, dynamic> n, ColorScheme scheme) {
    final id = n['id'] as String;
    final read = n['read'] == true;
    final title = (n['title'] as String?) ?? '';
    final body = (n['body'] as String?) ?? '';
    final link = n['link'] as String?;
    final category = (n['category'] as String?) ?? (n['type'] as String?) ?? 'system';
    final severity = (n['severity'] as String?) ?? 'info';
    final style = _categoryStyle(category, severity, scheme);
    // Company-wide ("*") items are shared — an individual must not hard-delete
    // them for everyone; only personal items are swipe-deletable.
    final personal = n['operatorEmail'] != null && n['operatorEmail'] != '*';

    return Dismissible(
      key: ValueKey(id),
      direction: personal ? DismissDirection.endToStart : DismissDirection.none,
      background: Container(
        alignment: Alignment.centerRight,
        color: scheme.errorContainer,
        padding: const EdgeInsets.only(right: 24),
        child: Icon(Icons.delete_outline_rounded, color: scheme.onErrorContainer),
      ),
      onDismissed: (_) => deleteNotification(paths, id),
      child: InkWell(
        onTap: () {
          if (!read) markNotificationRead(paths, id);
          if (link != null && link.isNotEmpty) context.go(link);
        },
        child: Container(
          color: read ? null : scheme.primary.withValues(alpha: 0.04),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(color: style.color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                child: Icon(style.icon, size: 20, color: style.color),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(title,
                              style: TextStyle(fontSize: 14, fontWeight: read ? FontWeight.w600 : FontWeight.w700, color: scheme.onSurface)),
                        ),
                        Text(_relTime(n['createdAt']),
                            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant.withValues(alpha: 0.8))),
                      ],
                    ),
                    if (body.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(body, style: TextStyle(fontSize: 12.5, height: 1.4, color: scheme.onSurfaceVariant)),
                    ],
                  ],
                ),
              ),
              if (!read) ...[
                const SizedBox(width: 10),
                Container(width: 8, height: 8, margin: const EdgeInsets.only(top: 6),
                    decoration: BoxDecoration(color: scheme.primary, shape: BoxShape.circle)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

({IconData icon, Color color}) _categoryStyle(String category, String severity, ColorScheme scheme) {
  IconData icon;
  Color color;
  switch (category) {
    case 'security':
      icon = Icons.shield_outlined; color = scheme.error; break;
    case 'billing':
      icon = Icons.payments_outlined; color = Colors.amber.shade800; break;
    case 'licence':
    case 'license':
      icon = Icons.workspace_premium_outlined; color = scheme.primary; break;
    case 'operator':
      icon = Icons.person_outline_rounded; color = Colors.blue.shade600; break;
    case 'kyc':
      icon = Icons.verified_user_outlined; color = Colors.purple.shade400; break;
    case 'backup':
      icon = Icons.cloud_off_outlined; color = Colors.orange.shade700; break;
    case 'account':
      icon = Icons.lock_outline_rounded; color = scheme.tertiary; break;
    case 'welcome':
      icon = Icons.celebration_outlined; color = scheme.primary; break;
    default:
      icon = Icons.notifications_none_rounded; color = scheme.onSurfaceVariant;
  }
  if (severity == 'critical') color = scheme.error;
  return (icon: icon, color: color);
}

String _relTime(dynamic ts) {
  if (ts is! Timestamp) return '';
  final d = ts.toDate();
  final diff = DateTime.now().difference(d);
  if (diff.inMinutes < 1) return 'now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m';
  if (diff.inHours < 24) return '${diff.inHours}h';
  if (diff.inDays < 7) return '${diff.inDays}d';
  return '${d.day}/${d.month}';
}

class _DayGroup {
  final String label;
  final List<Map<String, dynamic>> items;
  _DayGroup(this.label, this.items);
}

List<_DayGroup> _groupByDay(List<Map<String, dynamic>> items) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final yesterday = today.subtract(const Duration(days: 1));
  final out = <String, List<Map<String, dynamic>>>{};
  String keyFor(DateTime d) {
    final day = DateTime(d.year, d.month, d.day);
    if (day == today) return 'TODAY';
    if (day == yesterday) return 'YESTERDAY';
    if (today.difference(day).inDays < 7) return 'THIS WEEK';
    return 'EARLIER';
  }

  for (final n in items) {
    final ts = n['createdAt'];
    final d = ts is Timestamp ? ts.toDate() : now;
    out.putIfAbsent(keyFor(d), () => []).add(n);
  }
  const order = ['TODAY', 'YESTERDAY', 'THIS WEEK', 'EARLIER'];
  return [for (final k in order) if (out[k] != null) _DayGroup(k, out[k]!)];
}
