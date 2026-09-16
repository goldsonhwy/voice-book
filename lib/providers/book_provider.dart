import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:audio_metadata_reader/audio_metadata_reader.dart' as meta;
import '../models/book.dart';
import '../models/audio_file.dart';
import '../services/database_service.dart';
import '../services/file_scanner_service.dart';
import '../services/webdav_cache_service.dart';

/// 书籍管理 Provider
///
/// 负责管理书籍的增删改查操作，包括：
/// - 书籍列表的加载和缓存
/// - 书籍的创建、更新、删除
/// - 书籍的搜索和筛选
/// - 音频文件的关联管理
class BookProvider extends ChangeNotifier {
  final DatabaseService _databaseService = DatabaseService();

  /// 获取数据库服务实例（用于直接数据库操作）
  DatabaseService get databaseService => _databaseService;

  /// 书籍列表
  List<Book> _books = [];

  /// 当前选中的书籍
  Book? _currentBook;

  /// 当前书籍的音频文件列表
  List<AudioFile> _currentBookAudioFiles = [];

  /// 是否正在加载
  bool _isLoading = false;

  /// 错误信息
  String? _errorMessage;

  // Getters
  List<Book> get books => _books;
  Book? get currentBook => _currentBook;
  List<AudioFile> get currentBookAudioFiles => _currentBookAudioFiles;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  /// 收藏的书籍列表
  List<Book> get favoriteBooks =>
      _books.where((book) => book.isFavorite).toList();

  /// 加载所有书籍
  Future<void> loadBooks() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final db = await _databaseService.database;
      final List<Map<String, dynamic>> maps = await db.query(
        'books',
        orderBy: 'updated_at DESC',
      );

      _books = maps.map((map) => Book.fromMap(map)).toList();

      // 后台补全缺失的音频时长（仅在有书籍时执行，不等待，避免阻塞）
      if (_books.isNotEmpty) {
        _updateMissingDurations();
      }
    } catch (e) {
      _errorMessage = '加载书籍失败: $e';
      debugPrint(_errorMessage);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 根据 ID 获取书籍
  Future<Book?> getBookById(int id) async {
    try {
      final db = await _databaseService.database;
      final List<Map<String, dynamic>> maps = await db.query(
        'books',
        where: 'id = ?',
        whereArgs: [id],
      );

      if (maps.isNotEmpty) {
        return Book.fromMap(maps.first);
      }
      return null;
    } catch (e) {
      _errorMessage = '获取书籍失败: $e';
      debugPrint(_errorMessage);
      return null;
    }
  }

  /// 创建书籍
  Future<Book?> createBook(Book book) async {
    try {
      final db = await _databaseService.database;
      final id = await db.insert('books', book.toMap());

      final newBook = book.copyWith(id: id);
      _books.insert(0, newBook);
      notifyListeners();

      return newBook;
    } catch (e) {
      _errorMessage = '创建书籍失败: $e';
      debugPrint(_errorMessage);
      notifyListeners();
      return null;
    }
  }

  /// 更新书籍
  Future<bool> updateBook(Book book) async {
    if (book.id == null) return false;

    try {
      final db = await _databaseService.database;
      await db.update(
        'books',
        book.toMap(),
        where: 'id = ?',
        whereArgs: [book.id],
      );

      final index = _books.indexWhere((b) => b.id == book.id);
      if (index != -1) {
        _books[index] = book;
      }

      if (_currentBook?.id == book.id) {
        _currentBook = book;
      }

      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = '更新书籍失败: $e';
      debugPrint(_errorMessage);
      notifyListeners();
      return false;
    }
  }

  /// 删除书籍
  Future<bool> deleteBook(int id) async {
    try {
      final db = await _databaseService.database;
      await db.delete(
        'books',
        where: 'id = ?',
        whereArgs: [id],
      );

      // 删除书籍时同时清理其 WebDAV 缓存
      unawaited(WebDavCacheService().clearBookCache(id));

      _books.removeWhere((book) => book.id == id);

      if (_currentBook?.id == id) {
        _currentBook = null;
        _currentBookAudioFiles = [];
      }

      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = '删除书籍失败: $e';
      debugPrint(_errorMessage);
      notifyListeners();
      return false;
    }
  }

  /// 切换收藏状态
  Future<bool> toggleFavorite(int id) async {
    final book = _books.firstWhere((b) => b.id == id);
    final updatedBook = book.copyWith(
      isFavorite: !book.isFavorite,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    return await updateBook(updatedBook);
  }

  /// 设置当前书籍
  Future<void> setCurrentBook(Book book) async {
    _currentBook = book;
    await loadAudioFilesForBook(book.id!);
    notifyListeners();
  }

  /// 加载书籍的音频文件列表
  Future<void> loadAudioFilesForBook(int bookId) async {
    try {
      final db = await _databaseService.database;
      final List<Map<String, dynamic>> maps = await db.query(
        'audio_files',
        where: 'book_id = ?',
        whereArgs: [bookId],
        orderBy: 'sort_order ASC',
      );

      _currentBookAudioFiles =
          maps.map((map) => AudioFile.fromMap(map)).toList();
      notifyListeners();
    } catch (e) {
      _errorMessage = '加载音频文件失败: $e';
      debugPrint(_errorMessage);
      notifyListeners();
    }
  }

  /// 搜索书籍
  List<Book> searchBooks(String query) {
    if (query.isEmpty) return _books;

    final lowerQuery = query.toLowerCase();
    return _books.where((book) {
      return book.title.toLowerCase().contains(lowerQuery) ||
          (book.author?.toLowerCase().contains(lowerQuery) ?? false);
    }).toList();
  }

  /// 更新书籍的当前播放音频
  Future<void> updateCurrentAudio(int bookId, int audioFileId) async {
    try {
      final db = await _databaseService.database;
      await db.update(
        'books',
        {
          'current_audio_file_id': audioFileId,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [bookId],
      );

      final index = _books.indexWhere((b) => b.id == bookId);
      if (index != -1) {
        _books[index] = _books[index].copyWith(
          currentAudioFileId: audioFileId,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        );
      }

      if (_currentBook?.id == bookId) {
        _currentBook = _currentBook!.copyWith(
          currentAudioFileId: audioFileId,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        );
      }

      notifyListeners();
    } catch (e) {
      debugPrint('更新书籍当前音频失败: $e');
    }
  }

  /// 清空错误信息
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  /// 预览重新扫描结果（不修改数据库）
  /// 返回扫描结果：{added: 新增数, removed: 删除数, updated: 更新数}
  Future<Map<String, int>> previewRescanFolder(Book book) async {
    if (book.sourceFolderPath == null || book.id == null) {
      throw Exception('书籍没有源文件夹路径');
    }

    final dir = Directory(book.sourceFolderPath!);
    if (!await dir.exists()) {
      throw Exception('源文件夹不存在: ${book.sourceFolderPath}');
    }

    // 扫描文件夹获取当前文件
    final scannedFiles = <String, File>{};
    await for (final entity in dir.list(recursive: true)) {
      if (entity is File && _isAudioFile(entity.path)) {
        scannedFiles[entity.path] = entity;
      }
    }

    final db = await _databaseService.database;

    // 获取现有音频记录
    final existingRows = await db.query(
      'audio_files',
      where: 'book_id = ?',
      whereArgs: [book.id],
    );
    final existingPaths = <String, int>{};
    for (final row in existingRows) {
      existingPaths[row['file_path'] as String] = row['file_size'] as int;
    }

    int added = 0, removed = 0, updated = 0;

    // 检测删除的文件
    for (final path in existingPaths.keys) {
      if (!scannedFiles.containsKey(path)) {
        removed++;
      }
    }

    // 检测新增和更新的文件
    for (final entry in scannedFiles.entries) {
      final path = entry.key;
      final file = entry.value;

      if (!existingPaths.containsKey(path)) {
        added++;
      } else {
        final stat = await file.stat();
        if (stat.size != existingPaths[path]) {
          updated++;
        }
      }
    }

    return {'added': added, 'removed': removed, 'updated': updated};
  }

  /// 应用重新扫描的变更
  Future<void> applyRescanChanges(Book book, Map<String, int> preview) async {
    if (book.sourceFolderPath == null || book.id == null) return;

    final dir = Directory(book.sourceFolderPath!);
    if (!await dir.exists()) return;

    // 扫描文件夹获取当前文件
    final scannedFiles = <String, File>{};
    await for (final entity in dir.list(recursive: true)) {
      if (entity is File && _isAudioFile(entity.path)) {
        scannedFiles[entity.path] = entity;
      }
    }

    final db = await _databaseService.database;

    // 获取现有音频记录
    final existingRows = await db.query(
      'audio_files',
      where: 'book_id = ?',
      whereArgs: [book.id],
    );
    final existingPaths = <String, Map<String, dynamic>>{};
    for (final row in existingRows) {
      existingPaths[row['file_path'] as String] = row;
    }

    // 删除不存在的文件
    for (final path in existingPaths.keys) {
      if (!scannedFiles.containsKey(path)) {
        await db.delete('audio_files', where: 'file_path = ?', whereArgs: [path]);
      }
    }

    // 新增和更新文件
    int maxSortOrder = existingRows.isEmpty
        ? -1
        : existingRows.map((r) => r['sort_order'] as int).reduce((a, b) => a > b ? a : b);

    for (final entry in scannedFiles.entries) {
      final path = entry.key;
      final file = entry.value;

      if (!existingPaths.containsKey(path)) {
        maxSortOrder++;
        final stat = await file.stat();
        final fileName = path.split(Platform.pathSeparator).last;
        await db.insert('audio_files', {
          'book_id': book.id,
          'file_path': path,
          'file_name': fileName,
          'file_size': stat.size,
          'duration': 0,
          'sort_order': maxSortOrder,
          'created_at': DateTime.now().millisecondsSinceEpoch,
        });
      } else {
        final existing = existingPaths[path]!;
        final stat = await file.stat();
        if (stat.size != existing['file_size']) {
          await db.update(
            'audio_files',
            {'file_size': stat.size, 'duration': 0},
            where: 'id = ?',
            whereArgs: [existing['id']],
          );
        }
      }
    }

    // 更新书籍总时长
    final totalResult = await db.rawQuery(
      'SELECT SUM(duration) as total FROM audio_files WHERE book_id = ?',
      [book.id],
    );
    final totalDuration = totalResult.first['total'] as int? ?? 0;
    await db.update(
      'books',
      {
        'total_duration': totalDuration,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [book.id],
    );

    // 刷新数据
    await loadBooks();
    if (_currentBook?.id == book.id) {
      await loadAudioFilesForBook(book.id!);
    }

    // 后台补全新增文件的时长
    _updateMissingDurations();
  }

  /// 判断是否为支持的音频文件
  bool _isAudioFile(String path) {
    const extensions = [
      '.mp3', '.m4a', '.m4b', '.wav', '.flac', '.aac', '.ogg', '.opus',
      '.wma', '.ape', '.amr', '.ac3', '.dts', '.ra', '.rm',
      '.wv', '.tta', '.mka', '.spx', '.caf', '.au', '.snd',
    ];
    final lower = path.toLowerCase();
    return extensions.any((ext) => lower.endsWith(ext));
  }

  /// 后台补全缺失的音频时长（duration=0 的记录）
  Future<void> _updateMissingDurations() async {
    try {
      final db = await _databaseService.database;

      // 查找所有 duration=0 的本地音频文件（跳过 WebDAV 远程文件）
      final rows = await db.query(
        'audio_files',
        where: 'duration = 0 AND remote_path IS NULL',
      );
      if (rows.isEmpty) return;

      // 在隔离线程中批量读取时长
      final filePaths = rows.map((r) => r['file_path'] as String).toList();
      final durations = await compute(_readDurationsInIsolate, filePaths);

      // 按书籍分组统计
      final Map<int, int> bookDurations = {};

      for (int i = 0; i < rows.length; i++) {
        final id = rows[i]['id'] as int;
        final bookId = rows[i]['book_id'] as int;
        final duration = durations[i];

        if (duration > 0) {
          await db.update('audio_files', {'duration': duration}, where: 'id = ?', whereArgs: [id]);
          bookDurations[bookId] = (bookDurations[bookId] ?? 0) + duration;
        }
      }

      // 更新受影响书籍的总时长
      for (final entry in bookDurations.entries) {
        final totalResult = await db.rawQuery(
          'SELECT SUM(duration) as total FROM audio_files WHERE book_id = ?',
          [entry.key],
        );
        final total = totalResult.first['total'] as int? ?? 0;
        await db.update('books', {'total_duration': total}, where: 'id = ?', whereArgs: [entry.key]);
      }

      // 刷新数据（直接查询，避免递归调用 loadBooks）
      if (bookDurations.isNotEmpty) {
        final bookMaps = await db.query('books', orderBy: 'updated_at DESC');
        _books = bookMaps.map((map) => Book.fromMap(map)).toList();

        if (_currentBook != null && bookDurations.containsKey(_currentBook!.id)) {
          await loadAudioFilesForBook(_currentBook!.id!);
        }
        notifyListeners();
      }
    } catch (e) {
      debugPrint('补全音频时长失败: $e');
    }
  }

  /// 将本地音频文件导入为书籍（本地导入与 WebDAV 导入共用）
  ///
  /// [files] 本地音频文件列表（已按播放顺序排好）
  /// [sourceFolderPath] 源文件夹路径（用于后续重新扫描）
  /// [onProgress] 元数据读取进度回调 (当前, 总数)
  /// 返回创建的书籍；失败返回 null
  Future<Book?> importAudioFiles({
    required String title,
    String? author,
    required List<File> files,
    String? sourceFolderPath,
    void Function(int current, int total)? onProgress,
  }) async {
    if (files.isEmpty) return null;

    // 读取所有音频文件的元数据
    final metadataList = await FileScannerService().readMultipleMetadata(
      files,
      onProgress: onProgress,
    );

    // 计算总时长
    int totalDuration = 0;
    for (final metadata in metadataList) {
      totalDuration += metadata.duration ?? 0;
    }

    final now = DateTime.now().millisecondsSinceEpoch;

    // 创建书籍
    final book = Book(
      title: title,
      author: author,
      totalDuration: totalDuration,
      createdAt: now,
      updatedAt: now,
      sourceFolderPath: sourceFolderPath,
    );

    final createdBook = await createBook(book);
    if (createdBook == null) return null;

    // 创建音频文件记录（使用已读取的元数据）
    final db = await _databaseService.database;
    for (int i = 0; i < files.length; i++) {
      final metadata = metadataList[i];
      final audioFile = AudioFile(
        bookId: createdBook.id!,
        filePath: metadata.filePath,
        fileName: metadata.fileName,
        fileSize: metadata.fileSize,
        duration: metadata.duration ?? 0,
        sortOrder: i,
        createdAt: now,
      );
      await db.insert('audio_files', audioFile.toMap());
    }

    // 刷新书籍列表（会自动触发后台补全时长）
    await loadBooks();

    return createdBook;
  }

  /// 创建 WebDAV 书籍（只记录远程路径，不下载文件，播放时按需拉取缓存）
  ///
  /// [files] 远程文件信息列表（已按播放顺序排好）
  /// [webdavSourceId] 关联的书源 ID
  Future<Book?> createWebDavBook({
    required String title,
    String? author,
    required String webdavSourceId,
    required List<WebDavRemoteFileInfo> files,
  }) async {
    if (files.isEmpty) return null;

    final now = DateTime.now().millisecondsSinceEpoch;

    final book = Book(
      title: title,
      author: author,
      createdAt: now,
      updatedAt: now,
      webdavSourceId: webdavSourceId,
    );

    final createdBook = await createBook(book);
    if (createdBook == null) return null;

    final db = await _databaseService.database;
    for (int i = 0; i < files.length; i++) {
      final info = files[i];
      final audioFile = AudioFile(
        bookId: createdBook.id!,
        // 远程书籍没有本地文件，file_path 存远程路径用于标识
        filePath: info.remotePath,
        fileName: info.fileName,
        fileSize: info.fileSize,
        duration: 0,
        sortOrder: i,
        createdAt: now,
        remotePath: info.remotePath,
      );
      await db.insert('audio_files', audioFile.toMap());
    }

    // 刷新书籍列表
    await loadBooks();

    return createdBook;
  }
}

/// WebDAV 远程文件信息（导入时使用）
class WebDavRemoteFileInfo {
  final String remotePath;
  final String fileName;
  final int fileSize;

  const WebDavRemoteFileInfo({
    required this.remotePath,
    required this.fileName,
    required this.fileSize,
  });
}

/// 在隔离线程中读取音频时长（顶层函数）
List<int> _readDurationsInIsolate(List<String> filePaths) {
  return filePaths.map((path) {
    try {
      final metadata = meta.readMetadata(File(path), getImage: false);
      return metadata.duration?.inMilliseconds ?? 0;
    } catch (_) {
      return 0;
    }
  }).toList();
}
