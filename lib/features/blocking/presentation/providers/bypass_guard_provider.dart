import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class BypassGuardState {
  final DateTime? lockoutUntil;
  final bool isLockoutActive;
  
  final bool isBypassRequested;
  final int bypassCountdownSeconds;
  final bool canConfirmBypass;

  BypassGuardState({
    this.lockoutUntil,
    this.isLockoutActive = false,
    this.isBypassRequested = false,
    this.bypassCountdownSeconds = 0,
    this.canConfirmBypass = false,
  });

  BypassGuardState copyWith({
    DateTime? lockoutUntil,
    bool? isLockoutActive,
    bool? isBypassRequested,
    int? bypassCountdownSeconds,
    bool? canConfirmBypass,
  }) {
    return BypassGuardState(
      lockoutUntil: lockoutUntil ?? this.lockoutUntil,
      isLockoutActive: isLockoutActive ?? this.isLockoutActive,
      isBypassRequested: isBypassRequested ?? this.isBypassRequested,
      bypassCountdownSeconds: bypassCountdownSeconds ?? this.bypassCountdownSeconds,
      canConfirmBypass: canConfirmBypass ?? this.canConfirmBypass,
    );
  }
}

class BypassGuardNotifier extends Notifier<BypassGuardState> {
  Timer? _countdownTimer;
  Timer? _lockoutTimer;
  int _blockTriggerHits = 0;
  DateTime? _lastHitTime;

  @override
  BypassGuardState build() {
    // Return initial state
    return BypassGuardState();
  }

  BypassGuardState get currentState => state;

  // Triggered when a system block event is logged
  void recordBlockTrigger() {
    final now = DateTime.now();
    if (_lastHitTime != null && now.difference(_lastHitTime!) < const Duration(seconds: 30)) {
      _blockTriggerHits++;
    } else {
      _blockTriggerHits = 1;
    }
    _lastHitTime = now;

    const bool disableLockoutTesting = false; // Production mode: Lockout active
    if (disableLockoutTesting) {
      return;
    }

    if (_blockTriggerHits >= 3) {
      // Repeated hits lock the user out for 15 minutes
      triggerLockout(const Duration(minutes: 15));
    }
  }

  void triggerLockout(Duration duration) {
    final lockoutUntilTime = DateTime.now().add(duration);
    state = state.copyWith(
      lockoutUntil: lockoutUntilTime,
      isLockoutActive: true,
      isBypassRequested: false, // Override active bypass request
      bypassCountdownSeconds: 0,
      canConfirmBypass: false,
    );
    _countdownTimer?.cancel();

    _lockoutTimer?.cancel();
    _lockoutTimer = Timer(duration, () {
      state = state.copyWith(
        isLockoutActive: false,
        lockoutUntil: null,
      );
    });
  }

  void startBypassRequest(int durationSeconds) {
    if (state.isLockoutActive) return;
    
    // Set to true when running on the device to temporarily bypass the 60s countdown for testing
    const bool isTestingMode = false; // Production mode: 60s countdown active
    
    _countdownTimer?.cancel();
    if (isTestingMode) {
      state = state.copyWith(
        isBypassRequested: true,
        bypassCountdownSeconds: 0,
        canConfirmBypass: true,
      );
      return;
    }
    
    state = state.copyWith(
      isBypassRequested: true,
      bypassCountdownSeconds: durationSeconds,
      canConfirmBypass: false,
    );

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final current = state.bypassCountdownSeconds;
      if (current <= 1) {
        timer.cancel();
        state = state.copyWith(
          bypassCountdownSeconds: 0,
          canConfirmBypass: true,
        );
      } else {
        state = state.copyWith(
          bypassCountdownSeconds: current - 1,
        );
      }
    });
  }

  void cancelBypassRequest() {
    _countdownTimer?.cancel();
    state = state.copyWith(
      isBypassRequested: false,
      bypassCountdownSeconds: 0,
      canConfirmBypass: false,
    );
  }

  void completeBypass() {
    if (!state.canConfirmBypass) return;
    _countdownTimer?.cancel();
    state = state.copyWith(
      isBypassRequested: false,
      bypassCountdownSeconds: 0,
      canConfirmBypass: false,
    );
  }
}

final bypassGuardProvider = NotifierProvider<BypassGuardNotifier, BypassGuardState>(() {
  return BypassGuardNotifier();
});
