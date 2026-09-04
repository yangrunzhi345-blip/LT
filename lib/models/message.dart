import 'package:equatable/equatable.dart';

class Message with Equatable {
  final String id;
  final String content;
  final bool isUser;
  final DateTime timestamp;
  final bool isHtml;
  final bool isEdited;
  final String? errorType;

  Message({
    required this.id,
    required this.content,
    required this.isUser,
    DateTime? timestamp,
    this.isHtml = false,
    this.isEdited = false,
    this.errorType,
  }) : timestamp = timestamp ?? DateTime.now();

  Message copyWith({
    String? id,
    String? content,
    bool? isUser,
    DateTime? timestamp,
    bool? isHtml,
    bool? isEdited,
    String? errorType,
  }) {
    return Message(
      id: id ?? this.id,
      content: content ?? this.content,
      isUser: isUser ?? this.isUser,
      timestamp: timestamp ?? this.timestamp,
      isHtml: isHtml ?? this.isHtml,
      isEdited: isEdited ?? this.isEdited,
      errorType: errorType ?? this.errorType,
    );
  }

  /// 是否为错误消息（通过 errorType 字段判断，替代 startsWith('⚠️')）
  bool get isError => errorType != null;

  @override
  List<Object?> get props => [id];
}
