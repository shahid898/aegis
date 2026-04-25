import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../core/storage/storage_service.dart';

part 'splash_cubit.freezed.dart';

@freezed
sealed class SplashState with _$SplashState {
  const factory SplashState.initial() = SplashInitial;
  const factory SplashState.goToOnboarding() = SplashGoToOnboarding;
  const factory SplashState.goToHome() = SplashGoToHome;
}

class SplashCubit extends Cubit<SplashState> {
  SplashCubit(this._storage) : super(const SplashState.initial());

  final StorageService _storage;

  Future<void> decide() async {
    // Keep the splash visible just long enough to feel intentional, not laggy.
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (_storage.isOnboardingCompleted) {
      emit(const SplashState.goToHome());
    } else {
      emit(const SplashState.goToOnboarding());
    }
  }
}
