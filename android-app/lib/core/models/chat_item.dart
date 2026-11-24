class ChatItem {
  final String id;
  final String title;
  final DateTime created;
  final bool isPinned;

  ChatItem({
    required this.id,
    required this.title,
    required this.created,
    this.isPinned = false,
  });

  ChatItem copyWith({
    String? id,
    String? title,
    DateTime? created,
    bool? isPinned,
  }) => ChatItem(
    id: id ?? this.id,
    title: title ?? this.title,
    created: created ?? this.created,
    isPinned: isPinned ?? this.isPinned,
  );
}
