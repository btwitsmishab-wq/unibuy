import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';
import 'order_summary_screen.dart';
import '../widgets/confidence_score_widget.dart';

class AlternativeSelection {
  final String name;
  final double price;
  final int quantity;
  AlternativeSelection({required this.name, required this.price, required this.quantity});
}

class RoomDetailsScreen extends StatefulWidget {
  final int roomId;
  final String roomName;
  final String roomCode;

  const RoomDetailsScreen({
    super.key,
    required this.roomId,
    required this.roomName,
    required this.roomCode,
  });

  @override
  State<RoomDetailsScreen> createState() => _RoomDetailsScreenState();
}

class _RoomDetailsScreenState extends State<RoomDetailsScreen> with SingleTickerProviderStateMixin {
  final ApiService _apiService = ApiService();
  final SocketService _socketService = SocketService();
  final _itemController = TextEditingController();
  final _quantityController = TextEditingController();
  final _priceController = TextEditingController();
  
  // Alternative Controllers
  final _alt1Controller = TextEditingController();
  final _alt1QtyController = TextEditingController();
  final _alt1PriceController = TextEditingController();
  final _alt2Controller = TextEditingController();
  final _alt2QtyController = TextEditingController();
  final _alt2PriceController = TextEditingController();
  final _alt3Controller = TextEditingController();
  final _alt3QtyController = TextEditingController();
  final _alt3PriceController = TextEditingController();

  List<dynamic> _items = [];
  Map<String, dynamic>? _budgetStatus;
  String? _roomOwner;
  bool _isShopping = false;
  bool _isLoading = true;
  int _participantCount = 0;
  String _roomStatus = 'active';
  Timer? _refreshTimer;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  final Map<int, bool> _expandedItems = {};

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.6, end: 1.0).animate(_pulseController);
    
    _fetchItems();
    _setupSocket();
    _startPolling();
  }

  void _setupSocket() {
    _socketService.connect();
    _socketService.joinRoom(widget.roomId);
    _socketService.onItemsUpdated('room_details_${widget.roomId}', () {
      if (mounted) {
        _fetchItems(isSilent: true);
      }
    });
    _socketService.onRoomStatusUpdated('room_details_${widget.roomId}', (data) {
       if (mounted && data['roomId'] == widget.roomId) {
         setState(() {
           _roomStatus = data['status'];
           _isShopping = (_roomStatus == 'shopping');
         });
         _fetchItems(isSilent: true);
       }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _pulseController.dispose();
    _socketService.offItemsUpdated('room_details_${widget.roomId}');
    _socketService.offRoomStatusUpdated('room_details_${widget.roomId}');
    _socketService.leaveRoom(widget.roomId);
    super.dispose();
  }

  void _startPolling() {
    // Polling increased to 60 seconds as a fallback, real-time is handled by Socket.io
    _refreshTimer = Timer.periodic(const Duration(seconds: 60), (timer) {
      if (mounted) _fetchItems(isSilent: true);
    });
  }

  double _calculateTotalPurchased() {
    double total = 0;
    for (var item in _items) {
      if (item['is_bought'] == true) {
        final price = double.tryParse((item['purchased_price'] ?? item['price_estimate'] ?? '0').toString()) ?? 0.0;
        final qty = int.tryParse((item['purchased_quantity'] ?? item['quantity'] ?? '1').toString()) ?? 1;
        total += price * qty;
      }
    }
    return total;
  }

  Future<void> _fetchItems({bool isSilent = false}) async {
    if (!mounted) return;
    if (!isSilent) setState(() => _isLoading = true);
    try {
      final data = await _apiService.getRoomItems(widget.roomId);
      if (!mounted) return;
      setState(() {
        _items = data['items'];
        _roomOwner = data['roomOwner'];
        _budgetStatus = data['budgetStatus'];
        _isShopping = data['isShopping'] ?? false;
        _roomStatus = data['status'] ?? 'active';
        _participantCount = data['participantCount'] ?? 0;
        _isLoading = false;
        
        // Redirection logic for completed rooms
        if (_roomStatus == 'completed') {
          Future.delayed(Duration.zero, () {
            if (mounted) {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (context) => OrderSummaryScreen(
                    roomId: widget.roomId,
                    roomName: widget.roomName,
                  ),
                ),
              );
            }
          });
        }
      });
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading items: $e')),
        );
      }
    }
  }

  Future<void> _addItem(BuildContext dialogContext, {int priority = 1}) async {
    final name = _itemController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(dialogContext).showSnackBar(
        const SnackBar(content: Text('Please enter an item name')),
      );
      return;
    }

    try {
      final user = FirebaseAuth.instance.currentUser;
      
      List<Map<String, dynamic>> alternatives = [];
      if (_alt1Controller.text.trim().isNotEmpty) {
        alternatives.add({
          'name': _alt1Controller.text.trim(),
          'quantity': int.tryParse(_alt1QtyController.text) ?? 1,
          'price_estimate': double.tryParse(_alt1PriceController.text) ?? 0.0,
        });
      }
      if (_alt2Controller.text.trim().isNotEmpty) {
        alternatives.add({
          'name': _alt2Controller.text.trim(),
          'quantity': int.tryParse(_alt2QtyController.text) ?? 1,
          'price_estimate': double.tryParse(_alt2PriceController.text) ?? 0.0,
        });
      }
      if (_alt3Controller.text.trim().isNotEmpty) {
        alternatives.add({
          'name': _alt3Controller.text.trim(),
          'quantity': int.tryParse(_alt3QtyController.text) ?? 1,
          'price_estimate': double.tryParse(_alt3PriceController.text) ?? 0.0,
        });
      }

      final result = await _apiService.addItem(
        roomId: widget.roomId,
        name: name,
        quantity: int.tryParse(_quantityController.text) ?? 1,
        priority: priority,
        priceEstimate: double.tryParse(_priceController.text) ?? 0,
        userName: (user?.displayName != null && user!.displayName!.isNotEmpty)
            ? user.displayName
            : (user?.email?.split('@')[0] ?? 'A user'),
        alternatives: alternatives,
      );
      
      _itemController.clear();
      _quantityController.clear();
      _priceController.clear();
      _alt1Controller.clear();
      _alt1QtyController.clear();
      _alt1PriceController.clear();
      _alt2Controller.clear();
      _alt2QtyController.clear();
      _alt2PriceController.clear();
      _alt3Controller.clear();
      _alt3QtyController.clear();
      _alt3PriceController.clear();

      if (dialogContext.mounted) Navigator.of(dialogContext).pop();

      if (!mounted) return;
      if (result['budgetStatus']?['budgetExceeded'] == true) {
        _showBudgetAlert(result['budgetStatus']['currentTotal'], result['budgetStatus']['totalBudget']);
      }
      _fetchItems();
    } catch (e) {
      if (dialogContext.mounted) Navigator.of(dialogContext).pop();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error adding item: $e'), backgroundColor: Colors.red),
      );
    }
  }

  void _showBudgetAlert(dynamic current, dynamic budget) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning, color: Colors.orange),
            SizedBox(width: 8),
            Text('Budget Exceeded!'),
          ],
        ),
        content: Text('Total cost (\$$current) exceeds your budget of \$$budget.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Understood')),
        ],
      ),
    );
  }

  Future<void> _toggleItemPurchase(int itemId, bool currentStatus) async {
    if (!currentStatus) {
      final item = _items.firstWhere((i) => i['id'] == itemId);
      await _showConfirmPurchaseDialog(item);
    } else {
      try {
        await _apiService.updateItemPurchaseStatus(itemId, isBought: false);
        _fetchItems();
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<bool> _showConfirmPurchaseDialog(dynamic item, {AlternativeSelection? altSelection}) async {
    final priceCtrl = TextEditingController(text: (item['purchased_price'] ?? altSelection?.price ?? item['price_estimate'] ?? 0).toString());
    final qtyCtrl = TextEditingController(text: (item['purchased_quantity'] ?? altSelection?.quantity ?? item['quantity'] ?? 1).toString());

    final expectedPrice = altSelection?.price ?? double.tryParse((item['price_estimate'] ?? 0).toString()) ?? 0.0;
    final expectedQty = altSelection?.quantity ?? int.tryParse((item['quantity'] ?? 1).toString()) ?? 1;

    final bool? success = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final actualPrice = double.tryParse(priceCtrl.text) ?? 0.0;
          final actualQty = int.tryParse(qtyCtrl.text) ?? 0;

          return AlertDialog(
            title: Text('Confirm Purchase: ${altSelection?.name ?? item['name']}'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (altSelection != null)
                   Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text('Alternative: ${altSelection.name}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                  ),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Expected Price', style: TextStyle(fontSize: 10, color: Colors.grey)),
                          Text('\$${expectedPrice.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Expected Qty', style: TextStyle(fontSize: 10, color: Colors.grey)),
                          Text('$expectedQty', style: const TextStyle(fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: priceCtrl,
                  decoration: const InputDecoration(labelText: 'Actual Price (\$)'),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (v) => setDialogState(() {}),
                ),
                TextField(
                  controller: qtyCtrl,
                  decoration: const InputDecoration(labelText: 'Actual Quantity'),
                  keyboardType: TextInputType.number,
                  onChanged: (v) => setDialogState(() {}),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(8),
                  color: Colors.grey.shade100,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Total Actual:', style: TextStyle(fontWeight: FontWeight.bold)),
                      Text(
                        '\$${(actualPrice * actualQty).toStringAsFixed(2)}',
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              ElevatedButton(
                onPressed: () async {
                  try {
                    if (altSelection != null) {
                      await _apiService.selectAlternative(
                        item['id'], 
                        altSelection.name, 
                        altSelection.price,
                        purchasedPrice: actualPrice,
                        purchasedQuantity: actualQty,
                      );
                    } else {
                      await _apiService.updateItemPurchaseStatus(
                        item['id'], 
                        isBought: true,
                        purchasedPrice: actualPrice,
                        purchasedQuantity: actualQty,
                      );
                    }
                    if (ctx.mounted) Navigator.pop(ctx, true);
                    _fetchItems();
                  } catch (e) {
                    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                  }
                },
                child: const Text('Confirm'),
              ),
            ],
          );
        },
      ),
    );
    return success ?? false;
  }

  Future<void> _startShopping() async {
    try {
      await _apiService.startShopping(widget.roomId);
      _fetchItems();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _finalizeShopping() async {
    final pendingItems = _items.where((it) => !(it['is_bought'] ?? false)).toList();
    if (pendingItems.isEmpty) {
      try {
        await _apiService.finalizeShopping(widget.roomId);
        _fetchItems();
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
      return;
    }
    _showFinalizeDialog(pendingItems);
  }

  Future<void> _confirmDeleteItem(int itemId, String itemName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Item?'),
        content: Text('Are you sure you want to remove "$itemName" from the list?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _apiService.deleteItem(itemId);
        // Real-time update will trigger _fetchItems via socket
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  void _showFinalizeDialog(List<dynamic> pendingItems) {
    Map<int, List<dynamic>> itemAlternatives = {};
    Map<int, String?> selectedAltName = {};

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Finalize Orders'),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: pendingItems.length,
                itemBuilder: (ctx, index) {
                  final item = pendingItems[index];
                  final bool showAlternatives = item['status'] == 'unavailable' || item['status'] == 'out_of_budget';
                  
                  if (showAlternatives && !itemAlternatives.containsKey(item['id'])) {
                    itemAlternatives[item['id']] = []; 
                    _apiService.getItemAlternatives(item['id']).then((alts) {
                      if (mounted) setDialogState(() => itemAlternatives[item['id']] = alts);
                    });
                  }

                  return Column(
                    children: [
                      ListTile(
                        title: Text(item['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('Status: ${item['status']}'),
                        trailing: (item['is_bought'] ?? false) ? const Icon(Icons.check_circle, color: Colors.green) : null,
                      ),
                      Wrap(
                        spacing: 8,
                        children: [
                          ActionChip(
                            label: const Text('Purchased', style: TextStyle(fontSize: 10, color: Colors.green)),
                            onPressed: () async {
                              await _showConfirmPurchaseDialog(item);
                              setDialogState(() {});
                            },
                          ),
                          ActionChip(
                            label: const Text('Unavailable', style: TextStyle(fontSize: 10, color: Colors.red)),
                            onPressed: () => _updateItemStatusInDialog(item['id'], 'unavailable', setDialogState, pendingItems),
                          ),
                          ActionChip(
                            label: const Text('Out of Budget', style: TextStyle(fontSize: 10, color: Colors.orange)),
                            onPressed: () => _updateItemStatusInDialog(item['id'], 'out_of_budget', setDialogState, pendingItems),
                          ),
                        ],
                      ),
                      if (showAlternatives && itemAlternatives[item['id']] != null) ...[
                        ...itemAlternatives[item['id']]!.map((alt) => RadioListTile<String>(
                          title: Text(alt['alternative_name'], style: const TextStyle(fontSize: 12)),
                          // ignore: deprecated_member_use
                          value: alt['alternative_name'],
                          // ignore: deprecated_member_use
                          groupValue: selectedAltName[item['id']],
                          // ignore: deprecated_member_use
                          onChanged: (val) async {
                            if (val != null) {
                              setDialogState(() => selectedAltName[item['id']] = val);
                              final bool ok = await _showConfirmPurchaseDialog(
                                item, 
                                altSelection: AlternativeSelection(
                                  name: alt['alternative_name'],
                                  price: double.tryParse(alt['price_estimate']?.toString() ?? '0') ?? 0.0,
                                  quantity: int.tryParse(alt['quantity']?.toString() ?? '1') ?? 1,
                                ),
                              );
                              if (!ok) {
                                setDialogState(() => selectedAltName[item['id']] = null);
                              } else {
                                setDialogState(() {});
                              }
                            }
                          },
                        )),
                      ],
                      const Divider(),
                    ],
                  );
                },
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
              ElevatedButton(
                onPressed: () async {
                  await _apiService.finalizeShopping(widget.roomId);
                  if (context.mounted) Navigator.pop(context);
                  _fetchItems();
                },
                child: const Text('Complete Purchase'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _updateItemStatusInDialog(int itemId, String status, StateSetter setDialogState, List<dynamic> pendingItems) async {
    try {
      await _apiService.updateItemPurchaseStatus(itemId, status: status);
      setDialogState(() {
        final index = pendingItems.indexWhere((i) => i['id'] == itemId);
        if (index != -1) pendingItems[index]['status'] = status;
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _closeRoom() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Wipe Room?'),
        content: const Text('This will PERMANENTLY delete all items. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Wipe & Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _apiService.closeRoom(widget.roomId);
        if (mounted) Navigator.pop(context);
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  void _showSetBudgetDialog() {
    final budgetController = TextEditingController(text: _budgetStatus?['totalBudget'].toString());
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Set Room Budget'),
        content: TextField(
          controller: budgetController,
          decoration: const InputDecoration(labelText: 'Budget Amount (\$)'),
          keyboardType: TextInputType.number,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final budget = double.tryParse(budgetController.text) ?? 0;
              await _apiService.setRoomBudget(widget.roomId, budget);
              if (context.mounted) Navigator.pop(context);
              _fetchItems();
            },
            child: const Text('Set'),
          ),
        ],
      ),
    );
  }


  void _showAddItemDialog() {
    int selectedPriority = 1;
    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Add Item'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(controller: _itemController, decoration: const InputDecoration(labelText: 'Item Name *', border: OutlineInputBorder()), autofocus: true),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: TextField(controller: _quantityController, decoration: const InputDecoration(labelText: 'Qty', border: OutlineInputBorder(), hintText: '1'), keyboardType: TextInputType.number)),
                      const SizedBox(width: 12),
                      Expanded(child: TextField(controller: _priceController, decoration: const InputDecoration(labelText: 'Price (\$)', border: OutlineInputBorder(), hintText: '0.00'), keyboardType: const TextInputType.numberWithOptions(decimal: true))),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text('Alternatives (Optional)', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  _buildAltField(_alt1Controller, _alt1QtyController, _alt1PriceController, 'Alt 1'),
                  const SizedBox(height: 8),
                  _buildAltField(_alt2Controller, _alt2QtyController, _alt2PriceController, 'Alt 2'),
                  const SizedBox(height: 8),
                  _buildAltField(_alt3Controller, _alt3QtyController, _alt3PriceController, 'Alt 3'),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<int>(
                    initialValue: selectedPriority,
                    decoration: const InputDecoration(labelText: 'Priority', border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(value: 3, child: Text('High')),
                      DropdownMenuItem(value: 2, child: Text('Medium')),
                      DropdownMenuItem(value: 1, child: Text('Low')),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setDialogState(() {
                          selectedPriority = val;
                        });
                      }
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
              ElevatedButton(onPressed: () => _addItem(dialogContext, priority: selectedPriority), child: const Text('Add Item')),
            ],
          );
        }
      ),
    );
  }

  Widget _buildAltField(TextEditingController nameCtrl, TextEditingController qtyCtrl, TextEditingController priceCtrl, String label) {
    return Row(
      children: [
        Expanded(flex: 2, child: TextField(controller: nameCtrl, decoration: InputDecoration(hintText: '$label name', isDense: true, border: const OutlineInputBorder()))),
        const SizedBox(width: 4),
        Expanded(flex: 1, child: TextField(controller: qtyCtrl, decoration: const InputDecoration(hintText: 'Qty', isDense: true, border: OutlineInputBorder()), keyboardType: TextInputType.number)),
        const SizedBox(width: 4),
        Expanded(flex: 1, child: TextField(controller: priceCtrl, decoration: const InputDecoration(hintText: 'Price (\$)', isDense: true, border: OutlineInputBorder()), keyboardType: const TextInputType.numberWithOptions(decimal: true))),
      ],
    );
  }

  Widget _buildItemCard(Map<String, dynamic> item) {
    final bool isExpanded = _expandedItems[item['id']] ?? false;
    final bool isBought = item['is_bought'] ?? false;
    final priority = item['priority'] ?? 1;

    // Priority config
    Color priorityColor;
    Color priorityBg;
    String priorityText;
    IconData priorityIcon;
    if (priority >= 3) {
      priorityColor = const Color(0xFFE53935);
      priorityBg = const Color(0xFFFFEBEE);
      priorityText = 'High';
      priorityIcon = Icons.priority_high_rounded;
    } else if (priority == 2) {
      priorityColor = const Color(0xFFF57C00);
      priorityBg = const Color(0xFFFFF3E0);
      priorityText = 'Medium';
      priorityIcon = Icons.remove_rounded;
    } else {
      priorityColor = const Color(0xFF1D5DE4);
      priorityBg = const Color(0xFFE8EDFB);
      priorityText = 'Low';
      priorityIcon = Icons.arrow_downward_rounded;
    }

    final String addedByName = item['added_by_name'] ?? 'A user';
    final String initials = addedByName.isNotEmpty ? addedByName[0].toUpperCase() : '?';
    final bool canDelete = item['added_by'] == FirebaseAuth.instance.currentUser?.uid ||
        _roomOwner == FirebaseAuth.instance.currentUser?.uid;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isBought ? Colors.green.shade200 : Colors.grey.shade200,
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => setState(() => _expandedItems[item['id']] = !isExpanded),
          borderRadius: BorderRadius.circular(16),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    // Left accent indicator
                    Container(
                      width: 4,
                      height: 48,
                      decoration: BoxDecoration(
                        color: isBought ? Colors.green : priorityColor,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Main content
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  item['name'],
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: isBought ? Colors.grey.shade500 : const Color(0xFF0F264D),
                                    decoration: isBought ? TextDecoration.lineThrough : null,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (canDelete)
                                InkWell(
                                  onTap: () => _confirmDeleteItem(item['id'], item['name']),
                                  borderRadius: BorderRadius.circular(8),
                                  child: Padding(
                                    padding: const EdgeInsets.all(4),
                                    child: Icon(Icons.delete_outline_rounded, color: Colors.red.shade300, size: 18),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              // Priority badge
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: priorityBg,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(priorityIcon, size: 11, color: priorityColor),
                                    const SizedBox(width: 3),
                                    Text(
                                      priorityText,
                                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: priorityColor),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              // Added by
                              CircleAvatar(
                                radius: 10,
                                backgroundColor: const Color(0xFF1D5DE4).withValues(alpha: 0.15),
                                child: Text(initials, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFF1D5DE4))),
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  addedByName,
                                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Right side: Qty + Price + expand
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8F9FB),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'x${item['quantity']}',
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF0F264D)),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          item['price_estimate'] != null && item['price_estimate'].toString() != '0'
                              ? '\$${item['price_estimate']}'
                              : 'No price',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade500,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Icon(
                          isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                          color: Colors.grey.shade400,
                          size: 20,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (isExpanded) ..._buildExpandedSection(item),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildExpandedSection(Map<String, dynamic> item) {
    return [
      const Divider(height: 1, indent: 16, endIndent: 16),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Info row
            Row(
              children: [
                _buildInfoChip(Icons.attach_money_rounded, 'Est. Price', '\$${item['price_estimate'] ?? '—'}'),
                const SizedBox(width: 8),
                if (item['status'] != null && item['status'] != 'pending')
                  _buildInfoChip(Icons.info_outline_rounded, 'Status', item['status'].toString().toUpperCase(), statusColor: _getStatusColor(item['status'])),
              ],
            ),
            const SizedBox(height: 14),
            // Shopping action button
            if (_isShopping)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: Icon(
                    item['is_bought'] == true ? Icons.check_circle_rounded : Icons.shopping_bag_outlined,
                    size: 18,
                  ),
                  label: Text(
                    item['is_bought'] == true ? 'Marked as Purchased ✓' : 'Mark as Bought',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: item['is_bought'] == true ? Colors.green.shade600 : const Color(0xFF0F264D),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  onPressed: () => _toggleItemPurchase(item['id'], item['is_bought'] ?? false),
                ),
              ),
            if (_isShopping) const SizedBox(height: 14),
            // Alternatives
            FutureBuilder<List<dynamic>>(
              future: _apiService.getItemAlternatives(item['id']),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: LinearProgressIndicator(minHeight: 2),
                  );
                }
                if (snapshot.hasError || !snapshot.hasData || snapshot.data!.isEmpty) {
                  return const SizedBox.shrink();
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.compare_arrows_rounded, size: 14, color: Colors.grey.shade500),
                        const SizedBox(width: 4),
                        Text('Alternatives', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.grey.shade600, letterSpacing: 0.5)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ...snapshot.data!.map((alt) => Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8F9FB),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              '${alt['alternative_name']} (x${alt['quantity']})',
                              style: const TextStyle(fontSize: 13, color: Color(0xFF0F264D)),
                            ),
                          ),
                          Text(
                            '\$${alt['price_estimate']}',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF1D5DE4)),
                          ),
                        ],
                      ),
                    )),
                    const SizedBox(height: 6),
                  ],
                );
              },
            ),
            // Confidence Score
            FutureBuilder<Map<String, dynamic>>(
              future: _apiService.getProductConfidence(
                item['name'],
                double.tryParse(item['price_estimate']?.toString() ?? '0') ?? 0.0,
              ),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: LinearProgressIndicator(minHeight: 2),
                  );
                }
                if (snapshot.hasError || !snapshot.hasData) return const SizedBox.shrink();
                final data = snapshot.data!;
                return ConfidenceScoreWidget(
                  productName: item['name'] ?? 'Unknown',
                  proposedPrice: double.tryParse(item['price_estimate']?.toString() ?? '0') ?? 0.0,
                  initialScore: data['score'] ?? 50,
                  initialBreakdown: data['breakdown'] ?? {},
                );
              },
            ),
          ],
        ),
      ),
    ];
  }

  Widget _buildInfoChip(IconData icon, String label, String value, {Color? statusColor}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFF8F9FB),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(icon, size: 14, color: statusColor ?? Colors.grey.shade500),
            const SizedBox(width: 6),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: statusColor ?? const Color(0xFF0F264D))),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color _getStatusColor(String? status) {
    switch (status) {
      case 'unavailable': return Colors.red;
      case 'out_of_budget': return Colors.orange;
      case 'replaced': return Colors.blue;
      case 'purchased': return Colors.green;
      default: return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final bool isOwner = _roomOwner == user?.uid;
    final bool budgetSet = _budgetStatus != null && (_budgetStatus!['totalBudget'] ?? 0) > 0;
    final bool budgetExceeded = _budgetStatus?['budgetExceeded'] == true;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FB),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F264D),
        foregroundColor: Colors.white,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.roomName, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            Text(
              '$_participantCount members  ·  Code: ${widget.roomCode}',
              style: const TextStyle(fontSize: 11, color: Colors.white60),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_rounded),
            tooltip: 'Share Code',
            onPressed: () => showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                title: const Text('Room Code', textAlign: TextAlign.center),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEEF4FF),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        widget.roomCode,
                        style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold, letterSpacing: 10, color: Color(0xFF0F264D)),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text('Share this code with your team', style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
                  ],
                ),
                actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Done'))],
              ),
            ),
          ),
          if (isOwner) ...[
            if (_isShopping)
              TextButton(
                onPressed: _finalizeShopping,
                child: const Text('FINALIZE', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 13)),
              )
            else ...[
              IconButton(
                icon: const Icon(Icons.shopping_cart_checkout_rounded),
                onPressed: _startShopping,
                tooltip: 'Start Shopping',
              ),
              TextButton(
                onPressed: _finalizeShopping,
                child: const Text('CLOSE', style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 13)),
              ),
            ],
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              onSelected: (value) {
                if (value == 'complete') { _finalizeShopping(); }
                if (value == 'close') { _closeRoom(); }
                if (value == 'budget') { _showSetBudgetDialog(); }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'complete',
                  child: Row(children: [Icon(Icons.check_circle_outline_rounded, color: Colors.green, size: 18), SizedBox(width: 8), Text('Complete Room', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold))]),
                ),
                const PopupMenuItem(
                  value: 'budget',
                  child: Row(children: [Icon(Icons.account_balance_wallet_outlined, size: 18), SizedBox(width: 8), Text('Set Budget')])
                ),
                const PopupMenuItem(
                  value: 'close',
                  child: Row(children: [Icon(Icons.delete_forever_rounded, color: Colors.red, size: 18), SizedBox(width: 8), Text('Delete Room', style: TextStyle(color: Colors.red))]),
                ),
              ],
            ),
          ],
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddItemDialog,
        backgroundColor: const Color(0xFF1D5DE4),
        icon: const Icon(Icons.add_shopping_cart_rounded, color: Colors.white),
        label: const Text('Add Item', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        elevation: 4,
      ),
      body: Column(
        children: [
          // === STATUS HEADER STRIP ===
          if (_roomStatus == 'shopping' || budgetSet)
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: Row(
                children: [
                  if (_roomStatus == 'shopping') ...
                    [
                      FadeTransition(
                        opacity: _pulseAnimation,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.orange.shade200),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.shopping_cart_rounded, color: Colors.orange, size: 13),
                              SizedBox(width: 6),
                              Text('SHOPPING MODE', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange, fontSize: 11)),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                  if (_isShopping) ...
                    [
                      Icon(Icons.receipt_long_rounded, size: 14, color: Colors.green.shade700),
                      const SizedBox(width: 4),
                      Text(
                        'Total: \$${_calculateTotalPurchased().toStringAsFixed(2)}',
                        style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green.shade700, fontSize: 13),
                      ),
                      const SizedBox(width: 8),
                    ],
                  if (budgetSet) ...
                    [
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: budgetExceeded ? Colors.red.shade50 : Colors.green.shade50,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: budgetExceeded ? Colors.red.shade200 : Colors.green.shade200),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              budgetExceeded ? Icons.warning_rounded : Icons.account_balance_wallet_rounded,
                              size: 13,
                              color: budgetExceeded ? Colors.red : Colors.green.shade700,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              '\$${_budgetStatus!['currentTotal']} / \$${_budgetStatus!['totalBudget']}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                                color: budgetExceeded ? Colors.red.shade700 : Colors.green.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                ],
              ),
            ),
          const Divider(height: 1, color: Color(0xFFEEEEEE)),
          // === ITEMS LIST ===
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _fetchItems,
                    child: _items.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.shopping_basket_outlined, size: 72, color: Colors.grey.shade300),
                                const SizedBox(height: 16),
                                Text('No items yet', style: TextStyle(fontSize: 18, color: Colors.grey.shade500, fontWeight: FontWeight.w600)),
                                const SizedBox(height: 8),
                                Text('Tap the button below to add your first item.', style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
                              ],
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(0, 12, 0, 100),
                            itemCount: _items.length,
                            itemBuilder: (context, index) => _buildItemCard(_items[index]),
                          ),
                  ),
          ),
        ],
      ),
    );
  }
}
