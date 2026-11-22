/// How a piece of reference material reaches the generation prompt.
///
/// The three modes cover what the create/detail pages can collect without
/// pulling in a platform file picker:
/// - [paste]: free text the user typed or pasted into the page.
/// - [file]: an imported file, where [SettingCardReferenceInput.label] holds
///   the file name and [SettingCardReferenceInput.text] holds its decoded body.
/// - [existingCard]: a pointer to an existing setting card, carried by
///   [SettingCardReferenceInput.sourceCardId] so the service can load the
///   card's current body at generation time.
enum SettingCardReferenceMode { paste, file, existingCard }

/// One user-supplied reference source for setting-card generation.
final class SettingCardReferenceInput {
  const SettingCardReferenceInput({
    required this.mode,
    this.label = '',
    this.text = '',
    this.sourceCardId = '',
  });

  final SettingCardReferenceMode mode;
  final String label;
  final String text;

  /// Id of an existing card used as reference; empty for paste/file modes.
  final String sourceCardId;

  /// True when there is neither inline text nor a card id to resolve.
  ///
  /// Generation treats this as "no reference supplied" instead of appending an
  /// empty reference section to the prompt.
  bool get isEmpty => text.trim().isEmpty && sourceCardId.trim().isEmpty;
}
