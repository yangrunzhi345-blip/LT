import 'package:flutter/material.dart';

import '../../controllers/resource_crud_controller.dart';
import '../../core/feedback/app_feedback.dart';
import '../../l10n/generated/app_localizations.dart';

void showResourceOperationSuccess(
  BuildContext context,
  ResourceOperationResult result,
  AppLocalizations l10n,
) {
  final message = switch (result.notice) {
    ResourceOperationNotice.movedToTrash => l10n.resourceStudioMovedToTrash,
    null => result.message,
  };
  if (message != null) AppFeedback.success(context, message);
}
