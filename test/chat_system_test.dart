import 'package:flutter_test/flutter_test.dart';
import 'package:habit_breaker/features/chat/domain/entities/chat_message.dart';

void main() {
  group('ChatMessage Serialization Tests', () {
    test('fromJson deserializes correctly', () {
      final now = DateTime.now();
      final json = {
        'id': 'msg_123',
        'sender_id': 'usr_abc',
        'recipient_id': 'usr_xyz',
        'message': 'Seek confession recovery help here.',
        'is_read': true,
        'created_at': now.toIso8601String(),
      };

      final msg = ChatMessage.fromJson(json);

      expect(msg.id, 'msg_123');
      expect(msg.senderId, 'usr_abc');
      expect(msg.recipientId, 'usr_xyz');
      expect(msg.message, 'Seek confession recovery help here.');
      expect(msg.isRead, isTrue);
      expect(msg.createdAt.difference(now).inMilliseconds.abs() < 1000, isTrue);
    });

    test('toJson serializes correctly', () {
      final now = DateTime.now();
      final msg = ChatMessage(
        id: 'msg_999',
        senderId: 'usr_me',
        recipientId: 'usr_supporter',
        message: 'Looking for a clean path forward.',
        isRead: false,
        createdAt: now,
      );

      final json = msg.toJson();

      expect(json['id'], 'msg_999');
      expect(json['sender_id'], 'usr_me');
      expect(json['recipient_id'], 'usr_supporter');
      expect(json['message'], 'Looking for a clean path forward.');
      expect(json['is_read'], isFalse);
      expect(json['created_at'], now.toIso8601String());
    });
  });
}
