import 'sync_process_rss_stub.dart'
    if (dart.library.io) 'sync_process_rss_io.dart' as impl;

/// RSS del proceso (null en web / si no soportado).
int? readProcessRssBytes() => impl.readProcessRssBytes();
