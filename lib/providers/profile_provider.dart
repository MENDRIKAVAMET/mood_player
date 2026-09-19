import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/user_profile.dart';
import '../services/profile_service.dart';

final profileServiceProvider = Provider<ProfileService>((ref) {
  return ProfileService();
});

final profileProvider =
    StateNotifierProvider<ProfileNotifier, UserProfile>((ref) {
  return ProfileNotifier(ref.watch(profileServiceProvider));
});

class ProfileNotifier extends StateNotifier<UserProfile> {
  final ProfileService _service;

  ProfileNotifier(this._service) : super(const UserProfile.empty()) {
    _load();
  }

  Future<void> _load() async {
    state = await _service.load();
  }

  Future<void> setName(String name) async {
    state = state.copyWith(name: name);
    await _service.save(state);
  }

  Future<void> setFavoriteArtists(List<String> artists) async {
    state = state.copyWith(favoriteArtists: artists);
    await _service.save(state);
  }

  Future<void> completeOnboarding() async {
    state = state.copyWith(onboardingCompleted: true);
    await _service.save(state);
  }
}
