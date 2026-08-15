import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:linkstudy/data/migrations/app_data_migrations.dart';
import 'package:linkstudy/data/migrations/migration.dart';
import 'package:linkstudy/models/app_data.dart';
import 'package:linkstudy/utils/constants.dart';

void main() {
  group('AppData schemaVersion', () {
    test('toJson always writes the current schemaVersion', () {
      final data = AppData(
        
        
        generalMode: AppData.fromJson(const {}).generalMode,
      );

      final json = data.toJson();

      expect(json['schemaVersion'], equals(appDataCurrentSchemaVersion));
    });

    test('encode -> decode round-trips schemaVersion to current', () {
      final original = AppData.fromJson(const {});
      final encoded = original.encode();

      final decoded = AppData.decode(encoded);
      final reencoded = jsonDecode(decoded.encode()) as Map<String, dynamic>;

      expect(reencoded['schemaVersion'], equals(appDataCurrentSchemaVersion));
    });

    test('fromJson accepts raw maps without schemaVersion (legacy)', () {
      // No schemaVersion -> treated as v1 by runner -> still upgrades cleanly.
      final json = <String, dynamic>{};

      // Should not throw.
      final data = AppData.fromJson(json);

      expect(data.generalMode.activeScheduleOrNull, isNotNull);
    });

    test('fromJson throws MigrationException for future schemaVersion', () {
      final json = <String, dynamic>{
        'schemaVersion': appDataCurrentSchemaVersion + 99,
      };

      expect(() => AppData.fromJson(json), throwsA(isA<MigrationException>()));
    });

    test('fromJson rejects future schemaVersion encoded as a string', () {
      final json = <String, dynamic>{
        'schemaVersion': '${appDataCurrentSchemaVersion + 99}',
      };

      expect(() => AppData.fromJson(json), throwsA(isA<MigrationException>()));
    });

    test('fromJson rejects malformed schemaVersion values', () {
      for (final value in ['future', '1.0', 1.5, 0, -1, null]) {
        expect(
          () => AppData.fromJson({'schemaVersion': value}),
          throwsA(isA<MigrationException>()),
        );
      }
    });

    test('import/export envelopes reject non-positive versions', () {
      for (final value in [0, -1]) {
        expect(
          () => ImportExportEnvelope.fromJson({
            'schema': appDataSchema,
            'version': value,
            'data': <String, dynamic>{},
          }),
          throwsA(isA<FormatException>()),
        );
      }
    });

    test('decode runs migrations before constructing AppData', () {
      // Synthesize a JSON document at the current schemaVersion.
      final source = jsonEncode({
        'schemaVersion': appDataCurrentSchemaVersion,
        
      });

      final data = AppData.decode(source);

      expect(data.generalMode.activeScheduleOrNull, isNotNull);
    });
  });
}
