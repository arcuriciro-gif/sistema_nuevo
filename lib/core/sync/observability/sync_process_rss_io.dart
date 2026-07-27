import 'dart:io' show ProcessInfo;

int? readProcessRssBytes() {
  try {
    return ProcessInfo.currentRss;
  } catch (_) {
    return null;
  }
}
