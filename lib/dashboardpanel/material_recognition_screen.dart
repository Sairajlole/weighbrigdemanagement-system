import 'package:flutter/material.dart';

class MaterialRecognitionScreen extends StatefulWidget {
  const MaterialRecognitionScreen({super.key});

  @override
  State<MaterialRecognitionScreen> createState() => _MaterialRecognitionScreenState();
}

class _MaterialRecognitionScreenState extends State<MaterialRecognitionScreen> {
  static const Color emerald = Color(0xFF059669);
  static const Color emeraldLight = Color(0xFFD1FAE5);
  
  String _selectedMaterial = "Cotton Bales";
  final List<String> _materials = [
    "Cotton Bales",
    "Steel Rods",
    "Cement Bags",
    "Sand",
    "Gravel",
    "Coal",
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          // Dark Header Bar
          _buildHeader(),
          
          // Main Content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Breadcrumb
                  _buildBreadcrumb(),
                  const SizedBox(height: 16),
                  
                  // Title Row
                  _buildTitleRow(),
                  const SizedBox(height: 24),
                  
                  // Main Content Row
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Camera Feed
                      Expanded(
                        flex: 6,
                        child: _buildCameraFeed(),
                      ),
                      const SizedBox(width: 24),
                      // AI Analysis Panel
                      SizedBox(
                        width: 280,
                        child: _buildAIAnalysisPanel(),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      color: const Color(0xFF1F2937),
      child: Row(
        children: [
          // Logo
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: emerald,
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(Icons.scale, color: Colors.white, size: 16),
          ),
          const SizedBox(width: 10),
          const Text(
            "Weighbridge Management",
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 48),
          
          // Nav Tabs
          _navTab("Dashboard", false),
          _navTab("Weighing", true),
          _navTab("Reports", false),
          _navTab("Settings", false),
          
          const Spacer(),
          
          // Icons
          const Icon(Icons.notifications_none, color: Colors.white, size: 22),
          const SizedBox(width: 16),
          Container(
            width: 32,
            height: 32,
            decoration: const BoxDecoration(
              color: emerald,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.person, color: Colors.white, size: 18),
          ),
        ],
      ),
    );
  }

  Widget _navTab(String label, bool isActive) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: isActive ? emerald : Colors.grey.shade400,
        ),
      ),
    );
  }

  Widget _buildBreadcrumb() {
    return Row(
      children: [
        Text("Home", style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
        Text("  /  ", style: TextStyle(fontSize: 13, color: Colors.grey.shade400)),
        Text("Weighbridge #04", style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
        Text("  /  ", style: TextStyle(fontSize: 13, color: Colors.grey.shade400)),
        const Text(
          "Material Recognition",
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: emerald),
        ),
      ],
    );
  }

  Widget _buildTitleRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Material Recognition",
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1F2937),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.auto_awesome, size: 14, color: Colors.grey.shade500),
                const SizedBox(width: 6),
                Text(
                  "AI Assisted Verification",
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                ),
              ],
            ),
          ],
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: emeraldLight,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(color: emerald, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              const Text(
                "System Online",
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: emerald),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCameraFeed() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Camera Header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                const Icon(Icons.videocam, size: 18, color: Color(0xFF374151)),
                const SizedBox(width: 8),
                const Text(
                  "Top Camera #04 Feed",
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1F2937),
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    "REC",
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  "• 1980p • 30fps",
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Camera View
        Container(
          height: 420,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: const Color(0xFF0A1628),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              children: [
                // Dark background with subtle pattern
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        const Color(0xFF1A2A3A),
                        const Color(0xFF0A1628),
                      ],
                    ),
                  ),
                ),

                // Simulated cargo/cotton bales area (light colored)
                Positioned(
                  left: 50,
                  top: 80,
                  child: Container(
                    width: 340,
                    height: 240,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Colors.white.withOpacity(0.15),
                          Colors.white.withOpacity(0.08),
                        ],
                      ),
                    ),
                    child: GridView.builder(
                      physics: const NeverScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(8),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 6,
                        crossAxisSpacing: 4,
                        mainAxisSpacing: 4,
                      ),
                      itemCount: 30,
                      itemBuilder: (context, index) {
                        return Container(
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        );
                      },
                    ),
                  ),
                ),

                // Detection Box with Corners
                Positioned(
                  left: 45,
                  top: 75,
                  child: SizedBox(
                    width: 350,
                    height: 250,
                    child: CustomPaint(
                      painter: _DetectionBoxPainter(emerald),
                    ),
                  ),
                ),

                // Object Detected Label
                Positioned(
                  left: 50,
                  top: 55,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: emerald,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.auto_awesome, size: 12, color: Colors.white),
                        SizedBox(width: 5),
                        Text(
                          "Object Detected",
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // LIVE Badge
                Positioned(
                  top: 16,
                  right: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: emerald,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      "LIVE",
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),

                // Timestamp
                Positioned(
                  bottom: 16,
                  left: 16,
                  child: Text(
                    "2023-10-24 14:32:05 UTC",
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withOpacity(0.6),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAIAnalysisPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: emerald,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.auto_awesome, size: 16, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "AI Analysis Result",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1F2937),
                  ),
                ),
                Text(
                  "Review the detected material below.",
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 24),

        // Detected Material Label
        Text(
          "DETECTED MATERIAL",
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade500,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 12),

        // Material Card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFF9FAFB),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.inventory_2, size: 20, color: Color(0xFF374151)),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Text(
                  "Cotton Bales",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1F2937),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: emerald,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check, size: 16, color: Colors.white),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Confidence Score
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              "Confidence Score",
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
            const Text(
              "87%",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: emerald),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: 0.87,
            backgroundColor: const Color(0xFFE5E7EB),
            valueColor: const AlwaysStoppedAnimation<Color>(emerald),
            minHeight: 8,
          ),
        ),
        const SizedBox(height: 24),

        // Correction Needed
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              "Correction Needed?",
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
            GestureDetector(
              onTap: () {},
              child: const Text(
                "Report Issue",
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: emerald),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Dropdown
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedMaterial,
              isExpanded: true,
              icon: const Icon(Icons.keyboard_arrow_down),
              items: _materials.map((String material) {
                return DropdownMenuItem<String>(
                  value: material,
                  child: Row(
                    children: [
                      const Icon(Icons.inventory_2_outlined, size: 18, color: Color(0xFF6B7280)),
                      const SizedBox(width: 10),
                      Text(material, style: const TextStyle(fontSize: 14)),
                    ],
                  ),
                );
              }).toList(),
              onChanged: (String? newValue) {
                setState(() {
                  _selectedMaterial = newValue!;
                });
              },
            ),
          ),
        ),
        const SizedBox(height: 20),

        // Info Box
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFF0F9FF),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFBAE6FD)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info, size: 16, color: Colors.blue.shade600),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  "AI will auto-select the best match based on historical data. Please verify visual accuracy before confirming.",
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.blue.shade700,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Confirm Button
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () {
              Navigator.pushReplacementNamed(context, '/customerIdentification');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: emerald,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              elevation: 0,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Text(
                  "Confirm Material",
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
                SizedBox(width: 8),
                Icon(Icons.arrow_forward, size: 18),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _DetectionBoxPainter extends CustomPainter {
  final Color color;
  
  _DetectionBoxPainter(this.color);
  
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    final cornerLength = 30.0;

    // Top-left corner
    canvas.drawLine(const Offset(0, 0), Offset(cornerLength, 0), paint);
    canvas.drawLine(const Offset(0, 0), Offset(0, cornerLength), paint);

    // Top-right corner
    canvas.drawLine(Offset(size.width, 0), Offset(size.width - cornerLength, 0), paint);
    canvas.drawLine(Offset(size.width, 0), Offset(size.width, cornerLength), paint);

    // Bottom-left corner
    canvas.drawLine(Offset(0, size.height), Offset(cornerLength, size.height), paint);
    canvas.drawLine(Offset(0, size.height), Offset(0, size.height - cornerLength), paint);

    // Bottom-right corner
    canvas.drawLine(Offset(size.width, size.height), Offset(size.width - cornerLength, size.height), paint);
    canvas.drawLine(Offset(size.width, size.height), Offset(size.width, size.height - cornerLength), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
