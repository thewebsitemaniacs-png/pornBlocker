import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:habit_breaker/features/blocking/presentation/providers/bypass_guard_provider.dart';

void main() {
  group('BypassGuardNotifier Tests', () {
    late ProviderContainer container;
    late BypassGuardNotifier notifier;

    setUp(() {
      container = ProviderContainer();
      notifier = container.read(bypassGuardProvider.notifier);
    });

    tearDown(() {
      container.dispose();
    });

    test('Initial state is clean', () {
      final state = container.read(bypassGuardProvider);
      expect(state.isLockoutActive, false);
      expect(state.lockoutUntil, null);
      expect(state.isBypassRequested, false);
      expect(state.bypassCountdownSeconds, 0);
      expect(state.canConfirmBypass, false);
    });

    test('Triggering block hits repeatedly activates 15-minute lockout', () {
      // Record 3 hits immediately
      notifier.recordBlockTrigger();
      notifier.recordBlockTrigger();
      notifier.recordBlockTrigger();

      final state = container.read(bypassGuardProvider);
      expect(state.isLockoutActive, true);
      expect(state.lockoutUntil, isNotNull);
      expect(state.isBypassRequested, false); // Cancel bypass when locked out
    });

    test('Requesting blocker bypass starts countdown timer', () {
      notifier.startBypassRequest(10); // Start 10s countdown

      final state = container.read(bypassGuardProvider);
      expect(state.isBypassRequested, true);
      expect(state.bypassCountdownSeconds, 10);
      expect(state.canConfirmBypass, false);
    });

    test('Cancelling deactivation request resets state', () {
      notifier.startBypassRequest(10);
      notifier.cancelBypassRequest();

      final state = container.read(bypassGuardProvider);
      expect(state.isBypassRequested, false);
      expect(state.bypassCountdownSeconds, 0);
      expect(state.canConfirmBypass, false);
    });
  });
}
