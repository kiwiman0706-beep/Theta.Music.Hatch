import 'core/art_cache.dart';
import 'core/dsaudio.dart';
import 'core/favorites.dart';
import 'core/library.dart';
import 'core/obsidian.dart';
import 'core/player.dart';
import 'core/scanner.dart';
import 'core/settings.dart';
import 'core/series.dart';
import 'core/shelf.dart';
import 'core/visualizer.dart';
import 'ui/hud/skins.g.dart';

/// アプリ全体のサービス（シングルトン）
class Services {
  final AppSettings settings;
  final Library library;
  final DsAudioClient ds;
  final Scanner scanner;
  final ArtCache art;
  final Player player;
  final ObsidianExporter obsidian;
  final Favorites favorites;
  final Recents recents;
  final ShelfWriter shelf;
  final VisualizerFeed visualizer;

  Services._(this.settings, this.library, this.ds, this.scanner, this.art, this.player, this.obsidian, this.favorites,
      this.recents, this.shelf, this.visualizer);

  /// ハブ（Theta Home Hatch）のスキン（ui.skin）に合わせる。起動時とアプリに戻ったとき
  Future<void> syncFromHub() async {
    if (!settings.followSeriesSkin) return;
    final skin = (await Series.info())['ui.skin'];
    if (skin != null && skinNames.contains(skin) && skin != settings.hudTheme) {
      settings.hudTheme = skin;
      await settings.save();
    }
  }

  static Future<Services> create() async {
    final settings = AppSettings();
    await settings.load();
    final library = Library();
    await library.load();
    final ds = DsAudioClient(settings);
    final art = ArtCache(settings, ds);
    final favorites = Favorites(library, favRating: () => settings.dsFavRating, setRating: ds.setRating);
    await favorites.load();
    final recents = Recents();
    await recents.load();
    final player = Player(settings, art, ds);
    // 再生したアルバムを覚える（Home の棚の「最近再生」）
    player.addListener(() {
      final t = player.current;
      if (t != null && player.playing) recents.played(t);
    });
    final shelf = ShelfWriter(settings, library, favorites, recents, art.load)..start();
    return Services._(
      settings,
      library,
      ds,
      Scanner(settings, library, ds),
      art,
      player,
      // DS audio のときは File Station、WebDAV のときは WebDAV で Vault に書く
      ObsidianExporter(settings, library,
          () => settings.source == MusicSource.dsaudio ? ds : settings.client(),
          favorites: favorites),
      favorites,
      recents,
      shelf,
      VisualizerFeed(settings, player),
    );
  }
}

late final Services services;
