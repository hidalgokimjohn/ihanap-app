import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/auth_service.dart';

class OfferBottomSheet extends StatefulWidget {
  final String requestId;
  final Map<String, dynamic>? request;
  final String shopName;

  const OfferBottomSheet({super.key, required this.requestId, this.request, this.shopName = 'My Shop'});

  @override
  State<OfferBottomSheet> createState() => _OfferBottomSheetState();
}

class _OfferBottomSheetState extends State<OfferBottomSheet> {
  final _priceController    = TextEditingController();
  final _noteController     = TextEditingController();
  final _availabilityController = TextEditingController();

  bool _isSubmitting = false;
  bool _includesFreeDelivery = false;
  bool _itemInStock = true;
  String _condition = 'Brand New';

  final List<String> _conditions = ['Brand New', 'Good Condition', 'Refurbished', 'Open Box'];

  String get _category => (widget.request?['category'] ?? '') as String;
  String get _description => (widget.request?['description'] ?? '') as String;
  String get _fulfillment => (widget.request?['fulfillment_type'] ?? 'pickup') as String;
  double get _maxBudget => ((widget.request?['max_budget'] ?? 0) as num).toDouble();

  String _getNoteLabel() {
    switch (_category) {
      case 'Rooms & Boarding': return 'Room Details (inclusive, rules, etc.)';
      case 'Express Rider':    return 'Rider Notes (ETA, vehicle type, etc.)';
      default:                 return 'Warranty / Additional Details';
    }
  }

  String _getNoteHint() {
    switch (_category) {
      case 'Rooms & Boarding': return 'e.g. Monthly rent, includes water, move-in ready';
      case 'Express Rider':    return 'e.g. Estimated 30 mins, using motorcycle';
      default:                 return 'e.g. 6-month warranty, receipt included, OEM part';
    }
  }

  String _getPriceLabel() {
    switch (_category) {
      case 'Rooms & Boarding': return 'Monthly Rental Price (₱)';
      case 'Express Rider':    return 'Delivery Fee (₱)';
      default:                 return 'Your Offer Price (₱)';
    }
  }

  bool get _showCondition => _category.contains('Parts') || _category.isEmpty;
  bool get _showDeliveryToggle => _fulfillment == 'delivery' || _fulfillment == 'pickup';
  bool get _showAvailability => _category == 'Rooms & Boarding';

  Future<void> _submitOffer() async {
    final shopName = widget.shopName;
    final priceText = _priceController.text.trim();
    final price = double.tryParse(priceText);
    final note = _noteController.text.trim();

    if (price == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid price.')),
      );
      return;
    }

    // Build a rich note from all fields
    final List<String> noteParts = [];
    if (note.isNotEmpty) noteParts.add(note);
    if (_showCondition) noteParts.add('Condition: $_condition');
    if (_includesFreeDelivery) noteParts.add('✅ Free Delivery Included');
    if (!_itemInStock) noteParts.add('⚠️ Pre-order / On-request');
    if (_showAvailability && _availabilityController.text.trim().isNotEmpty) {
      noteParts.add('Available: ${_availabilityController.text.trim()}');
    }
    final fullNote = noteParts.join(' • ');

    setState(() => _isSubmitting = true);

    try {
      await Supabase.instance.client.from('offers').insert({
        'request_id': widget.requestId,
        'seller_name': shopName,
        'offered_price': price,
        'note': fullNote.isNotEmpty ? fullNote : null,
        if (AuthService.currentUserId != null) 'user_id': AuthService.currentUserId,
      });

      // Send notification to the requester
      final requestOwnerId = widget.request?['user_id'];
      if (requestOwnerId != null && requestOwnerId != AuthService.currentUserId) {
        await Supabase.instance.client.from('notifications').insert({
          'user_id': requestOwnerId,
          'title': 'New Offer Received',
          'body': '$shopName sent an offer of ₱${price.toStringAsFixed(0)} for your Ping!',
          'type': 'new_offer',
          'reference_id': widget.requestId,
        });
      }

      if (mounted) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(children: [
              const Icon(Icons.check_circle, color: Colors.white),
              const SizedBox(width: 8),
              Text('Offer from $shopName sent!'),
            ]),
            backgroundColor: const Color(0xFF004D40),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
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
            // ── Handle bar ───────────────────────────────────────────────
            Center(
              child: Container(
                width: 48, height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // ── Header ───────────────────────────────────────────────────
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE2F0F0),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.storefront, color: Color(0xFF004D40), size: 22),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Send Your Offer',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF0F172A))),
                      Text('Customer will see this immediately',
                          style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                    ],
                  ),
                ),
              ],
            ),

            // ── Customer request preview ──────────────────────────────────
            if (_description.isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Customer Ping', style: TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text(_description, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF0F172A))),
                    if (_maxBudget > 0) ...[
                      const SizedBox(height: 6),
                      Text('Budget: ₱${_maxBudget.toStringAsFixed(0)}',
                          style: const TextStyle(fontSize: 12, color: Color(0xFF004D40), fontWeight: FontWeight.bold)),
                    ],
                  ],
                ),
              ),
            ],

            const SizedBox(height: 20),

            // ── Sending as badge ──────────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFBBF7D0)),
              ),
              child: Row(children: [
                const Icon(Icons.storefront, size: 16, color: Color(0xFF059669)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Sending offer as: ${widget.shopName}',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF059669)),
                  ),
                ),
              ]),
            ),

            const SizedBox(height: 16),

            // ── Price ─────────────────────────────────────────────────────
            Text(_getPriceLabel(), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            TextField(
              controller: _priceController,
              keyboardType: TextInputType.number,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF004D40)),
              decoration: InputDecoration(
                hintText: '0.00',
                prefixText: '₱ ',
                prefixStyle: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF004D40)),
                contentPadding: const EdgeInsets.all(16),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
              ),
            ),

            // ── Condition chips (for parts) ───────────────────────────────
            if (_showCondition) ...[
              const SizedBox(height: 16),
              const Text('Item Condition', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: _conditions.map((c) {
                  final selected = _condition == c;
                  return ChoiceChip(
                    label: Text(c),
                    selected: selected,
                    onSelected: (_) => setState(() => _condition = c),
                    selectedColor: const Color(0xFFE2F0F0),
                    backgroundColor: const Color(0xFFF8FAFC),
                    labelStyle: TextStyle(
                      color: selected ? const Color(0xFF004D40) : const Color(0xFF64748B),
                      fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                      fontSize: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(color: selected ? const Color(0xFF004D40) : const Color(0xFFE2E8F0)),
                    ),
                    showCheckmark: false,
                  );
                }).toList(),
              ),
            ],

            // ── Availability field (for Rooms) ────────────────────────────
            if (_showAvailability) ...[
              const SizedBox(height: 16),
              const Text('Availability / Move-in Date', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              TextField(
                controller: _availabilityController,
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'e.g. Available now, or August 1',
                  hintStyle: TextStyle(color: Colors.grey[400]),
                  prefixIcon: const Icon(Icons.calendar_month_outlined, color: Color(0xFF64748B)),
                  contentPadding: const EdgeInsets.all(16),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                ),
              ),
            ],

            const SizedBox(height: 16),

            // ── Note field ────────────────────────────────────────────────
            Text(_getNoteLabel(), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            TextField(
              controller: _noteController,
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                hintText: _getNoteHint(),
                hintStyle: TextStyle(color: Colors.grey[400]),
                contentPadding: const EdgeInsets.all(16),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
              ),
              maxLines: 3,
            ),

            const SizedBox(height: 16),

            // ── Quick toggles ─────────────────────────────────────────────
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  SwitchListTile(
                    dense: true,
                    title: const Text('Item is In-Stock / Ready Now',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    subtitle: const Text('Turn off if pre-order or on-request',
                        style: TextStyle(fontSize: 11)),
                    value: _itemInStock,
                    onChanged: (val) => setState(() => _itemInStock = val),
                    activeColor: const Color(0xFF004D40),
                  ),
                  if (_showDeliveryToggle) ...[
                    const Divider(height: 1, color: Color(0xFFE2E8F0)),
                    SwitchListTile(
                      dense: true,
                      title: const Text('Free Delivery Included',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      subtitle: const Text('Toggle if delivery is part of your offer',
                          style: TextStyle(fontSize: 11)),
                      value: _includesFreeDelivery,
                      onChanged: (val) => setState(() => _includesFreeDelivery = val),
                      activeColor: const Color(0xFF004D40),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ── Photo placeholder ─────────────────────────────────────────
            OutlinedButton.icon(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('📸 Live Photo Upload — Coming Soon!')),
                );
              },
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 52),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                side: const BorderSide(color: Color(0xFFE2E8F0), width: 1.5),
                foregroundColor: const Color(0xFF64748B),
              ),
              icon: const Icon(Icons.camera_alt_outlined),
              label: const Text('Attach Stock Photo (Optional)',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            ),

            const SizedBox(height: 20),

            // ── Submit ────────────────────────────────────────────────────
            ElevatedButton(
              onPressed: _isSubmitting ? null : _submitOffer,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF004D40),
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 56),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: _isSubmitting
                  ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.send_rounded, size: 18),
                        SizedBox(width: 8),
                        Text('Send My Offer', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
