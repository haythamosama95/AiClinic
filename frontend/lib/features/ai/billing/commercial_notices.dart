import 'package:ai_clinic/features/ai/billing/abo_client.dart';
import 'package:ai_clinic/features/ai/availability/ai_availability.dart';
import 'package:flutter/material.dart';

/// Shows commercial notice codes from `GET /v1/subscription`.
class CommercialNotices extends StatefulWidget {
  const CommercialNotices({
    super.key,
    required this.client,
  });

  final AboClient client;

  @override
  State<CommercialNotices> createState() => _CommercialNoticesState();
}

class _CommercialNoticesState extends State<CommercialNotices> {
  var _loading = true;
  List<String> _notices = const [];
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final subscription = await widget.client.getSubscription();
      if (!mounted) {
        return;
      }
      setState(() {
        _notices = subscription.notices;
        _loading = false;
      });
    } on AboContractVersionUnsupportedException {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = const ContractVersionUnsupportedException();
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: const Key('billing_commercial_notices'),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: _buildBody(context),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Text('$_error');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final notice in _notices) Text(notice),
      ],
    );
  }
}
