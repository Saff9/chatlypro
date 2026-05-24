import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import '../../../../navigation/main_navigation.dart';
import '../../../../services/auth_service.dart';
import 'welcome_screen.dart';


class CalculatorScreen extends StatefulWidget {
  const CalculatorScreen({super.key});

  @override
  State<CalculatorScreen> createState() => _CalculatorScreenState();
}

class _CalculatorScreenState extends State<CalculatorScreen> {
  String _display = '0';
  String _expression = '';
  
  // Secret code to exit camouflage and unlock Chatly
  static const String _secretUnlockCode = '5555';
  static const String _decoyUnlockCode = '9999';

  void _onButtonPressed(String value) async {
    if (value == 'C') {
      setState(() {
        _display = '0';
        _expression = '';
      });
    } else if (value == '=') {
      // Unlock check: Check if entered code matches secret passcode or decoy passcode
      final isRealUnlock = _expression == _secretUnlockCode;
      final isDecoyUnlock = _expression == _decoyUnlockCode;

      if (isRealUnlock || isDecoyUnlock) {
        final settingsBox = Hive.box('settings');
        await settingsBox.put('is_duress_active', isDecoyUnlock);

        final hasSession = await AuthService().tryAutoLogin();
        if (mounted) {
          if (hasSession) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (context) => const MainNavigation()),
            );
          } else {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (context) => const WelcomeScreen()),
            );
          }
        }
        return;
      }

      setState(() {
        // Run math evaluation mock
        try {
          _display = _evaluateExpression(_expression);
        } catch (e) {
          _display = 'Error';
        }
      });
    } else {
      setState(() {
        if (_display == '0' || _display == 'Error') {
          _display = value;
          _expression = value;
        } else {
          _display += value;
          _expression += value;
        }
      });
    }
  }

  String _evaluateExpression(String expr) {
    // Simple basic evaluation mock for demo UI
    if (expr.contains('+')) {
      final parts = expr.split('+');
      return (double.parse(parts[0]) + double.parse(parts[1])).toString();
    } else if (expr.contains('-')) {
      final parts = expr.split('-');
      return (double.parse(parts[0]) - double.parse(parts[1])).toString();
    } else if (expr.contains('*')) {
      final parts = expr.split('*');
      return (double.parse(parts[0]) * double.parse(parts[1])).toString();
    }
    return expr;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Display Screen
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                alignment: Alignment.bottomRight,
                child: Text(
                  _display,
                  style: const TextStyle(color: Colors.white, fontSize: 64, fontWeight: FontWeight.w300),
                ),
              ),
              const SizedBox(height: 20),
              
              // Button Layout
              _buildButtonRow(['7', '8', '9', '/']),
              _buildButtonRow(['4', '5', '6', '*']),
              _buildButtonRow(['1', '2', '3', '-']),
              _buildButtonRow(['C', '0', '=', '+']),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildButtonRow(List<String> buttons) {
    return Expanded(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: buttons.map((btn) {
          final isOperator = ['/', '*', '-', '+', '='].contains(btn);
          final isClear = btn == 'C';
          
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: isOperator 
                      ? Colors.orange 
                      : (isClear ? Colors.grey[700] : Colors.grey[850]),
                  shape: const CircleBorder(),
                ),
                onPressed: () => _onButtonPressed(btn),
                child: Text(
                  btn,
                  style: const TextStyle(fontSize: 28, color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
