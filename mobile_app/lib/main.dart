// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'screens/patient_home_screen.dart';
import 'services/background_notification_service.dart';
import 'services/hydropod_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await BackgroundNotificationService.initialize();
  runApp(const HydropodPatientApp());
}

class HydropodPatientApp extends StatefulWidget {
  const HydropodPatientApp({super.key});

  @override
  State<HydropodPatientApp> createState() => _HydropodPatientAppState();
}

class _HydropodPatientAppState extends State<HydropodPatientApp> {
  late final HydropodService _service;

  @override
  void initState() {
    super.initState();
    _service = HydropodService();
  }

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Hydration Pod - Patient App',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0B0D14),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF0EA5E9),
          secondary: Color(0xFF38BDF8),
          surface: Color(0xFF11141C),
          error: Color(0xFFE5484D),
        ),
      ),
      home: PatientHomeScreen(service: _service),
    );
  }
}

