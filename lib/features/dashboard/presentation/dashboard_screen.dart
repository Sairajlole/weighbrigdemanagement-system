import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:weighbridgemanagement/shared/providers/auth_provider.dart';
import 'package:weighbridgemanagement/shared/providers/firestore_provider.dart';

// ─── Providers ─────────────────────────────────────────────────────────────────

final _weighmentsProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  final db = ref.watch(firestoreProvider);
  return db
      .collection('weighments')
      .orderBy('createdAt', descending: true)
      .limit(100)
      .snapshots()
      .map((snap) => snap.docs.map((d) => {'id': d.id, ...d.data()}).toList());
});

final _operatorProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null) return null;
  final db = ref.read(firestoreProvider);
  final snap = await db.collection('operators').where('uid', isEqualTo: user.uid).limit(1).get();
  if (snap.docs.isEmpty) return null;
  return {'id': snap.docs.first.id, ...snap.docs.first.data()};
});

final _customersProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  final db = ref.watch(firestoreProvider);
  return db
      .collection('customers')
      .orderBy('totalWeighments', descending: true)
      .limit(10)
      .snapshots()
      .map((snap) => snap.docs.map((d) => {'id': d.id, ...d.data()}).toList());
});

// ─── Dashboard Screen ──────────────────────────────────────────────────────────

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen>
    with TickerProviderStateMixin {
  late final AnimationController _entranceController;
  late final AnimationController _pulseController;
  late final AnimationController _shimmerController;

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..forward();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _pulseController.dispose();
    _shimmerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final weighments = ref.watch(_weighmentsProvider).valueOrNull ?? [];
    final operator = ref.watch(_operatorProvider).valueOrNull;
    final customers = ref.watch(_customersProvider).valueOrNull ?? [];

    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final today = weighments.where((w) {
      final ts = w['createdAt'] as Timestamp?;
      return ts != null && ts.toDate().isAfter(todayStart);
    }).toList();
    final completed = today.where((w) => w['status'] == 'completed').length;
    final awaitingTare = weighments.where((w) => w['status'] == 'awaitingTare').toList();
    final totalNetWeight = weighments.fold<double>(
        0, (acc, w) => acc + ((w['netWeight'] as num?) ?? 0).toDouble());
    final todayNetWeight = today.fold<double>(
        0, (acc, w) => acc + ((w['netWeight'] as num?) ?? 0).toDouble());

    final hourlyData = _computeHourlyData(today, now);
    final materialBreakdown = _computeMaterialBreakdown(weighments);
    final weeklyData = _computeWeeklyData(weighments, now);

    return AnimatedBuilder(
      animation: _entranceController,
      builder: (context, child) => child!,
      child: Container(
        color: scheme.surfaceContainerLowest,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ─── Header ────────────────────────────────────────────
              _SlideIn(
                controller: _entranceController,
                delay: 0.0,
                child: _DashboardHeader(
                  operatorName: operator?['name'] ?? 'Operator',
                  now: now,
                  onNewWeighment: () => context.go('/weighment'),
                ),
              ),
              const SizedBox(height: 28),

              // ─── Metric Cards ──────────────────────────────────────
              _SlideIn(
                controller: _entranceController,
                delay: 0.1,
                child: Row(
                  children: [
                    Expanded(
                      child: _MetricCard(
                        title: "Today's Weighments",
                        value: completed,
                        suffix: 'completed',
                        icon: Icons.check_circle_rounded,
                        gradient: [scheme.primary, scheme.primary.withValues(alpha: 0.7)],
                        sparkData: hourlyData,
                        pulseController: _pulseController,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _MetricCard(
                        title: 'Awaiting Tare',
                        value: awaitingTare.length,
                        suffix: 'vehicles',
                        icon: Icons.hourglass_top_rounded,
                        gradient: [scheme.tertiary, scheme.tertiary.withValues(alpha: 0.7)],
                        sparkData: const [],
                        pulseController: _pulseController,
                        alert: awaitingTare.length > 3,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _MetricCard(
                        title: "Today's Throughput",
                        value: todayNetWeight.round(),
                        suffix: 'kg',
                        icon: Icons.trending_up_rounded,
                        gradient: [scheme.secondary, scheme.secondary.withValues(alpha: 0.7)],
                        sparkData: hourlyData,
                        pulseController: _pulseController,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _MetricCard(
                        title: 'Total Processed',
                        value: totalNetWeight.round(),
                        suffix: 'kg all-time',
                        icon: Icons.inventory_2_rounded,
                        gradient: [
                          const Color(0xFF7C3AED),
                          const Color(0xFF7C3AED).withValues(alpha: 0.7),
                        ],
                        sparkData: weeklyData,
                        pulseController: _pulseController,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // ─── Main Content Grid ─────────────────────────────────
              _SlideIn(
                controller: _entranceController,
                delay: 0.2,
                child: SizedBox(
                  height: 340,
                  child: Row(
                    children: [
                      // Throughput Chart
                      Expanded(
                        flex: 3,
                        child: _ThroughputChart(
                          weeklyData: weeklyData,
                          scheme: scheme,
                          text: text,
                          shimmerController: _shimmerController,
                        ),
                      ),
                      const SizedBox(width: 16),
                      // Material Breakdown
                      Expanded(
                        flex: 2,
                        child: _MaterialBreakdownCard(
                          data: materialBreakdown,
                          scheme: scheme,
                          text: text,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // ─── Bottom Section ────────────────────────────────────
              _SlideIn(
                controller: _entranceController,
                delay: 0.3,
                child: SizedBox(
                  height: 380,
                  child: Row(
                    children: [
                      // Live Activity Feed
                      Expanded(
                        flex: 2,
                        child: _LiveActivityFeed(
                          weighments: weighments.take(12).toList(),
                          scheme: scheme,
                          text: text,
                        ),
                      ),
                      const SizedBox(width: 16),
                      // Awaiting Tare Queue
                      Expanded(
                        flex: 2,
                        child: _AwaitingTareQueue(
                          items: awaitingTare,
                          scheme: scheme,
                          text: text,
                        ),
                      ),
                      const SizedBox(width: 16),
                      // Top Customers
                      Expanded(
                        flex: 2,
                        child: _TopCustomersCard(
                          customers: customers,
                          scheme: scheme,
                          text: text,
                        ),
                      ),
                    ],
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

// ─── Helper Functions ────────────────────────────────────────────────────────

List<double> _computeHourlyData(List<Map<String, dynamic>> today, DateTime now) {
  final hours = List.filled(24, 0.0);
  for (final w in today) {
    final ts = w['createdAt'] as Timestamp?;
    if (ts != null) {
      hours[ts.toDate().hour] += 1;
    }
  }
  return hours.sublist(0, now.hour + 1);
}

List<double> _computeWeeklyData(List<Map<String, dynamic>> weighments, DateTime now) {
  final data = List.filled(7, 0.0);
  for (final w in weighments) {
    final ts = w['createdAt'] as Timestamp?;
    if (ts == null) continue;
    final diff = now.difference(ts.toDate()).inDays;
    if (diff < 7) {
      data[6 - diff] += ((w['netWeight'] as num?) ?? 0).toDouble();
    }
  }
  return data;
}

Map<String, double> _computeMaterialBreakdown(List<Map<String, dynamic>> weighments) {
  final map = <String, double>{};
  for (final w in weighments) {
    final mat = (w['material'] as String?) ?? 'Unknown';
    map[mat] = (map[mat] ?? 0) + ((w['netWeight'] as num?) ?? 0).toDouble();
  }
  final sorted = map.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  return Map.fromEntries(sorted.take(6));
}

// ─── Slide In Animation Widget ───────────────────────────────────────────────

class _SlideIn extends StatelessWidget {
  final AnimationController controller;
  final double delay;
  final Widget child;

  const _SlideIn({required this.controller, required this.delay, required this.child});

  @override
  Widget build(BuildContext context) {
    final animation = CurvedAnimation(
      parent: controller,
      curve: Interval(delay, math.min(delay + 0.4, 1.0), curve: Curves.easeOutCubic),
    );

    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) => Transform.translate(
        offset: Offset(0, 20 * (1 - animation.value)),
        child: Opacity(opacity: animation.value, child: child),
      ),
      child: child,
    );
  }
}

// ─── Dashboard Header ────────────────────────────────────────────────────────

class _DashboardHeader extends StatelessWidget {
  final String operatorName;
  final DateTime now;
  final VoidCallback onNewWeighment;

  const _DashboardHeader({
    required this.operatorName,
    required this.now,
    required this.onNewWeighment,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final hour = now.hour;
    final greeting = hour < 12
        ? 'Good morning'
        : hour < 17
            ? 'Good afternoon'
            : 'Good evening';

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$greeting, $operatorName',
                style: text.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: scheme.primary.withValues(alpha: 0.4),
                          blurRadius: 6,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Live',
                    style: text.labelMedium?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    DateFormat('EEEE, d MMMM yyyy  •  HH:mm').format(now),
                    style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ],
          ),
        ),
        _GlowButton(
          onPressed: onNewWeighment,
          icon: Icons.add_rounded,
          label: 'New Weighment',
        ),
      ],
    );
  }
}

// ─── Glow Button ─────────────────────────────────────────────────────────────

class _GlowButton extends StatefulWidget {
  final VoidCallback onPressed;
  final IconData icon;
  final String label;

  const _GlowButton({required this.onPressed, required this.icon, required this.label});

  @override
  State<_GlowButton> createState() => _GlowButtonState();
}

class _GlowButtonState extends State<_GlowButton> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return MouseRegion(
      onEnter: (_) => _controller.forward(),
      onExit: (_) => _controller.reverse(),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) => Transform.scale(
          scale: 1.0 + (_controller.value * 0.03),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: scheme.primary.withValues(alpha: 0.3 * _controller.value),
                  blurRadius: 16 * _controller.value,
                  spreadRadius: 2 * _controller.value,
                ),
              ],
            ),
            child: child,
          ),
        ),
        child: FilledButton.icon(
          onPressed: widget.onPressed,
          icon: Icon(widget.icon, size: 18),
          label: Text(widget.label),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ),
    );
  }
}

// ─── Metric Card ─────────────────────────────────────────────────────────────

class _MetricCard extends StatefulWidget {
  final String title;
  final int value;
  final String suffix;
  final IconData icon;
  final List<Color> gradient;
  final List<double> sparkData;
  final AnimationController pulseController;
  final bool alert;

  const _MetricCard({
    required this.title,
    required this.value,
    required this.suffix,
    required this.icon,
    required this.gradient,
    required this.sparkData,
    required this.pulseController,
    this.alert = false,
  });

  @override
  State<_MetricCard> createState() => _MetricCardState();
}

class _MetricCardState extends State<_MetricCard> with SingleTickerProviderStateMixin {
  late final AnimationController _countController;
  bool _hovered = false;

  @override
  void initState() {
    super.initState();
    _countController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..forward();
  }

  @override
  void dispose() {
    _countController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        transform: Matrix4.translationValues(0.0, _hovered ? -4.0 : 0.0, 0.0),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _hovered
                ? widget.gradient[0].withValues(alpha: 0.4)
                : scheme.outlineVariant.withValues(alpha: 0.3),
          ),
          boxShadow: [
            BoxShadow(
              color: _hovered
                  ? widget.gradient[0].withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.03),
              blurRadius: _hovered ? 20 : 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: widget.gradient,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: widget.gradient[0].withValues(alpha: 0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Icon(widget.icon, color: Colors.white, size: 18),
                ),
                const Spacer(),
                if (widget.alert)
                  AnimatedBuilder(
                    animation: widget.pulseController,
                    builder: (context, child) => Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: scheme.error,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: scheme.error.withValues(
                              alpha: 0.4 * widget.pulseController.value,
                            ),
                            blurRadius: 8 * widget.pulseController.value,
                            spreadRadius: 2 * widget.pulseController.value,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            AnimatedBuilder(
              animation: CurvedAnimation(parent: _countController, curve: Curves.easeOutExpo),
              builder: (context, _) {
                final v = (_countController.value * widget.value).round();
                return Text(
                  NumberFormat('#,###').format(v),
                  style: text.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                );
              },
            ),
            const SizedBox(height: 2),
            Text(
              widget.title,
              style: text.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
            Text(
              widget.suffix,
              style: text.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
              ),
            ),
            if (widget.sparkData.isNotEmpty) ...[
              const SizedBox(height: 12),
              SizedBox(
                height: 32,
                child: CustomPaint(
                  size: const Size(double.infinity, 32),
                  painter: _SparklinePainter(
                    data: widget.sparkData,
                    color: widget.gradient[0],
                    filled: true,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Sparkline Painter ───────────────────────────────────────────────────────

class _SparklinePainter extends CustomPainter {
  final List<double> data;
  final Color color;
  final bool filled;

  _SparklinePainter({required this.data, required this.color, this.filled = false});

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final maxVal = data.reduce(math.max);
    if (maxVal == 0) return;

    final points = <Offset>[];
    for (var i = 0; i < data.length; i++) {
      final x = (i / (data.length - 1).clamp(1, double.infinity)) * size.width;
      final y = size.height - (data[i] / maxVal) * size.height * 0.9;
      points.add(Offset(x, y));
    }

    final path = Path();
    if (points.length < 2) return;

    path.moveTo(points[0].dx, points[0].dy);
    for (var i = 1; i < points.length; i++) {
      final cp1x = points[i - 1].dx + (points[i].dx - points[i - 1].dx) / 3;
      final cp2x = points[i].dx - (points[i].dx - points[i - 1].dx) / 3;
      path.cubicTo(cp1x, points[i - 1].dy, cp2x, points[i].dy, points[i].dx, points[i].dy);
    }

    final linePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, linePaint);

    if (filled) {
      final fillPath = Path.from(path);
      fillPath.lineTo(size.width, size.height);
      fillPath.lineTo(0, size.height);
      fillPath.close();

      final fillPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.2), color.withValues(alpha: 0.0)],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
      canvas.drawPath(fillPath, fillPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter old) =>
      old.data != data || old.color != color;
}

// ─── Throughput Chart ────────────────────────────────────────────────────────

class _ThroughputChart extends StatefulWidget {
  final List<double> weeklyData;
  final ColorScheme scheme;
  final TextTheme text;
  final AnimationController shimmerController;

  const _ThroughputChart({
    required this.weeklyData,
    required this.scheme,
    required this.text,
    required this.shimmerController,
  });

  @override
  State<_ThroughputChart> createState() => _ThroughputChartState();
}

class _ThroughputChartState extends State<_ThroughputChart>
    with SingleTickerProviderStateMixin {
  late final AnimationController _chartAnim;

  @override
  void initState() {
    super.initState();
    _chartAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..forward();
  }

  @override
  void dispose() {
    _chartAnim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final dayLabels = List.generate(7, (i) {
      final d = now.subtract(Duration(days: 6 - i));
      return DateFormat('EEE').format(d);
    });

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: widget.scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: widget.scheme.outlineVariant.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.show_chart_rounded, size: 18, color: widget.scheme.primary),
              const SizedBox(width: 8),
              Text(
                'Weekly Throughput',
                style: widget.text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: widget.scheme.primaryContainer.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${NumberFormat('#,###').format(widget.weeklyData.fold(0.0, (a, b) => a + b).round())} kg',
                  style: widget.text.labelSmall?.copyWith(
                    color: widget.scheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Expanded(
            child: AnimatedBuilder(
              animation: CurvedAnimation(parent: _chartAnim, curve: Curves.easeOutCubic),
              builder: (context, _) => CustomPaint(
                size: const Size(double.infinity, double.infinity),
                painter: _BarChartPainter(
                  data: widget.weeklyData,
                  labels: dayLabels,
                  color: widget.scheme.primary,
                  bgColor: widget.scheme.surfaceContainerHigh,
                  textColor: widget.scheme.onSurfaceVariant,
                  progress: _chartAnim.value,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Bar Chart Painter ───────────────────────────────────────────────────────

class _BarChartPainter extends CustomPainter {
  final List<double> data;
  final List<String> labels;
  final Color color;
  final Color bgColor;
  final Color textColor;
  final double progress;

  _BarChartPainter({
    required this.data,
    required this.labels,
    required this.color,
    required this.bgColor,
    required this.textColor,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final maxVal = data.reduce(math.max);
    if (maxVal == 0) return;

    final barWidth = (size.width / data.length) * 0.5;
    final gap = (size.width - barWidth * data.length) / (data.length + 1);
    final chartHeight = size.height - 28;

    for (var i = 0; i < data.length; i++) {
      final x = gap + i * (barWidth + gap);
      final barHeight = (data[i] / maxVal) * chartHeight * progress;

      // Background bar
      final bgRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, 0, barWidth, chartHeight),
        const Radius.circular(6),
      );
      canvas.drawRRect(bgRect, Paint()..color = bgColor.withValues(alpha: 0.4));

      // Data bar with gradient
      final barRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, chartHeight - barHeight, barWidth, barHeight),
        const Radius.circular(6),
      );
      final gradient = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [color, color.withValues(alpha: 0.6)],
      );
      canvas.drawRRect(
        barRect,
        Paint()
          ..shader = gradient.createShader(
            Rect.fromLTWH(x, chartHeight - barHeight, barWidth, barHeight),
          ),
      );

      // Glow effect on top
      if (barHeight > 4) {
        canvas.drawCircle(
          Offset(x + barWidth / 2, chartHeight - barHeight + 2),
          barWidth / 3,
          Paint()
            ..color = color.withValues(alpha: 0.2 * progress)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
        );
      }

      // Label
      final labelPainter = TextPainter(
        text: TextSpan(
          text: labels[i],
          style: TextStyle(color: textColor, fontSize: 10, fontWeight: FontWeight.w500),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      labelPainter.paint(
        canvas,
        Offset(x + (barWidth - labelPainter.width) / 2, chartHeight + 10),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BarChartPainter old) =>
      old.progress != progress || old.data != data;
}

// ─── Material Breakdown Card ─────────────────────────────────────────────────

class _MaterialBreakdownCard extends StatelessWidget {
  final Map<String, double> data;
  final ColorScheme scheme;
  final TextTheme text;

  const _MaterialBreakdownCard({
    required this.data,
    required this.scheme,
    required this.text,
  });

  static const _colors = [
    Color(0xFF059669),
    Color(0xFF0EA5E9),
    Color(0xFF7C3AED),
    Color(0xFFF59E0B),
    Color(0xFFEF4444),
    Color(0xFF6366F1),
  ];

  @override
  Widget build(BuildContext context) {
    final total = data.values.fold(0.0, (a, b) => a + b);
    final entries = data.entries.toList();

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.donut_small_rounded, size: 18, color: scheme.secondary),
              const SizedBox(width: 8),
              Text(
                'Materials',
                style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (entries.isEmpty)
            Expanded(
              child: Center(
                child: Text(
                  'No data yet',
                  style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
            )
          else ...[
            // Donut-style stacked bar
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                height: 12,
                child: Row(
                  children: entries.asMap().entries.map((e) {
                    final fraction = total > 0 ? e.value.value / total : 0.0;
                    return Expanded(
                      flex: (fraction * 100).round().clamp(1, 100),
                      child: Container(color: _colors[e.key % _colors.length]),
                    );
                  }).toList(),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: ListView.separated(
                itemCount: entries.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  final pct = total > 0 ? (entries[i].value / total * 100) : 0.0;
                  return Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: _colors[i % _colors.length],
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          entries[i].key,
                          style: text.bodySmall?.copyWith(fontWeight: FontWeight.w500),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        '${pct.toStringAsFixed(1)}%',
                        style: text.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${NumberFormat.compact().format(entries[i].value)} kg',
                        style: text.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Live Activity Feed ──────────────────────────────────────────────────────

class _LiveActivityFeed extends StatelessWidget {
  final List<Map<String, dynamic>> weighments;
  final ColorScheme scheme;
  final TextTheme text;

  const _LiveActivityFeed({
    required this.weighments,
    required this.scheme,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: scheme.primary,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: scheme.primary.withValues(alpha: 0.4),
                      blurRadius: 4,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Live Activity',
                style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              Text(
                '${weighments.length} recent',
                style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: weighments.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.pending_actions_rounded, size: 32, color: scheme.outlineVariant),
                        const SizedBox(height: 8),
                        Text(
                          'No activity yet',
                          style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: weighments.length,
                    itemBuilder: (context, i) {
                      final w = weighments[i];
                      final ts = w['createdAt'] as Timestamp?;
                      final time = ts != null ? _timeAgo(ts.toDate()) : '';
                      final status = w['status'] as String? ?? 'pending';

                      return _ActivityItem(
                        vehicle: w['vehicleNumber'] ?? '--',
                        customer: w['customerName'] ?? '--',
                        material: w['material'] ?? '--',
                        weight: w['netWeight'] as num?,
                        status: status,
                        time: time,
                        scheme: scheme,
                        text: text,
                        isFirst: i == 0,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

class _ActivityItem extends StatelessWidget {
  final String vehicle;
  final String customer;
  final String material;
  final num? weight;
  final String status;
  final String time;
  final ColorScheme scheme;
  final TextTheme text;
  final bool isFirst;

  const _ActivityItem({
    required this.vehicle,
    required this.customer,
    required this.material,
    required this.weight,
    required this.status,
    required this.time,
    required this.scheme,
    required this.text,
    required this.isFirst,
  });

  @override
  Widget build(BuildContext context) {
    final (IconData icon, Color color) = switch (status) {
      'completed' => (Icons.check_circle_rounded, scheme.primary),
      'awaitingTare' => (Icons.hourglass_top_rounded, scheme.tertiary),
      _ => (Icons.radio_button_unchecked, scheme.outline),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isFirst ? scheme.primaryContainer.withValues(alpha: 0.08) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        vehicle,
                        style: text.labelMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '• $material',
                        style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                  Text(
                    customer,
                    style: text.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (weight != null)
                  Text(
                    '${NumberFormat('#,###').format(weight)} kg',
                    style: text.labelSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                Text(
                  time,
                  style: text.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Awaiting Tare Queue ─────────────────────────────────────────────────────

class _AwaitingTareQueue extends StatelessWidget {
  final List<Map<String, dynamic>> items;
  final ColorScheme scheme;
  final TextTheme text;

  const _AwaitingTareQueue({
    required this.items,
    required this.scheme,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: items.isNotEmpty
              ? scheme.tertiary.withValues(alpha: 0.3)
              : scheme.outlineVariant.withValues(alpha: 0.3),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.queue_rounded, size: 18, color: scheme.tertiary),
              const SizedBox(width: 8),
              Text(
                'Tare Queue',
                style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              if (items.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: scheme.tertiaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${items.length}',
                    style: text.labelSmall?.copyWith(
                      color: scheme.onTertiaryContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: items.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle_outline_rounded, size: 36, color: scheme.primary.withValues(alpha: 0.4)),
                        const SizedBox(height: 8),
                        Text(
                          'All clear!',
                          style: text.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          'No vehicles waiting',
                          style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant.withValues(alpha: 0.6)),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final w = items[i];
                      final ts = w['createdAt'] as Timestamp?;
                      final waitTime = ts != null
                          ? _formatWait(DateTime.now().difference(ts.toDate()))
                          : '';

                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.2)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: scheme.tertiaryContainer.withValues(alpha: 0.5),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Center(
                                child: Text(
                                  '${i + 1}',
                                  style: text.labelMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: scheme.tertiary,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    w['vehicleNumber'] ?? '--',
                                    style: text.labelMedium?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                  Text(
                                    '${w['customerName'] ?? ''} • ${((w['grossWeight'] as num?)?.toStringAsFixed(0) ?? '--')} kg gross',
                                    style: text.labelSmall?.copyWith(
                                      color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  waitTime,
                                  style: text.labelSmall?.copyWith(
                                    color: scheme.tertiary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'waiting',
                                  style: text.labelSmall?.copyWith(
                                    color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
                                    fontSize: 9,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  String _formatWait(Duration d) {
    if (d.inMinutes < 60) return '${d.inMinutes}m';
    if (d.inHours < 24) return '${d.inHours}h ${d.inMinutes % 60}m';
    return '${d.inDays}d';
  }
}

// ─── Top Customers Card ──────────────────────────────────────────────────────

class _TopCustomersCard extends StatelessWidget {
  final List<Map<String, dynamic>> customers;
  final ColorScheme scheme;
  final TextTheme text;

  const _TopCustomersCard({
    required this.customers,
    required this.scheme,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.people_rounded, size: 18, color: const Color(0xFF7C3AED)),
              const SizedBox(width: 8),
              Text(
                'Top Customers',
                style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: customers.isEmpty
                ? Center(
                    child: Text(
                      'No customers yet',
                      style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  )
                : ListView.separated(
                    itemCount: customers.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (context, i) {
                      final c = customers[i];
                      final name = c['name'] ?? 'Unknown';
                      final totalW = (c['totalWeighments'] as num?) ?? 0;
                      final totalKg = (c['totalNetWeight'] as num?) ?? 0;
                      final maxKg = customers.isNotEmpty
                          ? ((customers[0]['totalNetWeight'] as num?) ?? 1).toDouble()
                          : 1.0;
                      final fraction = maxKg > 0 ? totalKg.toDouble() / maxKg : 0.0;

                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          color: i == 0
                              ? const Color(0xFF7C3AED).withValues(alpha: 0.05)
                              : Colors.transparent,
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: _avatarColor(i).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(7),
                              ),
                              child: Center(
                                child: Text(
                                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                                  style: text.labelSmall?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: _avatarColor(i),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name,
                                    style: text.labelMedium?.copyWith(fontWeight: FontWeight.w600),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 3),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(2),
                                    child: LinearProgressIndicator(
                                      value: fraction,
                                      minHeight: 3,
                                      backgroundColor: scheme.surfaceContainerHigh,
                                      valueColor: AlwaysStoppedAnimation(_avatarColor(i).withValues(alpha: 0.6)),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  NumberFormat.compact().format(totalKg),
                                  style: text.labelSmall?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                Text(
                                  '$totalW trips',
                                  style: text.labelSmall?.copyWith(
                                    color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
                                    fontSize: 9,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Color _avatarColor(int i) {
    const colors = [
      Color(0xFF7C3AED),
      Color(0xFF059669),
      Color(0xFF0EA5E9),
      Color(0xFFF59E0B),
      Color(0xFFEF4444),
      Color(0xFF6366F1),
      Color(0xFFEC4899),
      Color(0xFF14B8A6),
      Color(0xFFF97316),
      Color(0xFF8B5CF6),
    ];
    return colors[i % colors.length];
  }
}
