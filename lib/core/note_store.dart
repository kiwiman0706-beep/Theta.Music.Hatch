/// Obsidian ノートの読み書き先（WebDAV か、Synology File Station）
abstract class NoteStore {
  /// 存在しなければ null
  Future<String?> getText(String path);
  Future<void> putText(String path, String text);
  Future<void> mkdirs(String path);
  void close();
}
