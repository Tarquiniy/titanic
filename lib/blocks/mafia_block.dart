// lib/mafia_block.dart
import 'package:flutter/material.dart';

class MafiaBlock extends StatelessWidget {
  final VoidCallback? onManage;
  const MafiaBlock({Key? key, this.onManage}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onManage,
        child: const Text('Управление предприятиями'),
      ),
    );
  }
}
