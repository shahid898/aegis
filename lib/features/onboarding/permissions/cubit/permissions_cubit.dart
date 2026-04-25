import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:permission_handler/permission_handler.dart';

part 'permissions_cubit.freezed.dart';

enum AegisPermission { microphone, camera, location, notifications }

extension AegisPermissionX on AegisPermission {
  Permission get platform {
    switch (this) {
      case AegisPermission.microphone:
        return Permission.microphone;
      case AegisPermission.camera:
        return Permission.camera;
      case AegisPermission.location:
        return Permission.locationWhenInUse;
      case AegisPermission.notifications:
        return Permission.notification;
    }
  }
}

@freezed
abstract class PermissionsState with _$PermissionsState {
  const factory PermissionsState({
    @Default(<AegisPermission, PermissionStatus>{})
    Map<AegisPermission, PermissionStatus> statuses,
    @Default(false) bool isRequesting,
  }) = _PermissionsState;
}

class PermissionsCubit extends Cubit<PermissionsState> {
  PermissionsCubit() : super(const PermissionsState()) {
    refresh();
  }

  Future<void> refresh() async {
    final next = <AegisPermission, PermissionStatus>{};
    for (final p in AegisPermission.values) {
      next[p] = await p.platform.status;
    }
    emit(state.copyWith(statuses: next));
  }

  Future<void> request(AegisPermission permission) async {
    if (state.isRequesting) return;
    emit(state.copyWith(isRequesting: true));
    final status = await permission.platform.request();
    final next = Map<AegisPermission, PermissionStatus>.from(state.statuses);
    next[permission] = status;
    emit(state.copyWith(statuses: next, isRequesting: false));
  }

  Future<void> openSettings() => openAppSettings();
}
