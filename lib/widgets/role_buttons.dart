// lib/widgets/role_buttons.dart
import 'package:flutter/material.dart';
import '../models/app_user.dart';
import '../blocks/journalist_block.dart';
import '../blocks/politician_block.dart';
import '../blocks/generic_blocks.dart';

class RoleButtons extends StatelessWidget {
  final AppUser user;
  final bool isListenEnabled;
  final VoidCallback onListenPressed;
  final bool isSpeechEnabled;
  final bool speechActive;
  final DateTime? speechExpiresAt;
  final String? speechActorId;
  final Future<void> Function()? onStartSpeech;
  final VoidCallback onOpenTransfer;
  final Future<void> Function()? onRefreshProfile;

  const RoleButtons({
    super.key,
    required this.user,
    required this.isListenEnabled,
    required this.onListenPressed,
    required this.isSpeechEnabled,
    required this.speechActive,
    required this.speechExpiresAt,
    required this.speechActorId,
    this.onStartSpeech,
    required this.onOpenTransfer,
    this.onRefreshProfile,
  });

  @override
  Widget build(BuildContext context) {
    final role = user.role;
    final List<Widget> buttons = [];

    Widget fullWidth(Widget child) => Padding(padding: const EdgeInsets.symmetric(vertical: 6.0), child: SizedBox(width: double.infinity, child: child));

    buttons.add(fullWidth(ElevatedButton(onPressed: onOpenTransfer, child: const Text('Перевести V/M'))));
    buttons.add(fullWidth(ElevatedButton(onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Опросы/Аукционы'))), child: const Text('Опросы / Аукционы'))));

    if (role == 'politician') {
      buttons.add(fullWidth(PoliticianBlock(isEnabled: isSpeechEnabled, speechActive: speechActive, speechExpiresAt: speechExpiresAt, speechActorId: speechActorId, onStartSpeech: onStartSpeech)));
    }

    buttons.add(fullWidth(ElevatedButton(
      onPressed: isListenEnabled ? onListenPressed : null,
      style: ElevatedButton.styleFrom(backgroundColor: isListenEnabled ? Colors.blueAccent : Colors.grey),
      child: Text(isListenEnabled ? 'Прослушал речь жизни' : 'Уже прослушал'),
    )));

    if (role == 'economist') buttons.add(fullWidth(EconomistBlock(onAnalytics: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Аналитика'))))));
    if (role == 'hollywood') buttons.add(fullWidth(HollywoodBlock(onOpen: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Hollywood'))))));
    if (role == 'mafia') buttons.add(fullWidth(MafiaBlock(onManage: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Предприятия'))))));
    if (role == 'journalist') buttons.add(fullWidth(JournalistBlock(currentUserId: user.id, onPublished: onRefreshProfile)));
    if (role == 'public_figure') buttons.add(fullWidth(PublicFigureBlock(onOpen: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('События'))))));
    if (role == 'admin') buttons.add(fullWidth(AdminBlock(onRefresh: onRefreshProfile, onAction: (label) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(label))))));

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: buttons);
  }
}
