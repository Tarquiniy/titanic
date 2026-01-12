// lib/public_figure_block.dart
import 'package:flutter/material.dart';

class PublicFigureBlock extends StatelessWidget {
  final VoidCallback? onOpen;
  const PublicFigureBlock({Key? key, this.onOpen}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onOpen,
        child: const Text('События / Прослушал'),
      ),
    );
  }
}
