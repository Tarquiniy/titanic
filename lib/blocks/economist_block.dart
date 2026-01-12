// lib/economist_block.dart
import 'package:flutter/material.dart';

class EconomistBlock extends StatelessWidget {
  final VoidCallback? onAnalytics;
  const EconomistBlock({Key? key, this.onAnalytics}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onAnalytics,
        child: const Text('Аналитика / Ставки'),
      ),
    );
  }
}
