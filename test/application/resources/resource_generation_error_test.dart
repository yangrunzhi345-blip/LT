import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:lt_dialogue/application/resources/part_generation_validator.dart';
import 'package:lt_dialogue/application/resources/resource_generation_error.dart';
import 'package:lt_dialogue/core/localization/app_error_localizer.dart';
import 'package:lt_dialogue/domain/errors/app_error.dart';
import 'package:lt_dialogue/domain/resources/generation_budget_allocation.dart';
import 'package:lt_dialogue/features/resource_studio/presentation/resource_studio_user_message.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations.dart';
import 'package:lt_dialogue/services/api_error.dart';
import 'package:lt_dialogue/services/llm_service.dart';

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

    test('should classify provider-incomplete and transport failures exactly',
        () {
      final incomplete = LLMResponseIncompleteException(const LLMStreamResult(
        content: '',
        finishReason: LLMFinishReason.interrupted,
        responseCompleted: false,
      ));
      expect(resourceGenerationError(incomplete).code,
          AppErrorCode.resourceProviderIncomplete);

      expect(resourceGenerationError(http.ClientException('reset')).code,
          AppErrorCode.networkUnavailable);
      expect(resourceGenerationError(const SocketException('closed')).code,
          AppErrorCode.networkUnavailable);
      expect(resourceGenerationError(TimeoutException('idle')).code,
          AppErrorCode.timeout);
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

    const infeasibleAllocation = PartGenerationBudgetAllocation(
      ceiling: 1200,
      transportCap: 3000,
      savedOther: 1100,
      remaining: 100,
      futureReserve: 180,
      dispatchableMaximum: 0,
      recommendedTarget: 0,
      minimumCharacters: 180,
      infeasibility: BudgetInfeasibility.belowMinimum,
      unfinishedRequiredCount: 2,
    );

    test('should split infeasible, over-budget and content-incomplete codes',
        () {
      final infeasible = resourceGenerationError(
          const PartGenerationBudgetInfeasibleException(infeasibleAllocation));
      expect(infeasible.code, AppErrorCode.resourceGenerationBudgetInfeasible);
      expect(infeasible.parameters['ceiling'], 1200);
      expect(infeasible.parameters['minimum'], 180);
      expect(infeasible.parameters['allowed'], 0);
      expect(infeasible.parameters['reserve'], 180);

      final overBudget = resourceGenerationError(
          const PartGenerationValidationException('x',
              field: 'generation_budget',
              parameters: {'allowed': 10, 'actual': 20}));
      expect(overBudget.code, AppErrorCode.resourceGenerationBudgetExceeded);
      expect(overBudget.parameters['actual'], 20);

      final contentIncomplete = resourceGenerationError(
          const PartGenerationValidationException('x',
              field: 'content_requirements',
              parameters: {'minimum': 180, 'actual': 1}));
      expect(contentIncomplete.code, AppErrorCode.resourceContentIncomplete);
      expect(contentIncomplete.parameters['minimum'], 180);

      final other = resourceGenerationError(
          const PartGenerationValidationException('x', field: 'part_id'));
      expect(other.code, AppErrorCode.resourceContentInvalid);
    });

    test('should round-trip safe numbers through the persisted diagnostic', () {
      final encoded = encodeGenerationDiagnostic(
          const PartGenerationBudgetInfeasibleException(infeasibleAllocation));
      final decoded = resourceGenerationErrorFromCode(encoded);
      expect(decoded.code, AppErrorCode.resourceGenerationBudgetInfeasible);
      expect(decoded.parameters['ceiling'], 1200);
      expect(decoded.parameters['minimum'], 180);

      // Codes with nothing extra stay plain, so historical rows and existing
      // consumers are unaffected and no ad-hoc JSON is written.
      expect(encodeGenerationDiagnostic(StateError('x')),
          AppErrorCode.unknown.name);
      expect(
          resourceGenerationErrorFromCode(AppErrorCode.resourceParseFailed.name)
              .code,
          AppErrorCode.resourceParseFailed);
      expect(resourceGenerationErrorFromCode('legacy-secret').code,
          AppErrorCode.unknown);
    });

    test('should render infeasible numbers safely in every locale', () {
      final error = resourceGenerationError(
          const PartGenerationBudgetInfeasibleException(infeasibleAllocation));
      for (final locale in const [
        Locale('en'),
        Locale('ja'),
        Locale('ko'),
        Locale('zh'),
        Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
        Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant')
      ]) {
        final copy = localizeAppError(lookupAppLocalizations(locale), error);
        expect(copy, contains('1200'), reason: locale.toString());
        expect(copy, contains('180'), reason: locale.toString());
      }
    });
  });
}
