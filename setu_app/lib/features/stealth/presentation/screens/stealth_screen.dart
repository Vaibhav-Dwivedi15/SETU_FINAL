// =====================================================
// SETU Project
// Module : Stealth Mode (disguised SOS trigger)
// Owner  : Sudheer
// =====================================================
//
// This screen IS the disguise: a working calculator.
// Typing the secret code and pressing "=" fires a silent
// SOS instead of showing a result. No dialog, no snackbar,
// no visible change of any kind — a visible confirmation
// here would defeat the entire point of stealth mode.
//
// Secret code is intentionally simple for the SIH build.
// Before any public/production use this MUST move to a
// user-configurable, securely stored value (Settings) —
// a hardcoded code is a demo-only shortcut, not a real
// safety mechanism.
//
// Block 25: long-press "C" to reach Settings (exit hatch —
// needed once Settings > Stealth Mode makes this the app's
// launch screen, see app_router.dart).
//
// Block 28: also added a faster exit — 3 quick taps on "C"
// (within 1.5s) turns Stealth Mode OFF directly and returns
// to the real home screen, no need to go through Settings.
// Long-press "C" still works too (goes to Settings) as a
// secondary path.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import 'package:setu_app/features/sos/data/models/alert_mode.dart';
import 'package:setu_app/features/sos/data/repositories/sos_repository.dart';
import 'package:setu_app/features/settings/data/repositories/settings_repository.dart';

class StealthScreen extends StatefulWidget {
  const StealthScreen({super.key});

  @override
  State<StealthScreen> createState() => _StealthScreenState();
}

class _StealthScreenState extends State<StealthScreen> {
  // Demo-only hardcoded trigger. See file header note above.
  static const String _secretCode = '1213';

  final SosRepository _sosRepository = SosRepository();

  String _display = '0';
  String _expression = '';
  bool _isSending = false;

  // Block 28: triple-tap "C" exit tracking.
  int _clearTapCount = 0;
  DateTime? _lastClearTapTime;

  void _onDigitPressed(String digit) {
    setState(() {
      if (_display == '0') {
        _display = digit;
      } else {
        _display += digit;
      }
    });
  }

  void _onOperatorPressed(String operator) {
    setState(() {
      _expression += '$_display $operator ';
      _display = '0';
    });
  }

  void _onClearPressed() {
    final now = DateTime.now();

    // Block 28: 3 quick taps on "C" (within 1.5s) turns
    // Stealth Mode off directly and returns to real home —
    // faster than the long-press-to-Settings path.
    if (_lastClearTapTime == null ||
        now.difference(_lastClearTapTime!) > const Duration(milliseconds: 1500)) {
      _clearTapCount = 0;
    }
    _clearTapCount++;
    _lastClearTapTime = now;

    if (_clearTapCount >= 3) {
      _clearTapCount = 0;
      _exitStealthModeDirectly();
      return;
    }

    setState(() {
      _display = '0';
      _expression = '';
    });
  }

  Future<void> _exitStealthModeDirectly() async {
    final settingsRepository = SettingsRepository();
    final settings = await settingsRepository.getSettings();
    await settingsRepository.saveSettings(
      settings.copyWith(stealthMode: false),
    );

    HapticFeedback.heavyImpact();

    if (!mounted) return;
    context.go('/');
  }

  // Hidden exit gesture — long-press "C" to get back into the
  // real app. Without this, once stealth mode redirects the
  // whole app here on launch, there'd be no way back to
  // Settings to turn it off short of clearing app data.
  void _onClearLongPress() {
    context.push('/settings');
  }

  void _onBackspacePressed() {
    setState(() {
      if (_display.length > 1) {
        _display = _display.substring(0, _display.length - 1);
      } else {
        _display = '0';
      }
    });
  }

  Future<void> _onEqualsPressed() async {
    final fullEntry = (_expression + _display)
        .replaceAll(' ', '')
        .replaceAll(RegExp(r'[+\-*/]'), '');

    if (_expression.isEmpty && fullEntry == _secretCode) {
      await _fireSilentSOS();
      return;
    }

    setState(() {
      _display = _evaluate('$_expression$_display');
      _expression = '';
    });
  }

  Future<void> _fireSilentSOS() async {
    if (_isSending) return;
    _isSending = true;

    // Only feedback the sender gets — nothing visible on screen.
    HapticFeedback.vibrate();

    try {
      await _sosRepository.triggerSOS(alertMode: AlertMode.private);
    } catch (_) {
      // Deliberately swallowed: any visible error dialog here
      // would break the disguise. Failures are still recorded
      // in SOS History via SosRepository's own history write.
    } finally {
      _isSending = false;
      if (mounted) {
        setState(() {
          _display = '0';
          _expression = '';
        });
      }
    }
  }

  String _evaluate(String expr) {
    final tokens = expr
        .split(RegExp(r'([+\-*/])'))
        .where((t) => t.trim().isNotEmpty)
        .toList();
    final operators = RegExp(r'[+\-*/]').allMatches(expr).map((m) => m.group(0)!).toList();

    if (tokens.isEmpty) return '0';

    try {
      double result = double.parse(tokens[0]);

      for (int i = 0; i < operators.length && i + 1 < tokens.length; i++) {
        final next = double.parse(tokens[i + 1]);
        switch (operators[i]) {
          case '+':
            result += next;
            break;
          case '-':
            result -= next;
            break;
          case '*':
            result *= next;
            break;
          case '/':
            result = next == 0 ? double.nan : result / next;
            break;
        }
      }

      if (result.isNaN) return 'Error';

      return result == result.roundToDouble()
          ? result.toStringAsFixed(0)
          : result.toString();
    } catch (_) {
      return 'Error';
    }
  }

  Widget _buildButton(
    String label, {
    Color? color,
    Color? textColor,
    VoidCallback? onTap,
    VoidCallback? onLongPress,
  }) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: AspectRatio(
          aspectRatio: 1,
          child: ElevatedButton(
            onPressed: onTap,
            onLongPress: onLongPress,
            style: ElevatedButton.styleFrom(
              backgroundColor: color ?? const Color(0xFF2A2A2A),
              foregroundColor: textColor ?? Colors.white,
              shape: const CircleBorder(),
              padding: EdgeInsets.zero,
            ),
            child: Text(label, style: const TextStyle(fontSize: 24)),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              flex: 2,
              child: Container(
                alignment: Alignment.bottomRight,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 16,
                ),
                child: Text(
                  _display,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 64,
                    fontWeight: FontWeight.w300,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            Expanded(
              flex: 5,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  children: [
                    Row(
                      children: [
                        _buildButton(
                          'C',
                          color: const Color(0xFF3A3A3A),
                          onTap: _onClearPressed,
                          onLongPress: _onClearLongPress,
                        ),
                        _buildButton(
                          '⌫',
                          color: const Color(0xFF3A3A3A),
                          onTap: _onBackspacePressed,
                        ),
                        _buildButton('%', color: const Color(0xFF3A3A3A)),
                        _buildButton(
                          '÷',
                          color: Colors.orange,
                          onTap: () => _onOperatorPressed('/'),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        _buildButton('7', onTap: () => _onDigitPressed('7')),
                        _buildButton('8', onTap: () => _onDigitPressed('8')),
                        _buildButton('9', onTap: () => _onDigitPressed('9')),
                        _buildButton(
                          '×',
                          color: Colors.orange,
                          onTap: () => _onOperatorPressed('*'),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        _buildButton('4', onTap: () => _onDigitPressed('4')),
                        _buildButton('5', onTap: () => _onDigitPressed('5')),
                        _buildButton('6', onTap: () => _onDigitPressed('6')),
                        _buildButton(
                          '−',
                          color: Colors.orange,
                          onTap: () => _onOperatorPressed('-'),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        _buildButton('1', onTap: () => _onDigitPressed('1')),
                        _buildButton('2', onTap: () => _onDigitPressed('2')),
                        _buildButton('3', onTap: () => _onDigitPressed('3')),
                        _buildButton(
                          '+',
                          color: Colors.orange,
                          onTap: () => _onOperatorPressed('+'),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        _buildButton('0', onTap: () => _onDigitPressed('0')),
                        _buildButton('.', onTap: () => _onDigitPressed('.')),
                        _buildButton(
                          '=',
                          color: Colors.orange,
                          onTap: _isSending ? null : _onEqualsPressed,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
