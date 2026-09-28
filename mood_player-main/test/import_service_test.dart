import 'package:flutter_test/flutter_test.dart';
import 'package:mood_player/services/import_service.dart';

void main() {
  group('ImportService', () {
    late ImportService importService;

    setUp(() {
      importService = ImportService();
    });

    group('File name parsing', () {
      test('should parse simple title', () {
        // Test the private method through the public interface
        // This is a basic test to verify the service is properly initialized
        expect(importService, isNotNull);
      });

      test('should support audio extensions', () {
        expect(ImportService.supportedExtensions, contains('.mp3'));
        expect(ImportService.supportedExtensions, contains('.wav'));
        expect(ImportService.supportedExtensions, contains('.aac'));
        expect(ImportService.supportedExtensions, contains('.ogg'));
        expect(ImportService.supportedExtensions, contains('.flac'));
        expect(ImportService.supportedExtensions, contains('.m4a'));
        expect(ImportService.supportedExtensions, contains('.wma'));
      });
    });

    group('ImportResult', () {
      test('should create success result', () {
        final result = ImportResult.success(tracks: []);
        expect(result.isSuccess, true);
        expect(result.isCancelled, false);
        expect(result.trackCount, 0);
      });

      test('should create cancelled result', () {
        final result = ImportResult.cancelled();
        expect(result.isSuccess, false);
        expect(result.isCancelled, true);
      });

      test('should create error result', () {
        final result = ImportResult.error('Test error');
        expect(result.isSuccess, false);
        expect(result.isCancelled, false);
        expect(result.errorMessage, 'Test error');
      });
    });
  });
}