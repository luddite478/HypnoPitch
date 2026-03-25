import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'screens/main_navigation_screen.dart';
import 'state/audio_player_state.dart';
import 'state/library_state.dart';
import 'state/library_samples_state.dart';
import 'state/patterns_state.dart';
import 'state/sequencer/table.dart';
import 'state/sequencer/playback.dart';
import 'state/sequencer/sample_bank.dart';
import 'state/sequencer_version_state.dart';
import 'state/app_state.dart';
import 'services/local_pattern_service.dart';
import 'services/local_library_service.dart';
import 'services/cache/working_state_cache_service.dart';
import 'services/reliable_storage.dart';
import 'services/tutorial_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);
  await dotenv.load(fileName: ".env");
  GoogleFonts.config.allowRuntimeFetching = false;
  
  // Apply DevHttpOverrides for stage environment to trust self-signed certificates
  final env = dotenv.env['ENV'] ?? '';
  if (env == 'stage') {
    HttpOverrides.global = DevHttpOverrides();
  }
  
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // Audio and library management
        ChangeNotifierProvider(create: (context) => AudioPlayerState()),
        ChangeNotifierProvider(create: (context) => LibraryState()),
        ChangeNotifierProvider(create: (context) => LibrarySamplesState()),
        ChangeNotifierProvider(create: (context) => AppState()),
        
        // Pattern management (replaces thread/collaboration)
        ChangeNotifierProvider(create: (context) => PatternsState()),
        
        // Sequencer states
        ChangeNotifierProvider(create: (context) => SequencerVersionState()),
        ChangeNotifierProvider(create: (context) => TableState()),
        ChangeNotifierProvider(
          create: (context) => PlaybackState(
            Provider.of<TableState>(context, listen: false),
          ),
        ),
        ChangeNotifierProvider(create: (context) => SampleBankState()),
      ],
      child: MaterialApp(
        title: 'App',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
          useMaterial3: true,
        ),
        home: const MainPage(),
      ),
    );
  }
}

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  bool _isLoading = true;
  static const bool _clearStorageOnLaunch = bool.fromEnvironment(
    'CLEAR_STORAGE',
    defaultValue: false,
  );
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeApp();
    });
  }
  
  Future<void> _initializeApp() async {
    final patternsState = context.read<PatternsState>();
    final libraryState = context.read<LibraryState>();
    final appState = context.read<AppState>();
    await _applyClearStorageIfRequested(patternsState, libraryState);
    
    await Future.wait([
      patternsState.loadPatterns(),
      libraryState.loadLibrary(),
      appState.initialize(),
    ]);
    
    setState(() {
      _isLoading = false;
    });
    
    debugPrint('✅ [MAIN] App initialized - loaded patterns and library');
  }

  Future<void> _applyClearStorageIfRequested(
    PatternsState patternsState,
    LibraryState libraryState,
  ) async {
    if (!_clearStorageOnLaunch) {
      return;
    }

    debugPrint('🗑️ [MAIN] CLEAR_STORAGE=true - clearing local app data');
    await Future.wait([
      LocalPatternService.clearAll(),
      LocalLibraryService.clearAll(),
      WorkingStateCacheService.clearAllWorkingStates(),
      ReliableStorage.remove(TutorialService.hasLaunchedBeforeKey),
    ]);

    // Reset in-memory providers to ensure clean reload.
    patternsState.clear();
    libraryState.clear();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Spacer(),
                
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    backgroundColor: Colors.grey[200],
                    valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF333333)),
                    minHeight: 3,
                  ),
                ),
                
                const Spacer(),
              ],
            ),
          ),
        ),
      );
    }

    return const MainNavigationScreen();
  }
}

/// HTTP overrides for development environment
class DevHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (X509Certificate cert, String host, int port) => true;
  }
}
