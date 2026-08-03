import '../domain/sos_state.dart';

class SosService {
  SosState _state = SosState.idle;

  SosState get state => _state;

  void startCountdown() {
    _state = SosState.countdown;
  }

  void sendSOS() {
    _state = SosState.sending;
  }

  void completeSOS() {
    _state = SosState.completed;
  }

  void cancelSOS() {
    _state = SosState.cancelled;
  }

  void reset() {
    _state = SosState.idle;
  }
}
