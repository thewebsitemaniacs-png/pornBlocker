import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:habit_breaker/core/services/storage_service.dart';
import 'package:habit_breaker/features/auth/domain/entities/user_profile.dart';
import 'package:habit_breaker/features/auth/presentation/providers/auth_provider.dart';
import 'package:habit_breaker/features/habit_engine/presentation/providers/habit_provider.dart';

class TestStorageService implements StorageService {
  @override
  late Box<Map> tasksBox;
  @override
  late Box<Map> logsBox;
  @override
  late Box<dynamic> settingsBox;

  Future<void> initTest() async {
    tasksBox = await Hive.openBox<Map>('test_tasks_bd');
    logsBox = await Hive.openBox<Map>('test_logs_bd');
    settingsBox = await Hive.openBox('test_settings_bd');
  }

  @override
  Future<void> init() async {}
}

class FakeSupabaseClient {
  final List<Map<String, dynamic>> profilesTable = [
    {
      'id': 'buddy_uuid_123',
      'username': 'CalmEagle2019',
      'is_premium': false,
      'buddy_id': null,
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    }
  ];

  final List<Map<String, dynamic>> logsTable = [];

  FakeQueryBuilder from(String table) => FakeQueryBuilder(this, table);
}

class FakeQueryBuilder implements Future<dynamic> {
  final FakeSupabaseClient client;
  final String table;
  String? eqField;
  dynamic eqValue;

  FakeQueryBuilder(this.client, this.table);

  FakeQueryBuilder eq(String field, dynamic val) {
    eqField = field;
    eqValue = val;
    return this;
  }

  FakeQueryBuilder select() => this;

  Future<dynamic> single() async {
    if (table == 'profiles') {
      return client.profilesTable.first;
    }
    return {};
  }

  Future<dynamic> maybeSingle() async {
    if (table == 'profiles') {
      if (eqField == 'username') {
        final matches = client.profilesTable.where((e) => e['username'] == eqValue);
        return matches.isEmpty ? null : matches.first;
      }
      return client.profilesTable.first;
    }
    return null;
  }

  FakeQueryBuilder update(Map<String, dynamic> values) {
    if (table == 'profiles') {
      final index = client.profilesTable.indexWhere((e) => e['id'] == eqValue || eqValue == null);
      if (index != -1) {
        client.profilesTable[index] = {
          ...client.profilesTable[index],
          ...values,
        };
      }
    }
    return this;
  }

  Future<dynamic> get _future {
    if (table == 'profiles') {
      return Future.value(client.profilesTable);
    }
    return Future.value([]);
  }

  @override
  Stream<dynamic> asStream() => _future.asStream();

  @override
  Future<dynamic> catchError(Function onError, {bool Function(Object error)? test}) =>
      _future.catchError(onError, test: test);

  @override
  Future<R> then<R>(FutureOr<R> Function(dynamic value) onValue, {Function? onError}) =>
      _future.then(onValue, onError: onError);

  @override
  Future<dynamic> timeout(Duration timeLimit, {FutureOr<dynamic> Function()? onTimeout}) =>
      _future.timeout(timeLimit, onTimeout: onTimeout);

  @override
  Future<dynamic> whenComplete(FutureOr<void> Function() action) =>
      _future.whenComplete(action);
}

void main() {
  late Directory tempDir;
  late TestStorageService storageService;
  late FakeSupabaseClient fakeSupabase;
  late ProviderContainer container;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp();
    Hive.init(tempDir.path);

    storageService = TestStorageService();
    await storageService.initTest();

    fakeSupabase = FakeSupabaseClient();

    container = ProviderContainer(
      overrides: [
        storageServiceProvider.overrideWithValue(storageService),
        supabaseClientProvider.overrideWithValue(fakeSupabase),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await Hive.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('AuthNotifier searchBuddy returns UserProfile when matching username', () async {
    final notifier = container.read(authProvider.notifier);
    final result = await notifier.searchBuddy('CalmEagle2019');
    expect(result, isNotNull);
    expect(result!.username, 'CalmEagle2019');
  });

  test('UserProfile copyWith holds and clears buddyId correctly', () {
    final profile = UserProfile(
      id: 'usr_1',
      username: 'UserOne',
      isPremium: false,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    expect(profile.buddyId, null);

    final linked = profile.copyWith(buddyId: 'buddy_1');
    expect(linked.buddyId, 'buddy_1');

    final unlinked = linked.copyWith(clearBuddy: true);
    expect(unlinked.buddyId, null);
  });
}
