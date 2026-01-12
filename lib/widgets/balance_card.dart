// lib/widgets/balance_card.dart
import 'package:flutter/material.dart';
import '../models/app_user.dart';

class BalanceCard extends StatelessWidget {
  final AppUser user;
  const BalanceCard({Key? key, required this.user}) : super(key: key);

  Color? _parseHexColor(String? s) {
    if (s == null) return null;
    final str = s.trim();
    if (!str.startsWith('#')) return null;
    String hex = str.substring(1);
    if (hex.length == 6) hex = 'FF' + hex;
    else if (hex.length == 3) {
      final r = hex[0], g = hex[1], b = hex[2];
      hex = 'FF' + r + r + g + g + b + b;
    }
    final val = int.tryParse(hex, radix: 16);
    if (val == null) return null;
    return Color(val);
  }

  @override
  Widget build(BuildContext context) {
    final parsedColor = _parseHexColor(user.color);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${user.firstName} ${user.lastName}', style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Row(children: [
              Text('Роль: ${user.role}'),
              if (user.color != null && user.color!.isNotEmpty) const SizedBox(width: 10),
              if (parsedColor != null)
                Container(width: 16, height: 16, decoration: BoxDecoration(color: parsedColor, borderRadius: BorderRadius.circular(3), border: Border.all(color: Colors.black12))),
              if (user.color != null && user.color!.isNotEmpty) const SizedBox(width: 6),
              if (user.color != null && user.color!.isNotEmpty) Text('Цвет: ${user.color}'),
            ]),
          ]),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('V: ${user.vBalance.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 6),
            Text('M: ${user.mBalance.toStringAsFixed(2)}', style: const TextStyle(fontSize: 14)),
          ]),
        ]),
      ),
    );
  }
}
