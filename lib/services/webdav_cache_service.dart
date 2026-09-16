import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/audio_file.dart';
import 'webdav_service.dart';

/// WebDAV 缓存服务
///
/// 负责管理 WebDAV 文件的本地缓存：
/// - 按需下载：播放前确保文件在本地缓存（拉取到本地再播放）
/// - 预取：播放时提前下载后续几个文件
/// - 清理：停止播放超过 [staleAfter] 时间后自动清除全部缓存
class WebDavCacheService {
  static final WebDavCacheService _instance = WebDavCacheService._internal();
  factory WebDavCacheService() => _instance;
  WebDavCacheService._internal();

  /// 预取的文件数量（当前播放文件之后）
  static const int prefetchCount = 2;

  /// 停止播放多久后自动清除缓存
  static const Duration staleAfter = Duration(hours: 24);

  /// 记录上次播放时间的 SharedPreferences key
  static const String lastPlayTimeKey = 'webdav_last_play_time';

  /// 缓存根目录：应用文档目录/webdav_cache/<bookId>/<文件名>
  Future<Directory> _cacheRoot() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(path.join(docs.path, 'webdav_cache'));
    await dir.create(recursive: true);
    return dir;
  }

  /// 计算缓存文件路径
  Future<String> _cachePathFor(int bookId, AudioFile audio) async {
    final root = await _cacheRoot();
    return path.join(root.path, '$bookId', audio.fileName);
  }

  /// 获取已缓存的文件（不存在或为空时返回 null）
  Future<File?> getCached(int bookId, AudioFile audio) async {
    final file = File(await _cachePathFor(bookId, audio));
    try {
      if (await file.exists() && await file.length() > 0) {
        return file;
      }
    } catch (_) {
      // 忽略检查异常
    }
    return null;
  }

  /// 确保文件在本地缓存（没有则从 WebDAV 下载）
  ///
  /// [onProgress] 下载进度回调 (已下载字节, 总字节)
  Future<File> ensureLocal(
    WebDavSource source,
    int bookId,
    AudioFile audio, {
    void Function(int count, int total)? onProgress,
  }) async {
    final cached = await getCached(bookId, audio);
    if (cached != null) return cached;

    final file = File(await _cachePathFor(bookId, audio));
    await WebDavService().downloadFile(
      source,
      audio.remotePath!,
      file.path,
      onProgress: onProgress,
    );
    return file;
  }

  /// 预取后续文件（逐个下载，失败不中断）
  Future<void> prefetch(
    WebDavSource source,
    int bookId,
    List<AudioFile> upcoming,
  ) async {
    for (final audio in upcoming) {
      if (!audio.isRemote) continue;
      try {
        await ensureLocal(source, bookId, audio);
      } catch (e) {
        // 预取失败不影响主流程，记录日志后继续
        debugPrint('预取失败: ${audio.fileName} - $e');
      }
    }
  }

  /// 记录播放时间（用于闲置清理判断）
  Future<void> recordPlayTime() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      lastPlayTimeKey,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// 检查并清除过期缓存：距离上次播放超过 [staleAfter] 时清空缓存目录
  Future<void> clearStaleCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastPlay = prefs.getInt(lastPlayTimeKey);
      if (lastPlay == null) return;

      final idle = DateTime.now().millisecondsSinceEpoch - lastPlay;
      if (idle > staleAfter.inMilliseconds) {
        debugPrint('⏰ 播放空闲超过 24 小时，自动清除 WebDAV 缓存');
        await clearAllCache();
      }
    } catch (e) {
      debugPrint('清除过期缓存失败: $e');
    }
  }

  /// 清空全部 WebDAV 缓存
  Future<void> clearAllCache() async {
    try {
      final root = await _cacheRoot();
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    } catch (e) {
      debugPrint('清空缓存失败: $e');
    }
  }

  /// 清除某本书的缓存
  Future<void> clearBookCache(int bookId) async {
    try {
      final root = await _cacheRoot();
      final dir = Directory(path.join(root.path, '$bookId'));
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (e) {
      debugPrint('清除书籍缓存失败: $e');
    }
  }
}