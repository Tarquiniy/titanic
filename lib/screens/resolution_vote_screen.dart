import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:titanic/services/game_service.dart';
import 'package:titanic/theme/app_theme.dart';
import 'package:titanic/widgets/art_deco_button.dart';

class ResolutionVoteScreen extends StatefulWidget {
  final int? resolutionId;
  final String userId;
  final GameService service;

  const ResolutionVoteScreen({
    super.key,
    this.resolutionId,
    required this.userId,
    required this.service,
  });

  @override
  State<ResolutionVoteScreen> createState() => _ResolutionVoteScreenState();
}

class _ResolutionVoteScreenState extends State<ResolutionVoteScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final TextEditingController _amountCtrl = TextEditingController();

  bool _loading = true;
  bool _submitting = false;
  bool _success = false;
  String? _successLabel;
  int? _successAmount;

  String _resolutionTitle = 'Политрешение';
  double _mBalance = 0;
  int? _selectedOptionId;
  List<Map<String, dynamic>> _options = [];
  List<Map<String, dynamic>> _resolutions = [];
  Set<int> _betResolutionIds = <int>{};

  bool get _isListMode => widget.resolutionId == null;

  @override
  void initState() {
    super.initState();
    _amountCtrl.addListener(_onAmountChanged);
    _loadData();
  }

  @override
  void dispose() {
    _amountCtrl.removeListener(_onAmountChanged);
    _amountCtrl.dispose();
    super.dispose();
  }

  void _onAmountChanged() {
    if (mounted) setState(() {});
  }

  bool get _hasValidAmount {
    final n = int.tryParse(_amountCtrl.text.trim());
    return n != null && n > 0;
  }

  bool get _canSubmit {
    if (_isListMode) return false;
    return !_loading &&
        !_success &&
        !_submitting &&
        _options.isNotEmpty &&
        _selectedOptionId != null &&
        _hasValidAmount;
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
    });

    try {
      final profile = await _supabase
          .from('user_credentials')
          .select('m_balance')
          .eq('id', widget.userId)
          .maybeSingle();

      double balance = 0;
      final raw = (profile is Map<String, dynamic>) ? profile['m_balance'] : null;
      if (raw is num) {
        balance = raw.toDouble();
      } else {
        balance = double.tryParse((raw ?? '0').toString()) ?? 0;
      }

      if (_isListMode) {
        final rows = await _supabase
            .from('political_resolutions')
            .select('id,title,created_at')
            .eq('is_closed', false)
            .order('created_at', ascending: false);

        final List<Map<String, dynamic>> resolutions = [];
        if (rows is List) {
          resolutions.addAll(rows.map((e) => Map<String, dynamic>.from(e as Map)));
        }

        final ids = resolutions
            .map((r) => r['id'])
            .where((id) => id != null)
            .map((id) => (id is int) ? id : int.tryParse(id.toString()))
            .whereType<int>()
            .toList(growable: false);

        final Set<int> betIds = <int>{};
        if (ids.isNotEmpty) {
          final bets = await _supabase
              .from('political_bets')
              .select('resolution_id')
              .eq('user_id', widget.userId)
              .inFilter('resolution_id', ids);
          if (bets is List) {
            for (final b in bets) {
              final map = (b is Map) ? Map<String, dynamic>.from(b) : null;
              if (map == null) continue;
              final ridRaw = map['resolution_id'];
              final rid = (ridRaw is int) ? ridRaw : int.tryParse(ridRaw?.toString() ?? '');
              if (rid != null) betIds.add(rid);
            }
          }
        }

        if (!mounted) return;
        setState(() {
          _mBalance = balance;
          _resolutions = resolutions;
          _betResolutionIds = betIds;
          _loading = false;
        });
        return;
      }

      final titleRow = await _supabase
          .from('political_resolutions')
          .select('title')
          .eq('id', widget.resolutionId!)
          .maybeSingle();

      final opts = await _supabase
          .from('resolution_options')
          .select('id,label,color')
          .eq('resolution_id', widget.resolutionId!)
          .order('id', ascending: true);

      String title = 'Политрешение';
      if (titleRow is Map<String, dynamic>) {
        final t = (titleRow['title'] ?? '').toString().trim();
        if (t.isNotEmpty) title = t;
      }

      final List<Map<String, dynamic>> options = [];
      if (opts is List) {
        options.addAll(opts.map((e) => Map<String, dynamic>.from(e as Map)));
      }

      if (!mounted) return;
      setState(() {
        _mBalance = balance;
        _resolutionTitle = title;
        _options = options;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось загрузить политрешение: $e')),
      );
    }
  }

  Future<void> _submit() async {
    if (_submitting) return;

    if (_selectedOptionId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Выберите вариант')),
      );
      return;
    }

    final amount = int.tryParse(_amountCtrl.text.trim());
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Введите количество майндов')),
      );
      return;
    }

    if (amount > _mBalance) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Недостаточно майндов: ${_mBalance.toStringAsFixed(0)}')),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      await widget.service.placeBetInResolution(
        resolutionId: widget.resolutionId!,
        optionId: _selectedOptionId!,
        userId: widget.userId,
        amount: amount,
      );

      final selected = _options.firstWhere(
        (e) => (e['id']?.toString() ?? '') == _selectedOptionId.toString(),
        orElse: () => <String, dynamic>{'label': 'вариант'},
      );
      final label = (selected['label'] ?? 'вариант').toString();

      await _loadData();
      if (!mounted) return;
      setState(() {
        _success = true;
        _successLabel = label;
        _successAmount = amount;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка при ставке: $e')),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Widget _buildListMode() {
    return SafeArea(
      child: Column(
        children: [
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: TitanicTheme.surfaceNavy.withOpacity(0.35),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: TitanicTheme.raptureGold.withOpacity(0.35),
              ),
            ),
            child: Text(
              '\u0412\u0430\u0448\u0438 \u043c\u0430\u0439\u043d\u0434\u044b: ${_mBalance.toStringAsFixed(0)}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            child: _resolutions.isEmpty
                ? const Center(
                    child: Text('\u041d\u0435\u0442 \u0430\u043a\u0442\u0438\u0432\u043d\u044b\u0445 \u043f\u043e\u043b\u0438\u0442\u0440\u0435\u0448\u0435\u043d\u0438\u0439'),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    itemCount: _resolutions.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, i) {
                      final res = _resolutions[i];
                      final ridRaw = res['id'];
                      final rid = (ridRaw is int)
                          ? ridRaw
                          : int.tryParse(ridRaw?.toString() ?? '');
                      if (rid == null) return const SizedBox.shrink();
                      final title =
                          (res['title'] ?? '\u041f\u043e\u043b\u0438\u0442\u0440\u0435\u0448\u0435\u043d\u0438\u0435').toString().trim();
                      final alreadyBet = _betResolutionIds.contains(rid);

                      return Container(
                        decoration: BoxDecoration(
                          color: TitanicTheme.surfaceNavy.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: TitanicTheme.raptureGold.withOpacity(0.3),
                          ),
                        ),
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title.isEmpty ? '\u041f\u043e\u043b\u0438\u0442\u0440\u0435\u0448\u0435\u043d\u0438\u0435' : title,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              alreadyBet
                                  ? '\u0412\u044b \u0443\u0436\u0435 \u0441\u0434\u0435\u043b\u0430\u043b\u0438 \u0441\u0442\u0430\u0432\u043a\u0443'
                                  : '\u0421\u0442\u0430\u0432\u043a\u0430 \u0435\u0449\u0435 \u043d\u0435 \u0441\u0434\u0435\u043b\u0430\u043d\u0430',
                            ),
                            const SizedBox(height: 10),
                            ArtDecoButton(
                              text: alreadyBet
                                  ? '\u0421\u0442\u0430\u0432\u043a\u0430 \u0441\u0434\u0435\u043b\u0430\u043d\u0430'
                                  : '\u041e\u0442\u043a\u0440\u044b\u0442\u044c \u043f\u043e\u043b\u0438\u0442\u0440\u0435\u0448\u0435\u043d\u0438\u0435',
                              primary: !alreadyBet,
                              expanded: true,
                              onPressed: alreadyBet
                                  ? null
                                  : () async {
                                      final updated = await Navigator.of(context).push<bool>(
                                        MaterialPageRoute(
                                          builder: (_) => ResolutionVoteScreen(
                                            resolutionId: rid,
                                            userId: widget.userId,
                                            service: widget.service,
                                          ),
                                        ),
                                      );
                                      if (updated == true) {
                                        await _loadData();
                                      }
                                    },
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final keyboardInset = MediaQuery.of(context).viewInsets.bottom;

    return Scaffold(
      appBar: AppBar(title: const Text('Политрешение')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _isListMode
              ? _buildListMode()
              : SafeArea(
              child: Column(
                children: [
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                      children: [
                        Text(
                          _resolutionTitle,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: TitanicTheme.surfaceNavy.withOpacity(0.35),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: TitanicTheme.raptureGold.withOpacity(0.35),
                            ),
                          ),
                          child: Text(
                            'Текущее количество майндов: ${_mBalance.toStringAsFixed(0)}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (_options.isEmpty)
                          const Padding(
                            padding: EdgeInsets.only(top: 16),
                            child: Text('Нет доступных вариантов'),
                          )
                        else ...[
                          ..._options.map((opt) {
                            final oid = (opt['id'] is int)
                                ? opt['id'] as int
                                : int.tryParse(opt['id'].toString()) ?? 0;
                            return RadioListTile<int>(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              value: oid,
                              groupValue: _selectedOptionId,
                              onChanged: _success
                                  ? null
                                  : (v) => setState(() => _selectedOptionId = v),
                              title: Text((opt['label'] ?? '-').toString()),
                              activeColor: TitanicTheme.raptureGold,
                            );
                          }),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _amountCtrl,
                            enabled: !_success,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Введите количество майндов',
                              hintText: 'Введите количество майндов',
                            ),
                          ),
                          const SizedBox(height: 16),
                          if (_success)
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.green.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.green.withOpacity(0.5),
                                ),
                              ),
                              child: Text(
                                'Ставка принята: $_successAmount майндов за "$_successLabel".',
                              ),
                            ),
                        ],
                      ],
                    ),
                  ),
                  AnimatedPadding(
                    duration: const Duration(milliseconds: 160),
                    curve: Curves.easeOut,
                    padding: EdgeInsets.fromLTRB(
                      16,
                      8,
                      16,
                      keyboardInset > 0 ? keyboardInset : 16,
                    ),
                    child: _success
                        ? ArtDecoButton(
                            text: 'Готово',
                            primary: true,
                            expanded: true,
                            onPressed: () => Navigator.of(context).pop(true),
                          )
                        : ArtDecoButton(
                            text: _submitting ? 'Отправка...' : 'Подтвердить',
                            primary: true,
                            expanded: true,
                            loading: _submitting,
                            onPressed: _canSubmit ? _submit : null,
                          ),
                  ),
                ],
              ),
            ),
    );
  }
}
