import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../../auth/domain/entities/user_profile.dart';
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
  static const List<String> _defaultKeywords = ['hot girls', 'fuck', 'sex videos', 'porn', 'adult', 'xxx'];

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

final linkedPartnersProvider = FutureProvider<List<UserProfile>>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  final auth = ref.watch(authProvider);
  final user = auth.user;
  if (user == null) return [];

  final response = await client
      .from('profiles')
      .select()
      .eq('buddy_id', user.id);
  
  return (response as List)
      .map((e) => UserProfile.fromJson(Map<String, dynamic>.from(e)))
      .toList();
});

final partnerLogsProvider = FutureProvider.family<List<HabitLog>, String>((ref, partnerId) async {
  final client = ref.watch(supabaseClientProvider);
  
  final response = await client
      .from('habit_logs')
      .select()
      .eq('user_id', partnerId)
      .order('logged_at', ascending: false);

  return (response as List)
      .map((e) => HabitLog.fromJson(Map<String, dynamic>.from(e)))
      .toList();
});

class BuddyAlert {
  final String id;
  final String partnerName;
  final String message;
  final DateTime timestamp;

  BuddyAlert({
    required this.id,
    required this.partnerName,
    required this.message,
    required this.timestamp,
  });
}

class BuddyNotificationNotifier extends Notifier<List<BuddyAlert>> {
  DateTime _lastChecked = DateTime.now();
  Timer? _timer;

  @override
  List<BuddyAlert> build() {
    final partnersVal = ref.watch(linkedPartnersProvider);
    
    partnersVal.whenData((partners) {
      if (partners.isEmpty) return;
      final client = ref.read(supabaseClientProvider);

      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 30), (_) async {
        await _checkNewAlerts(partners, client);
      });

      ref.onDispose(() {
        _timer?.cancel();
      });
    });

    return [];
  }

  Future<void> _checkNewAlerts(List<UserProfile> partners, dynamic client) async {
    final now = DateTime.now();
    final newlyFoundAlerts = <BuddyAlert>[];

    for (final partner in partners) {
      try {
        final response = await client
            .from('habit_logs')
            .select()
            .eq('user_id', partner.id)
            .eq('event_type', 'block_triggered')
            .gt('logged_at', _lastChecked.toUtc().toIso8601String())
            .order('logged_at', ascending: false);

        final logs = (response as List)
            .map((e) => HabitLog.fromJson(Map<String, dynamic>.from(e)))
            .toList();

        for (final log in logs) {
          newlyFoundAlerts.add(BuddyAlert(
            id: log.id,
            partnerName: partner.username,
            message: 'A blocker rule was breached. Please check on your partner.',
            timestamp: log.loggedAt,
          ));
        }
      } catch (_) {}
    }

    _lastChecked = now;
    if (newlyFoundAlerts.isNotEmpty) {
      state = [...newlyFoundAlerts, ...state];
    }
  }

  void dismissAlert(String alertId) {
    state = state.where((a) => a.id != alertId).toList();
  }
}

final buddyNotificationProvider = NotifierProvider<BuddyNotificationNotifier, List<BuddyAlert>>(() {
  return BuddyNotificationNotifier();
});

class BadgeAchievement {
  final String title;
  final String description;
  final bool isUnlocked;

  BadgeAchievement({
    required this.title,
    required this.description,
    required this.isUnlocked,
  });
}

class AnalyticsState {
  final int currentStreak;
  final int longestStreak;
  final List<String> cleanDays;
  final List<String> violationDays;
  final Map<int, int> hourlyUrgeDistribution;
  final List<BadgeAchievement> badges;

  AnalyticsState({
    required this.currentStreak,
    required this.longestStreak,
    required this.cleanDays,
    required this.violationDays,
    required this.hourlyUrgeDistribution,
    required this.badges,
  });
}

final analyticsProvider = Provider<AsyncValue<AnalyticsState>>((ref) {
  final logsAsync = ref.watch(habitLogsProvider);
  final authState = ref.watch(authProvider);
  final profile = authState.profile;

  return logsAsync.when(
    data: (logs) {
      final joinedDate = profile?.createdAt ?? DateTime.now().subtract(const Duration(days: 30));
      
      final violationDays = <String>{};
      int taskCompletions = 0;
      
      for (final log in logs) {
        if (log.eventType == 'block_triggered' || log.eventType == 'blocker_stopped') {
          violationDays.add(_toDateString(log.loggedAt));
        }
        if (log.eventType == 'task_completed') {
          taskCompletions++;
        }
      }

      final currentStreak = _calculateCurrentStreak(violationDays, joinedDate);
      final longestStreak = _calculateLongestStreak(violationDays, joinedDate);

      final cleanDays = <String>[];
      DateTime checkDate = joinedDate;
      final todayStr = _toDateString(DateTime.now());
      while (true) {
        final dateStr = _toDateString(checkDate);
        if (!violationDays.contains(dateStr)) {
          cleanDays.add(dateStr);
        }
        if (dateStr == todayStr) {
          break;
        }
        checkDate = checkDate.add(const Duration(days: 1));
        if (checkDate.isAfter(DateTime.now().add(const Duration(days: 1)))) break;
      }

      final hourlyUrgeDistribution = <int, int>{};
      for (int i = 0; i < 24; i++) {
        hourlyUrgeDistribution[i] = 0;
      }
      for (final log in logs) {
        if (log.eventType == 'block_triggered') {
          final hr = log.loggedAt.toLocal().hour;
          hourlyUrgeDistribution[hr] = (hourlyUrgeDistribution[hr] ?? 0) + 1;
        }
      }

      final badges = [
        BadgeAchievement(
          title: 'First Step',
          description: 'Log your first clean day without block events.',
          isUnlocked: cleanDays.isNotEmpty,
        ),
        BadgeAchievement(
          title: 'Bronze Shield',
          description: 'Maintain a 3-day focus streak.',
          isUnlocked: longestStreak >= 3,
        ),
        BadgeAchievement(
          title: 'Obsidian Shield',
          description: 'Reach a 7-day focus streak.',
          isUnlocked: longestStreak >= 7,
        ),
        BadgeAchievement(
          title: 'Consistency Master',
          description: 'Achieve a 14-day focus streak.',
          isUnlocked: longestStreak >= 14,
        ),
        BadgeAchievement(
          title: 'Task Champion',
          description: 'Successfully complete 5 habit tasks.',
          isUnlocked: taskCompletions >= 5,
        ),
        BadgeAchievement(
          title: 'Iron Will',
          description: 'Maintain a 30-day focus streak.',
          isUnlocked: longestStreak >= 30,
        ),
      ];

      return AsyncValue.data(AnalyticsState(
        currentStreak: currentStreak,
        longestStreak: longestStreak,
        cleanDays: cleanDays,
        violationDays: violationDays.toList(),
        hourlyUrgeDistribution: hourlyUrgeDistribution,
        badges: badges,
      ));
    },
    loading: () => const AsyncValue.loading(),
    error: (err, stack) => AsyncValue.error(err, stack),
  );
});

String _toDateString(DateTime dt) {
  return "${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}";
}

int _calculateCurrentStreak(Set<String> violationDays, DateTime joinedDate) {
  int streak = 0;
  DateTime checkDate = DateTime.now();
  final joinedStr = _toDateString(joinedDate);
  while (true) {
    final dateStr = _toDateString(checkDate);
    if (violationDays.contains(dateStr)) {
      break;
    }
    streak++;
    if (dateStr == joinedStr) {
      break;
    }
    checkDate = checkDate.subtract(const Duration(days: 1));
    if (streak > 365) break;
  }
  return streak;
}

int _calculateLongestStreak(Set<String> violationDays, DateTime joinedDate) {
  int longest = 0;
  int current = 0;
  DateTime checkDate = joinedDate;
  final todayStr = _toDateString(DateTime.now());
  
  while (true) {
    final dateStr = _toDateString(checkDate);
    if (violationDays.contains(dateStr)) {
      current = 0;
    } else {
      current++;
      if (current > longest) {
        longest = current;
      }
    }
    if (dateStr == todayStr) {
      break;
    }
    checkDate = checkDate.add(const Duration(days: 1));
    if (checkDate.isAfter(DateTime.now().add(const Duration(days: 2)))) {
      break;
    }
  }
  return longest;
}



