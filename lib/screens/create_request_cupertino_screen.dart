import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/auth_service.dart';
import '../services/location_service.dart';
import 'live_offers_screen.dart';

/// Ultra-Sleek, Premium, Clean Request Creation Screen
class CreateRequestCupertinoScreen extends StatefulWidget {
  final String? initialCategory;

  const CreateRequestCupertinoScreen({
    super.key,
    this.initialCategory,
  });

  @override
  State<CreateRequestCupertinoScreen> createState() =>
      _CreateRequestCupertinoScreenState();
}

class _CreateRequestCupertinoScreenState
    extends State<CreateRequestCupertinoScreen> {
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _budgetController = TextEditingController();
  final TextEditingController _vehicleModelController = TextEditingController();
  final TextEditingController _partSpecController = TextEditingController();

  late String _fulfillmentType;
  late String _category;
  bool _isSubmitting = false;

  String? _selectedSubCategory;
  bool _airconPreferred = false;

  final List<Map<String, String>> _allCategories = [
    {'name': 'Parts & Hardware', 'emoji': '🚗'},
    {'name': 'Express Rider',    'emoji': '📦'},
    {'name': 'Rooms & Boarding', 'emoji': '🏠'},
    {'name': 'Food & Catering',  'emoji': '🍽️'},
    {'name': 'Repair & Services','emoji': '🛠️'},
    {'name': 'General Store',    'emoji': '🏪'},
    {'name': 'Community Updates','emoji': '📍'},
    {'name': 'Community Helpers','emoji': '🚨'},
  ];

  @override
  void initState() {
    super.initState();
    _category = widget.initialCategory ?? 'Parts & Hardware';
    _setFulfillmentDefaults(_category);
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _budgetController.dispose();
    _vehicleModelController.dispose();
    _partSpecController.dispose();
    super.dispose();
  }

  void _setFulfillmentDefaults(String cat) {
    switch (cat) {
      case 'Express Rider':
      case 'Food & Catering':
        _fulfillmentType = 'delivery';
        break;
      case 'Rooms & Boarding':
      case 'Repair & Services':
        _fulfillmentType = 'visit';
        break;
      case 'Community Updates':
        _fulfillmentType = 'status';
        break;
      default:
        _fulfillmentType = 'pickup';
        break;
    }
  }

  String _getDescriptionLabel() {
    switch (_category) {
      case 'Parts & Hardware':  return 'What part or material do you need?';
      case 'Rooms & Boarding':  return 'Describe the room you are looking for';
      case 'Express Rider':     return 'What needs to be picked up or delivered?';
      case 'Food & Catering':   return 'What food or catering do you need?';
      case 'Repair & Services': return 'What repair or service do you need?';
      case 'General Store':     return 'What items or supplies do you need?';
      case 'Community Helpers': return 'What assistance or helper service do you need?';
      case 'Community Updates': return 'What do you want to check or verify?';
      default:                  return 'Describe what you need';
    }
  }

  String _getDescriptionSubLabel() {
    switch (_category) {
      case 'Parts & Hardware':  return 'Be specific — include brand, specs, or vehicle model.';
      case 'Rooms & Boarding':  return 'Mention preferred location, move-in date, or budget.';
      case 'Express Rider':     return 'Include pickup address, item size, and urgency.';
      case 'Food & Catering':   return 'Specify quantity, delivery time, or dietary needs.';
      case 'Repair & Services': return 'Describe the problem or service requirement in detail.';
      case 'General Store':     return 'List the items, brands, or retail goods required.';
      case 'Community Helpers': return 'Specify urgent or general assistance needed.';
      case 'Community Updates': return 'Describe the place or situation you want checked.';
      default:                  return 'The more detail, the better your offers will be.';
    }
  }

  String _getDescriptionHint() {
    switch (_category) {
      case 'Parts & Hardware':  return 'e.g. Front brake pads for 2020 Honda Click 125i';
      case 'Rooms & Boarding':  return 'e.g. Aircon bedspace near Robinsons Butuan';
      case 'Express Rider':     return 'e.g. Pick up documents from City Hall, deliver to SM';
      case 'Food & Catering':   return 'e.g. 5 packed lunches for office meeting at 12 PM';
      case 'Repair & Services': return 'e.g. AC cleaning for split type 1.5 HP unit';
      case 'General Store':     return 'e.g. 2 sacks of 25kg Sinandomeng rice';
      case 'Community Helpers': return 'e.g. Heavy lifting assistance for moving furniture';
      case 'Community Updates': return 'e.g. Is Jollibee Montilla open? Line status?';
      default:                  return 'e.g. I need a technician for a leaking pipe';
    }
  }

  List<String> _getSubCategories() {
    switch (_category) {
      case 'Parts & Hardware':
        return ['🚗 Car / Sedan', '🏍️ Motorcycle', '🔋 Battery / Tires', '🛢️ Oil & Fluids', '🚰 Plumbing', '⚡ Electrical', '🪚 Tools'];
      case 'Rooms & Boarding':
        return ['🚪 Private Room', '🛏️ Bedspace', '🏢 Studio Apartment'];
      case 'Express Rider':
        return ['📦 Small Package', '📄 Documents', '🛒 Grocery Run'];
      case 'Food & Catering':
        return ['🍱 Packed Lunches', '🎂 Cakes & Desserts', '🥘 Party Trays', '🥤 Beverages'];
      case 'Repair & Services':
        return ['❄️ AC Cleaning', '🔌 Appliance Repair', '💻 IT Repair', '🚰 Plumbing'];
      case 'General Store':
        return ['🌾 Rice & Grains', '🧼 Cleaning Supplies', '📦 Goods', '✏️ Stationery'];
      case 'Community Helpers':
        return ['💪 Heavy Lifting', '🌱 Yard Cleaning', '🚨 Emergency Aid', '🤝 Volunteer'];
      default:
        return [];
    }
  }

  void _showToast(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.w600,
            fontSize: 13,
            color: Colors.white,
          ),
        ),
        backgroundColor: isError ? const Color(0xFFEF4444) : const Color(0xFF004D40),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _submitRequest() async {
    final description = _descriptionController.text.trim();
    final budgetText = _budgetController.text.trim();
    final budget = double.tryParse(budgetText);

    if (description.isEmpty || budget == null) {
      _showToast('Please enter what you need and a valid budget.', isError: true);
      return;
    }

    Map<String, dynamic> tags = {};
    if (_category == 'Parts & Hardware') {
      if (_vehicleModelController.text.trim().isNotEmpty) {
        tags['vehicle_model'] = _vehicleModelController.text.trim();
        tags['spec_1'] = _vehicleModelController.text.trim();
      }
      if (_partSpecController.text.trim().isNotEmpty) {
        tags['part_spec'] = _partSpecController.text.trim();
        tags['spec_2'] = _partSpecController.text.trim();
      }
    }
    if (_category == 'Rooms & Boarding') {
      tags['aircon_preferred'] = _airconPreferred;
    }

    setState(() => _isSubmitting = true);

    try {
      final pos = await LocationService.getCurrentPosition();
      if (pos != null) {
        tags['lat'] = pos.latitude;
        tags['lng'] = pos.longitude;
      }

      final payload = <String, dynamic>{
        'user_id': AuthService.currentUserId,
        'category': _category,
        'description': description,
        'max_budget': budget,
        'fulfillment_type': _fulfillmentType,
        'status': 'open',
      };

      if (_selectedSubCategory != null) {
        payload['sub_category'] = _selectedSubCategory;
      }
      if (tags.isNotEmpty) {
        payload['tags'] = jsonEncode(tags);
      }

      final response = await Supabase.instance.client
          .from('requests')
          .insert(payload)
          .select()
          .single();

      if (mounted) {
        final requestId = response['id'];
        Navigator.of(context).pop();
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => LiveOffersScreen(requestId: requestId),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        _showToast('Error: ${e.toString()}', isError: true);
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Widget _buildSectionCard({required Widget child, EdgeInsetsGeometry? padding}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: padding ?? const EdgeInsets.all(18),
      child: child,
    );
  }

  Widget _buildSubCategoryChips() {
    final subs = _getSubCategories();
    if (subs.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'SELECT SPECIFIC TYPE',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF64748B),
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8.0,
          runSpacing: 8.0,
          children: subs.map((sub) {
            final isSelected = _selectedSubCategory == sub;
            return GestureDetector(
              onTap: () {
                setState(() {
                  _selectedSubCategory = isSelected ? null : sub;
                });
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFF004D40) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected ? const Color(0xFF004D40) : const Color(0xFFE2E8F0),
                  ),
                ),
                child: Text(
                  sub,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: isSelected ? Colors.white : const Color(0xFF334155),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 18),
      ],
    );
  }

  Widget _buildConditionalFields() {
    if (_category == 'Parts & Hardware') {
      return _buildSectionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'VEHICLE MAKE / MODEL',
              style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w800, color: const Color(0xFF64748B), letterSpacing: 0.8),
            ),
            const SizedBox(height: 6),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: TextField(
                controller: _vehicleModelController,
                style: GoogleFonts.plusJakartaSans(fontSize: 14, color: const Color(0xFF0F172A)),
                decoration: InputDecoration(
                  hintText: 'e.g. 2020 Honda Click 125i / Toyota Vios',
                  hintStyle: GoogleFonts.plusJakartaSans(color: const Color(0xFF94A3B8), fontSize: 13),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: InputBorder.none,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'PLACEMENT / PART CODE',
              style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w800, color: const Color(0xFF64748B), letterSpacing: 0.8),
            ),
            const SizedBox(height: 6),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: TextField(
                controller: _partSpecController,
                style: GoogleFonts.plusJakartaSans(fontSize: 14, color: const Color(0xFF0F172A)),
                decoration: InputDecoration(
                  hintText: 'e.g. Front Right / OEM Part #12345',
                  hintStyle: GoogleFonts.plusJakartaSans(color: const Color(0xFF94A3B8), fontSize: 13),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: InputBorder.none,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (_category == 'Rooms & Boarding') {
      return _buildSectionCard(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE0F2FE),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.ac_unit_rounded, color: Color(0xFF0284C7), size: 18),
                ),
                const SizedBox(width: 12),
                Text(
                  'Aircon Preferred',
                  style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, fontSize: 14, color: const Color(0xFF0F172A)),
                ),
              ],
            ),
            GestureDetector(
              onTap: () => setState(() => _airconPreferred = !_airconPreferred),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 48,
                height: 28,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: _airconPreferred ? const Color(0xFF004D40) : const Color(0xFFCBD5E1),
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: _airconPreferred ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildFulfillmentSelector() {
    final options = [
      {'id': 'pickup',   'label': 'Pickup',   'icon': Icons.storefront_rounded},
      {'id': 'delivery', 'label': 'Delivery', 'icon': Icons.two_wheeler_rounded},
      {'id': 'visit',    'label': 'On-Site',  'icon': Icons.handyman_rounded},
    ];

    return Row(
      children: options.map((opt) {
        final isSelected = _fulfillmentType == opt['id'];
        return Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _fulfillmentType = opt['id'] as String),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFFE6F4F1) : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isSelected ? const Color(0xFF004D40) : const Color(0xFFE2E8F0),
                  width: isSelected ? 1.5 : 1,
                ),
              ),
              child: Column(
                children: [
                  Icon(
                    opt['icon'] as IconData,
                    color: isSelected ? const Color(0xFF004D40) : const Color(0xFF64748B),
                    size: 20,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    opt['label'] as String,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                      color: isSelected ? const Color(0xFF004D40) : const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Stack(
          children: [
            // ── Main Content Layer ──────────────────────────────────────
            SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(20, 72, 20, 100 + viewInsets.bottom),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Headline Header
                  Text(
                    'Send New Ping',
                    style: GoogleFonts.outfit(
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      color: const Color(0xFF0F172A),
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Broadcast to local shops in seconds.',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      color: const Color(0xFF64748B),
                    ),
                  ),

                  const SizedBox(height: 18),

                  // Horizontal Category Bar
                  SizedBox(
                    height: 40,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: _allCategories.length,
                      itemBuilder: (ctx, idx) {
                        final item = _allCategories[idx];
                        final isSelected = _category == item['name'];
                        return GestureDetector(
                          onTap: () {
                            setState(() {
                              _category = item['name']!;
                              _selectedSubCategory = null;
                              _setFulfillmentDefaults(_category);
                            });
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: const EdgeInsets.only(right: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: isSelected ? const Color(0xFF004D40) : Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: isSelected ? const Color(0xFF004D40) : const Color(0xFFE2E8F0),
                              ),
                              boxShadow: isSelected
                                  ? [
                                      BoxShadow(
                                        color: const Color(0xFF004D40).withValues(alpha: 0.25),
                                        blurRadius: 8,
                                        offset: const Offset(0, 3),
                                      )
                                    ]
                                  : [],
                            ),
                            child: Row(
                              children: [
                                Text(item['emoji']!, style: const TextStyle(fontSize: 14)),
                                const SizedBox(width: 6),
                                Text(
                                  item['name']!,
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 12,
                                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                                    color: isSelected ? Colors.white : const Color(0xFF334155),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Subcategories if applicable
                  _buildSubCategoryChips(),

                  // Conditional Fields
                  _buildConditionalFields(),

                  if (_category == 'Parts & Hardware' || _category == 'Rooms & Boarding')
                    const SizedBox(height: 16),

                  // ── Card 1: Description Input ────────────────────────
                  _buildSectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _getDescriptionLabel(),
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _getDescriptionSubLabel(),
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            color: const Color(0xFF64748B),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: TextField(
                            controller: _descriptionController,
                            style: GoogleFonts.plusJakartaSans(fontSize: 14, color: const Color(0xFF0F172A)),
                            decoration: InputDecoration(
                              hintText: _getDescriptionHint(),
                              hintStyle: GoogleFonts.plusJakartaSans(color: const Color(0xFF94A3B8), fontSize: 13),
                              contentPadding: const EdgeInsets.all(14),
                              border: InputBorder.none,
                            ),
                            maxLines: 3,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // ── Card 2: Budget & Fulfillment ─────────────────────
                  _buildSectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'MAX BUDGET (₱)',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF64748B),
                            letterSpacing: 0.8,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: TextField(
                            controller: _budgetController,
                            keyboardType: TextInputType.number,
                            style: GoogleFonts.outfit(
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                              color: const Color(0xFF004D40),
                            ),
                            decoration: InputDecoration(
                              hintText: '0.00',
                              hintStyle: GoogleFonts.outfit(color: const Color(0xFFCBD5E1), fontSize: 24),
                              prefixIcon: Padding(
                                padding: const EdgeInsets.only(left: 16.0, right: 8.0, top: 12.0),
                                child: Text(
                                  '₱',
                                  style: GoogleFonts.outfit(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w900,
                                    color: const Color(0xFF004D40),
                                  ),
                                ),
                              ),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              border: InputBorder.none,
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          'FULFILLMENT METHOD',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF64748B),
                            letterSpacing: 0.8,
                          ),
                        ),
                        const SizedBox(height: 10),
                        _buildFulfillmentSelector(),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ── Clean Header Bar ─────────────────────────────────────────
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.90),
                  border: const Border(
                    bottom: BorderSide(color: Color(0xFFE2E8F0), width: 1),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: const Icon(Icons.close_rounded, color: Color(0xFF0F172A), size: 20),
                      ),
                    ),
                    Row(
                      children: [
                        Text(
                          'Ping',
                          style: GoogleFonts.outfit(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: const Color(0xFF004D40),
                          ),
                        ),
                        Container(
                          margin: const EdgeInsets.only(left: 3, top: 6),
                          width: 5,
                          height: 5,
                          decoration: const BoxDecoration(
                            color: Color(0xFFE28743),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 36), // Balance title
                  ],
                ),
              ),
            ),

            // ── Clean Floating Submit Bar ────────────────────────────────
            Positioned(
              bottom: 16 + viewInsets.bottom,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.10),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: GestureDetector(
                  onTap: _isSubmitting ? null : _submitRequest,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    height: 50,
                    decoration: BoxDecoration(
                      color: const Color(0xFF004D40),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    alignment: Alignment.center,
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.5,
                            ),
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'Send Ping Now',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 18),
                            ],
                          ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
