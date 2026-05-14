class UsernameValidator {
  static final _pattern =
      RegExp(r'^[a-zA-Z][a-zA-Z0-9_.]{2,28}[a-zA-Z0-9]$');
  static final _consecutive = RegExp(r'[._]{2,}');

  static bool isValidFormat(String v) => _pattern.hasMatch(v);
  static bool hasConsecutiveSpecial(String v) => _consecutive.hasMatch(v);

  /// Returns null if valid, or an error message if invalid.
  /// Prefer using the boolean helpers with localized messages in UI code.
  static String? validate(String? value) {
    if (value == null || value.isEmpty) return 'Username is required';
    final v = value.trim();
    if (v.length < 4) return 'Username must be at least 4 characters';
    if (v.length > 30) return 'Username cannot exceed 30 characters';
    if (!isValidFormat(v)) {
      return 'Letters, numbers, periods, underscores only. '
          'Must start with a letter, end with letter or number.';
    }
    if (hasConsecutiveSpecial(v)) {
      return 'Cannot have consecutive periods or underscores';
    }
    return null;
  }
}

class DisplayNameValidator {
  /// Returns null if valid (including empty — display name is optional).
  static String? validate(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    if (value.trim().length > 50) {
      return 'Display name cannot exceed 50 characters';
    }
    return null;
  }
}
