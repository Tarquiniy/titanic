// lib/hollywood_block.dart
import 'package:flutter/material.dart';

class HollywoodBlock extends StatelessWidget {
  final VoidCallback? onOpen;
  const HollywoodBlock({Key? key, this.onOpen}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onOpen,
        child: const Text('Контент / Ставки'),
      ),
    );
  }
}
