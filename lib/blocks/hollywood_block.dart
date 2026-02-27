import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:titanic/widgets/art_deco_button.dart';
import 'package:titanic/screens/pay_movie_screen.dart';
import 'package:titanic/screens/send_minds_screen.dart';

class HollywoodBlock extends StatelessWidget {
  final VoidCallback? onOpen;
  const HollywoodBlock({Key? key, this.onOpen}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ArtDecoButton(
        text: 'Контент / Ставки',
        onPressed: onOpen,
      ),
    );
  }
}

class HollywoodPayBlock extends StatefulWidget {
  final String currentUserId;
  final String? currentUserRole;
  final Future<void> Function()? onPaid;

  const HollywoodPayBlock({
    Key? key,
    required this.currentUserId,
    this.currentUserRole,
    this.onPaid,
  }) : super(key: key);

  @override
  State<HollywoodPayBlock> createState() => _HollywoodPayBlockState();
}

class _HollywoodPayBlockState extends State<HollywoodPayBlock> {
  final supabase = Supabase.instance.client;
  bool _loading = true;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _determineVisibility();
  }

  Future<void> _determineVisibility() async {
    final roleRaw = widget.currentUserRole ?? '';
    final roleStr = roleRaw.toString().toLowerCase();
    
    if (roleStr.contains('голливуд') || roleStr.contains('hollywood')) {
      setState(() {
        _visible = true;
        _loading = false;
      });
      return;
    }

    if (widget.currentUserId.isEmpty) {
      setState(() {
        _visible = false;
        _loading = false;
      });
      return;
    }

    try {
      final row = await supabase
          .from('user_credentials')
          .select('role')
          .eq('id', widget.currentUserId)
          .maybeSingle();
      
      if (row is Map<String, dynamic>) {
        final dbRole = (row['role'] ?? '').toString().toLowerCase();
        setState(() {
          _visible = dbRole.contains('голливуд') || dbRole.contains('hollywood');
          _loading = false;
        });
        return;
      }
    } catch (e) {
      debugPrint('HollywoodPayBlock: failed to fetch role -> $e');
    }

    setState(() {
      _visible = false;
      _loading = false;
    });
  }

  Future<void> _openPayScreen() async {
    if (!mounted) return;
    
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => PayMovieScreen(currentUserId: widget.currentUserId),
      ),
    );
    
    if (result == true) {
      if (widget.onPaid != null) {
        try {
          await widget.onPaid!();
        } catch (_) {}
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Фильм успешно оплачен!'),
        ),
      );
    }
  }

  Future<void> _openSendMinds() async {
    if (!mounted) return;
    
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => SendMindsScreen(currentUserId: widget.currentUserId),
      ),
    );
    
    if (result == true && widget.onPaid != null) {
      try {
        await widget.onPaid!();
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
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
    
    if (!_visible) {
      return const SizedBox.shrink();
    }
    
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: ArtDecoButton(
            text: 'Оплатить фильм (100 M)',
            onPressed: _openPayScreen,
            primary: true,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: ArtDecoButton(
            text: 'Потратить майнды на рецензию',
            onPressed: _openSendMinds,
          ),
        ),
      ],
    );
  }
}
