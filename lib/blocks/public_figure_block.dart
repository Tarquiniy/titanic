// lib/blocks/public_figure_block.dart
import 'package:flutter/material.dart';

typedef VoidCallbackAsync = Future<void> Function();

class PublicFigureBlock extends StatefulWidget {
  final VoidCallback? onOpen;
  /// Async callback to perform "Вложиться в цвет". Parent implements network/dialog flow.
  final VoidCallbackAsync? onInvestInColor;

  const PublicFigureBlock({Key? key, this.onOpen, this.onInvestInColor}) : super(key: key);

  @override
  State<PublicFigureBlock> createState() => _PublicFigureBlockState();
}

class _PublicFigureBlockState extends State<PublicFigureBlock> {
  bool _processingInvest = false;

  Future<void> _handleInvestPressed() async {
    if (widget.onInvestInColor == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Функция не реализована')));
      return;
    }
    if (_processingInvest) return;
    setState(() => _processingInvest = true);
    try {
      await widget.onInvestInColor!();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
    } finally {
      if (mounted) setState(() => _processingInvest = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 6.0),
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
            onPressed: _processingInvest ? null : _handleInvestPressed,
            child: _processingInvest
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Вложиться в цвет'),
          ),
        ),
      ),
    ]);
  }
}
