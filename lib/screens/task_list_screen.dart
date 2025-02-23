import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import '../models/task.dart';
import 'login_screen.dart';

class TaskListScreen extends StatefulWidget {
  const TaskListScreen({super.key});

  @override
  _TaskListScreenState createState() => _TaskListScreenState();
}

class _TaskListScreenState extends State<TaskListScreen> with SingleTickerProviderStateMixin {
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  int? _selectedPriorityFilter;
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
  FlutterLocalNotificationsPlugin();
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _checkExistingTasksForNotifications();
    _enableOfflineSupport(); // Включаем оффлайн-поддержку
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _enableOfflineSupport() {
    _firestore.settings = const Settings(
      persistenceEnabled: true, // Включаем локальное кэширование для оффлайн-доступа
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );
  }

  Future<void> _showAddTaskDialog() async {
    if (!mounted) return; // Проверка, что виджет ещё существует

    String? title;
    String? description;
    DateTime? deadline;
    int priority = 1;

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Text(
                "Добавить задачу",
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      decoration: InputDecoration(
                        labelText: "Название задачи",
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        filled: true,
                        fillColor: Colors.grey[200],
                      ),
                      onChanged: (value) => title = value,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      decoration: InputDecoration(
                        labelText: "Описание (опционально)",
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        filled: true,
                        fillColor: Colors.grey[200],
                      ),
                      onChanged: (value) => description = value,
                    ),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: () async {
                        final selectedDate = await showDatePicker(
                          context: dialogContext,
                          initialDate: DateTime.now(),
                          firstDate: DateTime.now(),
                          lastDate: DateTime(2100),
                          builder: (context, child) {
                            return Theme(
                              data: Theme.of(context).copyWith(
                                colorScheme: ColorScheme.fromSwatch(primarySwatch: Colors.blue),
                                dialogBackgroundColor: Colors.white,
                              ),
                              child: child!,
                            );
                          },
                        );
                        if (selectedDate != null) {
                          final selectedTime = await showTimePicker(
                            context: dialogContext,
                            initialTime: TimeOfDay.now(),
                            builder: (context, child) {
                              return Theme(
                                data: Theme.of(context).copyWith(
                                  colorScheme: ColorScheme.fromSwatch(primarySwatch: Colors.blue),
                                  dialogBackgroundColor: Colors.white,
                                ),
                                child: child!,
                              );
                            },
                          );
                          if (selectedTime != null) {
                            deadline = DateTime(
                              selectedDate.year,
                              selectedDate.month,
                              selectedDate.day,
                              selectedTime.hour,
                              selectedTime.minute,
                            );
                            setDialogState(() {});
                          }
                        }
                      },
                      child: Text(
                        deadline == null
                            ? "Выбрать дедлайн"
                            : "Дедлайн: ${deadline.toString().substring(0, 16)}",
                        style: TextStyle(color: Colors.blue),
                      ),
                    ),
                    const SizedBox(height: 16),
                    DropdownButton<int>(
                      value: priority,
                      items: [
                        const DropdownMenuItem(value: 1, child: Text("Низкий", style: TextStyle(fontSize: 16))),
                        const DropdownMenuItem(value: 2, child: Text("Средний", style: TextStyle(fontSize: 16))),
                        const DropdownMenuItem(value: 3, child: Text("Высокий", style: TextStyle(fontSize: 16))),
                      ],
                      onChanged: (value) {
                        setDialogState(() {
                          priority = value!;
                        });
                      },
                      style: const TextStyle(fontSize: 16, color: Colors.black87),
                      underline: Container(
                        height: 2,
                        color: Colors.blue,
                      ),
                      dropdownColor: Colors.white,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    if (dialogContext != null) {
                      Navigator.pop(dialogContext);
                    }
                  },
                  child: const Text("Отмена", style: TextStyle(color: Colors.grey)),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (title != null && title!.isNotEmpty) {
                      final user = _auth.currentUser;
                      if (user != null) {
                        final task = Task(
                          title: title!,
                          description: description,
                          deadline: deadline,
                          priority: priority,
                        );
                        print("Добавление задачи: ${task.toMap()}"); // Отладочный вывод
                        await _firestore
                            .collection('users')
                            .doc(user.uid)
                            .collection('tasks')
                            .add(task.toMap())
                            .then((value) => print("Задача успешно добавлена с ID: ${value.id}"))
                            .catchError((error) => print("Ошибка добавления задачи: $error"));
                        if (mounted && dialogContext != null) {
                          _scheduleNotification(task);
                          Navigator.pop(dialogContext);
                        }
                      } else {
                        if (mounted && dialogContext != null) {
                          ScaffoldMessenger.of(dialogContext).showSnackBar(
                            const SnackBar(content: Text("Пользователь не авторизован!")),
                          );
                        }
                      }
                    } else {
                      if (mounted && dialogContext != null) {
                        ScaffoldMessenger.of(dialogContext).showSnackBar(
                          const SnackBar(content: Text("Название задачи обязательно!")),
                        );
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text("Добавить", style: TextStyle(fontSize: 16)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _scheduleNotification(Task task) async {
    if (task.deadline != null) {
      final now = DateTime.now();
      final deadline = task.deadline!;
      final oneDayBefore = deadline.subtract(const Duration(days: 1));
      final oneHourBefore = deadline.subtract(const Duration(hours: 1));

      // Уведомление за 1 день до дедлайна
      if (oneDayBefore.isAfter(now)) {
        await flutterLocalNotificationsPlugin.zonedSchedule(
          task.hashCode, // Уникальный ID уведомления
          'Напоминание о задаче',
          'Дедлайн для "${task.title}" через 1 день!',
          tz.TZDateTime.from(oneDayBefore, tz.local),
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'task_reminder_channel',
              'Task Reminders',
              channelDescription: 'Напоминания о дедлайнах задач',
              importance: Importance.high,
              priority: Priority.high,
              // Используем androidScheduleMode для точного планирования в версии 18.0.1
            ),
          ),
          uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        );
      }

      // Уведомление за 1 час до дедлайна
      if (oneHourBefore.isAfter(now)) {
        await flutterLocalNotificationsPlugin.zonedSchedule(
          task.hashCode + 1, // Уникальный ID для второго уведомления
          'Напоминание о задаче',
          'Дедлайн для "${task.title}" через 1 час!',
          tz.TZDateTime.from(oneHourBefore, tz.local),
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'task_reminder_channel',
              'Task Reminders',
              channelDescription: 'Напоминания о дедлайнах задач',
              importance: Importance.high,
              priority: Priority.high,
            ),
          ),
          uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        );
      }
    }
  }

  void _sortTasksByPriority(List<Task> taskList) {
    taskList.sort((a, b) => b.priority.compareTo(a.priority));
  }

  Color _getPriorityColor(int priority) {
    switch (priority) {
      case 1:
        return Colors.green;
      case 2:
        return Colors.orange;
      case 3:
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _getPriorityText(int priority) {
    switch (priority) {
      case 1:
        return "Низкий";
      case 2:
        return "Средний";
      case 3:
        return "Высокий";
      default:
        return "Неизвестно";
    }
  }

  List<Task> _getFilteredTasks(List<Task> taskList) {
    if (_selectedPriorityFilter == null) {
      return List.from(taskList);
    }
    return taskList.where((task) => task.priority == _selectedPriorityFilter).toList();
  }

  Future<void> _checkExistingTasksForNotifications() async {
    final user = _auth.currentUser;
    if (user != null) {
      print("Проверка существующих задач для пользователя: ${user.uid}"); // Отладочный вывод
      final snapshot = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('tasks')
          .get();
      print("Найдено задач: ${snapshot.docs.length}"); // Отладочный вывод
      for (var doc in snapshot.docs) { // Исправляем здесь
        final task = Task.fromMap(doc.id, doc.data() as Map<String, dynamic>);
        print("Обработка задачи: ${task.title}"); // Отладочный вывод
        _scheduleNotification(task);
      }
    } else {
      print("Пользователь не авторизован при проверке задач"); // Отладочный вывод
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _auth.currentUser;
    if (user == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => LoginScreen()),
        );
      });
      return const Center(child: CircularProgressIndicator());
    }
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).primaryColor,
        elevation: 0,
        title: Text(
          "Мои задачи (Фильтр: ${_selectedPriorityFilter?.toString() ?? 'Все'})",
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.sort, color: Colors.white),
            onPressed: () async {
              final taskList = await _firestore
                  .collection('users')
                  .doc(user.uid)
                  .collection('tasks')
                  .get()
                  .then((snapshot) {
                print("Сортировка задач: найдено ${snapshot.docs.length} задач");
                return snapshot.docs
                    .map((doc) => Task.fromMap(doc.id, doc.data() as Map<String, dynamic>))
                    .toList();
              });
              _sortTasksByPriority(taskList);
              setState(() {});
            },
            tooltip: "Сортировать по приоритету",
          ),
          PopupMenuButton<int?>(
            icon: const Icon(Icons.filter_list, color: Colors.white),
            tooltip: "Фильтр по приоритету",
            onSelected: (value) {
              setState(() {
                _selectedPriorityFilter = value;
              });
            },
            itemBuilder: (context) => [
              const PopupMenuItem<int?>(value: null, child: Text("Все")),
              const PopupMenuItem<int?>(value: 1, child: Text("Низкий")),
              const PopupMenuItem<int?>(value: 2, child: Text("Средний")),
              const PopupMenuItem<int?>(value: 3, child: Text("Высокий")),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
            },
            tooltip: "Выйти",
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _firestore
            .collection('users')
            .doc(user.uid)
            .collection('tasks')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            print("Ошибка загрузки задач из Firestore: ${snapshot.error}"); // Отладочный вывод
            return const Center(child: Text("Ошибка загрузки задач", style: TextStyle(color: Colors.red)));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final taskDocs = snapshot.data!.docs;
          print("Загружено задач из Firestore: ${taskDocs.length}"); // Отладочный вывод
          final taskList = taskDocs
              .map((doc) => Task.fromMap(doc.id, doc.data() as Map<String, dynamic>))
              .toList();
          final filteredTasks = _getFilteredTasks(taskList);

          return filteredTasks.isEmpty
              ? const Center(
            child: Text(
              "Нет задач с выбранным приоритетом",
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
          )
              : ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: filteredTasks.length,
            itemBuilder: (context, index) {
              final task = filteredTasks[index];
              return Card(
                elevation: 4,
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  contentPadding: const EdgeInsets.all(16),
                  leading: CircleAvatar(
                    backgroundColor: _getPriorityColor(task.priority),
                    radius: 8,
                  ),
                  title: Text(
                    task.title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (task.deadline != null)
                        Text(
                          "Дедлайн: ${task.deadline!.toString().substring(0, 16)}",
                          style: TextStyle(
                            fontSize: 14,
                            color: task.deadline!.isBefore(DateTime.now()) && !task.isCompleted
                                ? Colors.red
                                : Colors.grey,
                          ),
                        ),
                      Text(
                        "Приоритет: ${_getPriorityText(task.priority)}",
                        style: const TextStyle(fontSize: 14, color: Colors.grey),
                      ),
                    ],
                  ),
                  trailing: Checkbox(
                    value: task.isCompleted,
                    onChanged: (value) async {
                      setState(() {
                        _firestore
                            .collection('users')
                            .doc(user.uid)
                            .collection('tasks')
                            .doc(task.id)
                            .update({'isCompleted': value}).then((_) {
                          print("Статус задачи обновлён: ${task.title}");
                        }).catchError((error) {
                          print("Ошибка обновления статуса задачи: $error");
                        });
                      });
                      if (value == true) {
                        // Отменяем уведомления, если задача выполнена
                        await flutterLocalNotificationsPlugin.cancel(task.hashCode);
                        await flutterLocalNotificationsPlugin.cancel(task.hashCode + 1);
                      } else {
                        _scheduleNotification(task); // Перепланируем уведомления, если задача снова стала невыполненной
                      }
                    },
                    activeColor: Colors.blue,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddTaskDialog,
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        elevation: 6,
        shape: const CircleBorder(),
        child: const Icon(Icons.add, size: 30),
        tooltip: "Добавить задачу",
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }
}