import 'package:drift/drift.dart';
// ignore: deprecated_member_use
import 'package:drift/web.dart';

QueryExecutor openDatabaseConnection() {
  return WebDatabase.withStorage(DriftWebStorage.indexedDb('avera_local'));
}
