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

  final List<String> _stages = ['To Do', 'In Progress', 'Done'];

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _checkExistingTasksForNotifications();
    _enableOfflineSupport();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _enableOfflineSupport() {
    _firestore.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );
  }

  Future<void> _showAddTaskDialog() async {
    if (!mounted) return;

    String? title;
    String? description;
    DateTime? deadline;
    int priority = 1;
    List<Map<String, dynamic>> checklist = [];

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
                  onPressed: () => Navigator.pop(dialogContext),
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
                          status: 'To Do',
                          checklist: checklist,
                        );
                        print("Добавление задачи: ${task.toMap()}");
                        await _firestore
                            .collection('users')
                            .doc(user.uid)
                            .collection('tasks')
                            .add(task.toMap())
                            .then((value) => print("Задача добавлена с ID: ${value.id}"))
                            .catchError((error) => print("Ошибка добавления: $error"));
                        if (mounted) {
                          _scheduleNotification(task);
                          Navigator.pop(dialogContext);
                          setState(() {});
                        }
                      } else {
                        if (mounted) {
                          ScaffoldMessenger.of(dialogContext).showSnackBar(
                            const SnackBar(content: Text("Пользователь не авторизован!")),
                          );
                        }
                      }
                    } else {
                      if (mounted) {
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

  Future<void> _showEditTaskDialog(Task task) async {
    if (!mounted) return;

    String title = task.title;
    String? description = task.description;
    DateTime? deadline = task.deadline;
    int priority = task.priority;
    List<Map<String, dynamic>> checklist = List.from(task.checklist); // Копия чек-листа

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Text(
                "Редактировать задачу",
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
                      controller: TextEditingController(text: title),
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
                      controller: TextEditingController(text: description),
                      onChanged: (value) => description = value,
                    ),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: () async {
                        final selectedDate = await showDatePicker(
                          context: dialogContext,
                          initialDate: deadline ?? DateTime.now(),
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
                            initialTime: deadline != null
                                ? TimeOfDay.fromDateTime(deadline!)
                                : TimeOfDay.now(),
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
                    const SizedBox(height: 16),
                    const Text("Чек-лист:", style: TextStyle(fontWeight: FontWeight.bold)),
                    ...checklist.map((item) {
                      return Row(
                        children: [
                          Checkbox(
                            value: item['isCompleted'] as bool,
                            onChanged: (value) {
                              setDialogState(() {
                                item['isCompleted'] = value!;
                              });
                            },
                          ),
                          Expanded(
                            child: TextField(
                              controller: TextEditingController(text: item['title'] as String),
                              onChanged: (value) => item['title'] = value,
                              decoration: const InputDecoration(
                                hintText: "Подзадача",
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () {
                              setDialogState(() {
                                checklist.remove(item);
                              });
                            },
                          ),
                        ],
                      );
                    }).toList(),
                    TextButton(
                      onPressed: () {
                        setDialogState(() {
                          checklist.add({'title': '', 'isCompleted': false});
                        });
                      },
                      child: const Text("Добавить подзадачу", style: TextStyle(color: Colors.blue)),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text("Отмена", style: TextStyle(color: Colors.grey)),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (title.isNotEmpty) {
                      final user = _auth.currentUser;
                      if (user != null) {
                        final updatedTask = Task(
                          id: task.id,
                          title: title,
                          description: description,
                          deadline: deadline,
                          priority: priority,
                          isCompleted: task.isCompleted,
                          status: task.status,
                          checklist: checklist,
                        );
                        print("Обновление задачи: ${updatedTask.toMap()}");
                        await _firestore
                            .collection('users')
                            .doc(user.uid)
                            .collection('tasks')
                            .doc(task.id)
                            .update(updatedTask.toMap())
                            .then((_) => print("Задача обновлена: ${task.id}"))
                            .catchError((error) => print("Ошибка: $error"));
                        if (mounted) {
                          if (!task.isCompleted) {
                            await flutterLocalNotificationsPlugin.cancel(task.hashCode);
                            await flutterLocalNotificationsPlugin.cancel(task.hashCode + 1);
                            _scheduleNotification(updatedTask);
                          }
                          Navigator.pop(dialogContext);
                          setState(() {});
                        }
                      }
                    } else {
                      if (mounted) {
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
                  child: const Text("Сохранить", style: TextStyle(fontSize: 16)),
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

      if (oneDayBefore.isAfter(now)) {
        await flutterLocalNotificationsPlugin.zonedSchedule(
          task.hashCode,
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
            ),
          ),
          uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        );
      }

      if (oneHourBefore.isAfter(now)) {
        await flutterLocalNotificationsPlugin.zonedSchedule(
          task.hashCode + 1,
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
      print("Фильтр 'Все': ${taskList.length} задач");
      return List.from(taskList);
    }
    final filtered = taskList.where((task) => task.priority == _selectedPriorityFilter).toList();
    print("Фильтр $_selectedPriorityFilter: ${filtered.length} задач");
    return filtered;
  }

  Future<void> _checkExistingTasksForNotifications() async {
    final user = _auth.currentUser;
    if (user != null) {
      print("Проверка существующих задач для пользователя: ${user.uid}");
      final snapshot = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('tasks')
          .get();
      print("Найдено задач: ${snapshot.docs.length}");
      for (var doc in snapshot.docs) {
        final task = Task.fromMap(doc.id, doc.data() as Map<String, dynamic>);
        print("Обработка задачи: ${task.title}");
        _scheduleNotification(task);
      }
    } else {
      print("Пользователь не авторизован при проверке задач");
    }
  }

  Future<void> _deleteTask(Task task) async {
    final user = _auth.currentUser;
    if (user != null) {
      try {
        print("Удаление задачи ${task.title}...");
        await _firestore
            .collection('users')
            .doc(user.uid)
            .collection('tasks')
            .doc(task.id)
            .delete();
        print("Задача удалена: ${task.title}");
        await flutterLocalNotificationsPlugin.cancel(task.hashCode);
        await flutterLocalNotificationsPlugin.cancel(task.hashCode + 1);
        setState(() {});
      } catch (error) {
        print("Ошибка при удалении задачи ${task.title}: $error");
      }
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
          key: ValueKey(_selectedPriorityFilter),
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
            itemBuilder: (context) => [
              PopupMenuItem<int?>(
                value: null,
                child: const Text("Все"),
                onTap: () {
                  print("Нажат 'Все'");
                  setState(() {
                    _selectedPriorityFilter = null;
                    print("Фильтр установлен: $_selectedPriorityFilter");
                  });
                },
              ),
              PopupMenuItem<int?>(
                value: 1,
                child: const Text("Низкий"),
                onTap: () {
                  print("Нажат 'Низкий'");
                  setState(() {
                    _selectedPriorityFilter = 1;
                    print("Фильтр установлен: $_selectedPriorityFilter");
                  });
                },
              ),
              PopupMenuItem<int?>(
                value: 2,
                child: const Text("Средний"),
                onTap: () {
                  print("Нажат 'Средний'");
                  setState(() {
                    _selectedPriorityFilter = 2;
                    print("Фильтр установлен: $_selectedPriorityFilter");
                  });
                },
              ),
              PopupMenuItem<int?>(
                value: 3,
                child: const Text("Высокий"),
                onTap: () {
                  print("Нажат 'Высокий'");
                  setState(() {
                    _selectedPriorityFilter = 3;
                    print("Фильтр установлен: $_selectedPriorityFilter");
                  });
                },
              ),
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
        key: ValueKey(_selectedPriorityFilter),
        stream: _firestore
            .collection('users')
            .doc(user.uid)
            .collection('tasks')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            print("Ошибка загрузки задач из Firestore: ${snapshot.error}");
            return const Center(child: Text("Ошибка загрузки задач", style: TextStyle(color: Colors.red)));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final taskDocs = snapshot.data!.docs;
          print("Загружено задач из Firestore: ${taskDocs.length}");
          final taskList = taskDocs
              .map((doc) => Task.fromMap(doc.id, doc.data() as Map<String, dynamic>))
              .toList();
          final filteredTasks = _getFilteredTasks(taskList);

          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: _stages.map((stage) {
                final stageTasks = filteredTasks.where((task) => task.status == stage).toList();
                return SizedBox(
                  width: 300,
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Column(
                      children: [
                        Container(
                          color: Colors.blue[100],
                          padding: const EdgeInsets.all(8.0),
                          child: Text(
                            stage == 'To Do'
                                ? 'К выполнению'
                                : stage == 'In Progress'
                                ? 'В процессе'
                                : 'Выполнено',
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        Expanded(
                          child: DragTarget<Task>(
                            onAcceptWithDetails: (details) async {
                              final movedTask = details.data;
                              final user = _auth.currentUser;
                              if (user != null) {
                                try {
                                  print("Перемещение задачи ${movedTask.title} в $stage...");
                                  await _firestore
                                      .collection('users')
                                      .doc(user.uid)
                                      .collection('tasks')
                                      .doc(movedTask.id)
                                      .update({'status': stage});
                                  print("Задача успешно перемещена в $stage: ${movedTask.title}");
                                  setState(() {});
                                } catch (error) {
                                  print("Ошибка при перемещении задачи ${movedTask.title}: $error");
                                }
                              } else {
                                print("Пользователь не авторизован для перемещения задачи");
                              }
                            },
                            builder: (context, candidateData, rejectedData) {
                              return Container(
                                color: Colors.grey[200],
                                child: stageTasks.isEmpty
                                    ? const Center(
                                  child: Text(
                                    "Нет задач",
                                    style: TextStyle(fontSize: 16, color: Colors.grey),
                                  ),
                                )
                                    : ListView.builder(
                                  itemCount: stageTasks.length,
                                  itemBuilder: (context, index) {
                                    final task = stageTasks[index];
                                    return Draggable<Task>(
                                      data: task,
                                      feedback: Material(
                                        elevation: 4,
                                        child: ConstrainedBox(
                                          constraints: const BoxConstraints(maxWidth: 280),
                                          child: _buildTaskCard(task),
                                        ),
                                      ),
                                      childWhenDragging: Opacity(
                                        opacity: 0.5,
                                        child: _buildTaskCard(task),
                                      ),
                                      child: _buildTaskCard(task),
                                    );
                                  },
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
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

  Widget _buildTaskCard(Task task) {
    return Card(
      elevation: 4,
      margin: const EdgeInsets.symmetric(vertical: 8),
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
            if (task.checklist.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text("Чек-лист:", style: TextStyle(fontWeight: FontWeight.bold)),
              ...task.checklist.map((item) {
                return Row(
                  children: [
                    Checkbox(
                      value: item['isCompleted'] as bool,
                      onChanged: (value) async {
                        setState(() {
                          item['isCompleted'] = value!;
                          _firestore
                              .collection('users')
                              .doc(_auth.currentUser!.uid)
                              .collection('tasks')
                              .doc(task.id)
                              .update({'checklist': task.checklist});
                        });
                      },
                    ),
                    Expanded(
                      child: Text(
                        item['title'] as String,
                        style: TextStyle(
                          fontSize: 14,
                          decoration: item['isCompleted'] ? TextDecoration.lineThrough : null,
                        ),
                      ),
                    ),
                  ],
                );
              }).toList(),
            ],
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Checkbox(
              value: task.isCompleted,
              onChanged: (value) async {
                setState(() {
                  _firestore
                      .collection('users')
                      .doc(_auth.currentUser!.uid)
                      .collection('tasks')
                      .doc(task.id)
                      .update({
                    'isCompleted': value,
                    if (value == true) 'status': 'Done',
                    if (value == false) 'status': 'To Do',
                  }).then((_) {
                    print("Статус задачи обновлён: ${task.title}");
                  }).catchError((error) {
                    print("Ошибка обновления статуса: $error");
                  });
                });
                if (value == true) {
                  await flutterLocalNotificationsPlugin.cancel(task.hashCode);
                  await flutterLocalNotificationsPlugin.cancel(task.hashCode + 1);
                } else {
                  _scheduleNotification(task);
                }
              },
              activeColor: Colors.blue,
            ),
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text("Удалить задачу?"),
                    content: Text("Вы уверены, что хотите удалить задачу '${task.title}'?"),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text("Отмена"),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text("Удалить", style: TextStyle(color: Colors.red)),
                      ),
                    ],
                  ),
                );
                if (confirm == true) {
                  await _deleteTask(task);
                }
              },
              tooltip: "Удалить задачу",
            ),
          ],
        ),
        onTap: () => _showEditTaskDialog(task),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }
}