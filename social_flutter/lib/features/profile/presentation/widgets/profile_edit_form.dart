import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/core/ui/destructive_actions.dart';
import 'package:social_flutter/features/follows/providers/follow_provider.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/markdown_notes_editor.dart';
import 'package:social_flutter/features/profile/presentation/country_picker_screen.dart';
import 'package:social_flutter/features/profile/presentation/language_picker_sheet.dart';
import 'package:social_flutter/features/profile/providers/profile_provider.dart';
import 'package:social_flutter/l10n/app_localizations.dart';
import 'package:social_flutter/shared/data/countries.dart';
import 'package:social_flutter/shared/models/user.dart';
import 'package:social_flutter/shared/widgets/user_avatar.dart';

class ProfileEditForm extends ConsumerStatefulWidget {
  final User user;
  final VoidCallback onCancel;
  final VoidCallback onSaved;

  const ProfileEditForm({
    super.key,
    required this.user,
    required this.onCancel,
    required this.onSaved,
  });

  @override
  ConsumerState<ProfileEditForm> createState() => _ProfileEditFormState();
}

class _ProfileEditFormState extends ConsumerState<ProfileEditForm> {
  late final TextEditingController _displayNameController;
  late final TextEditingController _bioController;
  late final TextEditingController _avatarUrlController;
  late bool? _editIsPrivate;
  late List<String> _editPassportCountries;
  bool _passportCountriesChanged = false;
  late String? _editResidentCountry;
  bool _residentChanged = false;
  late List<String> _editLanguages;
  bool _languagesChanged = false;

  @override
  void initState() {
    super.initState();
    final u = widget.user;
    _displayNameController = TextEditingController(text: u.displayName ?? '');
    _bioController = TextEditingController(text: u.bio ?? '');
    _avatarUrlController = TextEditingController(text: u.avatarUrl ?? '');
    _editIsPrivate = u.isPrivate;
    _editPassportCountries = List.from(u.passportCountries ?? []);
    _editResidentCountry = u.residentCountry;
    _editLanguages = List.from(u.languages ?? []);
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _bioController.dispose();
    _avatarUrlController.dispose();
    super.dispose();
  }

  Future<void> _saveEdits() async {
    final l10n = AppLocalizations.of(context)!;
    final pendingCount =
        ref.read(followRequestsProvider).valueOrNull?.length ?? 0;
    final switchingToPublic =
        widget.user.isPrivate && _editIsPrivate == false;

    if (switchingToPublic && pendingCount > 0) {
      final confirmed = await confirmDestructiveAction(
        context: context,
        title: l10n.switchToPublicTitle,
        message: l10n.switchToPublicMessage(pendingCount),
        confirmLabel: l10n.switchToPublicButton,
      );
      if (!confirmed) return;
    }

    final avatarText = _avatarUrlController.text.trim();
    await ref.read(myProfileProvider.notifier).updateProfile(
          displayName: _displayNameController.text.trim().isEmpty
              ? null
              : _displayNameController.text.trim(),
          bio: _bioController.text.trim().isEmpty
              ? null
              : _bioController.text.trim(),
          avatarUrl: avatarText.isEmpty ? null : avatarText,
          clearAvatarUrl: avatarText.isEmpty,
          isPrivate: _editIsPrivate,
          passportCountries: _editPassportCountries,
          passportCountriesChanged: _passportCountriesChanged,
          residentCountry: _editResidentCountry,
          clearResidentCountry:
              _residentChanged && _editResidentCountry == null,
          languages: _editLanguages,
          languagesChanged: _languagesChanged,
        );
    if (mounted) widget.onSaved();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final user = widget.user;

    return Column(
      children: [
        SafeArea(
          bottom: false,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                TextButton(
                  onPressed: widget.onCancel,
                  style: TextButton.styleFrom(foregroundColor: kText2),
                  child: Text(
                    l10n.cancel,
                    style: const TextStyle(
                        fontWeight: FontWeight.w500, fontSize: 15),
                  ),
                ),
                Expanded(
                  child: Text(
                    l10n.editProfileTitle,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: kBark,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _saveEdits,
                  child: Text(
                    l10n.save,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 80),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Center(
                    child: Column(
                      children: [
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: kSand,
                              ),
                              child: UserAvatar(
                                  avatarUrl: user.avatarUrl, radius: 46),
                            ),
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: kForest,
                                  shape: BoxShape.circle,
                                  border:
                                      Border.all(color: kSand, width: 3),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black
                                          .withValues(alpha: 0.15),
                                      blurRadius: 8,
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.photo_camera,
                                  color: Colors.white,
                                  size: 15,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          l10n.uploadPhoto,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: kForest,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                _SectionLabel(
                  icon: Icons.person_outline_rounded,
                  label: l10n.identitySection,
                ),
                _SectionCard(children: [
                  _EditFieldRow(
                    icon: Icons.badge_outlined,
                    label: l10n.displayNameLabel,
                    child: TextField(
                      controller: _displayNameController,
                      style: const TextStyle(
                          fontSize: 15,
                          color: kBark,
                          fontWeight: FontWeight.w500),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        contentPadding:
                            EdgeInsets.only(left: 8, top: 8, bottom: 8),
                        isDense: true,
                      ),
                    ),
                  ),
                  const _FieldDivider(),
                  _EditFieldRow(
                    icon: Icons.alternate_email_rounded,
                    label: 'Username',
                    child: Text(
                      user.handle,
                      style: const TextStyle(
                          fontSize: 15,
                          color: kText2,
                          fontWeight: FontWeight.w500),
                    ),
                  ),
                  const _FieldDivider(),
                  _EditFieldRow(
                    icon: Icons.notes_rounded,
                    child: MarkdownNotesEditor(
                      controller: _bioController,
                      readOnly: false,
                      label: l10n.bioLabel,
                      helpTitle: l10n.bioLabel,
                      helpMessage: l10n.bioHelpMessage,
                    ),
                  ),
                  const _FieldDivider(),
                  _EditFieldRow(
                    icon: Icons.link_rounded,
                    label: l10n.avatarUrlLabel,
                    child: TextField(
                      controller: _avatarUrlController,
                      style: const TextStyle(
                          fontSize: 15,
                          color: kBark,
                          fontWeight: FontWeight.w500),
                      decoration: const InputDecoration(
                        hintText: 'https://…',
                        hintStyle: TextStyle(color: kText3, fontSize: 14),
                        border: InputBorder.none,
                        contentPadding:
                            EdgeInsets.only(left: 8, top: 8, bottom: 8),
                        isDense: true,
                      ),
                    ),
                  ),
                ]),
                _SectionLabel(
                  icon: Icons.public_rounded,
                  label: l10n.travelIdentitySection,
                ),
                _SectionCard(children: [
                  _CodeChipsRow(
                    icon: Icons.badge_outlined,
                    label: l10n.passportLabel,
                    codes: _editPassportCountries,
                    labelFor: (code) =>
                        '${countryByCode(code)?.flag ?? ''} $code'.trim(),
                    onAdd: () async {
                      final code =
                          await Navigator.of(context).push<String?>(
                        MaterialPageRoute(
                          builder: (_) => CountryPickerScreen(
                            exclude: _editPassportCountries,
                          ),
                        ),
                      );
                      if (code != null && code.isNotEmpty && mounted) {
                        setState(() {
                          _editPassportCountries = [
                            ..._editPassportCountries,
                            code
                          ];
                          _passportCountriesChanged = true;
                        });
                      }
                    },
                    onRemove: (code) => setState(() {
                      _editPassportCountries = _editPassportCountries
                          .where((c) => c != code)
                          .toList();
                      _passportCountriesChanged = true;
                    }),
                  ),
                  const _FieldDivider(),
                  _PickerRow(
                    icon: Icons.location_on_outlined,
                    label: l10n.livesInLabel,
                    countryCode: _editResidentCountry,
                    onTap: () async {
                      final code =
                          await Navigator.of(context).push<String?>(
                        MaterialPageRoute(
                          builder: (_) =>
                              const CountryPickerScreen(allowClear: true),
                        ),
                      );
                      if (code != null && mounted) {
                        setState(() {
                          _editResidentCountry = code.isEmpty ? null : code;
                          _residentChanged = true;
                        });
                      }
                    },
                  ),
                  const _FieldDivider(),
                  _CodeChipsRow(
                    icon: Icons.translate_outlined,
                    label: l10n.languagesLabel,
                    codes: _editLanguages,
                    labelFor: (code) => code,
                    onAdd: () async {
                      final code = await showLanguagePickerSheet(
                        context,
                        exclude: _editLanguages,
                      );
                      if (code != null && mounted) {
                        setState(() {
                          _editLanguages = [..._editLanguages, code];
                          _languagesChanged = true;
                        });
                      }
                    },
                    onRemove: (code) => setState(() {
                      _editLanguages =
                          _editLanguages.where((c) => c != code).toList();
                      _languagesChanged = true;
                    }),
                  ),
                ]),
                _SectionLabel(
                  icon: Icons.lock_outline_rounded,
                  label: l10n.privacySection,
                ),
                _SectionCard(children: [
                  _ToggleRow(
                    icon: Icons.lock_rounded,
                    label: l10n.privateAccountLabel,
                    subtitle: l10n.privateAccountSubtitle,
                    value: _editIsPrivate ?? user.isPrivate,
                    onChanged: (v) => setState(() => _editIsPrivate = v),
                  ),
                ]),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final IconData icon;
  final String label;
  const _SectionLabel({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 14, 22, 8),
      child: Row(
        children: [
          Icon(icon, size: 14, color: kText2),
          const SizedBox(width: 6),
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: kText2,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final List<Widget> children;
  const _SectionCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: kBorder),
      ),
      child: Column(children: children),
    );
  }
}

class _FieldDivider extends StatelessWidget {
  const _FieldDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      margin: const EdgeInsets.only(left: 16),
      color: kBorder,
    );
  }
}

class _EditFieldRow extends StatelessWidget {
  final IconData icon;
  final String? label;
  final Widget child;

  const _EditFieldRow({
    required this.icon,
    this.label,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: const Color(0xFFD0EBDA),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 16, color: kForest),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: label != null
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label!.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: kText2,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      child,
                    ],
                  )
                : child,
          ),
        ],
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ToggleRow({
    required this.icon,
    required this.label,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: value
                  ? const Color(0xFFD0EBDA)
                  : const Color(0xFFF5F2EC),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon,
                size: 16, color: value ? kForest : kText2),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: kBark,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: const TextStyle(
                        fontSize: 12, color: kText2, height: 1.4),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: kForest,
          ),
        ],
      ),
    );
  }
}

class _PickerRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? countryCode;
  final VoidCallback onTap;

  const _PickerRow({
    required this.icon,
    required this.label,
    required this.countryCode,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final country = countryCode != null ? countryByCode(countryCode!) : null;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: const Color(0xFFD0EBDA),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 16, color: kForest),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: kText2,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    country != null
                        ? '${country.flag} ${country.name}'
                        : 'Select a country',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: country != null ? kBark : kText3,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 20, color: kText3),
          ],
        ),
      ),
    );
  }
}

class _CodeChipsRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final List<String> codes;
  final String Function(String code) labelFor;
  final VoidCallback onAdd;
  final void Function(String code) onRemove;

  const _CodeChipsRow({
    required this.icon,
    required this.label,
    required this.codes,
    required this.labelFor,
    required this.onAdd,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: const Color(0xFFD0EBDA),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 16, color: kForest),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: kText2,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    ...codes.map((code) => _Chip(
                          label: labelFor(code),
                          onRemove: () => onRemove(code),
                        )),
                    _AddChip(onTap: onAdd),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final VoidCallback onRemove;

  const _Chip({required this.label, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.only(left: 10, right: 4, top: 5, bottom: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFD0EBDA),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: kForest,
            ),
          ),
          const SizedBox(width: 2),
          GestureDetector(
            onTap: onRemove,
            child: const Icon(Icons.close_rounded,
                size: 14, color: kForest),
          ),
        ],
      ),
    );
  }
}

class _AddChip extends StatelessWidget {
  final VoidCallback onTap;
  const _AddChip({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          border:
              Border.all(color: kText3, style: BorderStyle.solid, width: 1.5),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add_rounded, size: 13, color: kText2),
            SizedBox(width: 3),
            Text(
              'Add',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: kText2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
