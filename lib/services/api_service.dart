import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import '../config.dart';

class ApiService {
  // Uses the centralized config for smooth deployments
  static final String baseUrl = '${AppConfig.baseUrl}/api';

  Future<Map<String, String>> _getHeaders() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('User not logged in');
    
    final idToken = await user.getIdToken();
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $idToken',
      'x-user-uid': user.uid, // Fallback for local dev without service account
    };
  }

  // Categories
  Future<List<dynamic>> getCategories() async {
    final response = await http.get(Uri.parse('$baseUrl/categories'));
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to load categories');
    }
  }

  // Rooms
  Future<Map<String, dynamic>> createRoom(String name, int categoryId) async {
    final user = FirebaseAuth.instance.currentUser;
    final headers = await _getHeaders();
    
    final response = await http.post(
      Uri.parse('$baseUrl/rooms'),
      headers: headers,
      body: json.encode({
        'name': name,
        'category_id': categoryId,
        'fire_base_uid': user!.uid,
      }),
    );

    if (response.statusCode == 201) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to create room: ${response.body}');
    }
  }

  Future<List<dynamic>> getUserRooms() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return [];

    final response = await http.get(
      Uri.parse('$baseUrl/rooms?fire_base_uid=${user.uid}'),
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to load rooms');
    }
  }

  Future<void> joinRoom(String roomCode) async {
    final user = FirebaseAuth.instance.currentUser;
    final headers = await _getHeaders();

    final response = await http.post(
      Uri.parse('$baseUrl/rooms/join'),
      headers: headers,
      body: json.encode({
        'room_code': roomCode,
        'fire_base_uid': user!.uid,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to join room: ${response.body}');
    }
  }

  Future<void> deleteRoom(int roomId) async {
    final user = FirebaseAuth.instance.currentUser;
    final response = await http.delete(
      Uri.parse('$baseUrl/rooms/$roomId?fire_base_uid=${user!.uid}'),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to delete room');
    }
  }

  // Items
  Future<Map<String, dynamic>> getRoomItems(int roomId) async {
    final response = await http.get(Uri.parse('$baseUrl/rooms/$roomId/items'));
    if (response.statusCode == 200) {
      return json.decode(response.body); // Returns {items: [], roomOwner: "...", budgetStatus: {...}}
    } else {
      throw Exception('Failed to load items');
    }
  }

  Future<Map<String, dynamic>> addItem({
    required int roomId,
    required String name,
    int quantity = 1,
    int priority = 1,
    int urgencyLevel = 1,
    double priceEstimate = 0,
    String? userName,
    List<Map<String, dynamic>>? alternatives,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    final headers = await _getHeaders();

    final response = await http.post(
      Uri.parse('$baseUrl/items'),
      headers: headers,
      body: json.encode({
        'room_id': roomId,
        'name': name,
        'quantity': quantity,
        'priority': priority,
        'urgency_level': urgencyLevel,
        'price_estimate': priceEstimate,
        'added_by': user!.uid,
        'user_name': userName ?? user.displayName,
        'alternatives': alternatives ?? [],
      }),
    );

    if (response.statusCode == 201) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to add item: ${response.body}');
    }
  }

  Future<Map<String, dynamic>> updateItemQuantity(int itemId, int quantity) async {
    final headers = await _getHeaders();
    final response = await http.put(
      Uri.parse('$baseUrl/items/$itemId'),
      headers: headers,
      body: json.encode({'quantity': quantity}),
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to update quantity');
    }
  }

  Future<void> toggleItemStatus(int itemId, bool isBought) async {
    final headers = await _getHeaders();
    final response = await http.patch(
      Uri.parse('$baseUrl/items/$itemId'),
      headers: headers,
      body: json.encode({'is_bought': isBought}),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to update item status');
    }
  }

  Future<Map<String, dynamic>> getBudgetStatus(int roomId) async {
    final response = await http.get(Uri.parse('$baseUrl/rooms/$roomId/budget'));
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to load budget status');
    }
  }

  Future<void> setRoomBudget(int roomId, double budget) async {
    final headers = await _getHeaders();
    final response = await http.post(
      Uri.parse('$baseUrl/rooms/$roomId/budget'),
      headers: headers,
      body: json.encode({'total_budget': budget}),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to set budget');
    }
  }

  Future<void> deleteItem(int itemId) async {
    final headers = await _getHeaders();
    final response = await http.delete(
      Uri.parse('$baseUrl/items/$itemId'),
      headers: headers,
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to delete item');
    }
  }

  // Notifications
  Future<List<dynamic>> getNotifications() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return [];

    final response = await http.get(
      Uri.parse('$baseUrl/notifications?fire_base_uid=${user.uid}'),
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to load notifications');
    }
  }

  Future<void> markNotificationAsRead(int notificationId) async {
    final headers = await _getHeaders();
    final response = await http.put(
      Uri.parse('$baseUrl/notifications/$notificationId/read'),
      headers: headers,
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to mark notification as read');
    }
  }

  Future<void> clearNotifications() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final headers = await _getHeaders();
    final response = await http.delete(
      Uri.parse('$baseUrl/notifications?fire_base_uid=${user.uid}'),
      headers: headers,
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to clear notifications');
    }
  }

  // Alternatives & Decisions (Module 5)
  Future<Map<String, dynamic>> getProductConfidence(String productName, double proposedPrice) async {
    final headers = await _getHeaders();
    final response = await http.post(
      Uri.parse('$baseUrl/products/confidence'),
      headers: headers,
      body: json.encode({
        'product_name': productName,
        'proposed_price': proposedPrice,
      }),
    );
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to load product confidence');
    }
  }

  Future<void> interactWithProduct(String productName, {String? review, double? voteVal}) async {
    final headers = await _getHeaders();
    final response = await http.post(
      Uri.parse('$baseUrl/products/interact'),
      headers: headers,
      body: json.encode({
        'product_name': productName,
        'new_review': review,
        'vote_val': voteVal,
      }),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to interact with product');
    }
  }

  Future<List<dynamic>> getItemAlternatives(int itemId) async {
    final response = await http.get(Uri.parse('$baseUrl/items/$itemId/alternatives'));
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to load alternatives');
    }
  }

  Future<void> updateItemStatus(int itemId, String status) async {
    final headers = await _getHeaders();
    final response = await http.patch(
      Uri.parse('$baseUrl/items/$itemId/status'),
      headers: headers,
      body: json.encode({'status': status}),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to update status');
    }
  }

  Future<void> recordDecision({
    required int itemId,
    required String selectedOption,
    required String decisionType,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    final headers = await _getHeaders();
    final response = await http.post(
      Uri.parse('$baseUrl/items/$itemId/decision'),
      headers: headers,
      body: json.encode({
        'selected_option': selectedOption,
        'decision_type': decisionType,
        'decided_by': user!.uid,
      }),
    );
    if (response.statusCode != 201) {
      throw Exception('Failed to record decision');
    }
  }

  // Specialized Module 5 Endpoints
  Future<Map<String, dynamic>> markItemUnavailable(int itemId) async {
    final response = await http.post(Uri.parse('$baseUrl/items/$itemId/unavailable'));
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to mark item unavailable');
    }
  }

  Future<void> selectAlternative(int itemId, String altName, double price, {double? purchasedPrice, int? purchasedQuantity}) async {
    final user = FirebaseAuth.instance.currentUser;
    final headers = await _getHeaders();
    final response = await http.post(
      Uri.parse('$baseUrl/items/$itemId/select-alternative'),
      headers: headers,
      body: json.encode({
        'alternative_name': altName,
        'price_estimate': price,
        'purchased_price': purchasedPrice,
        'purchased_quantity': purchasedQuantity,
        'decided_by': user!.uid,
      }),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to select alternative');
    }
  }

  Future<Map<String, dynamic>> autoSelectAlternative(int itemId) async {
    final response = await http.put(Uri.parse('$baseUrl/items/$itemId/auto-select'));
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed auto-selection');
    }
  }

  // Module 6: Purchase Finalization & Confidence Evaluation

  Future<Map<String, dynamic>> initiatePurchase(int roomId) async {
    final user = FirebaseAuth.instance.currentUser;
    final headers = await _getHeaders();
    final response = await http.post(
      Uri.parse('$baseUrl/rooms/$roomId/purchase'),
      headers: headers,
      body: json.encode({'finalizer_user_id': user!.uid}),
    );
    if (response.statusCode == 201) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to initiate purchase');
    }
  }

  Future<Map<String, dynamic>> approveOrRejectPurchase(int purchaseId, String decision) async {
    final user = FirebaseAuth.instance.currentUser;
    final headers = await _getHeaders();
    final response = await http.patch(
      Uri.parse('$baseUrl/purchases/$purchaseId/approve'),
      headers: headers,
      body: json.encode({'user_id': user!.uid, 'decision': decision}),
    );
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to process approval');
    }
  }

  Future<int> getRoomConfidence(int roomId) async {
    final response = await http.get(Uri.parse('$baseUrl/rooms/$roomId/confidence'));
    if (response.statusCode == 200) {
      return json.decode(response.body)['confidence_score'];
    } else {
      return 0;
    }
  }

  Future<Map<String, dynamic>> getPurchase(int purchaseId) async {
    final response = await http.get(Uri.parse('$baseUrl/purchases/$purchaseId'));
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Purchase not found');
    }
  }

  Future<Map<String, dynamic>> generatePurchaseSummary(int purchaseId) async {
    final headers = await _getHeaders();
    final response = await http.post(
      Uri.parse('$baseUrl/purchases/$purchaseId/summary'),
      headers: headers,
    );
    if (response.statusCode == 201) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to generate summary');
    }
  }

  // Shopping Mode
  Future<void> startShopping(int roomId) async {
    final headers = await _getHeaders();
    final response = await http.post(
      Uri.parse('$baseUrl/rooms/$roomId/start-shopping'),
      headers: headers,
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to start shopping: ${response.body}');
    }
  }

  Future<void> finalizeShopping(int roomId) async {
    final headers = await _getHeaders();
    final response = await http.post(
      Uri.parse('$baseUrl/rooms/$roomId/finalize-shopping'),
      headers: headers,
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to finalize shopping: ${response.body}');
    }
  }

  Future<void> closeRoom(int roomId) async {
    final headers = await _getHeaders();
    final response = await http.post(
      Uri.parse('$baseUrl/rooms/$roomId/close'),
      headers: headers,
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to close room: ${response.body}');
    }
  }

  Future<void> updateItemPurchaseStatus(int itemId, {bool? isBought, String? status, double? purchasedPrice, int? purchasedQuantity}) async {
    final headers = await _getHeaders();
    final Map<String, dynamic> requestBody = {};
    if (isBought != null) requestBody['is_bought'] = isBought;
    if (status != null) requestBody['status'] = status;
    if (purchasedPrice != null) requestBody['purchased_price'] = purchasedPrice;
    if (purchasedQuantity != null) requestBody['purchased_quantity'] = purchasedQuantity;

    final response = await http.patch(
      Uri.parse('$baseUrl/items/$itemId'),
      headers: headers,
      body: json.encode(requestBody),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to update item status: ${response.body}');
    }
  }
}
