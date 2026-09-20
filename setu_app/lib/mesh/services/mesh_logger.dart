import 'dart:developer' as developer;

class MeshLogger {
  const MeshLogger._();

  static void info(String message) {
    developer.log(
      message,
      name: 'SETU Mesh',
    );
  }

  static void warning(String message) {
    developer.log(
      message,
      name: 'SETU Mesh',
      level: 900,
    );
  }

  static void error(String message) {
    developer.log(
      message,
      name: 'SETU Mesh',
      level: 1000,
    );
  }
}