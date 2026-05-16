import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router.dart';
import '../../../../app/theme.dart';
import '../../../../core/constants/languages.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/storage/storage_service.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../models/language_option.dart';
import '../cubit/contacts_cubit.dart';

class ContactsPage extends StatelessWidget {
  const ContactsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => ContactsCubit(sl<StorageService>()),
      child: const _ContactsView(),
    );
  }
}

class _ContactsView extends StatelessWidget {
  const _ContactsView();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.contactsTitle),
        actions: [
          TextButton(
            onPressed: () => context.go(AppRoute.permissions.path),
            child: Text(l.actionSkip),
          ),
        ],
      ),
      body: SafeArea(
        child: BlocConsumer<ContactsCubit, ContactsState>(
          listener: (context, state) {
            if (state.errorMessage != null) {
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(SnackBar(content: Text(state.errorMessage!)));
              context.read<ContactsCubit>().clearError();
            }
          },
          builder: (context, state) {
            return Column(
              children: [
                Padding(
                  padding:
                      const EdgeInsets.fromLTRB(24, 8, 24, 12),
                  child: Text(
                    l.contactsBody,
                    style: const TextStyle(
                      color: AegisColors.onSurfaceMuted,
                      height: 1.4,
                    ),
                  ),
                ),
                Expanded(
                  child: state.contacts.isEmpty
                      ? const _EmptyState()
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 4),
                          itemCount: state.contacts.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, i) {
                            final c = state.contacts[i];
                            final lang = SupportedLanguages.findByCode(
                                c.preferredLanguageCode);
                            return Material(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              child: ListTile(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                title: Text(
                                  c.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                subtitle: Text(
                                    '${c.phone} • ${lang.nativeName}'),
                                trailing: IconButton(
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: () => context
                                      .read<ContactsCubit>()
                                      .removeContact(c.id),
                                ),
                              ),
                            );
                          },
                        ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding:
                        const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: Column(
                      children: [
                        if (state.contacts.length <
                            StorageService.maxContacts)
                          OutlinedButton.icon(
                            onPressed: () => _showAddSheet(context),
                            icon: const Icon(Icons.person_add_alt_1),
                            label: Text(
                              l.contactsAddWithCount(
                                state.contacts.length,
                                StorageService.maxContacts,
                              ),
                            ),
                          ),
                        const SizedBox(height: 10),
                        FilledButton(
                          onPressed: () =>
                              context.go(AppRoute.permissions.path),
                          child: Text(l.actionContinue),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _showAddSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => BlocProvider.value(
        value: context.read<ContactsCubit>(),
        child: const _AddContactSheet(),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.contacts_outlined,
              size: 48, color: AegisColors.onSurfaceMuted),
          const SizedBox(height: 10),
          Text(
            AppLocalizations.of(context).contactsEmpty,
            style: const TextStyle(
              color: AegisColors.onSurfaceMuted,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }
}

class _AddContactSheet extends StatefulWidget {
  const _AddContactSheet();

  @override
  State<_AddContactSheet> createState() => _AddContactSheetState();
}

class _AddContactSheetState extends State<_AddContactSheet> {
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  LanguageOption _language = SupportedLanguages.all.first;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final viewInsets = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + viewInsets),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.contactsAdd,
              style:
                  const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 14),
          TextField(
            controller: _nameCtrl,
            decoration: InputDecoration(labelText: l.contactsName),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phoneCtrl,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(labelText: l.contactsPhone),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<LanguageOption>(
            initialValue: _language,
            decoration:
                InputDecoration(labelText: l.contactsPreferredLanguage),
            isExpanded: true,
            items: SupportedLanguages.all
                .map((l) => DropdownMenuItem(
                      value: l,
                      child: Text('${l.nativeName}  ·  ${l.englishName}'),
                    ))
                .toList(),
            onChanged: (v) => setState(() => _language = v ?? _language),
          ),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: () async {
              await context.read<ContactsCubit>().addContact(
                    name: _nameCtrl.text,
                    phone: _phoneCtrl.text,
                    languageCode: _language.code,
                  );
              if (!context.mounted) return;
              Navigator.of(context).pop();
            },
            child: Text(l.contactsSave),
          ),
        ],
      ),
    );
  }
}
