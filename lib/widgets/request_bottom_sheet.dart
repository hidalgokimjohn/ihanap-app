import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/auth_service.dart';
import '../services/location_service.dart';
import 'premium_button.dart';

class RequestBottomSheet extends StatefulWidget {
  final String? initialCategory;
  const RequestBottomSheet({super.key, this.initialCategory});

  @override
  State<RequestBottomSheet> createState() => _RequestBottomSheetState();
}

class _RequestBottomSheetState extends State<RequestBottomSheet> {
  final _descriptionController = TextEditingController();
  final _budgetController = TextEditingController();
  final _vehicleModelController = TextEditingController();
  final _partSpecController = TextEditingController();
  
  late String _fulfillmentType;
  late String _category;
  bool _isSubmitting = false;

  String? _selectedSubCategory;
  bool _airconPreferred = false;
  String _urgencyLevel = 'normal';

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
    _setFulfillmentDefaults(_category);
  }

  void _setFulfillmentDefaults(String cat) {
    _urgencyLevel = 'normal';
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
      case 'Community Helpers':
        _fulfillmentType = 'onsite';
        break;
      default:
        _fulfillmentType = 'pickup';
        break;
    }
  }

  String _getFulfillmentLabel() {
    switch (_category) {
      case 'Community Helpers': return 'Where Do You Need Help?';
      default:                  return 'Fulfillment Method';
    }
  }

  String _getDescriptionLabel() {
    switch (_category) {
      case 'Parts & Hardware':  return '🔍 What part or material do you need?';
      case 'Rooms & Boarding':  return '🏠 Describe the room you are looking for';
      case 'Express Rider':     return '📦 What needs to be picked up or delivered?';
      case 'Food & Catering':   return '🍱 What food or catering do you need?';
      case 'Repair & Services': return '🛠️ What repair or service do you need?';
      case 'General Store':     return '🏪 What items or supplies do you need?';
      case 'Community Helpers': return '🚨 What assistance or helper service do you need?';
      case 'Community Updates': return '📍 What do you want to check or verify?';
      default:                  return '💬 Describe what you need';
    }
  }

  String _getDescriptionSubLabel() {
    switch (_category) {
      case 'Parts & Hardware':  return 'Be specific — include brand, specs, or vehicle model.';
      case 'Rooms & Boarding':  return 'Mention preferred location, move-in date, or budget range.';
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

  Future<void> _submitRequest() async {
    final description = _descriptionController.text.trim();
    final budgetText = _budgetController.text.trim();
    final budget = double.tryParse(budgetText);

    if (description.isEmpty || budget == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please enter what you need and a valid budget.'),
          backgroundColor: const Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
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
    if (_category == 'Community Helpers') {
      tags['urgency_level'] = _urgencyLevel;
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

      await Supabase.instance.client
          .from('requests')
          .insert(payload);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.bolt_rounded, color: Colors.white),
                SizedBox(width: 8),
                Text('⚡ Ping broadcasted to nearby shops!'),
              ],
            ),
            backgroundColor: Color(0xFF004D40),
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Widget _buildGlassCard({required Widget child, EdgeInsetsGeometry? padding}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.15),
          width: 1,
        ),
      ),
      padding: padding ?? const EdgeInsets.all(16),
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
          'Specific Sub-Category',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF94A3B8),
            letterSpacing: 0.3,
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
                  color: isSelected
                      ? const Color(0xFFE28743)
                      : Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected
                        ? const Color(0xFFE28743)
                        : Colors.white.withValues(alpha: 0.12),
                  ),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: const Color(0xFFE28743).withValues(alpha: 0.35),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          )
                        ]
                      : [],
                ),
                child: Text(
                  sub,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: isSelected ? Colors.white : const Color(0xFFCBD5E1),
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
      return _buildGlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Vehicle Make / Model (Optional)',
              style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w700, color: const Color(0xFF94A3B8)),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _vehicleModelController,
              style: GoogleFonts.plusJakartaSans(fontSize: 14, color: Colors.white),
              decoration: InputDecoration(
                hintText: 'e.g. 2020 Honda Click 125i / Toyota Vios',
                hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.35)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.05),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Placement / Part Code (Optional)',
              style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w700, color: const Color(0xFF94A3B8)),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _partSpecController,
              style: GoogleFonts.plusJakartaSans(fontSize: 14, color: Colors.white),
              decoration: InputDecoration(
                hintText: 'e.g. Front Right / OEM Part #12345',
                hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.35)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.05),
              ),
            ),
          ],
        ),
      );
    }

    if (_category == 'Rooms & Boarding') {
      return _buildGlassCard(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                const Icon(Icons.ac_unit, color: Color(0xFF38BDF8), size: 20),
                const SizedBox(width: 10),
                Text(
                  'Aircon Preferred',
                  style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, fontSize: 14, color: Colors.white),
                ),
              ],
            ),
            Switch(
              value: _airconPreferred,
              onChanged: (val) => setState(() => _airconPreferred = val),
              activeColor: const Color(0xFF10B981),
              activeTrackColor: const Color(0xFF10B981).withValues(alpha: 0.3),
            ),
          ],
        ),
      );
    }

    if (_category == 'Community Helpers') {
      const urgencyOptions = [
        {'id': 'normal',    'label': 'Not Urgent',  'emoji': '🟢', 'color': 0xFF10B981},
        {'id': 'urgent',    'label': 'Urgent',       'emoji': '🟡', 'color': 0xFFF59E0B},
        {'id': 'emergency', 'label': 'Emergency',    'emoji': '🔴', 'color': 0xFFEF4444},
      ];
      return _buildGlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Urgency Level',
              style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w700, color: const Color(0xFF94A3B8), letterSpacing: 0.3),
            ),
            const SizedBox(height: 10),
            Row(
              children: urgencyOptions.map((opt) {
                final isSelected = _urgencyLevel == opt['id'];
                final color = Color(opt['color'] as int);
                return Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _urgencyLevel = opt['id'] as String),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: isSelected ? color.withValues(alpha: 0.18) : Colors.white.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected ? color : Colors.white.withValues(alpha: 0.1),
                          width: isSelected ? 1.5 : 1,
                        ),
                      ),
                      child: Column(
                        children: [
                          Text(opt['emoji'] as String, style: const TextStyle(fontSize: 16)),
                          const SizedBox(height: 4),
                          Text(
                            opt['label'] as String,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 11,
                              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                              color: isSelected ? color : const Color(0xFF94A3B8),
                            ),
                          ),
                        ],
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

    return const SizedBox.shrink();
  }

  Widget _buildFulfillmentSelector() {
    final options = _category == 'Community Helpers'
        ? [
            {'id': 'onsite',  'label': 'Come to Me',   'icon': Icons.home_rounded},
            {'id': 'go_to',   'label': 'At a Place',   'icon': Icons.location_on_rounded},
            {'id': 'remote',  'label': 'Remote Help',  'icon': Icons.phone_in_talk_rounded},
          ]
        : [
            {'id': 'pickup',   'label': 'Pickup',   'icon': Icons.storefront},
            {'id': 'delivery', 'label': 'Delivery', 'icon': Icons.two_wheeler},
            {'id': 'visit',    'label': 'On-Site',  'icon': Icons.home_repair_service},
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
                color: isSelected
                    ? const Color(0xFF004D40)
                    : Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isSelected
                      ? const Color(0xFF10B981)
                      : Colors.white.withValues(alpha: 0.1),
                ),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: const Color(0xFF004D40).withValues(alpha: 0.4),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        )
                      ]
                    : [],
              ),
              child: Column(
                children: [
                  Icon(
                    opt['icon'] as IconData,
                    color: isSelected ? const Color(0xFF10B981) : const Color(0xFF94A3B8),
                    size: 20,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    opt['label'] as String,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                      color: isSelected ? Colors.white : const Color(0xFF94A3B8),
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

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          height: MediaQuery.of(context).size.height * 0.88,
          decoration: BoxDecoration(
            gradient: const RadialGradient(
              center: Alignment(-0.6, -0.7),
              radius: 1.3,
              colors: [
                Color(0xFF1E293B),
                Color(0xFF0F172A),
                Color(0xFF020617),
              ],
            ),
            border: Border(
              top: BorderSide(color: Colors.white.withValues(alpha: 0.18), width: 1.5),
            ),
          ),
          child: Stack(
            children: [
              // ── Main Scrollable Glass Form ─────────────────────────────
              SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(20, 16, 20, 100 + viewInsets.bottom),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Top Drag Indicator
                    Center(
                      child: Container(
                        width: 42,
                        height: 4.5,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),

                    const SizedBox(height: 18),

                    // Header & Category Picker Carousel
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Send New Ping',
                              style: GoogleFonts.outfit(
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                letterSpacing: -0.5,
                              ),
                            ),
                            Text(
                              'Broadcast to local shops in seconds.',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 12,
                                color: const Color(0xFF94A3B8),
                              ),
                            ),
                          ],
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.08),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                            ),
                            child: const Icon(Icons.close, color: Colors.white, size: 18),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // Category Selector Bar
                    SizedBox(
                      height: 38,
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
                                color: isSelected
                                    ? const Color(0xFF004D40)
                                    : Colors.white.withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: isSelected
                                      ? const Color(0xFF10B981)
                                      : Colors.white.withValues(alpha: 0.12),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Text(item['emoji']!, style: const TextStyle(fontSize: 14)),
                                  const SizedBox(width: 6),
                                  Text(
                                    item['name']!,
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 12,
                                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                      color: isSelected ? Colors.white : const Color(0xFFCBD5E1),
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

                    // Conditional Fields (Vehicle/Part/Aircon)
                    _buildConditionalFields(),

                    if (_category == 'Parts & Hardware' || _category == 'Rooms & Boarding' || _category == 'Community Helpers')
                      const SizedBox(height: 16),

                    // ── Card 1: Description Input ────────────────────────
                    _buildGlassCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _getDescriptionLabel(),
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _getDescriptionSubLabel(),
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              color: const Color(0xFF94A3B8),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _descriptionController,
                            style: GoogleFonts.plusJakartaSans(fontSize: 14, color: Colors.white),
                            decoration: InputDecoration(
                              hintText: _getDescriptionHint(),
                              hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.35)),
                              contentPadding: const EdgeInsets.all(14),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide.none,
                              ),
                              filled: true,
                              fillColor: Colors.white.withValues(alpha: 0.05),
                            ),
                            maxLines: 3,
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // ── Card 2: Budget & Fulfillment ─────────────────────
                    _buildGlassCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Max Budget (₱)',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _budgetController,
                            keyboardType: TextInputType.number,
                            style: GoogleFonts.outfit(
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              color: const Color(0xFFE28743),
                            ),
                            decoration: InputDecoration(
                              hintText: '0.00',
                              hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
                              prefixText: '₱ ',
                              prefixStyle: GoogleFonts.outfit(
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                color: const Color(0xFFE28743),
                              ),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide.none,
                              ),
                              filled: true,
                              fillColor: Colors.white.withValues(alpha: 0.05),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _getFulfillmentLabel(),
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF94A3B8),
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

              // ── Custom Glassmorphic Floating Action Bar ─────────────────
              Positioned(
                bottom: 16 + viewInsets.bottom,
                left: 16,
                right: 16,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.20),
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.4),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: PremiumButton(
                        onPressed: _isSubmitting ? null : _submitRequest,
                        isLoading: _isSubmitting,
                        height: 52,
                        color: const Color(0xFF004D40),
                        borderRadius: BorderRadius.circular(18),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Send Ping Now',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.2,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Icon(Icons.arrow_forward_rounded, size: 20, color: Colors.white),
                          ],
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
    );
  }
}
