import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../screens/live_offers_screen.dart';
import '../services/auth_service.dart';
import '../services/location_service.dart';

class RequestBottomSheet extends StatefulWidget {
  final String? initialCategory;
  const RequestBottomSheet({super.key, this.initialCategory});

  @override
  State<RequestBottomSheet> createState() => _RequestBottomSheetState();
}

class _RequestBottomSheetState extends State<RequestBottomSheet> {
  final _descriptionController = TextEditingController();
  final _budgetController = TextEditingController();
  final _vehicleModelController = TextEditingController(); // For Auto
  
  late String _fulfillmentType;
  late String _category;
  bool _isSubmitting = false;

  String? _selectedSubCategory;
  bool _airconPreferred = false; // For Rooms

  @override
  void initState() {
    super.initState();
    _category = widget.initialCategory ?? 'General';
    
    switch (_category) {
      case 'Express Rider':
        _fulfillmentType = 'delivery';
        break;
      case 'Rooms & Boarding':
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
      case 'Parts & Hardware': return '🔍 What part or material do you need?';
      case 'Rooms & Boarding': return '🏠 Describe the room you are looking for';
      case 'Express Rider':    return '📦 What needs to be picked up or delivered?';
      case 'Community Updates': return '📍 What do you want to check or verify?';
      default:                 return '💬 Describe what you need';
    }
  }

  String _getDescriptionSubLabel() {
    switch (_category) {
      case 'Parts & Hardware': return 'Be specific — include brand, specs, or condition if needed.';
      case 'Rooms & Boarding': return 'Mention preferred location, move-in date, or duration.';
      case 'Express Rider':    return 'Include pickup address, item size, and any special handling.';
      case 'Community Updates': return 'Describe the place or situation you want checked.';
      default:                  return 'The more detail, the better your offers will be.';
    }
  }

  String _getDescriptionHint() {
    switch (_category) {
      case 'Parts & Hardware': return 'e.g. Front brake pads for 2020 Honda Click 125i';
      case 'Rooms & Boarding': return 'e.g. Looking for aircon bedspace near Robinsons';
      case 'Express Rider':    return 'e.g. Pick up documents from City Hall, deliver to SM';
      case 'Community Updates': return 'e.g. Is Jollibee Montilla open? Line status?';
      default:                  return 'e.g. I need a plumber for a leaking pipe';
    }
  }

  List<String> _getSubCategories() {
    switch (_category) {
      case 'Parts & Hardware':
        return [
          '🚗 Car / Sedan', '🏍️ Motorcycle', '🔋 Battery / Tires', '🛢️ Oil & Fluids',
          '🚰 Plumbing', '⚡ Electrical', '🎨 Paint & Cement', '🪚 Tools'
        ];
      case 'Rooms & Boarding':
        return ['🚪 Private Room w/ CR', '🛏️ Bedspace', '🏢 Studio Apartment'];
      case 'Express Rider':
        return ['📦 Small Package', '📄 Documents', '🛒 Grocery Run'];
      default:
        return [];
    }
  }

  Widget _buildSubCategoryChips() {
    final subs = _getSubCategories();
    if (subs.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Specific Type',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF64748B)),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8.0,
          runSpacing: 8.0,
          children: subs.map((sub) {
            final isSelected = _selectedSubCategory == sub;
            return ChoiceChip(
              label: Text(sub),
              selected: isSelected,
              onSelected: (selected) {
                setState(() {
                  _selectedSubCategory = selected ? sub : null;
                });
              },
              selectedColor: const Color(0xFFE2F0F0),
              backgroundColor: const Color(0xFFF8FAFC),
              labelStyle: TextStyle(
                color: isSelected ? const Color(0xFF004D40) : const Color(0xFF64748B),
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(
                  color: isSelected ? const Color(0xFF004D40) : const Color(0xFFE2E8F0),
                ),
              ),
              showCheckmark: false,
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildConditionalFields() {
    if (_category == 'Parts & Hardware') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Vehicle Model & Year',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _vehicleModelController,
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
              hintText: 'e.g. 2023 Toyota Wigo',
              hintStyle: TextStyle(color: Colors.grey[400]),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
            ),
          ),
          const SizedBox(height: 16),
        ],
      );
    }

    if (_category == 'Rooms & Boarding') {
      return Column(
        children: [
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
            ),
            child: SwitchListTile(
              title: const Text('Aircon Preferred', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              value: _airconPreferred,
              onChanged: (val) {
                setState(() {
                  _airconPreferred = val;
                });
              },
              activeColor: const Color(0xFF004D40),
            ),
          ),
          const SizedBox(height: 16),
        ],
      );
    }

    return const SizedBox.shrink();
  }

  List<ButtonSegment<String>> _getFulfillmentSegments() {
    switch (_category) {
      case 'Express Rider':
        return [
          const ButtonSegment<String>(
            value: 'delivery',
            label: Padding(
              padding: EdgeInsets.symmetric(vertical: 12.0),
              child: Text('Express Delivery', style: TextStyle(fontSize: 12)),
            ),
            icon: Icon(Icons.two_wheeler),
          ),
        ];
      case 'Rooms & Boarding':
        return [
          const ButtonSegment<String>(
            value: 'visit',
            label: Padding(
              padding: EdgeInsets.symmetric(vertical: 12.0),
              child: Text('Schedule Site Visit', style: TextStyle(fontSize: 12)),
            ),
            icon: Icon(Icons.calendar_month),
          ),
          const ButtonSegment<String>(
            value: 'reserve',
            label: Padding(
              padding: EdgeInsets.symmetric(vertical: 12.0),
              child: Text('Inquire / Reserve', style: TextStyle(fontSize: 12)),
            ),
            icon: Icon(Icons.book_online),
          ),
        ];
      case 'Community Updates':
        return [
          const ButtonSegment<String>(
            value: 'status',
            label: Padding(
              padding: EdgeInsets.symmetric(vertical: 12.0),
              child: Text('Live Photo / Status', style: TextStyle(fontSize: 12)),
            ),
            icon: Icon(Icons.camera_alt),
          ),
        ];
      default:
        return [
          const ButtonSegment<String>(
            value: 'pickup',
            label: Padding(
              padding: EdgeInsets.symmetric(vertical: 12.0),
              child: Text('Reserve for Pickup', style: TextStyle(fontSize: 12)),
            ),
            icon: Icon(Icons.storefront),
          ),
          const ButtonSegment<String>(
            value: 'delivery',
            label: Padding(
              padding: EdgeInsets.symmetric(vertical: 12.0),
              child: Text('Express Delivery', style: TextStyle(fontSize: 12)),
            ),
            icon: Icon(Icons.two_wheeler),
          ),
        ];
    }
  }

  Future<void> _submitRequest() async {
    final description = _descriptionController.text.trim();
    final budgetText = _budgetController.text.trim();
    final budget = double.tryParse(budgetText);

    if (description.isEmpty || budget == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter what you need and a valid budget.')),
      );
      return;
    }

    Map<String, dynamic> tags = {};
    if (_category == 'Parts & Hardware' && _vehicleModelController.text.trim().isNotEmpty) {
      tags['vehicle_model'] = _vehicleModelController.text.trim();
    }
    if (_category == 'Rooms & Boarding') {
      tags['aircon_preferred'] = _airconPreferred;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      final pos = await LocationService.getCurrentPosition();
      if (pos != null) {
        tags['lat'] = pos.latitude;
        tags['lng'] = pos.longitude;
      }
      final Map<String, dynamic> payload = {
        'category': _category,
        'description': description,
        'max_budget': budget,
        'fulfillment_type': _fulfillmentType,
        if (AuthService.currentUserId != null) 'user_id': AuthService.currentUserId,
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
          MaterialPageRoute(builder: (_) => LiveOffersScreen(requestId: requestId)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(24, 16, 24, 24 + bottomPadding),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 48,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Text(
                    _category,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF004D40)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildSubCategoryChips(),
            _buildConditionalFields(),
            Text(
              _getDescriptionLabel(),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              _getDescriptionSubLabel(),
              style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _descriptionController,
              style: const TextStyle(fontSize: 16),
              decoration: InputDecoration(
                hintText: _getDescriptionHint(),
                hintStyle: TextStyle(color: Colors.grey[400]),
                contentPadding: const EdgeInsets.all(16),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 16),
            const Text(
              'Max Budget (₱)',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _budgetController,
              keyboardType: TextInputType.number,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                hintText: '0.00',
                prefixText: '₱ ',
                prefixStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
                contentPadding: const EdgeInsets.all(16),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
              ),
            ),
            const SizedBox(height: 24),
            SegmentedButton<String>(
              segments: _getFulfillmentSegments(),
              selected: {_fulfillmentType},
              onSelectionChanged: (Set<String> newSelection) {
                setState(() {
                  _fulfillmentType = newSelection.first;
                });
              },
              style: ButtonStyle(
                backgroundColor: WidgetStateProperty.resolveWith<Color>(
                  (Set<WidgetState> states) {
                    if (states.contains(WidgetState.selected)) return const Color(0xFFE2F0F0);
                    return Colors.transparent;
                  },
                ),
                foregroundColor: WidgetStateProperty.resolveWith<Color>(
                  (Set<WidgetState> states) {
                    if (states.contains(WidgetState.selected)) return const Color(0xFF004D40);
                    return const Color(0xFF64748B);
                  },
                ),
                side: WidgetStateProperty.all(const BorderSide(color: Color(0xFFE2E8F0))),
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _isSubmitting ? null : _submitRequest,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6B57), // Warm Coral Gold
                foregroundColor: Colors.white,
              ),
              child: _isSubmitting 
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) 
                : const Text('Post Request Now', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}
