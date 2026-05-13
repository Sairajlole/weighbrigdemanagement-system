import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:uuid/uuid.dart';
import 'package:weighbridgemanagement/shared/providers/auth_provider.dart';
import 'package:weighbridgemanagement/shared/providers/firestore_provider.dart';

// ─── Flow State ──────────────────────────────────────────────────────────────

enum WeighmentPhase {
  idle,
  operatorVerify,
  vehicleEntry,
  stabilizing,
  capturing,
  dataEntry,
  saving,
  complete,
}

enum ServiceStatus { offline, connecting, online, error }

class WeighmentState {
  final WeighmentPhase phase;
  final bool isTare;
  final double liveWeight;
  final bool weightStable;
  final String? vehicleNumber;
  final String? material;
  final String? customerName;
  final String? customerPhone;
  final double? grossWeight;
  final double? tareWeight;
  final String? rstNumber;
  final String? sessionId;
  final String? error;

  const WeighmentState({
    this.phase = WeighmentPhase.idle,
    this.isTare = false,
    this.liveWeight = 0,
    this.weightStable = false,
    this.vehicleNumber,
    this.material,
    this.customerName,
    this.customerPhone,
    this.grossWeight,
    this.tareWeight,
    this.rstNumber,
    this.sessionId,
    this.error,
  });

  WeighmentState copyWith({
    WeighmentPhase? phase,
    bool? isTare,
    double? liveWeight,
    bool? weightStable,
    String? vehicleNumber,
    String? material,
    String? customerName,
    String? customerPhone,
    double? grossWeight,
    double? tareWeight,
    String? rstNumber,
    String? sessionId,
    String? error,
  }) {
    return WeighmentState(
      phase: phase ?? this.phase,
      isTare: isTare ?? this.isTare,
      liveWeight: liveWeight ?? this.liveWeight,
      weightStable: weightStable ?? this.weightStable,
      vehicleNumber: vehicleNumber ?? this.vehicleNumber,
      material: material ?? this.material,
      customerName: customerName ?? this.customerName,
      customerPhone: customerPhone ?? this.customerPhone,
      grossWeight: grossWeight ?? this.grossWeight,
      tareWeight: tareWeight ?? this.tareWeight,
      rstNumber: rstNumber ?? this.rstNumber,
      sessionId: sessionId ?? this.sessionId,
      error: error,
    );
  }
}

final weighmentStateProvider =
    StateNotifierProvider<WeighmentNotifier, WeighmentState>((ref) {
  return WeighmentNotifier(ref);
});

class WeighmentNotifier extends StateNotifier<WeighmentState> {
  final Ref _ref;
  Timer? _weightSimTimer;

  WeighmentNotifier(this._ref) : super(const WeighmentState()) {
    _startWeightSimulation();
  }

  void _startWeightSimulation() {
    _weightSimTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (state.phase == WeighmentPhase.idle) {
        state = state.copyWith(liveWeight: 0, weightStable: true);
      }
    });
  }

  void startGross() {
    state = WeighmentState(
      phase: WeighmentPhase.operatorVerify,
      isTare: false,
      sessionId: const Uuid().v4(),
      liveWeight: state.liveWeight,
    );
    _simulateOperatorVerify();
  }

  void startTare() {
    state = WeighmentState(
      phase: WeighmentPhase.operatorVerify,
      isTare: true,
      sessionId: const Uuid().v4(),
      liveWeight: state.liveWeight,
    );
    _simulateOperatorVerify();
  }

  void _simulateOperatorVerify() {
    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      state = state.copyWith(phase: WeighmentPhase.vehicleEntry);
      _simulateVehicleEntry();
    });
  }

  void _simulateVehicleEntry() {
    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      state = state.copyWith(phase: WeighmentPhase.stabilizing);
      _simulateStabilization();
    });
  }

  void _simulateStabilization() {
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (!mounted) return;
      final weight = 12500.0 + (math.Random().nextDouble() * 15000);
      state = state.copyWith(
        liveWeight: weight,
        weightStable: false,
        phase: WeighmentPhase.stabilizing,
      );
    });
    Future.delayed(const Duration(seconds: 4), () {
      if (!mounted) return;
      state = state.copyWith(
        weightStable: true,
        phase: WeighmentPhase.capturing,
      );
      _simulateCapturing();
    });
  }

  void _simulateCapturing() {
    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      state = state.copyWith(phase: WeighmentPhase.dataEntry);
    });
  }

  void updateVehicle(String v) => state = state.copyWith(vehicleNumber: v);
  void updateMaterial(String m) => state = state.copyWith(material: m);
  void updateCustomerName(String n) => state = state.copyWith(customerName: n);
  void updateCustomerPhone(String p) => state = state.copyWith(customerPhone: p);

  Future<void> captureWeight() async {
    state = state.copyWith(phase: WeighmentPhase.saving);

    try {
      final db = _ref.read(firestoreProvider);
      final user = _ref.read(authStateProvider).valueOrNull;
      final now = DateTime.now();
      final ts = Timestamp.fromDate(now);

      final counterRef = db.collection('counters').doc('rst_default');
      final rst = await db.runTransaction((txn) async {
        final snap = await txn.get(counterRef);
        final current = (snap.exists ? (snap.data()?['value'] as num?)?.toInt() : 0) ?? 0;
        final next = current + 1;
        txn.set(counterRef, {'value': next});
        return next;
      });

      final data = <String, dynamic>{
        'sessionId': state.sessionId,
        'rstNumber': rst.toString(),
        'deviceId': 'desktop',
        'weighbridgeId': 'default',
        'vehicleNumber': (state.vehicleNumber ?? '').toUpperCase(),
        'customerName': state.customerName?.isNotEmpty == true ? state.customerName : 'Walk-in',
        'customerPhone': state.customerPhone ?? '',
        'material': state.material?.isNotEmpty == true ? state.material : 'Unknown',
        'operatorId': user?.uid ?? '',
        'operatorName': 'Operator',
        'operatorRole': 'operator',
        'createdAt': ts,
        'updatedAt': ts,
      };

      if (state.isTare) {
        data['tareWeight'] = state.liveWeight;
        data['tareDateTime'] = ts;
        data['grossWeight'] = state.grossWeight ?? 0;
        data['netWeight'] = (state.grossWeight ?? 0) - state.liveWeight;
        data['status'] = 'completed';
        data['currentStep'] = 'complete';
      } else {
        data['grossWeight'] = state.liveWeight;
        data['grossDateTime'] = ts;
        data['status'] = 'awaitingTare';
        data['currentStep'] = 'saveWeighment';
      }

      await db.collection('weighments').add(data);

      state = state.copyWith(
        phase: WeighmentPhase.complete,
        rstNumber: rst.toString(),
        grossWeight: state.isTare ? state.grossWeight : state.liveWeight,
        tareWeight: state.isTare ? state.liveWeight : null,
      );
    } catch (e) {
      state = state.copyWith(phase: WeighmentPhase.dataEntry, error: e.toString());
    }
  }

  void reset() {
    state = const WeighmentState();
  }

  @override
  void dispose() {
    _weightSimTimer?.cancel();
    super.dispose();
  }
}

// ─── Service Status Provider ─────────────────────────────────────────────────

final serviceStatusProvider = Provider<Map<String, ServiceStatus>>((ref) {
  return {
    'Scale': ServiceStatus.online,
    'CCTV': ServiceStatus.online,
    'AI/YOLO': ServiceStatus.online,
    'Printer': ServiceStatus.offline,
    'Gate': ServiceStatus.offline,
  };
});

// ─── Main Screen ─────────────────────────────────────────────────────────────

class WeighmentScreen extends ConsumerWidget {
  const WeighmentScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ws = ref.watch(weighmentStateProvider);

    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      child: Column(
        children: [
          const _ServiceStatusBar(),
          Expanded(
            child: ws.phase == WeighmentPhase.idle
                ? const _IdleState()
                : ws.phase == WeighmentPhase.complete
                    ? _CompletionState(state: ws)
                    : _ActiveWeighment(state: ws),
          ),
        ],
      ),
    );
  }
}

// ─── Service Status Bar ──────────────────────────────────────────────────────

class _ServiceStatusBar extends ConsumerWidget {
  const _ServiceStatusBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final services = ref.watch(serviceStatusProvider);

    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.2))),
      ),
      child: Row(
        children: [
          Icon(Icons.hub_rounded, size: 14, color: scheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Text(
            'Services',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 16),
          ...services.entries.map((e) => Padding(
                padding: const EdgeInsets.only(right: 14),
                child: _ServiceChip(name: e.key, status: e.value),
              )),
          const Spacer(),
          Text(
            DateFormat('HH:mm:ss').format(DateTime.now()),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _ServiceChip extends StatelessWidget {
  final String name;
  final ServiceStatus status;

  const _ServiceChip({required this.name, required this.status});

  @override
  Widget build(BuildContext context) {
    final (Color color, String label) = switch (status) {
      ServiceStatus.online => (const Color(0xFF059669), 'ON'),
      ServiceStatus.connecting => (const Color(0xFFF59E0B), '...'),
      ServiceStatus.error => (const Color(0xFFEF4444), 'ERR'),
      ServiceStatus.offline => (const Color(0xFF6B7280), 'OFF'),
    };

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: status == ServiceStatus.online
                ? [BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 4)]
                : null,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          name,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }
}

// ─── Idle State ──────────────────────────────────────────────────────────────

class _IdleState extends ConsumerWidget {
  const _IdleState();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.scale_rounded,
            size: 56,
            color: scheme.primary.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 20),
          Text(
            'Ready for Weighment',
            style: text.headlineMedium?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Select weighment type to begin the automated process',
            style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 48),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _WeighmentTypeCard(
                icon: Icons.download_rounded,
                title: 'Gross Weight',
                subtitle: 'First weighment — loaded vehicle',
                color: scheme.primary,
                onTap: () => ref.read(weighmentStateProvider.notifier).startGross(),
              ),
              const SizedBox(width: 20),
              _WeighmentTypeCard(
                icon: Icons.upload_rounded,
                title: 'Tare Weight',
                subtitle: 'Second weighment — empty vehicle',
                color: scheme.tertiary,
                onTap: () => ref.read(weighmentStateProvider.notifier).startTare(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WeighmentTypeCard extends StatefulWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _WeighmentTypeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  State<_WeighmentTypeCard> createState() => _WeighmentTypeCardState();
}

class _WeighmentTypeCardState extends State<_WeighmentTypeCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          width: 240,
          padding: const EdgeInsets.all(28),
          transform: Matrix4.translationValues(0, _hovered ? -6 : 0, 0),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: _hovered ? widget.color.withValues(alpha: 0.5) : scheme.outlineVariant.withValues(alpha: 0.3),
            ),
            boxShadow: [
              BoxShadow(
                color: _hovered ? widget.color.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.04),
                blurRadius: _hovered ? 24 : 8,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [widget.color, widget.color.withValues(alpha: 0.7)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: widget.color.withValues(alpha: 0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(widget.icon, color: Colors.white, size: 26),
              ),
              const SizedBox(height: 18),
              Text(
                widget.title,
                style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                widget.subtitle,
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Active Weighment Screen ─────────────────────────────────────────────────

class _ActiveWeighment extends ConsumerStatefulWidget {
  final WeighmentState state;

  const _ActiveWeighment({required this.state});

  @override
  ConsumerState<_ActiveWeighment> createState() => _ActiveWeighmentState();
}

class _ActiveWeighmentState extends ConsumerState<_ActiveWeighment> {
  final _vehicleCtrl = TextEditingController();
  final _materialCtrl = TextEditingController();
  final _customerNameCtrl = TextEditingController();
  final _customerPhoneCtrl = TextEditingController();

  @override
  void dispose() {
    _vehicleCtrl.dispose();
    _materialCtrl.dispose();
    _customerNameCtrl.dispose();
    _customerPhoneCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ws = widget.state;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // ─── Top: Phase Progress ────────────────────────────────
          _PhaseIndicator(phase: ws.phase, isTare: ws.isTare),
          const SizedBox(height: 16),

          // ─── Main Content: Camera Grid + Center Data ───────────
          Expanded(
            child: Row(
              children: [
                // Left cameras (2 stacked)
                SizedBox(
                  width: 200,
                  child: Column(
                    children: [
                      Expanded(child: _CameraFeed(label: 'Front View', index: 0)),
                      const SizedBox(height: 8),
                      Expanded(child: _CameraFeed(label: 'Rear View', index: 1)),
                    ],
                  ),
                ),
                const SizedBox(width: 16),

                // Center: Weight display + Data entry
                Expanded(
                  child: Column(
                    children: [
                      // Live weight display
                      _LiveWeightDisplay(
                        weight: ws.liveWeight,
                        stable: ws.weightStable,
                        isTare: ws.isTare,
                      ),
                      const SizedBox(height: 16),

                      // Data entry (only during dataEntry phase)
                      Expanded(
                        child: ws.phase == WeighmentPhase.dataEntry
                            ? _DataEntryPanel(
                                vehicleCtrl: _vehicleCtrl,
                                materialCtrl: _materialCtrl,
                                customerNameCtrl: _customerNameCtrl,
                                customerPhoneCtrl: _customerPhoneCtrl,
                                isTare: ws.isTare,
                                onCapture: _captureWeight,
                                error: ws.error,
                              )
                            : _PhaseStatusPanel(phase: ws.phase),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),

                // Right cameras (2 stacked)
                SizedBox(
                  width: 200,
                  child: Column(
                    children: [
                      Expanded(child: _CameraFeed(label: 'Top View', index: 2)),
                      const SizedBox(height: 8),
                      Expanded(child: _CameraFeed(label: 'Side View', index: 3)),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Bottom: Cancel bar
          const SizedBox(height: 12),
          Row(
            children: [
              TextButton.icon(
                onPressed: () => ref.read(weighmentStateProvider.notifier).reset(),
                icon: Icon(Icons.close_rounded, size: 16, color: scheme.error),
                label: Text(
                  'Cancel Weighment',
                  style: TextStyle(color: scheme.error, fontSize: 12),
                ),
              ),
              const Spacer(),
              Text(
                'Session: ${ws.sessionId?.substring(0, 8) ?? '--'}',
                style: TextStyle(
                  fontSize: 10,
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _captureWeight() {
    final notifier = ref.read(weighmentStateProvider.notifier);
    notifier.updateVehicle(_vehicleCtrl.text.trim());
    notifier.updateMaterial(_materialCtrl.text.trim());
    notifier.updateCustomerName(_customerNameCtrl.text.trim());
    notifier.updateCustomerPhone(_customerPhoneCtrl.text.trim());
    notifier.captureWeight();
  }
}

// ─── Phase Indicator ─────────────────────────────────────────────────────────

class _PhaseIndicator extends StatelessWidget {
  final WeighmentPhase phase;
  final bool isTare;

  const _PhaseIndicator({required this.phase, required this.isTare});

  static const _phases = [
    (WeighmentPhase.operatorVerify, 'Verify', Icons.person_rounded),
    (WeighmentPhase.vehicleEntry, 'Entry', Icons.directions_car_rounded),
    (WeighmentPhase.stabilizing, 'Stabilize', Icons.balance_rounded),
    (WeighmentPhase.capturing, 'Detect', Icons.camera_rounded),
    (WeighmentPhase.dataEntry, 'Confirm', Icons.edit_rounded),
    (WeighmentPhase.saving, 'Save', Icons.cloud_upload_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final currentIdx = _phases.indexWhere((p) => p.$1 == phase);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: isTare ? scheme.tertiaryContainer : scheme.primaryContainer,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              isTare ? 'TARE' : 'GROSS',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: isTare ? scheme.onTertiaryContainer : scheme.onPrimaryContainer,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(width: 20),
          ..._phases.asMap().entries.expand((entry) {
            final i = entry.key;
            final p = entry.value;
            final isActive = i == currentIdx;
            final isDone = i < currentIdx;

            return [
              if (i > 0)
                Container(
                  width: 24,
                  height: 2,
                  color: isDone
                      ? scheme.primary
                      : scheme.outlineVariant.withValues(alpha: 0.3),
                ),
              _PhaseStep(
                icon: p.$3,
                label: p.$2,
                isActive: isActive,
                isDone: isDone,
                scheme: scheme,
              ),
            ];
          }),
        ],
      ),
    );
  }
}

class _PhaseStep extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final bool isDone;
  final ColorScheme scheme;

  const _PhaseStep({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.isDone,
    required this.scheme,
  });

  @override
  Widget build(BuildContext context) {
    final color = isDone
        ? scheme.primary
        : isActive
            ? scheme.primary
            : scheme.onSurfaceVariant.withValues(alpha: 0.4);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: isActive ? 30 : 24,
          height: isActive ? 30 : 24,
          decoration: BoxDecoration(
            color: isDone
                ? scheme.primary
                : isActive
                    ? scheme.primaryContainer
                    : Colors.transparent,
            shape: BoxShape.circle,
            border: Border.all(color: color, width: isActive ? 2 : 1),
            boxShadow: isActive
                ? [BoxShadow(color: scheme.primary.withValues(alpha: 0.2), blurRadius: 8)]
                : null,
          ),
          child: Icon(
            isDone ? Icons.check_rounded : icon,
            size: isActive ? 14 : 12,
            color: isDone ? scheme.onPrimary : color,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          style: TextStyle(
            fontSize: 9,
            fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
            color: color,
          ),
        ),
      ],
    );
  }
}

// ─── Camera Feed ─────────────────────────────────────────────────────────────

class _CameraFeed extends StatelessWidget {
  final String label;
  final int index;

  const _CameraFeed({required this.label, required this.index});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.2)),
      ),
      child: Stack(
        children: [
          // Simulated video feed (dark with scan lines)
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(11),
              child: CustomPaint(
                painter: _VideoFeedPainter(index: index),
              ),
            ),
          ),
          // Label overlay
          Positioned(
            left: 8,
            top: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 5,
                    height: 5,
                    decoration: const BoxDecoration(
                      color: Color(0xFFEF4444),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Timestamp
          Positioned(
            right: 8,
            bottom: 8,
            child: Text(
              DateFormat('HH:mm:ss').format(DateTime.now()),
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 9,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VideoFeedPainter extends CustomPainter {
  final int index;
  _VideoFeedPainter({required this.index});

  @override
  void paint(Canvas canvas, Size size) {
    // Dark gradient background simulating CCTV
    final bgPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          const Color(0xFF1A1A2E),
          Color.lerp(const Color(0xFF1A1A2E), const Color(0xFF16213E), (index * 0.2).clamp(0.0, 1.0))!,
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    // Scan lines
    final linePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.02)
      ..strokeWidth = 1;
    for (var y = 0.0; y < size.height; y += 3) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
    }

    // Center crosshair
    final cx = size.width / 2;
    final cy = size.height / 2;
    final crossPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.15)
      ..strokeWidth = 0.5;
    canvas.drawLine(Offset(cx - 15, cy), Offset(cx + 15, cy), crossPaint);
    canvas.drawLine(Offset(cx, cy - 15), Offset(cx, cy + 15), crossPaint);

    // Corner brackets
    final bracketPaint = Paint()
      ..color = const Color(0xFF059669).withValues(alpha: 0.5)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    const m = 12.0;
    const l = 20.0;
    // Top-left
    canvas.drawPath(
      Path()..moveTo(m, m + l)..lineTo(m, m)..lineTo(m + l, m),
      bracketPaint,
    );
    // Top-right
    canvas.drawPath(
      Path()..moveTo(size.width - m - l, m)..lineTo(size.width - m, m)..lineTo(size.width - m, m + l),
      bracketPaint,
    );
    // Bottom-left
    canvas.drawPath(
      Path()..moveTo(m, size.height - m - l)..lineTo(m, size.height - m)..lineTo(m + l, size.height - m),
      bracketPaint,
    );
    // Bottom-right
    canvas.drawPath(
      Path()..moveTo(size.width - m - l, size.height - m)..lineTo(size.width - m, size.height - m)..lineTo(size.width - m, size.height - m - l),
      bracketPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ─── Live Weight Display ─────────────────────────────────────────────────────

class _LiveWeightDisplay extends StatefulWidget {
  final double weight;
  final bool stable;
  final bool isTare;

  const _LiveWeightDisplay({
    required this.weight,
    required this.stable,
    required this.isTare,
  });

  @override
  State<_LiveWeightDisplay> createState() => _LiveWeightDisplayState();
}

class _LiveWeightDisplayState extends State<_LiveWeightDisplay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accentColor = widget.isTare ? scheme.tertiary : scheme.primary;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 32),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: widget.stable
              ? accentColor.withValues(alpha: 0.4)
              : Colors.white.withValues(alpha: 0.1),
        ),
        boxShadow: widget.stable
            ? [BoxShadow(color: accentColor.withValues(alpha: 0.1), blurRadius: 20)]
            : null,
      ),
      child: Row(
        children: [
          // Weight value
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'LIVE WEIGHT',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Colors.white.withValues(alpha: 0.5),
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(width: 10),
                    AnimatedBuilder(
                      animation: _pulseCtrl,
                      builder: (context, _) => Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: widget.stable
                              ? accentColor
                              : Color.lerp(
                                  const Color(0xFFF59E0B),
                                  const Color(0xFFF59E0B).withValues(alpha: 0.3),
                                  _pulseCtrl.value,
                                ),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  NumberFormat('#,###').format(widget.weight.round()),
                  style: TextStyle(
                    fontSize: 42,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: -1,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                Text(
                  'KILOGRAMS',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withValues(alpha: 0.4),
                    letterSpacing: 1.5,
                  ),
                ),
              ],
            ),
          ),
          // Status badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: widget.stable
                  ? accentColor.withValues(alpha: 0.15)
                  : const Color(0xFFF59E0B).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: widget.stable
                    ? accentColor.withValues(alpha: 0.3)
                    : const Color(0xFFF59E0B).withValues(alpha: 0.3),
              ),
            ),
            child: Text(
              widget.stable ? 'STABLE' : 'SETTLING',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: widget.stable ? accentColor : const Color(0xFFF59E0B),
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Phase Status Panel (during auto-steps) ──────────────────────────────────

class _PhaseStatusPanel extends StatelessWidget {
  final WeighmentPhase phase;

  const _PhaseStatusPanel({required this.phase});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    final (String title, String subtitle, IconData icon) = switch (phase) {
      WeighmentPhase.operatorVerify => (
          'Verifying Operator',
          'Matching face with operator database...',
          Icons.face_rounded,
        ),
      WeighmentPhase.vehicleEntry => (
          'Vehicle Entry',
          'Waiting for vehicle to enter weighbridge...',
          Icons.directions_car_rounded,
        ),
      WeighmentPhase.stabilizing => (
          'Stabilizing Weight',
          'Waiting for weight reading to stabilize...',
          Icons.balance_rounded,
        ),
      WeighmentPhase.capturing => (
          'AI Detection',
          'Detecting vehicle plate, material, and faces...',
          Icons.auto_awesome_rounded,
        ),
      WeighmentPhase.saving => (
          'Saving',
          'Recording weighment data...',
          Icons.cloud_upload_rounded,
        ),
      _ => ('Processing', 'Please wait...', Icons.hourglass_top_rounded),
    };

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.2)),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _PulsingIcon(icon: icon, color: scheme.primary),
            const SizedBox(height: 20),
            Text(
              title,
              style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _PulsingIcon extends StatefulWidget {
  final IconData icon;
  final Color color;

  const _PulsingIcon({required this.icon, required this.color});

  @override
  State<_PulsingIcon> createState() => _PulsingIconState();
}

class _PulsingIconState extends State<_PulsingIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) => Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: widget.color.withValues(alpha: 0.08 + _ctrl.value * 0.05),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: widget.color.withValues(alpha: 0.15 * _ctrl.value),
              blurRadius: 20 * _ctrl.value,
              spreadRadius: 4 * _ctrl.value,
            ),
          ],
        ),
        child: Icon(widget.icon, size: 28, color: widget.color),
      ),
    );
  }
}

// ─── Data Entry Panel ────────────────────────────────────────────────────────

class _DataEntryPanel extends StatelessWidget {
  final TextEditingController vehicleCtrl;
  final TextEditingController materialCtrl;
  final TextEditingController customerNameCtrl;
  final TextEditingController customerPhoneCtrl;
  final bool isTare;
  final VoidCallback onCapture;
  final String? error;

  const _DataEntryPanel({
    required this.vehicleCtrl,
    required this.materialCtrl,
    required this.customerNameCtrl,
    required this.customerPhoneCtrl,
    required this.isTare,
    required this.onCapture,
    this.error,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final accentColor = isTare ? scheme.tertiary : scheme.primary;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.2)),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.edit_note_rounded, size: 18, color: accentColor),
                const SizedBox(width: 8),
                Text(
                  'Weighment Details',
                  style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (error != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: scheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(error!, style: text.bodySmall?.copyWith(color: scheme.onErrorContainer)),
              ),
              const SizedBox(height: 14),
            ],
            Row(
              children: [
                Expanded(
                  child: _EntryField(
                    label: 'Vehicle Number',
                    hint: 'MH12AB1234',
                    controller: vehicleCtrl,
                    icon: Icons.directions_car_outlined,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _EntryField(
                    label: 'Material',
                    hint: 'Sand, Gravel...',
                    controller: materialCtrl,
                    icon: Icons.inventory_2_outlined,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _EntryField(
                    label: 'Customer',
                    hint: 'Name',
                    controller: customerNameCtrl,
                    icon: Icons.person_outline_rounded,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _EntryField(
                    label: 'Phone',
                    hint: '10-digit',
                    controller: customerPhoneCtrl,
                    icon: Icons.phone_outlined,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton.icon(
                onPressed: onCapture,
                icon: const Icon(Icons.camera_rounded, size: 18),
                label: Text(isTare ? 'Capture Tare Weight' : 'Capture Gross Weight'),
                style: FilledButton.styleFrom(
                  backgroundColor: accentColor,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  textStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EntryField extends StatelessWidget {
  final String label;
  final String hint;
  final TextEditingController controller;
  final IconData icon;

  const _EntryField({
    required this.label,
    required this.hint,
    required this.controller,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 5),
        TextField(
          controller: controller,
          style: text.bodySmall,
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: Icon(icon, size: 16),
            prefixIconConstraints: const BoxConstraints(minWidth: 36),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            isDense: true,
          ),
        ),
      ],
    );
  }
}

// ─── Completion State ────────────────────────────────────────────────────────

class _CompletionState extends ConsumerStatefulWidget {
  final WeighmentState state;

  const _CompletionState({required this.state});

  @override
  ConsumerState<_CompletionState> createState() => _CompletionStateState();
}

class _CompletionStateState extends ConsumerState<_CompletionState>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entranceCtrl;

  @override
  void initState() {
    super.initState();
    _entranceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..forward();
  }

  @override
  void dispose() {
    _entranceCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final ws = widget.state;
    final netWeight = ws.isTare && ws.grossWeight != null && ws.tareWeight != null
        ? ws.grossWeight! - ws.tareWeight!
        : null;

    return AnimatedBuilder(
      animation: CurvedAnimation(parent: _entranceCtrl, curve: Curves.easeOutBack),
      builder: (context, child) => Transform.scale(
        scale: 0.9 + 0.1 * _entranceCtrl.value,
        child: Opacity(opacity: _entranceCtrl.value, child: child),
      ),
      child: Center(
        child: Container(
          width: 420,
          padding: const EdgeInsets.all(40),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: scheme.primary.withValues(alpha: 0.2)),
            boxShadow: [
              BoxShadow(
                color: scheme.primary.withValues(alpha: 0.08),
                blurRadius: 40,
                spreadRadius: 4,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Success icon
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.check_rounded, size: 36, color: scheme.primary),
              ),
              const SizedBox(height: 20),
              Text(
                'Weighment Captured',
                style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                'Transaction recorded successfully',
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 28),

              // RST badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'RST-${ws.rstNumber}',
                  style: text.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: scheme.primary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Details grid
              _CompletionRow(label: 'Vehicle', value: ws.vehicleNumber ?? '--'),
              _CompletionRow(label: 'Material', value: ws.material ?? 'Unknown'),
              _CompletionRow(label: 'Customer', value: ws.customerName ?? 'Walk-in'),
              const Divider(height: 24),
              if (ws.grossWeight != null)
                _CompletionRow(
                  label: 'Gross Weight',
                  value: '${NumberFormat('#,###').format(ws.grossWeight!.round())} kg',
                  bold: true,
                ),
              if (ws.tareWeight != null)
                _CompletionRow(
                  label: 'Tare Weight',
                  value: '${NumberFormat('#,###').format(ws.tareWeight!.round())} kg',
                  bold: true,
                ),
              if (netWeight != null)
                _CompletionRow(
                  label: 'Net Weight',
                  value: '${NumberFormat('#,###').format(netWeight.round())} kg',
                  bold: true,
                  accent: true,
                ),
              const SizedBox(height: 28),

              // Actions
              SizedBox(
                width: double.infinity,
                height: 46,
                child: FilledButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.print_rounded, size: 18),
                  label: const Text('Print RST Receipt'),
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 42,
                child: OutlinedButton.icon(
                  onPressed: () => ref.read(weighmentStateProvider.notifier).reset(),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('New Weighment'),
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompletionRow extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;
  final bool accent;

  const _CompletionRow({
    required this.label,
    required this.value,
    this.bold = false,
    this.accent = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(
            label,
            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const Spacer(),
          Text(
            value,
            style: text.bodySmall?.copyWith(
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
              color: accent ? scheme.primary : scheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}
