import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/auth_service.dart';
import '../services/location_service.dart';

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
    {'name': 'Community Check',  'emoji': '📍'},
    {'name': 'Community Helpers','emoji': '🚨'},
  ];

  @override
  void initState() {
    super.initState();
    _category = widget.initialCategory ?? 'Parts & Hardware';
    if (_category == 'Community Updates') {
      _category = 'Community Check';
    }
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
      case 'Community Check':
        _fulfillmentType = 'status';
        break;
      case 'Express Rider':
      case 'Food & Catering':
        _fulfillmentType = 'delivery';
        break;
      case 'Rooms & Boarding':
      case 'Repair & Services':
        _fulfillmentType = 'visit';
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
      case 'Community Check':   return 'What place or situation do you want to check?';
      default:                  return 'Describe what you need';
    }
  }

  String _getDescriptionSubLabel() {
    switch (_category) {
      case 'Parts & Hardware':  return 'Be specific — include brand, specs, or vehicle model.';
      case 'Rooms & Boarding':  return 'Mention preferred location, move-in date, or budget.';
      case 'Express Rider':     return 'Specify pickup location, dropoff point, and weight/item.';
      case 'Food & Catering':   return 'Mention quantity, dietary restrictions, or delivery time.';
      case 'Repair & Services': return 'Describe the issue or equipment needing service.';
      case 'General Store':     return 'List the items or supplies you are looking for.';
      case 'Community Helpers': return 'Describe the task or emergency assistance needed.';
      case 'Community Check':   return 'Describe the place, store, or road condition to check.';
      default:                  return 'Provide as many details as possible for better offers.';
    }
  }

  String _getDescriptionHint() {
    switch (_category) {
      case 'Parts & Hardware':  return 'e.g. Brake pads for 2018 Toyota Vios';
      case 'Rooms & Boarding':  return 'e.g. Aircon studio room near CSU, budget 5k';
      case 'Express Rider':     return 'e.g. Pick up document from Capitol to Montilla';
      case 'Food & Catering':   return 'e.g. 20 pax packed lunch for seminar tomorrow';
      case 'Repair & Services': return 'e.g. Split-type AC cleaning in Libertad';
      case 'General Store':     return 'e.g. 5 bags 25kg Sinandomeng rice';
      case 'Community Helpers': return 'e.g. Need 2 helpers to carry furniture';
      case 'Community Check':   return 'e.g. Is Jollibee Montilla open right now? Road flood status?';
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
      case 'Community Check':
        return ['📍 Store Status', '🌊 Flood & Road Check', '🚦 Traffic Status', '🏬 Opening Hours'];
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
      final pos = await LocationService.getCurrentPosition(forceRefresh: true);
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

      await Supabase.instance.client
          .from('requests')
          .insert(payload);

      if (mounted) {
        _showToast('⚡ Ping broadcasted to nearby shops!');
        Navigator.of(context).pop(true);
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

    return _buildSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'SELECT SPECIFIC TYPE',
            style: GoogleFonts.outfit(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF94A3B8),
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: subs.map((sub) {
              final isSelected = _selectedSubCategory == sub;
              return GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedSubCategory = isSelected ? null : sub;
                  });
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected ? const Color(0xFF004D40) : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isSelected ? const Color(0xFF004D40) : const Color(0xFFE2E8F0),
                    ),
                  ),
                  child: Text(
                    sub,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                      color: isSelected ? Colors.white : const Color(0xFF334155),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildDynamicSpecFields() {
    if (_category == 'Parts & Hardware') {
      return _buildSectionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'SPECIFICATIONS & VEHICLE MODEL',
              style: GoogleFonts.outfit(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF94A3B8),
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Vehicle Model / Make (Optional)',
              style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w700, color: const Color(0xFF334155)),
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
                  hintText: 'e.g. Toyota Vios 2018 / Honda Click 125i',
                  hintStyle: GoogleFonts.plusJakartaSans(color: const Color(0xFF94A3B8), fontSize: 13),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: InputBorder.none,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Part Specs / Side / Position (Optional)',
              style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w700, color: const Color(0xFF334155)),
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
    List<Map<String, dynamic>> options;

    switch (_category) {
      case 'Community Check':
        options = [
          {'id': 'status', 'label': 'Real-Time Status Check', 'icon': Icons.pin_drop_rounded},
        ];
        break;
      case 'Express Rider':
      case 'Food & Catering':
        options = [
          {'id': 'delivery', 'label': 'Delivery', 'icon': Icons.two_wheeler_rounded},
          {'id': 'pickup',   'label': 'Pickup',   'icon': Icons.storefront_rounded},
        ];
        break;
      case 'Rooms & Boarding':
      case 'Repair & Services':
        options = [
          {'id': 'visit',    'label': 'On-Site Visit', 'icon': Icons.handyman_rounded},
          {'id': 'pickup',   'label': 'Store / Office', 'icon': Icons.storefront_rounded},
        ];
        break;
      default: // Parts & Hardware, General Store, etc.
        options = [
          {'id': 'pickup',   'label': 'Store Pickup', 'icon': Icons.storefront_rounded},
          {'id': 'delivery', 'label': 'Delivery',     'icon': Icons.two_wheeler_rounded},
          {'id': 'visit',    'label': 'On-Site',       'icon': Icons.handyman_rounded},
        ];
        break;
    }

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
                color: isSelected ? const Color(0xFFE2F0F0) : const Color(0xFFF8FAFC),
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
                    textAlign: TextAlign.center,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
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
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF0F172A), size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [Color(0xFF004D40), Color(0xFF10B981)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ).createShader(bounds),
          child: Text(
            'Broadcast a Ping',
            style: GoogleFonts.outfit(
              fontWeight: FontWeight.w900,
              fontSize: 22,
              letterSpacing: -0.5,
              color: Colors.white,
            ),
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: const Color(0xFFE2E8F0), height: 1),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Category Selector Row ─────────────────────────────────
            Text(
              'SELECT CATEGORY',
              style: GoogleFonts.outfit(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF94A3B8),
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 44,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _allCategories.length,
                itemBuilder: (context, index) {
                  final cat = _allCategories[index];
                  final isSelected = _category == cat['name'];
                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        _category = cat['name']!;
                        _selectedSubCategory = null;
                        _setFulfillmentDefaults(_category);
                      });
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: isSelected ? const Color(0xFF004D40) : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected ? const Color(0xFF004D40) : const Color(0xFFE2E8F0),
                        ),
                      ),
                      child: Row(
                        children: [
                          Text(cat['emoji']!, style: const TextStyle(fontSize: 14)),
                          const SizedBox(width: 6),
                          Text(
                            cat['name']!,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
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

            const SizedBox(height: 16),

            // ── Sub-Category Chips (if available) ──────────────────────
            _buildSubCategoryChips(),

            const SizedBox(height: 16),

            // ── Dynamic Spec Fields (Vehicle / Aircon) ───────────────
            _buildDynamicSpecFields(),

            const SizedBox(height: 16),

            // ── Description Input ─────────────────────────────────────
            _buildSectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _getDescriptionLabel().toUpperCase(),
                    style: GoogleFonts.outfit(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF94A3B8),
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _getDescriptionSubLabel(),
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      color: const Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: TextField(
                      controller: _descriptionController,
                      maxLines: 4,
                      style: GoogleFonts.plusJakartaSans(fontSize: 14, color: const Color(0xFF0F172A)),
                      decoration: InputDecoration(
                        hintText: _getDescriptionHint(),
                        hintStyle: GoogleFonts.plusJakartaSans(color: const Color(0xFF94A3B8), fontSize: 13),
                        contentPadding: const EdgeInsets.all(14),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ── Fulfillment Selector ─────────────────────────────────
            _buildSectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'FULFILLMENT METHOD',
                    style: GoogleFonts.outfit(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF94A3B8),
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildFulfillmentSelector(),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ── Budget / Spotter Tip Input ─────────────────────────────
            _buildSectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _category == 'Community Check' ? 'TIP FOR SPOTTER (₱)' : 'MAXIMUM BUDGET (₱)',
                    style: GoogleFonts.outfit(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF94A3B8),
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _category == 'Community Check'
                        ? 'Offer a tip amount for the community spotter who checks this place.'
                        : 'Set your maximum expected budget for this request.',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      color: const Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: TextField(
                      controller: _budgetController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.w800, color: const Color(0xFF004D40)),
                      decoration: InputDecoration(
                        prefixIcon: Icon(
                          _category == 'Community Check' ? Icons.volunteer_activism_rounded : Icons.payments_outlined,
                          color: const Color(0xFF004D40),
                          size: 20,
                        ),
                        hintText: '0.00',
                        hintStyle: GoogleFonts.outfit(color: const Color(0xFF94A3B8), fontSize: 20, fontWeight: FontWeight.w800),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 28),

            // ── Submit Action Button ─────────────────────────────────
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _submitRequest,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF004D40),
                  foregroundColor: Colors.white,
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.bolt_rounded, size: 22, color: Color(0xFFFF8C42)),
                          const SizedBox(width: 8),
                          Text(
                            'Broadcast Ping Now',
                            style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: -0.2),
                          ),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
