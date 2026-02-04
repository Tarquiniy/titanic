// lib/screens/home_journal_section.dart
import 'package:flutter/material.dart';
import 'package:titanic/theme/app_theme.dart';
import 'package:titanic/widgets/journal_widget.dart';

class HomeJournalSection extends StatelessWidget {
  final List<Map<String, dynamic>> entries;

  const HomeJournalSection({Key? key, required this.entries}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: TitanicTheme.panelDecoration.copyWith(
        gradient: LinearGradient(
          colors: [
            TitanicTheme.darkEmerald.withOpacity(0.9),
            TitanicTheme.deepTeal.withOpacity(0.9),
          ],
        ),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: TitanicTheme.raptureGold, width: 1.5),
                  gradient: TitanicTheme.goldGradient,
                ),
                child: Icon(
                  Icons.history,
                  size: 20,
                  color: TitanicTheme.ivoryCream,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'БОРТОВОЙ ЖУРНАЛ',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: TitanicTheme.ivoryCream,
                  fontFamily: 'PlayfairDisplay',
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            height: 3,
            width: 60,
            decoration: BoxDecoration(
              gradient: TitanicTheme.goldGradient,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          Container(
            height: 300,
            decoration: BoxDecoration(
              color: TitanicTheme.deepTeal.withOpacity(0.5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: TitanicTheme.tealShade.withOpacity(0.3),
                width: 1,
              ),
            ),
            child: JournalWidget(entries: entries),
          ),
        ],
      ),
    );
  }
}
