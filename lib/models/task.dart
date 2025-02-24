import 'package:cloud_firestore/cloud_firestore.dart';

class Task {
  final String id;
  final String title;
  final String? description;
  final DateTime? deadline;
  final int priority;
  final bool isCompleted;
  final String status;
  final List<Map<String, dynamic>> checklist; // Новое поле для чек-листа

  Task({
    this.id = '',
    required this.title,
    this.description,
    this.deadline,
    required this.priority,
    this.isCompleted = false,
    this.status = 'To Do',
    this.checklist = const [], // По умолчанию пустой список
  });

  factory Task.fromMap(String id, Map<String, dynamic> data) {
    DateTime? deadline;
    if (data['deadline'] != null) {
      if (data['deadline'] is Timestamp) {
        deadline = (data['deadline'] as Timestamp).toDate();
      } else if (data['deadline'] is String) {
        deadline = DateTime.tryParse(data['deadline'] as String);
      }
    }

    // Преобразуем checklist из Firestore
    final checklistData = data['checklist'] as List<dynamic>? ?? [];
    final checklist = checklistData.map((item) {
      final mapItem = item as Map<String, dynamic>;
      return {
        'title': mapItem['title'] ?? '',
        'isCompleted': mapItem['isCompleted'] ?? false,
      };
    }).toList();

    return Task(
      id: id,
      title: data['title'] ?? '',
      description: data['description'],
      deadline: deadline,
      priority: data['priority'] ?? 1,
      isCompleted: data['isCompleted'] ?? false,
      status: data['status'] ?? 'To Do',
      checklist: checklist,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'description': description,
      'deadline': deadline,
      'priority': priority,
      'isCompleted': isCompleted,
      'status': status,
      'checklist': checklist, // Сохраняем чек-лист как массив
    };
  }
}