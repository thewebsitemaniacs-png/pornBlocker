import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';

class StorageService {
  final _secureStorage = const FlutterSecureStorage();
  late Box<Map> _tasksBox;
  late Box<Map> _logsBox;
  late Box<dynamic> _settingsBox;

  Future<void> init() async {
    await Hive.initFlutter();

    // Check if we have an existing encryption key in secure storage
    final encryptionKeyString = await _secureStorage.read(key: 'hive_encryption_key');
    List<int> encryptionKey;

    if (encryptionKeyString == null) {
      // Generate a new 256-bit AES key and save it securely
      final key = Hive.generateSecureKey();
      await _secureStorage.write(
        key: 'hive_encryption_key',
        value: base64UrlEncode(key),
      );
      encryptionKey = key;
    } else {
      encryptionKey = base64Url.decode(encryptionKeyString);
    }

    // Open Hive boxes with standard AES encryption
    _tasksBox = await Hive.openBox<Map>(
      'habit_tasks_encrypted',
      encryptionCipher: HiveAesCipher(encryptionKey),
    );
    _logsBox = await Hive.openBox<Map>(
      'habit_logs_encrypted',
      encryptionCipher: HiveAesCipher(encryptionKey),
    );
    _settingsBox = await Hive.openBox(
      'app_settings_encrypted',
      encryptionCipher: HiveAesCipher(encryptionKey),
    );
  }

  Box<Map> get tasksBox => _tasksBox;
  Box<Map> get logsBox => _logsBox;
  Box<dynamic> get settingsBox => _settingsBox;
}
