import 'core/art_cache.dart';
import 'core/library.dart';
import 'core/obsidian.dart';
import 'core/player.dart';
import 'core/scanner.dart';
import 'core/settings.dart';

/// アプリ全体のサービス（シングルトン）
class Services {
  final AppSettings settings;
  final Library library;
  final Scanner scanner;
  final ArtCache art;
  final Player player;
  final ObsidianExporter obsidian;

  Services._(this.settings, this.library, this.scanner, this.art, this.player, this.obsidian);

  static Future<Services> create() async {
    final settings = AppSettings();
    await settings.load();
    final library = Library();
    await library.load();
    final art = ArtCache(settings);
    return Services._(
      settings,
      library,
      Scanner(settings, library),
      art,
      Player(settings, art),
      ObsidianExporter(settings, library),
    );
  }
}

late final Services services;
