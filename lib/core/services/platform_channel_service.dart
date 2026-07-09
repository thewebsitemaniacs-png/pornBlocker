import 'dart:async';
import 'package:flutter/services.dart';

class PlatformChannelService {
  static const MethodChannel _methodChannel = MethodChannel('com.joshua.flee.app/blocking');
  static const EventChannel _eventChannel = EventChannel('com.joshua.flee.app/blocking_events');

  StreamSubscription? _eventSubscription;

  Future<Map<String, bool>> checkPermissions() async {
    try {
      final Map? result = await _methodChannel.invokeMethod<Map>('checkPermissions');
      if (result != null) {
        return Map<String, bool>.from(result);
      }
      return {};
    } on PlatformException catch (_) {
      return {};
    }
  }

  Future<bool> requestPermissions(String type) async {
    try {
      final bool result = await _methodChannel.invokeMethod('requestPermissions', {'type': type});
      return result;
    } on PlatformException catch (_) {
      return false;
    }
  }

  Future<void> startBlocking() async {
    try {
      await _methodChannel.invokeMethod('startBlocking');
    } on PlatformException catch (_) {
      // Silently handled
    }
  }

  Future<void> stopBlocking() async {
    try {
      await _methodChannel.invokeMethod('stopBlocking');
    } on PlatformException catch (_) {
      // Silently handled
    }
  }

  Future<void> updateBlocklist(List<String> domains, List<String> keywords) async {
    try {
      await _methodChannel.invokeMethod('updateBlocklist', {
        'domains': domains,
        'keywords': keywords,
      });
    } on PlatformException catch (_) {
      // Silently handled
    }
  }

  Future<void> updateAppBlockingModes(List<String> excluded, List<String> textBoxOnly) async {
    try {
      await _methodChannel.invokeMethod('updateAppBlockingModes', {
        'excluded': excluded,
        'textBoxOnly': textBoxOnly,
      });
    } on PlatformException catch (_) {
      // Silently handled
    }
  }

  void startListeningToBlockingEvents(void Function(Map<String, dynamic> event) onEvent) {
    _eventSubscription?.cancel();
    _eventSubscription = _eventChannel.receiveBroadcastStream().listen((dynamic event) {
      if (event is Map) {
        onEvent(Map<String, dynamic>.from(event));
      }
    }, onError: (dynamic error) {
      // Silently handled
    });
  }

  void stopListeningToBlockingEvents() {
    _eventSubscription?.cancel();
    _eventSubscription = null;
  }
}
