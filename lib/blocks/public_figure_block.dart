import 'package:flutter/material.dart';
import 'package:titanic/widgets/art_deco_button.dart';

typedef VoidCallbackAsync = Future<void> Function();

class PublicFigureBlock extends StatefulWidget {
  final VoidCallback? onOpen;
  final VoidCallbackAsync? onInvestInColor;

  const PublicFigureBlock({
    Key? key,
    this.onOpen,
    this.onInvestInColor,
  }) : super(key: key);

  @override
  State<PublicFigureBlock> createState() => _PublicFigureBlockState();
}

class _PublicFigureBlockState extends State<PublicFigureBlock> {
  bool _processingInvest = false;

  Future<void> _handleInvestPressed() async {
    if (widget.onInvestInColor == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Функция не реализована'))
      );
      return;
    }
    
    if (_processingInvest) return;
    
    setState(() => _processingInvest = true);
    
    try {
      await widget.onInvestInColor!();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e'))
      );
    } finally {
      if (mounted) setState(() => _processingInvest = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: double.infinity,
          child: ArtDecoButton(
            text: 'Вложиться в цвет',
            onPressed: _processingInvest ? null : _handleInvestPressed,
            loading: _processingInvest,
            primary: true,
          ),
        ),
      ],
    );
  }
}