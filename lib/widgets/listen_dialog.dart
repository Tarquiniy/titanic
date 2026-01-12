// lib/widgets/listen_dialog.dart
import 'package:flutter/material.dart';

/// Публичный результат диалога — теперь доступен из других файлов
class ListenDialogResult {
  final bool agree;
  final num n;
  const ListenDialogResult(this.agree, this.n);
}

/// Диалог — оставлен публичным именем ListenDialog
class ListenDialog extends StatefulWidget {
  final num defaultN;
  const ListenDialog({this.defaultN = 1, Key? key}) : super(key: key);

  @override
  State<ListenDialog> createState() => _ListenDialogState();
}

class _ListenDialogState extends State<ListenDialog> {
  bool _agree = false;
  final _nCtrl = TextEditingController();
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _nCtrl.text = widget.defaultN.toString();
  }

  @override
  void dispose() {
    _nCtrl.dispose();
    super.dispose();
  }

  void _onSubmit() {
    final n = num.tryParse(_nCtrl.text.trim());
    if (n == null || n <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Введите корректное положительное число n')));
      return;
    }
    Navigator.of(context).pop(ListenDialogResult(_agree, n));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Прослушал речь жизни'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          const Expanded(child: Text('Согласны сменить цвет на цвет политика, произносящего речь?')),
          const SizedBox(width: 8),
          Switch(value: _agree, onChanged: (v) => setState(() => _agree = v)),
        ]),
        const SizedBox(height: 8),
        TextField(
          controller: _nCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'n (количество базовой награды)'),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Отмена')),
        ElevatedButton(onPressed: _submitting ? null : _onSubmit, child: const Text('Подтвердить')),
      ],
    );
  }
}
