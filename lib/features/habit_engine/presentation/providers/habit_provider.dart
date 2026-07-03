import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/services/storage_service.dart';
import '../../../../core/services/platform_channel_service.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../blocking/presentation/providers/bypass_guard_provider.dart';
import '../../data/repositories/hybrid_habit_repository.dart';
import '../../domain/entities/habit_task.dart';
import '../../domain/entities/habit_log.dart';
import '../../domain/repositories/habit_repository.dart';

// Storage service provider (overridden in main.dart once initialized)
final storageServiceProvider = Provider<StorageService>((ref) {
  throw UnimplementedError('StorageService must be overridden in Main');
});

// Repository provider
final habitRepositoryProvider = Provider<HabitRepository>((ref) {
  final storage = ref.watch(storageServiceProvider);
  final client = ref.watch(supabaseClientProvider);
  
  // Wire dynamic auth states into the repository callbacks
  final isPremium = ref.watch(authProvider.select((state) => state.profile?.isPremium ?? false));
  final userId = ref.watch(authProvider.select((state) => state.user?.id));

  return HybridHabitRepository(
    storageService: storage,
    supabaseClient: client,
    isPremiumCallback: () => isPremium,
    currentUserIdCallback: () => userId,
  );
});

// Tasks state notifier provider
class HabitTasksNotifier extends AsyncNotifier<List<HabitTask>> {
  @override
  Future<List<HabitTask>> build() async {
    final repo = ref.watch(habitRepositoryProvider);
    // Try to trigger background sync if user is logged in
    final userId = ref.read(authProvider.select((state) => state.user?.id));
    if (userId != null) {
      repo.syncWithCloud().then((_) => ref.invalidateSelf()).catchError((_) {});
    }
    return repo.getTasks();
  }

  Future<void> addTask(String title, String? description) async {
    final repo = ref.read(habitRepositoryProvider);
    final userId = ref.read(authProvider.select((state) => state.user?.id)) ?? 'local_user';
    
    final newTask = HabitTask(
      id: const Uuid().v4(),
      userId: userId,
      title: title,
      description: description,
      isCompleted: false,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await repo.saveTask(newTask);
      return repo.getTasks();
    });
  }

  Future<void> toggleTaskCompletion(String taskId) async {
    final repo = ref.read(habitRepositoryProvider);
    final currentTasks = state.value ?? [];
    final taskIndex = currentTasks.indexWhere((t) => t.id == taskId);
    if (taskIndex == -1) return;

    final targetTask = currentTasks[taskIndex];
    final updatedTask = targetTask.copyWith(
      isCompleted: !targetTask.isCompleted,
      completedAt: !targetTask.isCompleted ? DateTime.now() : null,
      updatedAt: DateTime.now(),
      synced: false,
    );

    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await repo.saveTask(updatedTask);
      return repo.getTasks();
    });
  }

  Future<void> deleteTask(String taskId) async {
    final repo = ref.read(habitRepositoryProvider);
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await repo.deleteTask(taskId);
      return repo.getTasks();
    });
  }

  Future<void> sync() async {
    final repo = ref.read(habitRepositoryProvider);
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await repo.syncWithCloud();
      return repo.getTasks();
    });
  }
}

final habitTasksProvider = AsyncNotifierProvider.autoDispose<HabitTasksNotifier, List<HabitTask>>(() {
  return HabitTasksNotifier();
});

// Logs state notifier provider
class HabitLogsNotifier extends AsyncNotifier<List<HabitLog>> {
  @override
  Future<List<HabitLog>> build() async {
    return ref.watch(habitRepositoryProvider).getLogs();
  }

  Future<void> addLog(String eventType, Map<String, dynamic> payload) async {
    final repo = ref.read(habitRepositoryProvider);
    final userId = ref.read(authProvider.select((state) => state.user?.id)) ?? 'local_user';

    final newLog = HabitLog(
      id: const Uuid().v4(),
      userId: userId,
      eventType: eventType,
      payload: payload,
      loggedAt: DateTime.now(),
    );

    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await repo.saveLog(newLog);
      return repo.getLogs();
    });
  }

  Future<void> sync() async {
    final repo = ref.read(habitRepositoryProvider);
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await repo.syncWithCloud();
      return repo.getLogs();
    });
  }
}

final habitLogsProvider = AsyncNotifierProvider.autoDispose<HabitLogsNotifier, List<HabitLog>>(() {
  return HabitLogsNotifier();
});

final platformChannelServiceProvider = Provider<PlatformChannelService>((ref) {
  final service = PlatformChannelService();
  
  // Listen to native blocking event streams
  service.startListeningToBlockingEvents((event) {
    if (event['type'] == 'accessibility_block') {
      ref.read(bypassGuardProvider.notifier).recordBlockTrigger();
      ref.read(habitLogsProvider.notifier).addLog(
        'block_triggered',
        {'title': event['message'] ?? 'Distracting on-screen element matched keyword rules.'},
      );
    }
  });

  ref.onDispose(() {
    service.stopListeningToBlockingEvents();
  });

  return service;
});

class BlocklistState {
  final List<String> domains;
  final List<String> keywords;
  final bool isLoading;

  BlocklistState({
    required this.domains,
    required this.keywords,
    this.isLoading = false,
  });

  BlocklistState copyWith({
    List<String>? domains,
    List<String>? keywords,
    bool? isLoading,
  }) {
    return BlocklistState(
      domains: domains ?? this.domains,
      keywords: keywords ?? this.keywords,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class BlocklistNotifier extends Notifier<BlocklistState> {
  static const List<String> _defaultDomains = ['youtube.com', 'instagram.com', 'tiktok.com', 'pornhub.com', 'xvideos.com'];
  static const List<String> _defaultKeywords = ['shorts', 'reels', 'doomscroll', 'porn', 'adult', 'xxx'];

  @override
  BlocklistState build() {
    final storage = ref.watch(storageServiceProvider);
    
    final List<dynamic>? cachedDomains = storage.settingsBox.get('cached_domains');
    final List<dynamic>? cachedKeywords = storage.settingsBox.get('cached_keywords');

    final domains = cachedDomains?.map((e) => e.toString()).toList() ?? _defaultDomains;
    final keywords = cachedKeywords?.map((e) => e.toString()).toList() ?? _defaultKeywords;

    // Setup periodic polling timer (fallback for free tier databases lacking replication)
    final pollTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      fetchAndSync();
    });

    ref.onDispose(() {
      pollTimer.cancel();
    });

    // Trigger initial non-blocking cloud fetch
    Future.microtask(() => fetchAndSync());

    return BlocklistState(domains: domains, keywords: keywords);
  }

  Future<void> fetchAndSync() async {
    if (!ref.mounted) return;
    state = state.copyWith(isLoading: true);
    final storage = ref.read(storageServiceProvider);
    final client = ref.read(supabaseClientProvider);
    final channel = ref.read(platformChannelServiceProvider);

    try {
      final domainsRes = await client.from('global_domains').select();
      final keywordsRes = await client.from('global_keywords').select();

      final List<String> fetchedDomains = (domainsRes as List).map((e) => e['value'] as String).toList();
      final List<String> fetchedKeywords = (keywordsRes as List).map((e) => e['value'] as String).toList();

      if (!ref.mounted) return;

      await storage.settingsBox.put('cached_domains', fetchedDomains);
      await storage.settingsBox.put('cached_keywords', fetchedKeywords);
      
      state = BlocklistState(domains: fetchedDomains, keywords: fetchedKeywords, isLoading: false);
      
      // Update Native platforms
      await channel.updateBlocklist(fetchedDomains, fetchedKeywords);
    } catch (_) {
      if (ref.mounted) {
        state = state.copyWith(isLoading: false);
      }
    }
  }
}

final blocklistProvider = NotifierProvider<BlocklistNotifier, BlocklistState>(() {
  return BlocklistNotifier();
});

