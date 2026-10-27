import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio_background/just_audio_background.dart';

import 'app.dart';
import 'ui/hud/hud_shell.dart';
import 'ui/hud/hud_theme.dart';
import 'ui/shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.thetahatch.theta_music.playback',
    androidNotificationChannelName: 'Playback',
    androidNotificationOngoing: true,
  );
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  services = await Services.create();
  runApp(const ThetaMusicApp());
}

class ThetaMusicApp extends StatelessWidget {
  const ThetaMusicApp({super.key});

  @override
  Widget build(BuildContext context) {
    final s = services.settings;
    // スキンを切り替えたときだけ作り直す
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        if (s.skin == 'theta') {
          return MaterialApp(
            key: const ValueKey('theta'),
            title: 'Theta Music',
            debugShowCheckedModeBanner: false,
            theme: hudMaterialTheme(paletteFor(s.hudTheme, Brightness.light)),
            darkTheme: hudMaterialTheme(paletteFor(s.hudTheme, Brightness.dark)),
            themeMode: ThemeMode.system,
            home: const HudShell(),
          );
        }
        return MaterialApp(
          key: const ValueKey('ipod'),
          title: 'Theta Music',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(colorSchemeSeed: const Color(0xFF1C66D0), useMaterial3: true),
          home: const IPodShell(),
        );
      },
    );
  }
}
