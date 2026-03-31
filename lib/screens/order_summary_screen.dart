import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';

class OrderSummaryScreen extends StatefulWidget {
  final int roomId;
  final String roomName;

  const OrderSummaryScreen({
    super.key,
    required this.roomId,
    required this.roomName,
  });

  @override
  State<OrderSummaryScreen> createState() => _OrderSummaryScreenState();
}

class _OrderSummaryScreenState extends State<OrderSummaryScreen> {
  final ApiService _apiService = ApiService();
  List<dynamic> _items = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchSummary();
  }

  Future<void> _fetchSummary() async {
    setState(() => _isLoading = true);
    try {
      final data = await _apiService.getRoomItems(widget.roomId);
      if (!mounted) return;
      setState(() {
        // Filter only bought items for summary
        _items = (data['items'] as List).where((item) => item['is_bought'] == true).toList();
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error loading summary: $e')));
    }
  }

  double _calculateTotal() {
    double total = 0;
    for (var item in _items) {
      final price = double.tryParse((item['purchased_price'] ?? item['price_estimate'] ?? 0).toString()) ?? 0.0;
      final qty = int.tryParse((item['purchased_quantity'] ?? item['quantity'] ?? 1).toString()) ?? 1;
      total += price * qty;
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: _buildAppBar(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final String orderNumber = 'UNB${widget.roomId.toString().padLeft(6, '0')}';
    final String currentDate = DateFormat('yyyy-MM-dd').format(DateTime.now());

    Map<String, List<dynamic>> groupedItems = {};
    for (var item in _items) {
      final userName = item['added_by_name'] ?? 'A user';
      if (!groupedItems.containsKey(userName)) {
        groupedItems[userName] = [];
      }
      groupedItems[userName]!.add(item);
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: _buildAppBar(),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Success Card
            Container(
              padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
              decoration: BoxDecoration(
                color: const Color(0xFFF4F7FF),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                children: [
                  Container(
                    width: 70,
                    height: 70,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.check_circle_outline,
                        color: Color(0xFF1D5DE4),
                        size: 60,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Purchase Confirmed!',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF0F264D),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Your order #$orderNumber has been\nsuccessfully placed.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.blueGrey.shade400,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // 2. Order Details Area
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Order Details',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8EFFF),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'Confirmed', // Badge text
                    style: TextStyle(
                      color: Color(0xFF8BA6FC),
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            
            // Order Info Rows
            _buildDetailRow('Order Number:', orderNumber),
            const SizedBox(height: 12),
            _buildDetailRow('Order Date:', currentDate),
            const SizedBox(height: 12),
            _buildDetailRow('Room/Group:', widget.roomName),
            const SizedBox(height: 12),
            _buildDetailRow('Grand Total:', '\$${_calculateTotal().toStringAsFixed(2)}'),
            const SizedBox(height: 32),

            // 3. Billing Sections by Participant
            const Text(
              'Individual Bills',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 16),
            
            ...groupedItems.entries.map((entry) {
              final String userName = entry.key;
              final List<dynamic> userItems = entry.value;
              
              double userSubtotal = 0;
              for (var item in userItems) {
                final price = double.tryParse((item['purchased_price'] ?? item['price_estimate'] ?? 0).toString()) ?? 0.0;
                final qty = int.tryParse((item['purchased_quantity'] ?? item['quantity'] ?? 1).toString()) ?? 1;
                userSubtotal += price * qty;
              }

              return Container(
                margin: const EdgeInsets.only(bottom: 24),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade100),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.03),
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
                        CircleAvatar(
                          radius: 12,
                          backgroundColor: const Color(0xFF1D5DE4).withOpacity(0.1),
                          child: Text(
                            userName[0].toUpperCase(),
                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF1D5DE4)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          userName,
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0F264D)),
                        ),
                        const Spacer(),
                        Text(
                          'Subtotal: \$${userSubtotal.toStringAsFixed(2)}',
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 13),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    ...userItems.map((item) {
                      final actualPrice = double.tryParse((item['purchased_price'] ?? item['price_estimate'] ?? 0).toString()) ?? 0.0;
                      final actualQty = int.tryParse((item['purchased_quantity'] ?? item['quantity'] ?? 0).toString()) ?? 0;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _buildItemRow(
                          name: item['name'],
                          qty: actualQty,
                          price: actualPrice * actualQty,
                        ),
                      );
                    }),
                  ],
                ),
              );
            }),
            
            const SizedBox(height: 20),
            // Finish Button
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0F264D),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 0,
                ),
                onPressed: () => Navigator.of(context).pop(), // Go back home
                child: const Text(
                  'Back to Dashboard',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );

  }

  AppBar _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      iconTheme: const IconThemeData(color: Colors.black87), // Black back button
      centerTitle: true,
      title: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.shopping_cart, color: Colors.black87),
          SizedBox(width: 8),
          Text(
            'UniBuy',
            style: TextStyle(
              color: Colors.black87,
              fontWeight: FontWeight.w800,
              fontSize: 18,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 2,
          child: Text(
            label,
            style: TextStyle(
              color: Colors.blueGrey.shade400,
              fontSize: 14,
            ),
          ),
        ),
        Expanded(
          flex: 3,
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(
              color: Colors.black87,
              fontWeight: FontWeight.w600,
              fontSize: 14,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildItemRow({required String name, required int qty, required double price}) {
    // Determine an icon based on item name purely for aesthetic variation
    IconData itemIcon = Icons.shopping_bag_outlined;
    final lowerName = name.toLowerCase();
    if (lowerName.contains('headphone') || lowerName.contains('audio')) {
      itemIcon = Icons.headphones_outlined;
    } else if (lowerName.contains('watch') || lowerName.contains('clock')) {
      itemIcon = Icons.watch_outlined;
    } else if (lowerName.contains('chair') || lowerName.contains('furniture')) {
      itemIcon = Icons.chair_outlined;
    } else if (lowerName.contains('food') || lowerName.contains('milk') || lowerName.contains('egg')) {
      itemIcon = Icons.fastfood_outlined;
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Product Image Placeholder
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: const Color(0xFFF7F8FA),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: Icon(itemIcon, color: Colors.black87, size: 28),
          ),
        ),
        const SizedBox(width: 16),
        
        // Product Info
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: Colors.black87,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                'Quantity: $qty',
                style: TextStyle(
                  color: Colors.blueGrey.shade400,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
        
        // Price
        Text(
          '\$${price.toStringAsFixed(2)}',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: Colors.black87,
          ),
        ),
      ],
    );
  }
}
