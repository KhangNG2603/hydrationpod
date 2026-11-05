import 'package:flutter/material.dart';
import 'screens/patient_home_screen.dart';
import 'services/hydropod_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
        scaffoldBackgroundColor: const Color(0xFF0B0F17),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF0EA5E9),
          secondary: Color(0xFF38BDF8),
          surface: Color(0xFF111927),
          error: Color(0xFFEF4444),
        ),
      ),
      home: PatientHomeScreen(service: _service),
    );
  }
}

