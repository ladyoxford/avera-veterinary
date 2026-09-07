import 'dart:convert';
import 'dart:io';

import 'package:avera/core/database/app_database.dart';
import 'package:avera/core/repositories/clinic_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _TestPathProvider extends PathProviderPlatform {
  _TestPathProvider(this.documentsPath);

  final String documentsPath;

  @override
  Future<String?> getApplicationDocumentsPath() async => documentsPath;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'clinic logo is copied out of picker cache and survives repository reload',
    () async {
      final originalProvider = PathProviderPlatform.instance;
      final root = await Directory.systemTemp.createTemp('avera-logo-test-');
      addTearDown(() async {
        PathProviderPlatform.instance = originalProvider;
        if (await root.exists()) await root.delete(recursive: true);
      });
      PathProviderPlatform.instance = _TestPathProvider(root.path);
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final repository = ClinicRepository(database);
      await repository.seedSampleData();
      final session = (await repository.authenticateUser(
        username: 'admin@avera.test',
        password: 'admin123',
      ))!;
      final pickerFile = File('${root.path}/temporary-picker.png');
      final bytes = <int>[137, 80, 78, 71, 13, 10, 26, 10, 1, 2, 3];
      await pickerFile.writeAsBytes(bytes);

      await repository.updateClinicBrandAsset(
        session: session,
        kind: 'logo',
        localPath: pickerFile.path,
        contentType: 'image/png',
        base64Data: base64Encode(bytes),
      );
      await pickerFile.delete();
      final saved = await repository.refreshClinicSettings();
      expect(saved.logo, isNot(equals(pickerFile.path)));
      expect(await File(saved.logo!).readAsBytes(), bytes);

      final reloaded = ClinicRepository(database);
      expect((await reloaded.refreshClinicSettings()).logo, saved.logo);
    },
  );

  test(
    'failed logo replacement leaves the previous local logo intact',
    () async {
      final originalProvider = PathProviderPlatform.instance;
      final root = await Directory.systemTemp.createTemp('avera-logo-failure-');
      addTearDown(() async {
        PathProviderPlatform.instance = originalProvider;
        if (await root.exists()) await root.delete(recursive: true);
      });
      PathProviderPlatform.instance = _TestPathProvider(root.path);
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final repository = ClinicRepository(database);
      await repository.seedSampleData();
      final session = (await repository.authenticateUser(
        username: 'admin@avera.test',
        password: 'admin123',
      ))!;
      final first = <int>[137, 80, 78, 71, 13, 10, 26, 10, 4];
      await repository.updateClinicBrandAsset(
        session: session,
        kind: 'logo',
        localPath: 'first.png',
        contentType: 'image/png',
        base64Data: base64Encode(first),
      );
      final previous = (await repository.refreshClinicSettings()).logo;

      final notDirectory = File('${root.path}/not-a-directory');
      await notDirectory.writeAsString('occupied');
      PathProviderPlatform.instance = _TestPathProvider(notDirectory.path);
      await expectLater(
        repository.updateClinicBrandAsset(
          session: session,
          kind: 'logo',
          localPath: 'replacement.png',
          contentType: 'image/png',
          base64Data: base64Encode(<int>[137, 80, 78, 71, 13, 10, 26, 10, 5]),
        ),
        throwsA(anything),
      );
      expect((await repository.refreshClinicSettings()).logo, previous);
      expect(await File(previous!).readAsBytes(), first);
    },
  );
}
