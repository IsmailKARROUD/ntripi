import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:social_flutter/core/api/api_client.dart';
import 'package:social_flutter/core/moderation/nsfw_precheck.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/core/ui/destructive_actions.dart';
import 'package:social_flutter/features/follows/providers/follow_provider.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/cover_image_field.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/markdown_notes_editor.dart';
import 'package:social_flutter/features/profile/presentation/country_picker_screen.dart';
import 'package:social_flutter/features/profile/presentation/language_picker_sheet.dart';
import 'package:social_flutter/features/profile/providers/profile_provider.dart';
import 'package:social_flutter/l10n/app_localizations.dart';
import 'package:social_flutter/shared/data/countries.dart';
import 'package:social_flutter/shared/models/user.dart';
import 'package:social_flutter/shared/widgets/markdown_edit_screen.dart';
import 'package:social_flutter/shared/widgets/moderation_hint.dart';
import 'package:social_flutter/shared/widgets/offline_gate.dart';
import 'package:social_flutter/shared/widgets/saving_overlay.dart';
import 'package:social_flutter/shared/widgets/user_avatar.dart';

class ProfileEditForm extends ConsumerStatefulWidget {
  final User user;
  final VoidCallback onCancel;
  final VoidCallback onSaved;
  final VoidCallback onDeleteAccount;

  const ProfileEditForm({
    super.key,
    required this.user,
    required this.onCancel,
    required this.onSaved,
    required this.onDeleteAccount,
  });

  @override
  ConsumerState<ProfileEditForm> createState() => _ProfileEditFormState();
}

class _ProfileEditFormState extends ConsumerState<ProfileEditForm> {
  late final TextEditingController _displayNameController;
  late final TextEditingController _bioController;
  late bool? _editIsPrivate;
  late List<String> _editPassportCountries;
  bool _passportCountriesChanged = false;
  late String? _editResidentCountry;
  bool _residentChanged = false;
  late List<String> _editLanguages;
  bool _languagesChanged = false;

  // Picker state — bytes are uploaded inside _saveEdits before the JSON PATCH.
  Uint8List? _pickedAvatarBytes;
  String? _pickedAvatarFilename;
  bool _avatarRemoved = false;
  Uint8List? _pickedCoverBytes;
  String? _pickedCoverFilename;
  bool _coverRemoved = false;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final u = widget.user;
    _displayNameController = TextEditingController(text: u.displayName ?? '');
    _bioController = TextEditingController(text: u.bio ?? '');
    _editIsPrivate = u.isPrivate;
    _editPassportCountries = List.from(u.passportCountries ?? []);
    _editResidentCountry = u.residentCountry;
    _editLanguages = List.from(u.languages ?? []);
    // Warm up the NSFW model so the avatar pre-check is instant on pick.
    warmUpNsfwPrecheck();
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  /// Open gallery → 1:1 crop overlay → store bytes for upload during _saveEdits.
  /// Server runs the 800×800 square pipeline on the result; the UserAvatar
  /// widget clips to a circle with BoxFit.cover at display time.
  Future<void> _pickAvatar() async {
    if (_saving) return;
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: kIsWeb ? null : 2400,
        imageQuality: kIsWeb ? null : 90,
      );
      if (picked == null || !mounted) return;
      final raw = await picked.readAsBytes();
      if (!mounted) return;
      // Client-side NSFW pre-check — block before crop/upload. Returns false on
      // any failure (backend Rekognition scan is the real authority).
      if (await isLikelyNsfw(raw)) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.imageBlockedNsfw)),
        );
        return;
      }
      if (!mounted) return;
      final cropped = await openImageCropOverlay(
        context,
        sourceBytes: raw,
        targetWidth: 800,
        targetHeight: 800,
      );
      if (cropped == null || !mounted) return;
      setState(() {
        _pickedAvatarBytes = cropped;
        _pickedAvatarFilename = picked.name;
        _avatarRemoved = false;
      });
    } catch (_) {
      // Picker errors are silent — user can retry.
    }
  }

  /// Clear the avatar — drop picked bytes and mark _avatarRemoved so
  /// _saveEdits calls deleteAvatar() (storage + column).
  void _removeAvatar() {
    if (_saving) return;
    setState(() {
      _pickedAvatarBytes = null;
      _pickedAvatarFilename = null;
      _avatarRemoved = true;
    });
  }

  // Bio is edited on the shared full-screen markdown editor. It returns the new
  // text (null if cancelled); the form persists it with the other fields on Save.
  Future<void> _editBio() async {
    final l10n = AppLocalizations.of(context)!;
    final result = await editMarkdownField(
      context,
      initialText: _bioController.text,
      title: l10n.bioLabel,
      helpTitle: l10n.bioLabel,
      helpMessage: l10n.bioHelpMessage,
    );
    if (result == null || !mounted) return;
    setState(() => _bioController.text = result);
  }

  Future<void> _saveEdits() async {
    if (_saving) return;
    final l10n = AppLocalizations.of(context)!;
    // Capture before any await — context may be unmounted by the time we
    // need to show an error snackbar.
    final messenger = ScaffoldMessenger.maybeOf(context);
    final pendingCount =
        ref.read(followRequestsProvider).value?.length ?? 0;
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

    setState(() => _saving = true);
    final notifier = ref.read(myProfileProvider.notifier);

    try {
      // Binary phase first — avatar/cover are set only via the picker's scanned
      // upload endpoints (or cleared via delete); a Remove wins over an upload.
      if (_avatarRemoved) {
        await notifier.deleteAvatar();
      } else if (_pickedAvatarBytes != null) {
        await notifier.uploadAvatar(
          _pickedAvatarBytes!,
          _pickedAvatarFilename ?? 'avatar.jpg',
        );
      }
      if (_coverRemoved) {
        await notifier.deleteCoverImage();
      } else if (_pickedCoverBytes != null) {
        await notifier.uploadCoverImage(
          _pickedCoverBytes!,
          _pickedCoverFilename ?? 'cover.jpg',
        );
      }

      // Image columns are owned by the upload/delete endpoints above — the
      // profile PATCH never touches avatar_url / cover_image_url.
      await notifier.updateProfile(
        displayName: _displayNameController.text.trim().isEmpty
            ? null
            : _displayNameController.text.trim(),
        bio: _bioController.text.trim().isEmpty
            ? null
            : _bioController.text.trim(),
        isPrivate: _editIsPrivate,
        passportCountries: _editPassportCountries,
        passportCountriesChanged: _passportCountriesChanged,
        residentCountry: _editResidentCountry,
        clearResidentCountry:
            _residentChanged && _editResidentCountry == null,
        languages: _editLanguages,
        languagesChanged: _languagesChanged,
      );

      if (!mounted) return;
      widget.onSaved();
    } catch (e) {
      // Re-enable the form and surface the error. A moderation rejection shows
      // the real backend (AWS) reason via the same extractErrorMessage path
      // used elsewhere, so the user knows their image was refused; other
      // failures keep the generic retry message.
      if (!mounted) return;
      setState(() => _saving = false);
      final message = apiErrorCode(e) == 'image_moderation_rejected'
          ? extractErrorMessage(e, l10n)
          : l10n.couldNotLoadItineraries;
      messenger?.showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    final l10n = AppLocalizations.of(context)!;
    final user = widget.user;

    return SavingOverlay(
      saving: _saving,
      tint: nt.surface,
      child: Column(
      children: [
        SafeArea(
          bottom: false,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                TextButton(
                  onPressed: _saving ? null : widget.onCancel,
                  style: TextButton.styleFrom(foregroundColor: nt.text2),
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
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: nt.bark,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
                OfflineGate(
                  builder: (online) => TextButton(
                    onPressed: (_saving || !online) ? null : _saveEdits,
                    child: _saving
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation(nt.forest),
                            ),
                          )
                        : Text(
                            l10n.save,
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 15),
                          ),
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
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _pickAvatar,
                      child: Column(
                        children: [
                          Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: nt.sand,
                                ),
                                child: _pickedAvatarBytes != null
                                    ? ClipOval(
                                        child: Image.memory(
                                          _pickedAvatarBytes!,
                                          width: 92,
                                          height: 92,
                                          fit: BoxFit.cover,
                                        ),
                                      )
                                    : (_avatarRemoved
                                        ? const UserAvatar(
                                            avatarUrl: null, radius: 46)
                                        : UserAvatar(
                                            avatarUrl: user.avatarUrl,
                                            radius: 46,
                                          )),
                              ),
                              // X badge — top-start. Removes the avatar (clears
                              // picked bytes + URL, schedules deleteAvatar on
                              // save). Only shown when something is removable.
                              if (_pickedAvatarBytes != null ||
                                  (!_avatarRemoved && user.avatarUrl != null))
                                PositionedDirectional(
                                  top: 0,
                                  start: 0,
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: _removeAvatar,
                                    child: Container(
                                      width: 28,
                                      height: 28,
                                      decoration: BoxDecoration(
                                        color: nt.surface,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                            color: nt.sand, width: 2),
                                        boxShadow: [
                                          BoxShadow(
                                            color: nt.shadow
                                                .withValues(alpha: 0.15),
                                            blurRadius: 6,
                                          ),
                                        ],
                                      ),
                                      child: Icon(
                                        Icons.close_rounded,
                                        color: nt.bark,
                                        size: 16,
                                      ),
                                    ),
                                  ),
                                ),
                              PositionedDirectional(
                                bottom: 0,
                                end: 0,
                                child: Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color: nt.forest,
                                    shape: BoxShape.circle,
                                    border:
                                        Border.all(color: nt.sand, width: 3),
                                    boxShadow: [
                                      BoxShadow(
                                        color: nt.shadow
                                            .withValues(alpha: 0.15),
                                        blurRadius: 8,
                                      ),
                                    ],
                                  ),
                                  child: Icon(
                                    Icons.photo_camera,
                                    color:
                                        Theme.of(context).colorScheme.onPrimary,
                                    size: 15,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            l10n.uploadPhoto,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: nt.forest,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // Cover image section — picker only. Images are scanned on
                // upload (NSFWJS + AWS); no raw-URL entry so nothing bypasses it.
                _SectionLabel(
                  icon: Icons.image_outlined,
                  label: l10n.coverImageSection,
                ),
                _SectionCard(children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    child: CoverImageField(
                      initialUrl: user.coverImageUrl,
                      onImageSelected: (bytes, fn) => setState(() {
                        _pickedCoverBytes = bytes;
                        _pickedCoverFilename = fn;
                        _coverRemoved = false;
                      }),
                      onImageRemoved: () => setState(() {
                        _pickedCoverBytes = null;
                        _pickedCoverFilename = null;
                        _coverRemoved = true;
                      }),
                    ),
                  ),
                ]),
                _SectionLabel(
                  icon: Icons.person_outline_rounded,
                  label: l10n.identitySection,
                ),
                _SectionCard(children: [
                  _EditFieldRow(
                    icon: Icons.badge_outlined,
                    label: l10n.displayNameLabel,
                    child: ModerationHint(
                      controller: _displayNameController,
                      child: TextField(
                        controller: _displayNameController,
                        style: TextStyle(
                            fontSize: 15,
                            color: nt.bark,
                            fontWeight: FontWeight.w500),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          contentPadding: EdgeInsetsDirectional.only(
                              start: 8, top: 8, bottom: 8),
                          isDense: true,
                        ),
                      ),
                    ),
                  ),
                  const _FieldDivider(),
                  _EditFieldRow(
                    icon: Icons.alternate_email_rounded,
                    label: l10n.usernameLabel,
                    child: Text(
                      user.handle,
                      style: TextStyle(
                          fontSize: 15,
                          color: nt.text2,
                          fontWeight: FontWeight.w500),
                    ),
                  ),
                  const _FieldDivider(),
                  _EditFieldRow(
                    icon: Icons.notes_rounded,
                    label: l10n.bioLabel,
                    child: InkWell(
                      onTap: _editBio,
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: _bioController.text.trim().isEmpty
                                  ? Text(
                                      l10n.addBioLabel,
                                      style: TextStyle(
                                          fontSize: 15,
                                          color: nt.text3,
                                          fontWeight: FontWeight.w500),
                                    )
                                  // IgnorePointer so the selectable markdown
                                  // doesn't swallow the row's tap.
                                  : IgnorePointer(
                                      child: InertMarkdownBody(
                                          data: _bioController.text.trim()),
                                    ),
                            ),
                            const SizedBox(width: 8),
                            Icon(Icons.edit_outlined,
                                size: 16, color: nt.text3),
                          ],
                        ),
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
                      // Multi-select checklist: open once, apply the whole set.
                      // Cap is enforced inside the sheet.
                      final result = await showLanguagePickerSheet(
                        context,
                        selected: _editLanguages,
                      );
                      if (result != null && mounted) {
                        // Only mark dirty when the set actually changed.
                        final changed = result.length != _editLanguages.length ||
                            !result.toSet().containsAll(_editLanguages);
                        setState(() {
                          _editLanguages = result;
                          if (changed) _languagesChanged = true;
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
                // Only password accounts can change a password — Google-only
                // accounts (has_password == false) have nothing to change.
                if (user.hasPassword) ...[
                  _SectionLabel(
                    icon: Icons.lock_outline_rounded,
                    label: l10n.securitySection,
                  ),
                  _SectionCard(children: [
                    InkWell(
                      onTap: _saving
                          ? null
                          : () => context.push('/settings/change-password'),
                      borderRadius: BorderRadius.circular(18),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 13),
                        child: Row(
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: nt.mist,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(Icons.password_rounded,
                                  size: 16, color: nt.forest),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                l10n.changePasswordTitle,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: nt.bark,
                                ),
                              ),
                            ),
                            Icon(Icons.chevron_right,
                                size: 20, color: nt.text3),
                          ],
                        ),
                      ),
                    ),
                  ]),
                ],
                const SizedBox(height: 20),
                _SectionLabel(
                  icon: Icons.warning_amber_rounded,
                  label: l10n.dangerZoneSection,
                  color: nt.danger,
                ),
                _SectionCard(children: [
                  InkWell(
                    onTap: _saving ? null : widget.onDeleteAccount,
                    borderRadius: BorderRadius.circular(18),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 13),
                      child: Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: nt.dangerTint,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(Icons.delete_outline_rounded,
                                size: 16, color: nt.danger),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              l10n.settingsDeleteAccount,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: nt.danger,
                              ),
                            ),
                          ),
                          Icon(Icons.chevron_right,
                              size: 20, color: nt.danger),
                        ],
                      ),
                    ),
                  ),
                ]),
              ],
            ),
          ),
        ),
      ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final IconData icon;
  final String label;
  // Nullable: theme lookups aren't const, so the default resolves in build.
  final Color? color;
  const _SectionLabel({required this.icon, required this.label, this.color});

  @override
  Widget build(BuildContext context) {
    final color = this.color ?? context.nt.text2;
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 14, 22, 8),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
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
    final nt = context.nt;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: nt.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: nt.border),
      ),
      child: Column(children: children),
    );
  }
}

class _FieldDivider extends StatelessWidget {
  const _FieldDivider();

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    return Container(
      height: 1,
      margin: const EdgeInsetsDirectional.only(start: 16),
      color: nt.border,
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
    final nt = context.nt;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: nt.mist,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 16, color: nt.forest),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: label != null
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label!.toUpperCase(),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: nt.text2,
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
    final nt = context.nt;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: value ? nt.mist : nt.sand,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon,
                size: 16, color: value ? nt.forest : nt.text2),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: nt.bark,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: TextStyle(
                        fontSize: 12, color: nt.text2, height: 1.4),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: nt.forest,
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
    final nt = context.nt;
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
                color: nt.mist,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 16, color: nt.forest),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label.toUpperCase(),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: nt.text2,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    country != null
                        ? '${country.flag} ${country.localizedName(Localizations.localeOf(context).languageCode)}'
                        : AppLocalizations.of(context)!.countryPickerTitle,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: country != null ? nt.bark : nt.text3,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 20, color: nt.text3),
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
    final nt = context.nt;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: nt.mist,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 16, color: nt.forest),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: nt.text2,
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
    final nt = context.nt;
    return Container(
      padding:
          const EdgeInsetsDirectional.only(start: 10, end: 4, top: 5, bottom: 5),
      decoration: BoxDecoration(
        color: nt.mist,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: nt.forest,
            ),
          ),
          const SizedBox(width: 2),
          GestureDetector(
            onTap: onRemove,
            child: Icon(Icons.close_rounded,
                size: 14, color: nt.forest),
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
    final nt = context.nt;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          border:
              Border.all(color: nt.text3, style: BorderStyle.solid, width: 1.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add_rounded, size: 13, color: nt.text2),
            const SizedBox(width: 3),
            Text(
              AppLocalizations.of(context)!.addButton,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: nt.text2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
