// lib/screens/home_role_section.dart
import 'package:flutter/material.dart';
import 'package:titanic/models/app_user.dart';
import 'package:titanic/theme/app_theme.dart';

/// HomeRoleSection — модульный блок кнопок / действий.
/// Поведение:
///  - нормализует роль (lowercase, заменяет пробелы/дефисы на '_')
///  - отображает ТОЛЬКО релевантные кнопки для роли
///  - коллбэки асинхронные: Future<void> Function()?
class HomeRoleSection extends StatelessWidget {
  final AppUser user;

  // State flags
  final bool hasActiveDebate;
  final bool alreadyVotedInActiveDebate;
  final bool hasActiveResolution;
  final bool alreadyBetInActiveResolution;

  // Callbacks (async-friendly)
  final Future<void> Function()? onTransfer;
  final Future<void> Function()? onBuyTurn;
  final Future<void> Function()? onPurchaseEnterprise;
  final Future<void> Function()? onOpenDebates;
  final Future<void> Function()? onOpenResolution;
  final Future<void> Function()? onStartSpeech;

  // Widgets & flows
  final Widget? listenWidget;
  final Future<void> Function()? onHonorArticle;
  final Future<void> Function()? onInvestInColor;
  final bool honorAlreadyUsed;

  // коллбек для мафии — открывает flow "Предложение от которого нельзя отказаться"
  final Future<void> Function()? onMafiaOffer;
  final Future<void> Function()? onMafiaEnterprise;


  const HomeRoleSection({
    super.key,
    required this.user,
    this.hasActiveDebate = false,
    this.alreadyVotedInActiveDebate = false,
    this.hasActiveResolution = false,
    this.alreadyBetInActiveResolution = false,
    this.onTransfer,
    this.onBuyTurn,
    this.onPurchaseEnterprise,
    this.onOpenDebates,
    this.onOpenResolution,
    this.onStartSpeech,
    this.listenWidget,
    this.onHonorArticle,
    this.onInvestInColor,
    this.honorAlreadyUsed = false,
    this.onMafiaOffer, 
    this.onMafiaEnterprise,
  });

  String _normalizedRole() {
    final r = (user.role ?? '').toString();
    return r.toLowerCase().replaceAll(RegExp(r'[\s\-]+'), '_');
  }

  bool _is(String name) => _normalizedRole() == name;

  @override
  Widget build(BuildContext context) {
    final role = _normalizedRole();

    // helper to build a generic square action
    Widget _action(String label, IconData icon, {Future<void> Function()? onTap, String? tooltip}) {
      final enabled = onTap != null;
      return _ActionButton(
        label: label,
        icon: icon,
        onTap: onTap,
        tooltip: tooltip,
        enabled: enabled,
      );
    }

    // Build rows according to role
    final row1 = <Widget>[];
    if (onBuyTurn != null) row1.add(_action('КУПИТЬ ХОД', Icons.flash_on, onTap: onBuyTurn, tooltip: 'Купить ход (если доступно)'));
    if (_is('economist') && onPurchaseEnterprise != null) {
      row1.add(_action('ПРЕДПРИЯТИЕ', Icons.business, onTap: onPurchaseEnterprise, tooltip: 'Купить предприятие (экономистам)'));
    }

    final row2 = <Widget>[];
    if (_is('politician') && onStartSpeech != null) {
      row2.add(_action('Речь жизни (старт)', Icons.record_voice_over, onTap: onStartSpeech, tooltip: 'Запустить речь жизни'));
    }
    if (_is('мафия') && onMafiaEnterprise != null) {
  row2.add(_action('ПРЕДПРИЯТИЕ МАФИИ', Icons.business, 
    onTap: onMafiaEnterprise, 
    tooltip: 'Купить предприятие (только для мафии)'));
}

    final listenArea = <Widget>[];
    if (listenWidget != null) listenArea.add(listenWidget!);

    final rowExtras = <Widget>[];
    if (_is('public_figure') && onInvestInColor != null) {
      rowExtras.add(_action('ВЛОЖИТЬСЯ В ЦВЕТ', Icons.palette, onTap: onInvestInColor, tooltip: 'Вложиться в цвет'));
    }

    // If some rows are empty, we still keep consistent spacing / layout.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 4),
        _SectionTitle(title: 'ВОЗМОЖНОСТИ РОЛИ'),
        const SizedBox(height: 12),
        if (row1.isNotEmpty) _ActionButtonRow(children: row1),
        if (row1.isNotEmpty) const SizedBox(height: 12),
        if (row2.isNotEmpty) _ActionButtonRow(children: row2),
        if (row2.isNotEmpty) const SizedBox(height: 12),
        if (listenArea.isNotEmpty) ...[
          listenArea.first,
          const SizedBox(height: 12),
        ],
        if (rowExtras.isNotEmpty) _ActionButtonRow(children: rowExtras),
      ],
    );
  }
}

/// --------------------------------
/// Вспомогательные виджеты
/// --------------------------------

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: TitanicTheme.titleLarge),
      const SizedBox(height: 6),
      Container(
        width: 72,
        height: 3,
        decoration: BoxDecoration(
          gradient: TitanicTheme.goldGradient,
          borderRadius: BorderRadius.circular(3),
        ),
      ),
    ]);
  }
}

class _ActionButtonRow extends StatelessWidget {
  final List<Widget> children;
  const _ActionButtonRow({required this.children});

  @override
  Widget build(BuildContext context) {
    final items = List<Widget>.from(children);
    while (items.length < 3) items.add(const SizedBox.shrink());
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: items.map((w) => Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6.0), child: w))).toList(),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Future<void> Function()? onTap;
  final bool enabled;
  final String? tooltip;

  const _ActionButton({required this.label, required this.icon, required this.onTap, this.enabled = true, this.tooltip});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onTap == null ? null : () async {
        try {
          await onTap!();
        } catch (e) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
        }
      },
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 12),
      ),
      child: Column(
        children: [
          Icon(icon, size: 20),
          const SizedBox(height: 6),
          Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}
