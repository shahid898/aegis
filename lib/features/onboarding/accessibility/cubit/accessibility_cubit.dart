import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/storage/storage_service.dart';
import '../../../../models/accessibility_profile.dart';

class AccessibilityCubit extends Cubit<AccessibilityProfile> {
  AccessibilityCubit(this._storage) : super(_storage.accessibilityProfile);

  final StorageService _storage;

  void toggleWheelchair() =>
      emit(state.copyWith(usesWheelchair: !state.usesWheelchair));

  void toggleMedication() =>
      emit(state.copyWith(takesDailyMedication: !state.takesDailyMedication));

  void toggleDependent() =>
      emit(state.copyWith(hasDependent: !state.hasDependent));

  Future<void> confirm() => _storage.setAccessibilityProfile(state);
}
