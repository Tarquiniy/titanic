import 'package:flutter/material.dart';
import 'package:titanic/widgets/art_deco_button.dart';

class AdminBlock extends StatelessWidget {
  final Future<void> Function()? onRefresh;
  final void Function(String label)? onAction;

  const AdminBlock({Key? key, this.onRefresh, this.onAction}) : super(key: key);

  void _call(String label) {
    if (onAction != null) onAction!(label);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: double.infinity,
          child: ArtDecoButton(
            text: 'Админ-панель',
            onPressed: () => _call('Админ-панель'),
            primary: true,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: ArtDecoButton(
            text: 'Пополнить V/M',
            onPressed: () => _call('Пополнить V/M'),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: ArtDecoButton(
            text: 'Создать опрос',
            onPressed: () => _call('Создать опрос'),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: ArtDecoButton(
            text: 'Создать аукцион',
            onPressed: () => _call('Создать аукцион'),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: ArtDecoButton(
            text: 'Голосование за фильм',
            onPressed: () => _call('Голосование за фильм'),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: ArtDecoButton(
            text: 'Статистика цветов',
            onPressed: () => _call('Статистика цветов'),
          ),
        ),
      ],
    );
  }
}