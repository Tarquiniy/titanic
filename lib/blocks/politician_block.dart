import 'package:flutter/material.dart';
import 'package:titanic/widgets/art_deco_button.dart';

class PoliticianBlock extends StatelessWidget {
  final bool isEnabled;
  final bool speechActive;
  final DateTime? speechExpiresAt;
  final String? speechActorId;
  final Future<void> Function()? onStartSpeech;

  const PoliticianBlock({
    super.key,
    required this.isEnabled,
    required this.speechActive,
    required this.speechExpiresAt,
    required this.speechActorId,
    this.onStartSpeech,
  });

  String _formatYe(DateTime utc) {
    final ye = utc.toUtc().add(const Duration(hours: 5));
    String z(int n) => n.toString().padLeft(2, '0');
    return '${z(ye.day)}.${z(ye.month)} ${z(ye.hour)}:${z(ye.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final actorLabel = speechActorId ?? '—';
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: double.infinity,
          child: ArtDecoButton(
            text: isEnabled ? 'Речь жизни - сказать' : 'Речь жизни (неактивна)',
            onPressed: isEnabled ? onStartSpeech : null,
            primary: isEnabled,
          ),
        ),
        if (speechActive) 
          Padding(
            padding: const EdgeInsets.only(top: 6.0),
            child: Text(
              'Речь активна (инициатор: $actorLabel)',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
        if (speechExpiresAt != null) 
          Padding(
            padding: const EdgeInsets.only(top: 6.0),
            child: Text(
              'Кнопка снова будет доступна в ${_formatYe(speechExpiresAt!)} (YEKT)',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
      ],
    );
  }
}