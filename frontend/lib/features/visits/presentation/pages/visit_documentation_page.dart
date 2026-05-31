import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/core/utils/user_error_mapper.dart';
import 'package:ai_clinic/features/visits/data/visit_repository.dart';
import 'package:ai_clinic/features/visits/domain/visit_detail.dart';
import 'package:ai_clinic/features/visits/presentation/visit_rpc_messages.dart';

/// Visit documentation shell — loads visit context; SOAP and related sections follow in later stories (V1-5).
class VisitDocumentationPage extends ConsumerStatefulWidget {
  const VisitDocumentationPage({required this.visitId, super.key});

  final String? visitId;

  @override
  ConsumerState<VisitDocumentationPage> createState() => _VisitDocumentationPageState();
}

class _VisitDocumentationPageState extends ConsumerState<VisitDocumentationPage> {
  VisitDetail? _visit;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant VisitDocumentationPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.visitId != widget.visitId) {
      _load();
    }
  }

  Future<void> _load() async {
    final visitId = widget.visitId?.trim();
    if (visitId == null || visitId.isEmpty) {
      setState(() {
        _loading = false;
        _visit = null;
        _error = 'Visit not found.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final visit = await ref.read(visitRepositoryProvider).getVisit(visitId: visitId);
      if (!mounted) {
        return;
      }
      setState(() {
        _visit = visit;
        _loading = false;
      });
    } on RpcFailure catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = visitMessageForRpc(error);
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = UserErrorMapper.mapToUserMessage(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Visit documentation')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    final visit = _visit;
    if (visit == null) {
      return const Center(child: Text('Visit not found.'));
    }

    final dateLabel = DateFormat.yMMMd().format(visit.visitDate.toLocal());

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Visit on $dateLabel', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text('Doctor: ${visit.doctorName}'),
        const SizedBox(height: 4),
        Text('Status: ${visit.status.label}'),
        const SizedBox(height: 24),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              visit.soap == null
                  ? 'SOAP documentation will appear here once you have permission to edit clinical notes.'
                  : 'SOAP sections and specialty fields will be available in the next release step.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ),
      ],
    );
  }
}
