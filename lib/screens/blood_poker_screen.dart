import 'package:flutter/material.dart';
import 'package:titanic/blocks/blood_poker_block.dart';
import 'package:titanic/theme/app_theme.dart';

class BloodPokerScreen extends StatefulWidget {
  final String currentUserId;
  final Future<void> Function()? onBetPlaced;

  const BloodPokerScreen({
    Key? key,
    required this.currentUserId,
    this.onBetPlaced,
  }) : super(key: key);

  @override
  State<BloodPokerScreen> createState() => _BloodPokerScreenState();
}

class _BloodPokerScreenState extends State<BloodPokerScreen> {
  int _refreshKey = 0;

  Future<void> _onRefresh() async {
    if (!mounted) return;
    setState(() => _refreshKey++);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Покер на крови'),
      ),
      body: RefreshIndicator(
        onRefresh: _onRefresh,
        color: TitanicTheme.raptureGold,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  'Ставки доступны только мафии. '
                  'Выберите варианты, укажите майнды и подтвердите ставку.',
                  style: TitanicTheme.body,
                ),
              ),
            ),
            const SizedBox(height: 12),
            BloodPokerBlock(
              key: ValueKey(_refreshKey),
              currentUserId: widget.currentUserId,
              onBetPlaced: widget.onBetPlaced,
            ),
          ],
        ),
      ),
    );
  }
}
