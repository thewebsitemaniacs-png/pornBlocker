import '../entities/habit_task.dart';
import '../entities/habit_log.dart';

abstract class HabitRepository {
  Future<List<HabitTask>> getTasks();
  Future<void> saveTask(HabitTask task);
  Future<void> deleteTask(String id);
  
  Future<List<HabitLog>> getLogs();
  Future<void> saveLog(HabitLog log);
  
  Future<void> syncWithCloud();
  Future<void> clearLocalData();
}
