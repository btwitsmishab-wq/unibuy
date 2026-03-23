import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:flutter/foundation.dart' show debugPrint;
import '../config.dart';

class SocketService {
  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;
  SocketService._internal();

  io.Socket? _socket;
  final String _baseUrl = AppConfig.baseUrl;

  void connect() {
    if (_socket != null && _socket!.connected) return;

    _socket = io.io(_baseUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false,
    });

    _socket!.connect();

    _socket!.onConnect((_) {
      debugPrint('Connected to Socket.io server');
    });

    _socket!.onDisconnect((_) {
      debugPrint('Disconnected from Socket.io server');
    });

    _socket!.onConnectError((err) {
      debugPrint('Connection Error: $err');
    });

    _socket!.onError((err) {
      debugPrint('Socket Error: $err');
    });
  }

  void joinRoom(int roomId) {
    if (_socket == null || !_socket!.connected) {
      connect();
    }
    _socket?.emit('join_room', roomId);
    debugPrint('Joining room: room_$roomId');
  }

  void leaveRoom(int roomId) {
    _socket?.emit('leave_room', roomId);
    debugPrint('Leaving room: room_$roomId');
  }

  // --- PREVENT LISTENER CONFLICTS ACROSS SCREENS ---
  final Map<String, dynamic Function(dynamic)> _itemsHandlers = {};
  final Map<String, dynamic Function(dynamic)> _roomStatusHandlers = {};
  final Map<String, dynamic Function(dynamic)> _scoreHandlers = {};
  final Map<String, dynamic Function(dynamic)> _notifHandlers = {};

  void onItemsUpdated(String listenerId, Function callback) {
    if (_itemsHandlers.containsKey(listenerId)) return;
    void handler(dynamic _) {
      debugPrint('Items updated event ($listenerId)');
      callback();
    }
    _itemsHandlers[listenerId] = handler;
    _socket?.on('items_updated', handler);
  }

  void offItemsUpdated(String listenerId) {
    final handler = _itemsHandlers.remove(listenerId);
    if (handler != null) _socket?.off('items_updated', handler);
  }

  void onRoomStatusUpdated(String listenerId, Function(Map<String, dynamic>) callback) {
    if (_roomStatusHandlers.containsKey(listenerId)) return;
    void handler(dynamic data) {
      debugPrint('Room status updated ($listenerId): $data');
      callback(Map<String, dynamic>.from(data));
    }
    _roomStatusHandlers[listenerId] = handler;
    _socket?.on('room_status_updated', handler);
  }

  void offRoomStatusUpdated(String listenerId) {
    final handler = _roomStatusHandlers.remove(listenerId);
    if (handler != null) _socket?.off('room_status_updated', handler);
  }

  // --- CONFIDENCE SCORE EVENTS ---
  void onProductScoreUpdated(String listenerId, Function(dynamic) callback) {
    if (_scoreHandlers.containsKey(listenerId)) return;
    void handler(dynamic data) => callback(data);
    _scoreHandlers[listenerId] = handler;
    _socket?.on('product_score_updated', handler);
  }

  void offProductScoreUpdated(String listenerId) {
    final handler = _scoreHandlers.remove(listenerId);
    if (handler != null) _socket?.off('product_score_updated', handler);
  }

  // --- NOTIFICATION EVENTS ---
  void onNewNotification(String listenerId, String userId, Function(Map<String, dynamic>) callback) {
    if (_notifHandlers.containsKey(listenerId)) return;
    void handler(dynamic data) {
      debugPrint('New notification ($listenerId): $data');
      callback(Map<String, dynamic>.from(data));
    }
    _notifHandlers[listenerId] = handler;
    _socket?.on('notification_$userId', handler);
  }

  void offNewNotification(String listenerId, String userId) {
    final handler = _notifHandlers.remove(listenerId);
    if (handler != null) _socket?.off('notification_$userId', handler);
  }

  void disconnect() {
    _socket?.disconnect();
    _socket = null;
  }
}
