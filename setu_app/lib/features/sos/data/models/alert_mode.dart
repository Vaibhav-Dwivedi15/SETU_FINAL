enum AlertMode { private, public }

extension AlertModeExtension on AlertMode {
  String get title {
    switch (this) {
      case AlertMode.private:
        return "Private SOS";

      case AlertMode.public:
        return "Public SOS";
    }
  }

  String get description {
    switch (this) {
      case AlertMode.private:
        return "Emergency contacts + Government";

      case AlertMode.public:
        return "Emergency contacts + Nearby Users + Government";
    }
  }
}
