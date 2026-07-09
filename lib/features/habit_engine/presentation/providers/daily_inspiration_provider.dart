import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/entities/daily_inspiration.dart';
import 'habit_provider.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

final dailyInspirationProvider = FutureProvider<DailyInspiration>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  
  final fallback = DailyInspiration(
    id: 1,
    verse: '“For I know the plans I have for you,” declares the Lord, “plans to prosper you and not to harm you, plans to give you hope and a future.”',
    reference: 'Jeremiah 29:11',
    confessions: [
      'I am focused, disciplined, and in control of my habits.',
      'Every small step I take today leads to massive growth tomorrow.',
      'I choose progress over perfection and consistency over intensity.',
    ],
  );

  try {
    final response = await client
        .from('daily_inspirations')
        .select()
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();

    if (response != null) {
      return DailyInspiration.fromJson(response as Map<String, dynamic>);
    }
  } catch (_) {
    // Graceful fallback to static data when offline/unseeded
  }
  return fallback;
});

class DailyInspirationStatusNotifier extends Notifier<bool> {
  @override
  bool build() {
    final storage = ref.watch(storageServiceProvider);
    
    // Check if the currently loaded inspiration ID matches the cached last completed ID
    final inspirationAsync = ref.watch(dailyInspirationProvider);
    return inspirationAsync.when(
      data: (inspiration) {
        final lastReadId = storage.settingsBox.get('last_inspiration_read_id') as int?;
        return lastReadId == inspiration.id;
      },
      error: (_, __) => false,
      loading: () => false,
    );
  }

  Future<void> markAsRead(DailyInspiration inspiration) async {
    final storage = ref.read(storageServiceProvider);
    await storage.settingsBox.put('last_inspiration_read_id', inspiration.id);
    state = true;

    await ref.read(habitLogsProvider.notifier).addLog(
      'task_completed',
      {
        'title': 'Read Verse & Confessions',
        'verse': inspiration.verse,
        'reference': inspiration.reference,
        'inspiration_id': inspiration.id,
      },
    );
  }
}

final dailyInspirationStatusProvider = NotifierProvider<DailyInspirationStatusNotifier, bool>(
  DailyInspirationStatusNotifier.new,
);
