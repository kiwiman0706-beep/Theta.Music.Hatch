import 'core/art_cache.dart';
import 'core/dsaudio.dart';
import 'core/library.dart';
import 'core/obsidian.dart';
import 'core/player.dart';
import 'core/scanner.dart';
import 'core/settings.dart';

/// アプリ全体のサービス（シングルトン）
class Services {
  final AppSettings settings;
  final Library library;
  final DsAudioClient ds;
  final Scanner scanner;
  final ArtCache art;
  final Player player;
  final ObsidianExporter obsidian;

  Services._(this.settings, this.library, this.ds, this.scanner, this.art, this.player, this.obsidian);

  static Future<Services> create() async {
    final settings = AppSettings();
    await settings.load();
    final library = Library();
    await library.load();
    final ds = DsAudioClient(settings);
    final art = ArtCache(settings, ds);
    return Services._(
      settings,
      library,
      ds,
      Scanner(settings, library, ds),
      art,
      Player(settings, art, ds),
      // DS audio のときは File Station、WebDAV のときは WebDAV で Vault に書く
      ObsidianExporter(settings, library,
          () => settings.source == MusicSource.dsaudio ? ds : settings.client()),
    );
  }
}

late final Services services;
