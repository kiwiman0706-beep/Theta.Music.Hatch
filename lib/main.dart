import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio_background/just_audio_background.dart';

import 'app.dart';
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
    return MaterialApp(
      title: 'Theta Music',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: const Color(0xFF1C66D0), useMaterial3: true),
      home: const IPodShell(),
    );
  }
}
