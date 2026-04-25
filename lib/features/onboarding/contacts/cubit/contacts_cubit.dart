import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../../core/storage/storage_service.dart';
import '../../../../models/emergency_contact.dart';

part 'contacts_cubit.freezed.dart';

@freezed
abstract class ContactsState with _$ContactsState {
  const factory ContactsState({
    @Default(<EmergencyContact>[]) List<EmergencyContact> contacts,
    String? errorMessage,
  }) = _ContactsState;
}

class ContactsCubit extends Cubit<ContactsState> {
  ContactsCubit(this._storage)
      : super(ContactsState(contacts: _storage.emergencyContacts));

  final StorageService _storage;

  Future<void> addContact({
    required String name,
    required String phone,
    required String languageCode,
  }) async {
    if (state.contacts.length >= StorageService.maxContacts) {
      emit(state.copyWith(
        errorMessage: 'You can add up to ${StorageService.maxContacts} contacts.',
      ));
      return;
    }
    final trimmedName = name.trim();
    final trimmedPhone = phone.trim();
    if (trimmedName.isEmpty || trimmedPhone.isEmpty) {
      emit(state.copyWith(errorMessage: 'Name and phone are required.'));
      return;
    }

    final contact = EmergencyContact(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: trimmedName,
      phone: trimmedPhone,
      preferredLanguageCode: languageCode,
    );
    await _storage.upsertContact(contact);
    emit(ContactsState(contacts: _storage.emergencyContacts));
  }

  Future<void> removeContact(String id) async {
    await _storage.deleteContact(id);
    emit(ContactsState(contacts: _storage.emergencyContacts));
  }

  void clearError() => emit(state.copyWith(errorMessage: null));
}
