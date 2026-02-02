import 'package:flutter/material.dart';
import 'package:titanic/widgets/art_deco_button.dart';

class EconomistBlock extends StatelessWidget {
  final VoidCallback? onAnalytics;
  const EconomistBlock({Key? key, this.onAnalytics}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ArtDecoButton(
        text: 'Аналитика / Ставки',
        onPressed: onAnalytics,
      ),
    );
  }
}