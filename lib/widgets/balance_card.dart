// lib/widgets/balance_card.dart
import 'package:flutter/material.dart';
import 'package:titanic/models/app_user.dart';

class BalanceCard extends StatelessWidget {
  final AppUser user;
  final String? userColor;

  const BalanceCard({Key? key, required this.user, this.userColor}) : super(key: key);

  Color? _parseHexColor(String? s) {
    if (s == null) return null;
    final str = s.trim();
    if (!str.startsWith('#')) return null;
    String hex = str.substring(1);
    if (hex.length == 6) {
      hex = 'FF' + hex;
    } else if (hex.length == 3) {
      final r = hex[0];
      final g = hex[1];
      final b = hex[2];
      hex = 'FF' + r + r + g + g + b + b;
    } else if (hex.length == 8) {
      // assume AARRGGBB
    } else {
      return null;
    }
    final intVal = int.tryParse(hex, radix: 16);
    if (intVal == null) return null;
    return Color(intVal);
  }

  @override
  Widget build(BuildContext context) {
    final parsedColor = _parseHexColor(userColor);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${user.firstName} ${user.lastName}', style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Row(
              children: [
                Text('Роль: ${user.role}'),
                if (parsedColor != null) const SizedBox(width: 12),
                if (parsedColor != null)
                  Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: parsedColor,
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(color: Colors.black12),
                    ),
                  ),
                if (parsedColor != null) const SizedBox(width: 6),
                if (userColor != null && userColor!.isNotEmpty) Text('Цвет: ${userColor}', style: const TextStyle(color: Colors.black)),
              ],
            ),
            const SizedBox(height: 4),
            if (user.role == 'economist' && (user.region != null && user.region!.trim().isNotEmpty))
              Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Text('Экономический регион: ${user.region}', style: const TextStyle(fontSize: 13, color: Colors.black54)),
              ),
          ]),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('V: ${user.vBalance.toStringAsFixed(2)}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('M: ${user.mBalance.toStringAsFixed(2)}', style: const TextStyle(fontSize: 14)),
          ]),
        ]),
      ),
    );
  }
}
