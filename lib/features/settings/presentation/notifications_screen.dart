import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:weighbridgemanagement/shared/theme/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:weighbridgemanagement/shared/providers/firestore_path_provider.dart';
import 'package:weighbridgemanagement/shared/widgets/pro_feature_banner.dart';
import 'package:weighbridgemanagement/shared/widgets/weighbridge_context_bar.dart';
import 'package:weighbridgemanagement/shared/utils/responsive.dart';

// ---------------------------------------------------------------------------
// Local persistence helper
// ---------------------------------------------------------------------------

String get _localSettingsPath {
  final home = Platform.environment['HOME'] ??
      Platform.environment['USERPROFILE'] ??
      '.';
  final dir = Directory('$home/.weighbridge');
  if (!dir.existsSync()) dir.createSync(recursive: true);
  return '${dir.path}/notifications_settings.json';
}

Future<void> _saveLocally(Map<String, dynamic> data) async {
  final file = File(_localSettingsPath);
  await file.writeAsString(jsonEncode(data));
}

Future<Map<String, dynamic>> _loadLocally() async {
  try {
    final file = File(_localSettingsPath);
    if (await file.exists()) {
      final content = await file.readAsString();
      return jsonDecode(content) as Map<String, dynamic>;
    }
  } catch (_) {}
  return {};
}

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

final _notificationsSettingsProvider =
    FutureProvider<Map<String, dynamic>>((ref) async {
  final db = ref.watch(firestorePathsProvider);
  try {
    final doc = await db.notificationsSettings.get();
    if (doc.exists) {
      final data = doc.data()!;
      await _saveLocally(data);
      return data;
    }
  } catch (_) {}
  return _loadLocally();
});

final _operatorsProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final db = ref.watch(firestorePathsProvider);
  try {
    final snapshot = await db.operators.get();
    return snapshot.docs.map((doc) {
      final data = doc.data();
      return {
        'id': doc.id,
        'name': data['name'] as String? ?? doc.id,
      };
    }).toList();
  } catch (_) {}
  return [];
});

// ---------------------------------------------------------------------------
// Event definitions
// ---------------------------------------------------------------------------

class _EventDef {
  final String key;
  final String label;
  final IconData icon;
  final String subtitle;
  final bool hasOperators;

  const _EventDef({
    required this.key,
    required this.label,
    required this.icon,
    required this.subtitle,
    required this.hasOperators,
  });
}

const _eventDefinitions = <_EventDef>[
  _EventDef(
    key: 'weighmentComplete',
    label: 'Weighment Complete',
    icon: Icons.check_circle_rounded,
    subtitle: 'Notify customer on weighment completion',
    hasOperators: false,
  ),
  _EventDef(
    key: 'queueFailure',
    label: 'Queue Failure Alert',
    icon: Icons.error_outline_rounded,
    subtitle: 'Alert when print/sync/upload queue exceeds retry limit',
    hasOperators: true,
  ),
  _EventDef(
    key: 'operatorVerificationFailed',
    label: 'Operator Verification Failed',
    icon: Icons.no_accounts_rounded,
    subtitle: 'Alert on repeated failed operator face/biometric verification',
    hasOperators: true,
  ),
  _EventDef(
    key: 'driverMismatch',
    label: 'Driver Mismatch',
    icon: Icons.person_off_rounded,
    subtitle: 'Alert when face mismatch between gross and tare weighment',
    hasOperators: true,
  ),
  _EventDef(
    key: 'gateTimeout',
    label: 'Gate Timeout',
    icon: Icons.timer_off_rounded,
    subtitle: 'Alert when vehicle exit exceeds maximum wait time',
    hasOperators: true,
  ),
  _EventDef(
    key: 'scaleError',
    label: 'Scale Error',
    icon: Icons.warning_rounded,
    subtitle: 'Alert on negative weight or non-zero reading before entry',
    hasOperators: true,
  ),
  _EventDef(
    key: 'systemHealth',
    label: 'System Health',
    icon: Icons.monitor_heart_rounded,
    subtitle: 'Alert when camera, printer, or scale goes offline',
    hasOperators: true,
  ),
];

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  bool _loaded = false;
  bool _saving = false;
  bool _dirty = false;

  String? _headerMsg;
  bool _headerMsgIsError = false;

  // Channels
  bool _smsEnabled = true;
  bool _whatsappEnabled = true;
  bool _emailEnabled = true;
  bool _inAppEnabled = true;

  // Events state
  final _events = <String, _EventState>{};

  @override
  void initState() {
    super.initState();
    for (final def in _eventDefinitions) {
      _events[def.key] = _EventState();
    }
  }

  void _loadData(Map<String, dynamic> data) {
    if (_loaded) return;
    _loaded = true;

    final channels = data['channels'] as Map<String, dynamic>?;
    if (channels != null) {
      _smsEnabled = channels['sms'] as bool? ?? true;
      _whatsappEnabled = channels['whatsapp'] as bool? ?? true;
      _emailEnabled = channels['email'] as bool? ?? true;
      _inAppEnabled = channels['inApp'] as bool? ?? true;
    }

    final events = data['events'] as Map<String, dynamic>?;
    if (events != null) {
      for (final entry in events.entries) {
        final state = _events[entry.key];
        if (state != null && entry.value is Map<String, dynamic>) {
          final eventData = entry.value as Map<String, dynamic>;
          state.enabled = eventData['enabled'] as bool? ?? true;
          final channelsList = eventData['channels'] as List<dynamic>?;
          if (channelsList != null) {
            state.channels = channelsList.cast<String>().toSet();
          }
          final operatorsList = eventData['operators'] as List<dynamic>?;
          if (operatorsList != null) {
            state.operators = operatorsList.cast<String>().toSet();
          }
        }
      }
    }
  }

  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
  }

  void _showHeaderMsg(String msg, {bool isError = false}) {
    setState(() { _headerMsg = msg; _headerMsgIsError = isError; });
    Future.delayed(Duration(seconds: isError ? 5 : 3), () {
      if (mounted) setState(() => _headerMsg = null);
    });
  }

  Map<String, dynamic> _buildPayload() {
    final eventsData = <String, dynamic>{};
    for (final def in _eventDefinitions) {
      final state = _events[def.key]!;
      final eventPayload = <String, dynamic>{
        'enabled': state.enabled,
        'channels': state.channels.toList(),
      };
      if (def.hasOperators) {
        eventPayload['operators'] = state.operators.toList();
      }
      eventsData[def.key] = eventPayload;
    }
    return {
      'channels': {
        'sms': _smsEnabled,
        'whatsapp': _whatsappEnabled,
        'email': _emailEnabled,
        'inApp': _inAppEnabled,
      },
      'events': eventsData,
    };
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final payload = _buildPayload();
      await _saveLocally(payload);
      final db = ref.read(firestorePathsProvider);
      await db.notificationsSettings.set({
        ...payload,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      ref.invalidate(_notificationsSettingsProvider);
      if (mounted) {
        setState(() => _dirty = false);
        _showHeaderMsg('Notification settings saved');
      }
    } catch (e) {
      if (mounted) _showHeaderMsg('Failed: $e', isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final asyncData = ref.watch(_notificationsSettingsProvider);
    asyncData.whenData(_loadData);

    return Scaffold(
      backgroundColor: scheme.surfaceContainerLowest,
      body: Column(
        children: [
          _buildHeader(scheme, text),
          WeighbridgeContextBar(
            label: 'Notifications for',
            onSwitched: () {
              ref.invalidate(_notificationsSettingsProvider);
              ref.invalidate(_operatorsProvider);
              setState(() => _loaded = false);
            },
          ),
          Expanded(
            child: asyncData.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (_) => SingleChildScrollView(
                padding: EdgeInsets.all(28.rs),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const ProFeatureBanner(feature: 'Notifications & Alerts'),
                    _buildChannelsSection(scheme, text),
                    SizedBox(height: 24.rs),
                    _buildEventsSection(scheme, text),
                    SizedBox(height: 40.rs),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Header
  // ---------------------------------------------------------------------------

  Widget _buildHeader(ColorScheme scheme, TextTheme text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.2))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () => context.go('/settings'),
                icon: const Icon(Icons.arrow_back_rounded, size: 20),
                style: IconButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.rs))),
              ),
              SizedBox(width: 12.rs),
              Icon(Icons.notifications_rounded, size: 20, color: scheme.primary),
              SizedBox(width: 10.rs),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Notifications', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  Text('Alerts and event triggers', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                ],
              ),
              const Spacer(),
              if (_dirty) ...[
                TextButton(
                  onPressed: () { setState(() { _loaded = false; _dirty = false; }); ref.invalidate(_notificationsSettingsProvider); },
                  child: const Text('Cancel'),
                ),
                SizedBox(width: 8.rs),
              ],
              FilledButton.icon(
                onPressed: _dirty && !_saving ? _save : null,
                icon: _saving
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.save_rounded, size: 16),
                label: Text(_saving ? 'Saving...' : 'Save'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.rs)),
                ),
              ),
            ],
          ),
          if (_headerMsg != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: _headerMsgIsError ? scheme.errorContainer.withValues(alpha: 0.6) : AppTheme.successColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8.rs),
                  border: Border.all(color: _headerMsgIsError ? scheme.error.withValues(alpha: 0.3) : AppTheme.successColor.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Icon(
                      _headerMsgIsError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
                      size: 15,
                      color: _headerMsgIsError ? scheme.error : AppTheme.successColor,
                    ),
                    SizedBox(width: 8.rs),
                    Expanded(child: Text(_headerMsg!, style: text.bodySmall?.copyWith(color: _headerMsgIsError ? scheme.error : AppTheme.successColor, fontWeight: FontWeight.w500))),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Section 1: Notification Channels
  // ---------------------------------------------------------------------------

  Widget _buildChannelsSection(ColorScheme scheme, TextTheme text) {
    return _SectionCard(
      scheme: scheme,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.cell_tower_rounded, size: 18, color: scheme.primary),
              SizedBox(width: 10.rs),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Notification Channels',
                      style: text.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  Text(
                    'Master switches for each delivery channel',
                    style: text.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ],
          ),
          SizedBox(height: 16.rs),
          _FeatureToggle(
            icon: Icons.sms_rounded,
            label: 'SMS',
            subtitle:
                'Send notifications via text message',
            value: _smsEnabled,
            onChanged: (v) {
              setState(() => _smsEnabled = v);
              _markDirty();
            },
          ),
          SizedBox(height: 8.rs),
          _FeatureToggle(
            icon: Icons.chat_rounded,
            label: 'WhatsApp',
            subtitle:
                'Send notifications via WhatsApp messaging',
            value: _whatsappEnabled,
            onChanged: (v) {
              setState(() => _whatsappEnabled = v);
              _markDirty();
            },
          ),
          SizedBox(height: 8.rs),
          _FeatureToggle(
            icon: Icons.email_rounded,
            label: 'Email',
            subtitle:
                'Send notifications via email to registered addresses',
            value: _emailEnabled,
            onChanged: (v) {
              setState(() => _emailEnabled = v);
              _markDirty();
            },
          ),
          SizedBox(height: 8.rs),
          _FeatureToggle(
            icon: Icons.notifications_active_rounded,
            label: 'In-App',
            subtitle:
                'Show notifications within the application',
            value: _inAppEnabled,
            onChanged: (v) {
              setState(() => _inAppEnabled = v);
              _markDirty();
            },
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Section 2: Notification Events
  // ---------------------------------------------------------------------------

  Widget _buildEventsSection(ColorScheme scheme, TextTheme text) {
    return _SectionCard(
      scheme: scheme,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.event_note_rounded, size: 18, color: scheme.primary),
              SizedBox(width: 10.rs),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Notification Events',
                      style: text.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  Text(
                    'Configure alerts for specific system events',
                    style: text.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ],
          ),
          SizedBox(height: 16.rs),
          ..._eventDefinitions.map((def) => _buildEventCard(def, scheme, text)),
        ],
      ),
    );
  }

  Widget _buildEventCard(
      _EventDef def, ColorScheme scheme, TextTheme text) {
    final state = _events[def.key]!;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: state.enabled
            ? scheme.surfaceContainerLow
            : scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12.rs),
        border: Border.all(
          color: state.enabled
              ? scheme.primary.withValues(alpha: 0.12)
              : scheme.outlineVariant.withValues(alpha: 0.2),
        ),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          leading: Icon(def.icon,
              size: 18,
              color:
                  state.enabled ? scheme.primary : scheme.outlineVariant),
          title: Row(
            children: [
              Text(
                def.label,
                style: text.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: state.enabled
                      ? scheme.onSurface
                      : scheme.onSurfaceVariant,
                ),
              ),
              SizedBox(width: 8.rs),
              if (state.enabled)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.successColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4.rs),
                  ),
                  child: Text(
                    '${state.channels.length} channel${state.channels.length == 1 ? '' : 's'}',
                    style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.successColor),
                  ),
                ),
            ],
          ),
          subtitle: Text(def.subtitle,
              style:
                  TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
          trailing: Switch(
            value: state.enabled,
            onChanged: (v) {
              setState(() => state.enabled = v);
              _markDirty();
            },
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          children: [
            if (state.enabled) ...[
              SizedBox(height: 4.rs),
              _buildChannelDelivery(def, state, scheme, text),
              if (def.hasOperators) ...[
                SizedBox(height: 14.rs),
                _buildOperatorSelection(def, state, scheme, text),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildChannelDelivery(
      _EventDef def, _EventState state, ColorScheme scheme, TextTheme text) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Channel Delivery',
            style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
        SizedBox(height: 8.rs),
        Row(
          children: [
            _buildChannelCheckbox(
              label: 'SMS',
              icon: Icons.sms_rounded,
              channelKey: 'sms',
              enabled: _smsEnabled,
              state: state,
              scheme: scheme,
              text: text,
            ),
            SizedBox(width: 16.rs),
            _buildChannelCheckbox(
              label: 'WhatsApp',
              icon: Icons.chat_rounded,
              channelKey: 'whatsapp',
              enabled: _whatsappEnabled,
              state: state,
              scheme: scheme,
              text: text,
            ),
            SizedBox(width: 16.rs),
            _buildChannelCheckbox(
              label: 'Email',
              icon: Icons.email_rounded,
              channelKey: 'email',
              enabled: _emailEnabled,
              state: state,
              scheme: scheme,
              text: text,
            ),
            SizedBox(width: 16.rs),
            _buildChannelCheckbox(
              label: 'In-App',
              icon: Icons.notifications_active_rounded,
              channelKey: 'inApp',
              enabled: _inAppEnabled,
              state: state,
              scheme: scheme,
              text: text,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildChannelCheckbox({
    required String label,
    required IconData icon,
    required String channelKey,
    required bool enabled,
    required _EventState state,
    required ColorScheme scheme,
    required TextTheme text,
  }) {
    final isSelected = state.channels.contains(channelKey);
    final isDisabled = !enabled;

    return Opacity(
      opacity: isDisabled ? 0.4 : 1.0,
      child: InkWell(
        onTap: isDisabled
            ? null
            : () {
                setState(() {
                  if (isSelected) {
                    state.channels.remove(channelKey);
                  } else {
                    state.channels.add(channelKey);
                  }
                });
                _markDirty();
              },
        borderRadius: BorderRadius.circular(8.rs),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected && !isDisabled
                ? scheme.primaryContainer.withValues(alpha: 0.2)
                : scheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(8.rs),
            border: Border.all(
              color: isSelected && !isDisabled
                  ? scheme.primary.withValues(alpha: 0.4)
                  : scheme.outlineVariant.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isSelected && !isDisabled
                    ? Icons.check_box_rounded
                    : Icons.check_box_outline_blank_rounded,
                size: 16,
                color: isSelected && !isDisabled
                    ? scheme.primary
                    : scheme.outlineVariant,
              ),
              SizedBox(width: 6.rs),
              Icon(icon, size: 14, color: scheme.onSurfaceVariant),
              SizedBox(width: 4.rs),
              Text(
                label,
                style: text.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: isDisabled
                      ? scheme.onSurfaceVariant
                      : scheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOperatorSelection(
      _EventDef def, _EventState state, ColorScheme scheme, TextTheme text) {
    final operatorsAsync = ref.watch(_operatorsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Also Notify Operators',
            style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
        SizedBox(height: 8.rs),
        operatorsAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(8),
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
          error: (_, __) => Text(
            'Could not load operators',
            style: text.bodySmall?.copyWith(color: scheme.error),
          ),
          data: (operators) {
            if (operators.isEmpty) {
              return Container(
                padding: EdgeInsets.all(12.rs),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(8.rs),
                  border: Border.all(
                      color: scheme.outlineVariant.withValues(alpha: 0.2)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline_rounded,
                        size: 14, color: scheme.onSurfaceVariant),
                    SizedBox(width: 8.rs),
                    Text(
                      'No operators found in the system',
                      style: text.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              );
            }

            return Wrap(
              spacing: 8,
              runSpacing: 8,
              children: operators.map((op) {
                final opId = op['id'] as String;
                final opName = op['name'] as String;
                final isSelected = state.operators.contains(opId);

                return FilterChip(
                  label: Text(opName),
                  selected: isSelected,
                  onSelected: (selected) {
                    setState(() {
                      if (selected) {
                        state.operators.add(opId);
                      } else {
                        state.operators.remove(opId);
                      }
                    });
                    _markDirty();
                  },
                  avatar: Icon(
                    Icons.person_rounded,
                    size: 16,
                    color: isSelected
                        ? scheme.primary
                        : scheme.onSurfaceVariant,
                  ),
                  labelStyle: text.bodySmall?.copyWith(
                    fontWeight: FontWeight.w500,
                    color:
                        isSelected ? scheme.primary : scheme.onSurfaceVariant,
                  ),
                  selectedColor:
                      scheme.primaryContainer.withValues(alpha: 0.3),
                  backgroundColor: scheme.surfaceContainerLowest,
                  side: BorderSide(
                    color: isSelected
                        ? scheme.primary.withValues(alpha: 0.4)
                        : scheme.outlineVariant.withValues(alpha: 0.3),
                  ),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8.rs)),
                  showCheckmark: true,
                  checkmarkColor: scheme.primary,
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }
}

// =============================================================================
// Event state
// =============================================================================

class _EventState {
  bool enabled = true;
  Set<String> channels = {'sms', 'whatsapp', 'email', 'inApp'};
  Set<String> operators = {};
}

// =============================================================================
// Private widgets
// =============================================================================

class _SectionCard extends StatelessWidget {
  final ColorScheme scheme;
  final Widget child;

  const _SectionCard({required this.scheme, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(24.rs),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16.rs),
        border:
            Border.all(color: scheme.outlineVariant.withValues(alpha: 0.25)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _FeatureToggle extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _FeatureToggle({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: value
            ? scheme.primaryContainer.withValues(alpha: 0.15)
            : scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10.rs),
        border: Border.all(
          color: value
              ? scheme.primary.withValues(alpha: 0.2)
              : scheme.outlineVariant.withValues(alpha: 0.15),
        ),
      ),
      child: Row(
        children: [
          Icon(icon,
              size: 18, color: value ? scheme.primary : scheme.outlineVariant),
          SizedBox(width: 12.rs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style:
                        text.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                Text(subtitle,
                    style: TextStyle(
                        fontSize: 11, color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}
