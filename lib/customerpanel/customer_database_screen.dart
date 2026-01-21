import 'package:flutter/material.dart';
import 'package:weighbridgemanagement/widgets/main_layout.dart';
import 'package:weighbridgemanagement/customerpanel/add_customer_dialog.dart';

class CustomerDatabaseScreen extends StatefulWidget {
  const CustomerDatabaseScreen({super.key});

  @override
  State<CustomerDatabaseScreen> createState() => _CustomerDatabaseScreenState();
}

class _CustomerDatabaseScreenState extends State<CustomerDatabaseScreen> {
  // Green/Emerald color used throughout the app
  static const Color emerald = Color(0xFF059669);

  final TextEditingController _searchController = TextEditingController();
  String _selectedFilter = 'All';
  int _currentPage = 1;
  final int _totalPages = 8;
  final int _totalResults = 48;

  final List<Map<String, dynamic>> customers = [
    {
      'srNo': '01',
      'initials': 'AL',
      'name': 'Acme Logistics',
      'color': const Color(0xFF3B82F6),
      'phone': '+1 (555) 012-3456',
      'address': '123 Industrial Park, Sector 4, Spr...',
      'totalVisits': 142,
      'lastVisit': 'Oct 24, 2023',
    },
    {
      'srNo': '02',
      'initials': 'GC',
      'name': 'Globex Corp',
      'color': const Color(0xFF10B981),
      'phone': '+1 (555) 987-6543',
      'address': '88 Main St, District 9, Metropolis',
      'totalVisits': 89,
      'lastVisit': 'Oct 22, 2023',
    },
    {
      'srNo': '03',
      'initials': 'SC',
      'name': 'Soylent Corp',
      'color': const Color(0xFF6366F1),
      'phone': '+1 (555) 555-0199',
      'address': '45 Food Processing Way, City C...',
      'totalVisits': 210,
      'lastVisit': 'Oct 20, 2023',
    },
    {
      'srNo': '04',
      'initials': 'IT',
      'name': 'Initech',
      'color': const Color(0xFFF59E0B),
      'phone': '+1 (555) 111-2222',
      'address': '101 Software Blvd, Silicon Valley',
      'totalVisits': 15,
      'lastVisit': 'Oct 18, 2023',
    },
    {
      'srNo': '05',
      'initials': 'UC',
      'name': 'Umbrella Corp',
      'color': const Color(0xFFEF4444),
      'phone': '+1 (555) 666-7777',
      'address': 'Raccoon City Underground',
      'totalVisits': 350,
      'lastVisit': 'Oct 15, 2023',
    },
    {
      'srNo': '06',
      'initials': 'SI',
      'name': 'Stark Industries',
      'color': const Color(0xFF8B5CF6),
      'phone': '+1 (555) 300-3000',
      'address': '10880 Malibu Point',
      'totalVisits': 5,
      'lastVisit': 'Oct 10, 2023',
    },
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MainLayout(
      activeNav: "Customers",
      child: Container(
        color: Colors.white,
        child: Column(
          children: [
            // Page Header
            Container(
              padding: const EdgeInsets.fromLTRB(32, 24, 32, 20),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title Section
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Customer Database",
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF111827),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          "Manage client records, view history, and update details.",
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Add Customer Button - GREEN
                  ElevatedButton.icon(
                    onPressed: () {
                      _showAddCustomerDialog();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: emerald,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      elevation: 0,
                    ),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text(
                      "Add Customer",
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                  ),
                ],
              ),
            ),

            // Search and Filter Row
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Row(
                children: [
                  // Search Bar
                  SizedBox(
                    width: 320,
                    height: 42,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                      ),
                      child: TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: "Search customers by name, ID or phone...",
                          hintStyle: TextStyle(
                            color: Colors.grey.shade400,
                            fontSize: 13,
                          ),
                          prefixIcon: Icon(
                            Icons.search,
                            color: Colors.grey.shade400,
                            size: 18,
                          ),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                        ),
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ),
                  const Spacer(),
                  // Filter Dropdown
                  Container(
                    height: 42,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedFilter,
                        icon: const Icon(Icons.keyboard_arrow_down, size: 18),
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade700,
                        ),
                        items: ['All', 'Active', 'Inactive', 'New']
                            .map((filter) => DropdownMenuItem(
                                  value: filter,
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.filter_list,
                                        size: 16,
                                        color: Colors.grey.shade500,
                                      ),
                                      const SizedBox(width: 8),
                                      Text("Filter: $filter"),
                                    ],
                                  ),
                                ))
                            .toList(),
                        onChanged: (value) {
                          setState(() {
                            _selectedFilter = value!;
                          });
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Table
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  children: [
                    // Table Header
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        border: Border(
                          top: BorderSide(color: Colors.grey.shade200),
                          bottom: BorderSide(color: Colors.grey.shade200),
                        ),
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 50,
                            child: Text(
                              "SR\nNO",
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey.shade500,
                                height: 1.3,
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 3,
                            child: Text(
                              "NAME",
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey.shade500,
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              "PHONE NUMBER",
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey.shade500,
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 4,
                            child: Text(
                              "ADDRESS",
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey.shade500,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 100,
                            child: Text(
                              "TOTAL VISITS",
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey.shade500,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 100,
                            child: Text(
                              "LAST VISIT",
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey.shade500,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 110,
                            child: Text(
                              "ACTIONS",
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey.shade500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Table Rows
                    Expanded(
                      child: ListView.builder(
                        itemCount: customers.length,
                        itemBuilder: (context, index) {
                          return _buildCustomerRow(customers[index]);
                        },
                      ),
                    ),

                    // Pagination
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                      decoration: BoxDecoration(
                        border: Border(
                          top: BorderSide(color: Colors.grey.shade200),
                        ),
                      ),
                      child: Row(
                        children: [
                          RichText(
                            text: TextSpan(
                              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                              children: [
                                const TextSpan(text: "Showing "),
                                const TextSpan(
                                  text: "1",
                                  style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF111827)),
                                ),
                                const TextSpan(text: " to "),
                                const TextSpan(
                                  text: "6",
                                  style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF111827)),
                                ),
                                const TextSpan(text: " of "),
                                TextSpan(
                                  text: "$_totalResults",
                                  style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF111827)),
                                ),
                                const TextSpan(text: " results"),
                              ],
                            ),
                          ),
                          const Spacer(),
                          _buildPagination(),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomerRow(Map<String, dynamic> customer) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade100),
        ),
      ),
      child: Row(
        children: [
          // SR NO
          SizedBox(
            width: 50,
            child: Text(
              customer['srNo'],
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade600,
              ),
            ),
          ),
          // NAME with Avatar
          Expanded(
            flex: 3,
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: (customer['color'] as Color).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text(
                      customer['initials'],
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: customer['color'],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    customer['name'],
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF111827),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          // PHONE NUMBER
          Expanded(
            flex: 2,
            child: Text(
              customer['phone'],
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade600,
              ),
            ),
          ),
          // ADDRESS
          Expanded(
            flex: 4,
            child: Text(
              customer['address'],
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // TOTAL VISITS
          SizedBox(
            width: 100,
            child: Text(
              customer['totalVisits'].toString(),
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Color(0xFF111827),
              ),
            ),
          ),
          // LAST VISIT
          SizedBox(
            width: 100,
            child: Text(
              customer['lastVisit'],
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade600,
              ),
            ),
          ),
          // ACTIONS - Using green for view button
          SizedBox(
            width: 110,
            child: Row(
              children: [
                _buildActionButton(
                  icon: Icons.visibility_outlined,
                  color: emerald,
                  onTap: () {
                    Navigator.pushReplacementNamed(context, '/customerProfile');
                  },
                ),
                const SizedBox(width: 8),
                _buildActionButton(
                  icon: Icons.edit_outlined,
                  color: const Color(0xFFF59E0B),
                  onTap: () {},
                ),
                const SizedBox(width: 8),
                _buildActionButton(
                  icon: Icons.delete_outline,
                  color: const Color(0xFFEF4444),
                  onTap: () {},
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(
          icon,
          size: 15,
          color: color,
        ),
      ),
    );
  }

  Widget _buildPagination() {
    return Row(
      children: [
        // Previous
        _buildPageButton(
          child: Icon(Icons.chevron_left, size: 18, color: Colors.grey.shade600),
          isEnabled: _currentPage > 1,
          onTap: () {
            if (_currentPage > 1) {
              setState(() => _currentPage--);
            }
          },
        ),
        const SizedBox(width: 4),
        // Page Numbers
        _buildPageNumber(1),
        _buildPageNumber(2),
        _buildPageNumber(3),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            "...",
            style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
          ),
        ),
        _buildPageNumber(_totalPages),
        const SizedBox(width: 4),
        // Next
        _buildPageButton(
          child: Icon(Icons.chevron_right, size: 18, color: Colors.grey.shade600),
          isEnabled: _currentPage < _totalPages,
          onTap: () {
            if (_currentPage < _totalPages) {
              setState(() => _currentPage++);
            }
          },
        ),
      ],
    );
  }

  Widget _buildPageButton({
    required Widget child,
    required bool isEnabled,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: isEnabled ? onTap : null,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
        ),
        child: Center(child: child),
      ),
    );
  }

  Widget _buildPageNumber(int page) {
    final isActive = _currentPage == page;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: InkWell(
        onTap: () {
          setState(() => _currentPage = page);
        },
        borderRadius: BorderRadius.circular(6),
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: isActive ? emerald : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Center(
            child: Text(
              page.toString(),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: isActive ? Colors.white : Colors.grey.shade700,
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showAddCustomerDialog() {
    showAddCustomerDialog(context);
  }
}
