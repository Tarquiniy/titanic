// lib/models/app_user.dart
class AppUser {
  final String id;
  final String username;
  final String role;
  final String firstName;
  final String lastName;
  double vBalance;
  double mBalance;
  final String? color;
  final String? region; // новый столбец region (text в БД)

  AppUser({
    required this.id,
    required this.username,
    required this.role,
    required this.firstName,
    required this.lastName,
    required this.vBalance,
    required this.mBalance,
    this.color,
    this.region,
  });

  AppUser copyWith({
    String? id,
    String? username,
    String? role,
    String? firstName,
    String? lastName,
    double? vBalance,
    double? mBalance,
    String? color,
    String? region,
  }) =>
      AppUser(
        id: id ?? this.id,
        username: username ?? this.username,
        role: role ?? this.role,
        firstName: firstName ?? this.firstName,
        lastName: lastName ?? this.lastName,
        vBalance: vBalance ?? this.vBalance,
        mBalance: mBalance ?? this.mBalance,
        color: color ?? this.color,
        region: region ?? this.region,
      );

  factory AppUser.fromMap(Map<String, dynamic> m) {
    return AppUser(
      id: m['id'].toString(),
      username: (m['telegram_username'] ?? '') as String,
      role: (m['role'] ?? '') as String,
      firstName: (m['first_name'] ?? '') as String,
      lastName: (m['last_name'] ?? '') as String,
      vBalance: (m['v_balance'] is num) ? (m['v_balance'] as num).toDouble() : 0.0,
      mBalance: (m['m_balance'] is num) ? (m['m_balance'] as num).toDouble() : 0.0,
      color: m['color'] as String?,
      region: m['region'] is String ? m['region'] as String : (m['region']?.toString()),
    );
  }
}
