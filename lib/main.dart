import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio_background/just_audio_background.dart';

import 'app.dart';
import 'core/shelf.dart';
import 'ui/hud/hud_shell.dart';
import 'ui/hud/hud_theme.dart';
import 'ui/screens.dart' show nav;
import 'ui/shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await JustAudioBackground.init(
    androidNotificationChannelId: 'app.thetahatch.music.playback',
    androidNotificationChannelName: 'Playback',
    androidNotificationOngoing: true,
  );
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  services = await Services.create();
  runApp(const ThetaMusicApp());
  // スキンはシリーズ（Theta Home Hatch の ui.skin）に合わせる
  services.syncFromHub();
  AppLifecycleListener(onResume: services.syncFromHub);
  // Theta Home の棚から押されたら、そのアルバム・アーティストを再生
  ShelfWriter.listen((kind, key) {
    final r = ShelfWriter.resolve(services.library, services.favorites, kind, key);
    if (r == null) return;
    services.player.playList(r.$1, 0, shuffle: r.$2);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        if (services.settings.skin == 'theta') {
          hudNav.selectTab(nowTab);
        } else {
          nav.showNowPlaying();
        }
      } catch (_) {}
    });
  });
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
            title: 'Theta Music Hatch',
            debugShowCheckedModeBanner: false,
            theme: hudMaterialTheme(paletteFor(s.hudTheme, Brightness.light)),
            darkTheme: hudMaterialTheme(paletteFor(s.hudTheme, Brightness.dark)),
            themeMode: ThemeMode.system,
            home: const HudShell(),
          );
        }
        return MaterialApp(
          key: const ValueKey('ipod'),
          title: 'Theta Music Hatch',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(colorSchemeSeed: const Color(0xFF1C66D0), useMaterial3: true),
          home: const IPodShell(),
        );
      },
    );
  }
}
