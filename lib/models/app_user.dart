class AppUser {
  final String id;
  final String username;
  final String role;
  final String firstName;
  final String lastName;
  final String color;
  double vBalance;
  double mBalance;


  AppUser({
    required this.id,
    required this.username,
    required this.role,
    required this.firstName,
    required this.lastName,
    this.vBalance = 0,
    this.mBalance = 0,
    required this.color,
  });
}
