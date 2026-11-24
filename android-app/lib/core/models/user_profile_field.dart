import 'memory_entry.dart';

class UserProfileField {
  final String key;
  final String value;
  final MemorySource source;
  final DateTime updatedAt;

  const UserProfileField({
    required this.key,
    required this.value,
    this.source = MemorySource.manual,
    required this.updatedAt,
  });

  static const List<String> knownKeys = [
    'preferred_name',
    'gender',
    'pronouns',
    'preferred_language',
    'timezone',
    'occupation',
    'location',
  ];

  static final RegExp _validKeyPattern = RegExp(
    r'^(preferred_name|gender|pronouns|preferred_language|timezone|occupation|location|custom\.[A-Za-z0-9_\-]{1,32})$',
  );

  static bool isValidKey(String key) => _validKeyPattern.hasMatch(key);

  Map<String, dynamic> toPayload() => {
    'id': key,
    'value': value,
    'source': MemoryEntry.sourceToString(source),
    'updatedAt': updatedAt.microsecondsSinceEpoch,
  };

  static UserProfileField fromPayload(Map<String, dynamic> json) {
    return UserProfileField(
      key: json['id'] as String,
      value: json['value'] as String,
      source: MemoryEntry.sourceFromString(
        (json['source'] as String?) ?? 'manual',
      ),
      updatedAt: DateTime.fromMicrosecondsSinceEpoch(
        (json['updatedAt'] as num).toInt(),
      ),
    );
  }
}
