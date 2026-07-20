import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:habit_breaker/core/services/storage_service.dart';
import 'package:habit_breaker/features/habit_engine/data/repositories/hybrid_habit_repository.dart';
import 'package:habit_breaker/features/habit_engine/domain/entities/habit_task.dart';

class TestStorageService implements StorageService {
  late Box<Map> _tasksBox;
  late Box<Map> _logsBox;
  late Box<dynamic> _settingsBox;

  Future<void> initTest() async {
    _tasksBox = await Hive.openBox<Map>('tasks_test');
    _logsBox = await Hive.openBox<Map>('logs_test');
    _settingsBox = await Hive.openBox<dynamic>('settings_test');
  }

  @override
  Box<Map> get tasksBox => _tasksBox;
  @override
  Box<Map> get logsBox => _logsBox;
  @override
  Box<dynamic> get settingsBox => _settingsBox;
  
  @override
  Future<void> init() async {}
}

class FakeSupabaseQueryBuilder {
  final String tableName;
  final FakeSupabaseClient client;

  FakeSupabaseQueryBuilder(this.tableName, this.client);

  Future<List<Map<String, dynamic>>> upsert(dynamic data) async {
    final list = data is List ? data : [data];
    for (var item in list) {
      final map = Map<String, dynamic>.from(item);
      final id = map['id'];
      client.tables[tableName]!.removeWhere((element) => element['id'] == id);
      client.tables[tableName]!.add(map);
    }
    return (client.tables[tableName] as List).map((e) => Map<String, dynamic>.from(e)).toList();
  }

  FakeSupabaseFilterBuilder delete() {
    return FakeSupabaseFilterBuilder(tableName, client, isDelete: true);
  }

  FakeSupabaseFilterBuilder select() {
    return FakeSupabaseFilterBuilder(tableName, client);
  }
}

class FakeSupabaseFilterBuilder implements Future<List<Map<String, dynamic>>> {
  final String tableName;
  final FakeSupabaseClient client;
  final bool isDelete;
  String? filterField;
  dynamic filterValue;

  FakeSupabaseFilterBuilder(this.tableName, this.client, {this.isDelete = false});

  FakeSupabaseFilterBuilder eq(String field, dynamic value) {
    filterField = field;
    filterValue = value;
    if (isDelete) {
      client.tables[tableName]!.removeWhere((element) => element[field] == value);
    }
    return this;
  }

  FakeSupabaseFilterBuilder gt(String field, dynamic value) {
    return this;
  }

  Future<List<Map<String, dynamic>>> _execute() async {
    var data = client.tables[tableName]!;
    if (filterField != null) {
      data = data.where((e) => e[filterField] == filterValue).toList();
    }
    return data;
  }

  @override
  Stream<List<Map<String, dynamic>>> asStream() => _execute().asStream();

  @override
  Future<List<Map<String, dynamic>>> catchError(Function onError, {bool Function(Object error)? test}) =>
      _execute().catchError(onError, test: test);

  @override
  Future<R> then<R>(FutureOr<R> Function(List<Map<String, dynamic>> value) onValue, {Function? onError}) =>
      _execute().then(onValue, onError: onError);

  @override
  Future<List<Map<String, dynamic>>> timeout(Duration timeLimit, {FutureOr<List<Map<String, dynamic>>> Function()? onTimeout}) =>
      _execute().timeout(timeLimit, onTimeout: onTimeout);

  @override
  Future<List<Map<String, dynamic>>> whenComplete(FutureOr<void> Function() action) =>
      _execute().whenComplete(action);
}

class FakeSupabaseClient {
  final Map<String, List<Map<String, dynamic>>> tables = {
    'habit_tasks': [],
    'habit_logs': [],
  };

  FakeSupabaseQueryBuilder from(String table) {
    return FakeSupabaseQueryBuilder(table, this);
  }
}

void main() {
  late Directory tempDir;
  late TestStorageService storageService;
  late FakeSupabaseClient fakeSupabase;
  late HybridHabitRepository repository;
  
  String? userId = 'test_user_123';

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp();
    Hive.init(tempDir.path);

    storageService = TestStorageService();
    await storageService.initTest();

    fakeSupabase = FakeSupabaseClient();

    repository = HybridHabitRepository(
      storageService: storageService,
      supabaseClient: fakeSupabase,
      currentUserIdCallback: () => userId,
    );
  });

  tearDown(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('HybridHabitRepository Tests', () {
    test('Saving task when user is logged in uploads to Supabase and marks local copy synced = true', () async {
      userId = 'test_user_123';

      final task = HabitTask(
        id: 'task-1',
        userId: userId!,
        title: 'Mindful Breathing',
        isCompleted: false,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await repository.saveTask(task);

      final localTasks = await repository.getTasks();
      expect(localTasks.length, 1);
      expect(localTasks.first.id, 'task-1');
      expect(localTasks.first.synced, true);

      final remoteTasks = fakeSupabase.tables['habit_tasks']!;
      expect(remoteTasks.length, 1);
      expect(remoteTasks.first['id'], 'task-1');
    });

    test('Saving task when user is logged out saves locally with synced = false', () async {
      userId = null;

      final task = HabitTask(
        id: 'task-logged-out',
        userId: 'anonymous',
        title: 'Local only task',
        isCompleted: false,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await repository.saveTask(task);

      final localTasks = await repository.getTasks();
      final addedTask = localTasks.firstWhere((t) => t.id == 'task-logged-out');
      expect(addedTask.synced, false);

      expect(fakeSupabase.tables['habit_tasks']!.any((t) => t['id'] == 'task-logged-out'), false);
    });
  });
}
