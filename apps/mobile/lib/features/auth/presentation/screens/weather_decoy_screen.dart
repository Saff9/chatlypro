import 'package:flutter/material.dart';
import '../../../../services/auth_service.dart';
import '../../../../navigation/main_navigation.dart';
import 'welcome_screen.dart';

class WeatherDecoyScreen extends StatefulWidget {
  const WeatherDecoyScreen({super.key});

  @override
  State<WeatherDecoyScreen> createState() => _WeatherDecoyScreenState();
}

class _WeatherDecoyScreenState extends State<WeatherDecoyScreen> {
  int _tapCount = 0;

  Future<void> _handleUnlockTap() async {
    setState(() {
      _tapCount++;
    });

    if (_tapCount >= 3) {
      // Capture navigator before the async gap to satisfy lint.
      final navigator = Navigator.of(context);
      final hasSession = await AuthService().tryAutoLogin();
      if (mounted) {
        if (hasSession) {
          navigator.pushReplacement(
            MaterialPageRoute(builder: (_) => const MainNavigation()),
          );
        } else {
          navigator.pushReplacement(
            MaterialPageRoute(builder: (_) => const WelcomeScreen()),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Top Location Bar
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'New York',
                        style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Saturday, May 23',
                        style: TextStyle(color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.6)),
                      ),
                    ],
                  ),
                  const Icon(Icons.search_rounded, size: 28),
                ],
              ),
              const SizedBox(height: 24),

              // Temperature Display (Tapping this 3 times is the trigger!)
              GestureDetector(
                onTap: _handleUnlockTap,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF3B82F6), Color(0xFF60A5FA)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF3B82F6).withValues(alpha: 0.3),
                        blurRadius: 15,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Icon(Icons.cloud_queue_rounded, size: 72, color: Colors.white),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '72°F',
                                style: TextStyle(
                                  fontSize: 64,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              Text(
                                'Partly Cloudy',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.white70,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      const Divider(color: Colors.white30, height: 1),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildWeatherDetail(Icons.wind_power_rounded, '12 mph', 'Wind'),
                          _buildWeatherDetail(Icons.water_drop_rounded, '58%', 'Humidity'),
                          _buildWeatherDetail(Icons.wb_sunny_rounded, 'UV Index 3', 'Moderate'),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Hourly Forecast
              const Text(
                'Hourly Forecast',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 120,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    _buildHourlyItem('12 PM', '72°', Icons.cloud_queue_rounded),
                    _buildHourlyItem('1 PM', '74°', Icons.wb_sunny_rounded),
                    _buildHourlyItem('2 PM', '75°', Icons.wb_sunny_rounded),
                    _buildHourlyItem('3 PM', '73°', Icons.cloud_queue_rounded),
                    _buildHourlyItem('4 PM', '70°', Icons.cloud_queue_rounded),
                    _buildHourlyItem('5 PM', '68°', Icons.water_drop_rounded),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Daily Forecast
              const Text(
                '7-Day Forecast',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      _buildDailyRow('Today', '72° / 58°', Icons.cloud_queue_rounded),
                      const Divider(height: 20),
                      _buildDailyRow('Sunday', '75° / 60°', Icons.wb_sunny_rounded),
                      const Divider(height: 20),
                      _buildDailyRow('Monday', '78° / 62°', Icons.wb_sunny_rounded),
                      const Divider(height: 20),
                      _buildDailyRow('Tuesday', '70° / 55°', Icons.water_drop_rounded),
                      const Divider(height: 20),
                      _buildDailyRow('Wednesday', '68° / 52°', Icons.cloud_queue_rounded),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWeatherDetail(IconData icon, String value, String label) {
    return Column(
      children: [
        Icon(icon, color: Colors.white70, size: 20),
        const SizedBox(height: 6),
        Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 10)),
      ],
    );
  }

  Widget _buildHourlyItem(String time, String temp, IconData icon) {
    return Container(
      width: 70,
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.08)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          Text(time, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
          Icon(icon, color: Colors.blueAccent, size: 24),
          Text(temp, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildDailyRow(String day, String range, IconData icon) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(day, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        ),
        Icon(icon, color: Colors.blueAccent, size: 22),
        const SizedBox(width: 20),
        Text(range, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
      ],
    );
  }
}
