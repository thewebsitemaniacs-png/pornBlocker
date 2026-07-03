import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../auth/domain/entities/user_profile.dart';
import '../providers/chat_provider.dart';
import 'chat_room_screen.dart';

class SupportersListScreen extends ConsumerWidget {
  const SupportersListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final supportersAsync = ref.watch(supportersListProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0F0E17),
      appBar: AppBar(
        title: const Text(
          'RECOVERY SUPPORTERS',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.5,
            color: Colors.white,
          ),
        ),
        centerTitle: true,
        backgroundColor: const Color(0xFF1F1E29),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: supportersAsync.when(
        data: (supporters) {
          if (supporters.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24.0),
                child: Text(
                  'No supporters are currently available. Check back soon.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFFA7A9BE), fontSize: 14),
                ),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: supporters.length,
            itemBuilder: (context, index) {
              final supporter = supporters[index];
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF1F1E29),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF2E2F3E)),
                ),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: const Color(0xFFFF8906).withOpacity(0.1),
                    child: const Icon(Icons.support_agent, color: Color(0xFFFF8906)),
                  ),
                  title: Text(
                    supporter.username,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                  subtitle: const Text(
                    'Verified Recovery Companion',
                    style: TextStyle(color: Color(0xFFA7A9BE), fontSize: 12),
                  ),
                  trailing: ElevatedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ChatRoomScreen(partner: supporter),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF8906),
                      foregroundColor: const Color(0xFF0F0E17),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('CHAT', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  ),
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator(color: Color(0xFFFF8906))),
        error: (err, _) => Center(
          child: Text('Error loading supporters: $err', style: const TextStyle(color: Colors.redAccent)),
        ),
      ),
    );
  }
}
