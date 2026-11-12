import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../services/sync_service.dart';

class SyncStatusButton extends StatefulWidget {
  const SyncStatusButton({
    super.key,
    required this.onPressed,
    this.loadRecords = SyncService.pendingRecords,
  });
  final VoidCallback onPressed;
  final Future<List<Map<String, dynamic>>> Function() loadRecords;

  @override
  State<SyncStatusButton> createState() => _SyncStatusButtonState();
}

class _SyncStatusButtonState extends State<SyncStatusButton> {
  Future<List<Map<String, dynamic>>>? _records;
  int? _revision;
  String? _token, _scope;
  Future<List<Map<String, dynamic>>> Function()? _loader;

  Future<List<Map<String, dynamic>>> _recordsFor(int revision) {
    final scope = ApiClient.offlineStore?.scope;
    if (_records == null ||
        _revision != revision ||
        _token != ApiClient.token ||
        _scope != scope ||
        _loader != widget.loadRecords) {
      _revision = revision;
      _token = ApiClient.token;
      _scope = scope;
      _loader = widget.loadRecords;
      _records = widget.loadRecords();
    }
    return _records!;
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<String?>(
    valueListenable: SyncService.lastError,
    builder: (_, _, _) => ValueListenableBuilder<int>(
      valueListenable: SyncService.revision,
      builder: (_, revision, _) => FutureBuilder<List<Map<String, dynamic>>>(
        future: _recordsFor(revision),
        builder: (_, snapshot) {
          final pending =
              snapshot.data
                  ?.where(
                    (record) => !const {
                      'confirmed',
                      'verified_saved',
                    }.contains(record['status']),
                  )
                  .length ??
              0;
          return ValueListenableBuilder<bool>(
            valueListenable: ApiClient.offline,
            builder: (_, offline, _) => IconButton(
              tooltip: snapshot.hasError
                  ? 'تعذر قراءة العمليات المحلية — افتح المزامنة'
                  : SyncService.currentError ??
                        'المزامنة · $pending فاتورة تحتاج متابعة${offline ? ' · دون اتصال' : ''}',
              onPressed: widget.onPressed,
              icon: Badge(
                isLabelVisible: pending > 0 || snapshot.hasError,
                label: Text(snapshot.hasError ? '!' : '$pending'),
                child: Icon(
                  SyncService.currentError != null
                      ? Icons.sync_problem
                      : offline
                      ? Icons.cloud_off_outlined
                      : Icons.cloud_sync_outlined,
                  color: SyncService.currentError == null
                      ? null
                      : Theme.of(context).colorScheme.error,
                  size: 20,
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
}
