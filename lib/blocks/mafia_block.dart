import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:titanic/widgets/art_deco_button.dart';
import 'package:titanic/screens/mafia_proposal_screen.dart';
import 'package:titanic/screens/collect_debt_screen.dart';
import 'package:titanic/screens/mafia_enterprise_screen.dart';

class MafiaBlock extends StatefulWidget {
  final VoidCallback? onManage;
  final String? currentUserId;
  final String? currentUserRole;
  final Future<void> Function()? onProposalUsed;
  final Future<void> Function()? onDebtCollected;
  final Future<void> Function()? onEnterpriseBought;

  const MafiaBlock({
    Key? key,
    this.onManage,
    this.currentUserId,
    this.currentUserRole,
    this.onProposalUsed,
    this.onDebtCollected,
    this.onEnterpriseBought,
  }) : super(key: key);

  @override
  State<MafiaBlock> createState() => _MafiaBlockState();
}

class _MafiaBlockState extends State<MafiaBlock> {
  final supabase = Supabase.instance.client;
  bool _loading = true;
  bool _showProposalButton = false;
  bool _proposalUsed = false;
  bool _isUsurer = false;
  bool _isMafia = false;

  @override
  void initState() {
    super.initState();
    _checkMafiaRole();
    _checkProposalAvailability();
    _checkUsurerStatus();
  }

  Future<void> _checkMafiaRole() async {
    final roleRaw = widget.currentUserRole ?? '';
    final roleStr = roleRaw.toString().toLowerCase();
    final isMafia = roleStr.contains('мафия') || roleStr.contains('mafia');

    setState(() {
      _isMafia = isMafia;
    });

    if (!isMafia) {
      setState(() => _loading = false);
    }
  }

  Future<void> _checkUsurerStatus() async {
    if (widget.currentUserId == null || 
        widget.currentUserId!.isEmpty || 
        !_isMafia) {
      setState(() {
        _isUsurer = false;
        if (_isMafia) {
          _loading = false;
        }
      });
      return;
    }

    try {
      final row = await supabase
          .from('user_credentials')
          .select('usurer')
          .eq('id', widget.currentUserId!)
          .maybeSingle();

      if (row is Map<String, dynamic>) {
        final usurerFlag = row['usurer'];
        final bool isUsurer = (usurerFlag == true) || 
            (usurerFlag?.toString().toLowerCase() == 'true');

        setState(() {
          _isUsurer = isUsurer;
        });
      } else {
        setState(() {
          _isUsurer = false;
        });
      }
    } catch (e) {
      debugPrint('MafiaBlock._checkUsurerStatus error: $e');
      setState(() {
        _isUsurer = false;
      });
    } finally {
      if (_isMafia) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _checkProposalAvailability() async {
    if (!_isMafia || 
        widget.currentUserId == null || 
        widget.currentUserId!.isEmpty) {
      setState(() {
        _showProposalButton = false;
        if (_isMafia) {
          _loading = false;
        }
      });
      return;
    }

    try {
      final row = await supabase
          .from('user_credentials')
          .select('used_mafia_proposal')
          .eq('id', widget.currentUserId!)
          .maybeSingle();

      if (row is Map<String, dynamic>) {
        final usedFlag = row['used_mafia_proposal'];
        final bool used = (usedFlag == true) || 
            (usedFlag?.toString().toLowerCase() == 'true');

        setState(() {
          _showProposalButton = !used;
          _proposalUsed = used;
        });
      } else {
        setState(() {
          _showProposalButton = true;
          _proposalUsed = false;
        });
      }
    } catch (e) {
      debugPrint('MafiaBlock._checkProposalAvailability error: $e');
      setState(() {
        _showProposalButton = false;
      });
    } finally {
      if (_isMafia) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _openProposalScreen(BuildContext context) async {
    if (!_showProposalButton || _proposalUsed || !_isMafia) return;

    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => MafiaProposalScreen(
          mafiaUserId: widget.currentUserId!,
          onSuccess: () async {
            await _checkProposalAvailability();
            if (widget.onProposalUsed != null) {
              await widget.onProposalUsed!();
            }
          },
        ),
      ),
    );

    if (result == true) {
      setState(() {
        _showProposalButton = false;
        _proposalUsed = true;
      });
    }
  }

  Future<void> _openCollectDebtScreen(BuildContext context) async {
    if (!_isUsurer || !_isMafia) return;

    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CollectDebtScreen(
          usurerId: widget.currentUserId!,
          onSuccess: () async {
            await _checkUsurerStatus();
            if (widget.onDebtCollected != null) {
              await widget.onDebtCollected!();
            }
          },
        ),
      ),
    );

    if (result == true) {
      await _checkUsurerStatus();
      if (widget.onDebtCollected != null) {
        await widget.onDebtCollected!();
      }
    }
  }

  Future<void> _openMafiaEnterpriseScreen(BuildContext context) async {
    if (!_isMafia) return;

    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => MafiaEnterpriseScreen(
          mafiaUserId: widget.currentUserId!,
          onSuccess: () async {
            if (widget.onEnterpriseBought != null) {
              await widget.onEnterpriseBought!();
            }
          },
        ),
      ),
    );

    if (result == true) {
      if (widget.onEnterpriseBought != null) {
        await widget.onEnterpriseBought!();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isMafia) {
      return const SizedBox.shrink();
    }

    if (_loading) {
      return SizedBox(
        width: double.infinity,
        child: ArtDecoButton(
          text: 'Загрузка...',
          onPressed: null,
          loading: true,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: double.infinity,
          child: ArtDecoButton(
            text: 'Купить предприятие (мафия)',
            onPressed: () => _openMafiaEnterpriseScreen(context),
            primary: true,
          ),
        ),

        if (_showProposalButton) ...[
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ArtDecoButton(
              text: 'Предложение от которого нельзя отказаться',
              onPressed: () => _openProposalScreen(context),
              primary: true,
            ),
          ),
        ] else if (_proposalUsed) ...[
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ArtDecoButton(
              text: 'Предложение уже использовано',
              onPressed: null,
            ),
          ),
        ],

        if (_isUsurer) ...[
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ArtDecoButton(
              text: 'Ростовщичество',
              onPressed: () => _openCollectDebtScreen(context),
              primary: true,
            ),
          ),
        ],
      ],
    );
  }
}