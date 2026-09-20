class Validators {
  Validators._();

  static String? validateName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return "Please enter a name";
    }

    if (value.trim().length < 2) {
      return "Name must contain at least 2 characters";
    }

    return null;
  }

  static String? validatePhone(String? value) {
    if (value == null || value.trim().isEmpty) {
      return "Please enter a phone number";
    }

    final phone = value.trim();

    if (!RegExp(r'^[6-9]\d{9}$').hasMatch(phone)) {
      return "Enter a valid 10-digit Indian mobile number";
    }

    return null;
  }
}
