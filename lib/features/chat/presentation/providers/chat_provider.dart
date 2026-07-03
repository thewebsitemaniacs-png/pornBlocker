import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../auth/domain/entities/user_profile.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../domain/entities/chat_message.dart';

final supportersListProvider = FutureProvider<List<UserProfile>>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  
  final response = await client
      .from('profiles')
      .select()
      .eq('is_supporter', true);

  return (response as List)
      .map((e) => UserProfile.fromJson(Map<String, dynamic>.from(e)))
      .toList();
});

final activeChatsProvider = FutureProvider<List<UserProfile>>((ref) async {
  // Watch unread counts to trigger refresh whenever polling updates counts
  ref.watch(unreadCountsProvider);

  final client = ref.watch(supabaseClientProvider);
  final authState = ref.watch(authProvider);
  final currentUserId = authState.user?.id;
  if (currentUserId == null) {
    return [];
  }

  try {
    final response = await client
        .from('chat_messages')
        .select('sender_id, recipient_id')
        .or('sender_id.eq.$currentUserId,recipient_id.eq.$currentUserId');

    if (response == null) {
      return [];
    }

    final uniqueIds = <String>{};
    for (final item in response as List) {
      if (item == null) continue;
      final sId = item['sender_id'] as String?;
      final rId = item['recipient_id'] as String?;
      if (sId != null && sId != currentUserId) uniqueIds.add(sId);
      if (rId != null && rId != currentUserId) uniqueIds.add(rId);
    }

    if (uniqueIds.isEmpty) return [];

    final profilesResponse = await client
        .from('profiles')
        .select()
        .in_('id', uniqueIds.toList());

    if (profilesResponse == null) {
      return [];
    }

    return (profilesResponse as List)
        .map((e) {
          if (e == null) return null;
          try {
            return UserProfile.fromJson(Map<String, dynamic>.from(e));
          } catch (_) {
            return null;
          }
        })
        .whereType<UserProfile>()
        .toList();
  } catch (e) {
    return [];
  }
});

class UnreadCountsNotifier extends Notifier<Map<String, int>> {
  @override
  Map<String, int> build() {
    final client = ref.watch(supabaseClientProvider);
    final authState = ref.watch(authProvider);
    final currentUserId = authState.user?.id;
    if (currentUserId == null) return {};

    void poll() async {
      try {
        final response = await client
            .from('chat_messages')
            .select('sender_id')
            .eq('recipient_id', currentUserId)
            .eq('is_read', false);

        if (response == null) return;

        final counts = <String, int>{};
        for (final item in response as List) {
          if (item == null) continue;
          final senderId = item['sender_id'] as String?;
          if (senderId != null) {
            counts[senderId] = (counts[senderId] ?? 0) + 1;
          }
        }
        state = counts;
      } catch (_) {}
    }

    poll();

    final timer = Timer.periodic(const Duration(seconds: 3), (t) => poll());

    ref.onDispose(() {
      timer.cancel();
    });

    return {};
  }
}

final unreadCountsProvider = NotifierProvider<UnreadCountsNotifier, Map<String, int>>(() {
  return UnreadCountsNotifier();
});

class ChatMessagesNotifier extends Notifier<List<ChatMessage>> {
  final String partnerId;
  Timer? _pollingTimer;

  ChatMessagesNotifier(this.partnerId);

  @override
  List<ChatMessage> build() {
    _fetchMessages();
    _markAsRead();
    _startPolling();

    ref.onDispose(() {
      _pollingTimer?.cancel();
    });

    return [];
  }

  void _startPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _fetchMessages();
    });
  }

  Future<void> _markAsRead() async {
    final client = ref.read(supabaseClientProvider);
    final authState = ref.read(authProvider);
    final currentUserId = authState.user?.id;
    if (currentUserId == null) return;

    try {
      await client
          .from('chat_messages')
          .update({'is_read': true})
          .eq('sender_id', partnerId)
          .eq('recipient_id', currentUserId)
          .eq('is_read', false);
      ref.invalidate(unreadCountsProvider);
    } catch (_) {}
  }

  Future<void> _fetchMessages() async {
    final client = ref.read(supabaseClientProvider);
    final authState = ref.read(authProvider);
    final currentUserId = authState.user?.id;
    if (currentUserId == null) return;

    try {
      final response = await client
          .from('chat_messages')
          .select()
          .or('and(sender_id.eq.$currentUserId,recipient_id.eq.$partnerId),and(sender_id.eq.$partnerId,recipient_id.eq.$currentUserId)')
          .order('created_at', ascending: true);

      if (response == null) return;

      final fetchedMessages = (response as List)
          .map((e) {
            if (e == null) return null;
            try {
              return ChatMessage.fromJson(Map<String, dynamic>.from(e));
            } catch (_) {
              return null;
            }
          })
          .whereType<ChatMessage>()
          .toList();

      if (fetchedMessages.any((m) => m.senderId == partnerId && !m.isRead)) {
        await _markAsRead();
      }

      bool hasChanges = state.length != fetchedMessages.length;
      if (!hasChanges) {
        for (int i = 0; i < state.length; i++) {
          if (state[i].id != fetchedMessages[i].id || 
              state[i].isRead != fetchedMessages[i].isRead ||
              state[i].message != fetchedMessages[i].message) {
            hasChanges = true;
            break;
          }
        }
      }

      if (hasChanges) {
        state = fetchedMessages;
      }
    } catch (_) {}
  }

  Future<void> sendMessage(String text) async {
    final client = ref.read(supabaseClientProvider);
    final authState = ref.read(authProvider);
    final currentUserId = authState.user?.id;
    if (currentUserId == null) return;

    final tempId = DateTime.now().millisecondsSinceEpoch.toString();
    final tempMessage = ChatMessage(
      id: tempId,
      senderId: currentUserId,
      recipientId: partnerId,
      message: text,
      isRead: false,
      createdAt: DateTime.now(),
    );

    state = [...state, tempMessage];

    try {
      await client.from('chat_messages').insert({
        'sender_id': currentUserId,
        'recipient_id': partnerId,
        'message': text,
      });
      await _fetchMessages();
    } catch (e) {
      state = state.where((m) => m.id != tempId).toList();
    }
  }
}

final chatMessagesProvider = NotifierProvider.family<ChatMessagesNotifier, List<ChatMessage>, String>((partnerId) {
  return ChatMessagesNotifier(partnerId);
});
