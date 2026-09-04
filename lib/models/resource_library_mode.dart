enum ResourceLibraryMode {
  conversation,
  adventure,
  creation,
}

extension ResourceLibraryModeX on ResourceLibraryMode {
  String get storageValue => switch (this) {
        ResourceLibraryMode.conversation => 'conversation',
        ResourceLibraryMode.adventure => 'adventure',
        ResourceLibraryMode.creation => 'creation',
      };

  String get title => switch (this) {
        ResourceLibraryMode.conversation => '对话资料库',
        ResourceLibraryMode.adventure => '场景资料库',
        ResourceLibraryMode.creation => '创作资料库',
      };

  String get emptyTitle => switch (this) {
        ResourceLibraryMode.conversation => '暂无对话角色卡',
        ResourceLibraryMode.adventure => '暂无场景资料',
        ResourceLibraryMode.creation => '暂无创作资料',
      };

  String get emptySubtitle => switch (this) {
        ResourceLibraryMode.conversation => '创建自定义角色卡，或查看过去的聊天记录。',
        ResourceLibraryMode.adventure => '导入角色、地点、规则或剧情资料，用于场景对话。',
        ResourceLibraryMode.creation => '导入世界观、角色设定、章节参考或写作资料，用于创作模式。',
      };
}

ResourceLibraryMode resourceLibraryModeFromString(String? value) {
  return switch (value) {
    'conversation' => ResourceLibraryMode.conversation,
    'creation' => ResourceLibraryMode.creation,
    'adventure' => ResourceLibraryMode.adventure,
    _ => ResourceLibraryMode.adventure,
  };
}
