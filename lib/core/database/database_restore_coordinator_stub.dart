class DatabaseRestoreCoordinator {
  const DatabaseRestoreCoordinator._();

  static Future<void> stage(String sourcePath) async {
    throw UnsupportedError('SQLite restore is unavailable on this platform.');
  }

  static Future<void> applyPendingRestore() async {}

  static Future<Map<String, dynamic>?> readLastReport() async => null;
}
