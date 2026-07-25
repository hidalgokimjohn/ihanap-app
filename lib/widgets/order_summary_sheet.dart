import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class OrderSummarySheet extends StatefulWidget {
  final Map<String, dynamic> request;

  const OrderSummarySheet({super.key, required this.request});

  @override
  State<OrderSummarySheet> createState() => _OrderSummarySheetState();
}

class _OrderSummarySheetState extends State<OrderSummarySheet> {
  bool _isLoading = true;
  String _error = '';

  Map<String, dynamic>? _offer;
  Map<String, dynamic>? _buyerProfile;
  Map<String, dynamic>? _merchantProfile;

  @override
  void initState() {
    super.initState();
    _fetchDetails();
  }

  Future<void> _fetchDetails() async {
    try {
      final supabase = Supabase.instance.client;
      var offerId = widget.request['accepted_offer_id'];
      Map<String, dynamic>? offerRes;

      if (offerId != null) {
        offerRes = await supabase.from('offers').select().eq('id', offerId).maybeSingle();
      }

      // Fallback: If accepted_offer_id wasn't set or offer not found by ID, look up offer by request_id
      if (offerRes == null) {
        final reqId = widget.request['id'];
        if (reqId != null) {
          offerRes = await supabase
              .from('offers')
              .select()
              .eq('request_id', reqId)
              .order('created_at', ascending: false)
              .limit(1)
              .maybeSingle();

          if (offerRes != null) {
            // Auto-repair accepted_offer_id on request record
            try {
              await supabase.from('requests').update({
                'accepted_offer_id': offerRes['id'],
                'status': 'matched',
              }).eq('id', reqId);
            } catch (_) {}
          }
        }
      }

      if (offerRes == null) {
        throw Exception('No accepted offer found for this request.');
      }
      _offer = offerRes;

      // Fetch Buyer Profile (Requester)
      final buyerId = widget.request['user_id'];
      if (buyerId != null) {
        _buyerProfile = await supabase.from('profiles').select().eq('id', buyerId).maybeSingle();
      }

      // Fetch Merchant Profile (Responder)
      final merchantId = offerRes['user_id'];
      if (merchantId != null) {
        _merchantProfile = await supabase.from('profiles').select().eq('id', merchantId).maybeSingle();
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Widget _buildPartyCard({required String title, required String name, required String phone, String? subtitle, required Color iconBg, required Color iconColor, required IconData icon}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 8, offset: const Offset(0, 2))
        ]
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
            child: Icon(icon, color: iconColor),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 12, color: Color(0xFF64748B), fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                if (subtitle != null) ...[
                  Text(subtitle, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                  const SizedBox(height: 2),
                ],
                Text(name.isNotEmpty ? name : 'Unknown Name', 
                  style: TextStyle(fontSize: subtitle != null ? 13 : 15, fontWeight: subtitle != null ? FontWeight.w500 : FontWeight.bold, color: subtitle != null ? const Color(0xFF475569) : const Color(0xFF0F172A))),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.phone, size: 12, color: Color(0xFF004D40)),
                    const SizedBox(width: 4),
                    Text(phone.isNotEmpty ? phone : 'No contact provided', style: const TextStyle(fontSize: 13, color: Color(0xFF004D40), fontWeight: FontWeight.w600)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final String category = widget.request['category'] ?? 'General';
    final String description = widget.request['description'] ?? '';
    final String fulfillment = widget.request['fulfillment_type'] ?? 'pickup';

    String categoryEmoji = '📌';
    if (category.contains('Parts')) categoryEmoji = '🚗';
    if (category.contains('Rider')) categoryEmoji = '📦';
    if (category.contains('Rooms')) categoryEmoji = '🏠';
    if (category.contains('Community')) categoryEmoji = '📍';

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
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
          const Text(
            'Order Summary',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Color(0xFF0F172A)),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(40.0),
              child: Center(child: CircularProgressIndicator(color: Color(0xFF004D40))),
            )
          else if (_error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Text('Error: $_error', style: const TextStyle(color: Colors.red)),
            )
          else ...[
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(categoryEmoji, style: const TextStyle(fontSize: 18)),
                      const SizedBox(width: 8),
                      Text(category, style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF475569))),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(color: const Color(0xFFD1FAE5), borderRadius: BorderRadius.circular(8)),
                        child: const Text('Matched', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF059669))),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(description, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF0F172A))),
                  
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 16),
                  
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Fulfillment', style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w500)),
                      Text(fulfillment.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Agreed Price', style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w500)),
                      Text('₱${((_offer?['offered_price'] ?? 0) as num).toStringAsFixed(2)}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF004D40), letterSpacing: -0.5)),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),
            const Text('Transaction Parties', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF0F172A))),
            const SizedBox(height: 12),
            
            _buildPartyCard(
              title: 'CUSTOMER / BUYER',
              name: _buyerProfile?['full_name'] ?? '',
              phone: _buyerProfile?['contact_number'] ?? '',
              iconBg: const Color(0xFFE0E7FF),
              iconColor: const Color(0xFF4F46E5),
              icon: Icons.person,
            ),
            
            _buildPartyCard(
              title: 'MERCHANT / RESPONDER',
              subtitle: _offer?['seller_name'] ?? 'Shop',
              name: _merchantProfile?['full_name'] ?? '',
              phone: _merchantProfile?['contact_number'] ?? '',
              iconBg: const Color(0xFFDCFCE7),
              iconColor: const Color(0xFF16A34A),
              icon: Icons.storefront,
            ),

            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F172A),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: const Text('Close', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ]
        ],
      ),
    );
  }
}
