import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/resources/resource_generation_error.dart';
import 'package:lt_dialogue/domain/errors/app_error.dart';
import 'package:lt_dialogue/features/resource_studio/presentation/resource_studio_user_message.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations.dart';
import 'package:lt_dialogue/services/api_error.dart';

void main() {
  group('ResourceGenerationError', () {
    test('should preserve every API code without retaining provider details',
        () {
      for (final type in ApiErrorType.values) {
        final api = ApiError(type: type, message: 'secret-response');
        final error = resourceGenerationError(api);
        expect(error.code, api.code);
        expect(error.debugMessage, isNull);
        expect(error.cause, isNull);
        expect(error.parameters, isEmpty);
      }
    });

    test('should use types and execution stages rather than diagnostic text',
        () {
      expect(resourceGenerationError(TimeoutException('secret')).code,
          AppErrorCode.timeout);
      expect(resourceGenerationError(const SocketException('secret')).code,
          AppErrorCode.networkUnavailable);
      expect(resourceGenerationError(StateError('network timeout')).code,
          AppErrorCode.unknown);
      expect(
          resourceGenerationError(StateError('secret'),
                  stage: ResourceGenerationFailureStage.lifecycle)
              .code,
          AppErrorCode.resourceLifecycleFailed);
      expect(
          resourceGenerationError(StateError('secret'),
                  stage: ResourceGenerationFailureStage.persistence)
              .code,
          AppErrorCode.resourcePersistenceFailed);
      expect(resourceGenerationErrorFromCode('secret-history-response').code,
          AppErrorCode.unknown);
    });

    test('should render stable and historical failures safely in every locale',
        () {
      for (final locale in const [
        Locale('en'),
        Locale('ja'),
        Locale('ko'),
        Locale('zh'),
        Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
        Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant')
      ]) {
        final l10n = lookupAppLocalizations(locale);
        for (final value in <Object>[
          'secret-history-response',
          StateError('secret-response'),
          const ApiError(
              type: ApiErrorType.rateLimited, message: 'secret-response'),
          'resourceParseFailed',
          'resourceContentInvalid',
          'resourcePersistenceFailed',
          'resourceLifecycleFailed',
          'resourceProviderIncomplete',
        ]) {
          final copy = resourceStudioUserMessage(value, l10n);
          expect(copy, isNotEmpty);
          expect(copy, isNot(contains('secret')));
          expect(copy, isNot(contains('StateError')));
        }
        expect(
            resourceStudioUserMessage(
                ApiError.fromHttpStatus(503, 'secret-provider-response'), l10n),
            isNot(l10n.errorUnknown));
        expect(
            resourceStudioUserMessage(
                ApiError.fromHttpStatus(503, 'secret-provider-response'), l10n),
            isNot(contains('secret')));
        final unknown =
            resourceStudioUserMessage('secret-history-response', l10n);
        for (final code in [
          'resourceParseFailed',
          'resourceContentInvalid',
          'resourcePersistenceFailed',
          'resourceLifecycleFailed',
          'resourceProviderIncomplete'
        ]) {
          expect(resourceStudioUserMessage(code, l10n), isNot(unknown));
        }
      }
    });
  });
}
