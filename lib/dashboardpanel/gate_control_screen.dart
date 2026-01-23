import 'package:flutter/material.dart';
import 'dart:async';
import 'package:weighbridgemanagement/widgets/main_layout.dart';

class GateControlScreen extends StatefulWidget {
  const GateControlScreen({super.key});

  @override
  State<GateControlScreen> createState() => _GateControlScreenState();
}

class _GateControlScreenState extends State<GateControlScreen>
    with TickerProviderStateMixin {
  static const Color emerald = Color(0xFF059669);
  static const Color emeraldLight = Color(0xFFD1FAE5);

  // Gate states
  double _entryGateProgress = 0.0;
  Timer? _navigationTimer;

  late AnimationController _gateAnimationController;
  late Animation<double> _gateAnimation;

  @override
  void initState() {
    super.initState();
    _gateAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );
    _gateAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _gateAnimationController, curve: Curves.easeInOut),
    );
    _gateAnimationController.addListener(() {
      setState(() {
        _entryGateProgress = _gateAnimation.value;
      });
    });

    // Start the gate opening animation
    _startGateOpening();
    
    // Auto-navigate to Vehicle Detection after 5 seconds
    _navigationTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/vehicleDetection');
      }
    });
  }

  void _startGateOpening() {
    _gateAnimationController.forward();
  }

  @override
  void dispose() {
    _gateAnimationController.dispose();
    _navigationTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MainLayout(
      activeNav: "Weighbridge",
      child: Column(
        children: [
          // Header with breadcrumb
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(
                bottom: BorderSide(color: Color(0xFFE5E7EB)),
              ),
            ),
            child: Row(
              children: [
                // Breadcrumb
                Row(
                  children: [
                    Text(
                      "Home",
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Text("/", style: TextStyle(color: Colors.grey)),
                    ),
                    Text(
                      "Weighbridge",
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Text("/", style: TextStyle(color: Colors.grey)),
                    ),
                    const Text(
                      "Gate Control",
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1F2937),
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                // System Online indicator
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: emeraldLight,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: emerald,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        "System Online",
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: emerald,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Main content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title and Live Connection
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Gate Control",
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1F2937),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            "Monitoring Point A • Lane 01",
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: const BoxDecoration(
                              color: emerald,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            "Live Connection",
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: emerald,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Main content row
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Left side - Live Platform View
                      Expanded(
                        flex: 2,
                        child: _buildLivePlatformView(),
                      ),

                      const SizedBox(width: 20),

                      // Right side - Gate Controls
                      SizedBox(
                        width: 280,
                        child: Column(
                          children: [
                            _buildGateStatusCard(
                              title: "ENTRY GATE",
                              isOpen: _entryGateProgress > 0,
                              status: _entryGateProgress >= 1.0
                                  ? "Open"
                                  : "Opening...",
                              subtitle: _entryGateProgress >= 1.0
                                  ? "Gate fully opened"
                                  : "Barrier lifting to 90°",
                              progress: _entryGateProgress,
                              isEntry: true,
                            ),
                            const SizedBox(height: 16),
                            _buildGateStatusCard(
                              title: "EXIT GATE",
                              isOpen: false,
                              status: "Closed",
                              subtitle: "Waiting for weighing complete",
                              progress: 0.0,
                              isEntry: false,
                            ),
                            const SizedBox(height: 16),
                            _buildAutomationCard(),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Process Timeline
                  _buildProcessTimeline(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLivePlatformView() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Live Platform View",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1F2937),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.videocam,
                  size: 20,
                  color: Color(0xFF6B7280),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Platform visualization
          Container(
            height: 280,
            decoration: BoxDecoration(
              color: const Color(0xFFF9FAFB),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: Stack(
              children: [
                // Entry barrier (left)
                Positioned(
                  left: 80,
                  top: 30,
                  child: _buildBarrier(
                    isOpen: _entryGateProgress > 0.5,
                    rotation: _entryGateProgress * 90,
                  ),
                ),

                // Exit barrier (right)
                Positioned(
                  right: 80,
                  top: 30,
                  child: _buildBarrier(
                    isOpen: false,
                    rotation: 0,
                    isExit: true,
                  ),
                ),

                // Weighbridge platform
                Center(
                  child: Container(
                    width: 280,
                    height: 120,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: const Color(0xFF10B981),
                        width: 2,
                        strokeAlign: BorderSide.strokeAlignOutside,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.grey.withOpacity(0.1),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Stack(
                      children: [
                        // Corner markers
                        _buildCornerMarker(top: 8, left: 8),
                        _buildCornerMarker(top: 8, right: 8, rotated: true),
                        _buildCornerMarker(bottom: 8, left: 8, rotated: true),
                        _buildCornerMarker(bottom: 8, right: 8),

                        // Center dashed border
                        Center(
                          child: Container(
                            width: 200,
                            height: 60,
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: Colors.grey.shade300,
                                width: 1,
                              ),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: CustomPaint(
                              painter: DashedBorderPainter(),
                              child: const Center(
                                child: Text(
                                  "VEHICLE POSITION",
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: Color(0xFF9CA3AF),
                                    letterSpacing: 1,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Entry label
                Positioned(
                  left: 80,
                  bottom: 40,
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: const Color(0xFFE5E7EB)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.login, size: 14, color: Color(0xFF6B7280)),
                            SizedBox(width: 4),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        "ENTRY",
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF6B7280),
                        ),
                      ),
                    ],
                  ),
                ),

                // Exit label
                Positioned(
                  right: 80,
                  bottom: 40,
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: const Color(0xFFE5E7EB)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.logout, size: 14, color: Color(0xFF6B7280)),
                            SizedBox(width: 4),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        "EXIT",
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF6B7280),
                        ),
                      ),
                    ],
                  ),
                ),

                // Scale ID
                Positioned(
                  right: 16,
                  bottom: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                    ),
                    child: const Text(
                      "Scale ID: WB-01",
                      style: TextStyle(
                        fontSize: 11,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBarrier({
    required bool isOpen,
    required double rotation,
    bool isExit = false,
  }) {
    return SizedBox(
      width: 60,
      height: 100,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Barrier pole
          Positioned(
            bottom: 0,
            left: 25,
            child: Container(
              width: 10,
              height: 50,
              decoration: BoxDecoration(
                color: const Color(0xFF9CA3AF),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // Barrier arm
          Positioned(
            bottom: 45,
            left: isExit ? 15 : 15,
            child: Transform.rotate(
              angle: isExit
                  ? 0
                  : -rotation * 3.14159 / 180,
              alignment: Alignment.bottomCenter,
              child: Container(
                width: 8,
                height: 60,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white,
                      Color(0xFFDC2626),
                      Colors.white,
                      Color(0xFFDC2626),
                      Colors.white,
                      Color(0xFFDC2626),
                    ],
                    stops: [0.0, 0.15, 0.3, 0.45, 0.6, 0.75],
                  ),
                  borderRadius: BorderRadius.circular(2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 4,
                      offset: const Offset(1, 1),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCornerMarker({
    double? top,
    double? left,
    double? right,
    double? bottom,
    bool rotated = false,
  }) {
    return Positioned(
      top: top,
      left: left,
      right: right,
      bottom: bottom,
      child: Transform.rotate(
        angle: rotated ? 3.14159 : 0,
        child: Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: Colors.grey.shade400, width: 2),
              left: BorderSide(color: Colors.grey.shade400, width: 2),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGateStatusCard({
    required String title,
    required bool isOpen,
    required String status,
    required String subtitle,
    required double progress,
    required bool isEntry,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: isOpen || progress > 0 ? emerald : Colors.grey.shade400,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF6B7280),
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  status,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1F2937),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade500,
                  ),
                ),
                if (isEntry && progress > 0 && progress < 1.0) ...[
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress,
                      backgroundColor: const Color(0xFFE5E7EB),
                      valueColor: const AlwaysStoppedAnimation<Color>(emerald),
                      minHeight: 6,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAutomationCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.grey.shade400),
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                "Proceeding automatically...",
                style: TextStyle(
                  fontSize: 13,
                  color: Color(0xFF6B7280),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                // Skip gate control logic
              },
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                side: const BorderSide(color: Color(0xFFE5E7EB)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              icon: const Icon(
                Icons.skip_next,
                size: 18,
                color: Color(0xFF6B7280),
              ),
              label: const Text(
                "Skip Gate Control",
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF374151),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProcessTimeline() {
    final steps = [
      {"label": "ID Check", "icon": Icons.check_circle, "completed": true},
      {"label": "Gate Entry", "icon": Icons.door_front_door, "completed": true, "active": true},
      {"label": "Positioning", "icon": Icons.place, "completed": false},
      {"label": "Weighing", "icon": Icons.scale, "completed": false},
    ];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Process Timeline",
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1F2937),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: List.generate(steps.length * 2 - 1, (index) {
              if (index.isOdd) {
                // Connector line
                final stepIndex = index ~/ 2;
                final isCompleted = steps[stepIndex]["completed"] as bool;
                return Expanded(
                  child: Container(
                    height: 2,
                    color: isCompleted ? emerald : const Color(0xFFE5E7EB),
                  ),
                );
              }

              // Step indicator
              final stepIndex = index ~/ 2;
              final step = steps[stepIndex];
              final isCompleted = step["completed"] as bool;
              final isActive = step["active"] == true;

              return _buildTimelineStep(
                label: step["label"] as String,
                stepNumber: stepIndex + 1,
                isCompleted: isCompleted,
                isActive: isActive,
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineStep({
    required String label,
    required int stepNumber,
    required bool isCompleted,
    required bool isActive,
  }) {
    return Column(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: isCompleted
                ? emerald
                : isActive
                    ? emeraldLight
                    : const Color(0xFFF3F4F6),
            shape: BoxShape.circle,
            border: isActive
                ? Border.all(color: emerald, width: 2)
                : null,
          ),
          child: Center(
            child: isCompleted
                ? const Icon(Icons.check, color: Colors.white, size: 20)
                : Text(
                    "$stepNumber",
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isActive ? emerald : const Color(0xFF9CA3AF),
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
            color: isCompleted || isActive
                ? emerald
                : const Color(0xFF9CA3AF),
          ),
        ),
      ],
    );
  }
}

class DashedBorderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFD1D5DB)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    const dashWidth = 5.0;
    const dashSpace = 3.0;

    // Draw dashed rectangle
    double startX = 0;
    while (startX < size.width) {
      canvas.drawLine(
        Offset(startX, 0),
        Offset(startX + dashWidth, 0),
        paint,
      );
      startX += dashWidth + dashSpace;
    }

    double startY = 0;
    while (startY < size.height) {
      canvas.drawLine(
        Offset(size.width, startY),
        Offset(size.width, startY + dashWidth),
        paint,
      );
      startY += dashWidth + dashSpace;
    }

    startX = size.width;
    while (startX > 0) {
      canvas.drawLine(
        Offset(startX, size.height),
        Offset(startX - dashWidth, size.height),
        paint,
      );
      startX -= dashWidth + dashSpace;
    }

    startY = size.height;
    while (startY > 0) {
      canvas.drawLine(
        Offset(0, startY),
        Offset(0, startY - dashWidth),
        paint,
      );
      startY -= dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
