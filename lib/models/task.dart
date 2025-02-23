class Task {
  String id;
  String title;
  String? description;
  DateTime? deadline;
  bool isCompleted;
  int priority;

  Task({
    this.id = '',
    required this.title,
    this.description,
    this.deadline,
    this.isCompleted = false,
    this.priority = 1,
  });

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'description': description,
      'deadline': deadline?.toIso8601String(),
      'isCompleted': isCompleted,
      'priority': priority,
    };
  }

  factory Task.fromMap(String id, Map<String, dynamic> map) {
    return Task(
      id: id,
      title: map['title'] as String,
      description: map['description'] as String?,
      deadline: map['deadline'] != null ? DateTime.parse(map['deadline'] as String) : null,
      isCompleted: map['isCompleted'] as bool? ?? false,
      priority: (map['priority'] as num?)?.toInt() ?? 1,
    );
  }
}