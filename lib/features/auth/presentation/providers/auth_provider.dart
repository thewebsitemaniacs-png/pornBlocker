import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../domain/entities/user_profile.dart';

// Provides the Supabase Client instance
final supabaseClientProvider = Provider<dynamic>((ref) {
  return Supabase.instance.client;
});

class AuthState {
  final User? user;
  final UserProfile? profile;
  final bool isLoading;
  final String? errorMessage;

  AuthState({
    this.user,
    this.profile,
    this.isLoading = false,
    this.errorMessage,
  });

  AuthState copyWith({
    User? user,
    UserProfile? profile,
    bool clearProfile = false,
    bool isLoading = false,
    String? errorMessage,
  }) {
    return AuthState(
      user: user ?? this.user,
      profile: clearProfile ? null : (profile ?? this.profile),
      isLoading: isLoading,
      errorMessage: errorMessage,
    );
  }
}

class AuthNotifier extends Notifier<AuthState> {
  late final dynamic _client;

  @override
  AuthState build() {
    _client = ref.watch(supabaseClientProvider);
    
    // Listen to real-time auth changes
    _client.auth.onAuthStateChange.listen((data) {
      final sessionUser = data.session?.user;
      if (sessionUser != null) {
        state = state.copyWith(user: sessionUser, isLoading: false);
        _fetchProfile(sessionUser.id);
      } else {
        state = AuthState();
      }
    });

    final currentUser = _client.auth.currentUser;
    if (currentUser != null) {
      _fetchProfile(currentUser.id);
    }

    return AuthState(user: _client.auth.currentUser);
  }

  Future<void> _fetchProfile(String userId) async {
    try {
      final data = await _client.from('profiles').select().eq('id', userId).maybeSingle();
      if (data != null) {
        final profile = UserProfile.fromJson(Map<String, dynamic>.from(data));
        state = state.copyWith(user: state.user, profile: profile);
      }
    } catch (e) {
      // Keep state as is, profile loads on connection retry
    }
  }

  Future<void> signUp(String email, String password) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      await _client.auth.signUp(email: email, password: password);
      // Auth change listener handles routing and profile creation
    } on AuthException catch (e) {
      state = state.copyWith(user: null, profile: null, isLoading: false, errorMessage: e.message);
    } catch (e) {
      state = state.copyWith(user: null, profile: null, isLoading: false, errorMessage: 'An unexpected registration error occurred.');
    }
  }

  Future<void> signIn(String email, String password) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      await _client.auth.signInWithPassword(email: email, password: password);
    } on AuthException catch (e) {
      state = state.copyWith(user: null, profile: null, isLoading: false, errorMessage: e.message);
    } catch (e) {
      state = state.copyWith(user: null, profile: null, isLoading: false, errorMessage: 'An unexpected sign in error occurred.');
    }
  }

  Future<void> togglePremium() async {
    final profile = state.profile;
    if (profile == null) return;
    final updatedPremium = !profile.isPremium;

    state = state.copyWith(user: state.user, profile: profile, isLoading: true);
    try {
      final updatedProfileData = await _client
          .from('profiles')
          .update({'is_premium': updatedPremium})
          .eq('id', profile.id)
          .select()
          .single();

      final updatedProfile = UserProfile.fromJson(Map<String, dynamic>.from(updatedProfileData));
      state = state.copyWith(user: state.user, profile: updatedProfile, isLoading: false);
    } catch (e) {
      state = state.copyWith(user: state.user, profile: profile, isLoading: false, errorMessage: 'Failed to update premium subscription status.');
    }
  }

  Future<void> signOut() async {
    state = state.copyWith(isLoading: true);
    try {
      await _client.auth.signOut();
      state = AuthState();
    } catch (e) {
      state = state.copyWith(user: state.user, profile: state.profile, isLoading: false, errorMessage: 'Sign out failed.');
    }
  }

  Future<UserProfile?> searchBuddy(String username) async {
    try {
      final data = await _client.from('profiles').select().eq('username', username).maybeSingle();
      if (data != null) {
        return UserProfile.fromJson(Map<String, dynamic>.from(data));
      }
    } catch (_) {}
    return null;
  }

  Future<void> linkBuddy(String buddyId) async {
    final profile = state.profile;
    if (profile == null) return;

    state = state.copyWith(user: state.user, profile: profile, isLoading: true);
    try {
      final updatedProfileData = await _client
          .from('profiles')
          .update({'buddy_id': buddyId})
          .eq('id', profile.id)
          .select()
          .single();

      final updatedProfile = UserProfile.fromJson(Map<String, dynamic>.from(updatedProfileData));
      state = state.copyWith(user: state.user, profile: updatedProfile, isLoading: false);
    } catch (e) {
      state = state.copyWith(
        user: state.user, 
        profile: profile, 
        isLoading: false, 
        errorMessage: 'Failed to link accountability partner.'
      );
    }
  }

  Future<void> unlinkBuddy() async {
    final profile = state.profile;
    if (profile == null) return;

    state = state.copyWith(user: state.user, profile: profile, isLoading: true);
    try {
      final updatedProfileData = await _client
          .from('profiles')
          .update({'buddy_id': null})
          .eq('id', profile.id)
          .select()
          .single();

      final updatedProfile = UserProfile.fromJson(Map<String, dynamic>.from(updatedProfileData));
      state = state.copyWith(user: state.user, profile: updatedProfile, isLoading: false);
    } catch (e) {
      state = state.copyWith(
        user: state.user, 
        profile: profile, 
        isLoading: false, 
        errorMessage: 'Failed to unlink accountability partner.'
      );
    }
  }

  void clearError() {
    state = state.copyWith(user: state.user, profile: state.profile, errorMessage: null);
  }
}

final authProvider = NotifierProvider<AuthNotifier, AuthState>(() {
  return AuthNotifier();
});
