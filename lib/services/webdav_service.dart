import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:webdav_client/webdav_client.dart' as wd;

import 'file_scanner_service.dart';

/// WebDAV 书源配置
class WebDavSource {
  final String id;
  final String name;
  final String serverUrl;
  final String username;
  final String password;

  const WebDavSource({
    required this.id,
    required this.name,
    required this.serverUrl,
    required this.username,
    required this.password,
  });

  factory WebDavSource.fromJson(Map<String, dynamic> json) {
    return WebDavSource(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      serverUrl: json['server_url'] as String? ?? '',
      username: json['username'] as String? ?? '',
      password: json['password'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'server_url': serverUrl,
      'username': username,
      'password': password,
    };
  }
}

/// WebDAV 目录条目
class WebDavFileInfo {
  final String name;
  final String path;
  final bool isDirectory;
  final int size;
  final DateTime? modified;

  const WebDavFileInfo({
    required this.name,
    required this.path,
    required this.isDirectory,
    this.size = 0,
    this.modified,
  });
}

/// WebDAV 服务
///
/// 负责连接 WebDAV 网盘、浏览目录结构、下载音频文件到本地。
class WebDavService {
  /// 支持的音频格式（与本地扫描一致）
  static const List<String> supportedExtensions =
      FileScannerService.supportedExtensions;

  /// 创建 WebDAV 客户端
  wd.Client _createClient(WebDavSource source) {
    final client = wd.newClient(
      source.serverUrl.trim(),
      user: source.username.trim(),
      password: source.password,
      debug: false,
    );
    // 连接超时 20 秒；下载不限制时长（大文件可能耗时较长）
    client.setConnectTimeout(20000);
    client.setSendTimeout(60000);
    client.setReceiveTimeout(0);
    return client;
  }

  /// 读取目录内容
  ///
  /// [remotePath] 远程目录路径，如 '/' 或 '/有声书'
  /// 返回目录条目列表（文件夹在前，按名称自然排序）
  Future<List<WebDavFileInfo>> listDirectory(
    WebDavSource source,
    String remotePath,
  ) async {
    final client = _createClient(source);
    final files = await client.readDir(remotePath);

    final infos = <WebDavFileInfo>[];
    for (final file in files) {
      final name = file.name?.trim() ?? '';
      final entryPath = file.path?.trim() ?? '';
      if (name.isEmpty || entryPath.isEmpty) continue;
      // 跳过当前目录自身
      if (entryPath == remotePath) continue;
      infos.add(WebDavFileInfo(
        name: name,
        path: entryPath,
        isDirectory: file.isDir ?? false,
        size: file.size ?? 0,
        modified: file.mTime,
      ));
    }

    // 排序：文件夹优先，其余按名称自然排序
    infos.sort((a, b) {
      if (a.isDirectory != b.isDirectory) {
        return a.isDirectory ? -1 : 1;
      }
      return naturalCompare(a.name, b.name);
    });

    return infos;
  }

  /// 下载远程文件到本地
  ///
  /// [remotePath] 远程文件路径
  /// [localPath] 本地保存路径
  /// [onProgress] 下载进度回调 (已下载字节, 总字节)，总字节未知时为 -1
  Future<File> downloadFile(
    WebDavSource source,
    String remotePath,
    String localPath, {
    void Function(int count, int total)? onProgress,
  }) async {
    final client = _createClient(source);
    await client.read2File(remotePath, localPath, onProgress: onProgress);

    final file = File(localPath);
    if (!await file.exists() || await file.length() == 0) {
      throw Exception('下载失败或文件为空: $remotePath');
    }
    return file;
  }

  /// 判断是否为支持的音频文件
  bool isAudioFile(String name) {
    final lower = name.toLowerCase();
    return supportedExtensions.any((ext) => lower.endsWith(ext));
  }

  /// 从远程路径提取书籍名称（取最后一段目录名）
  static String bookNameFromPath(String remotePath) {
    final trimmed = remotePath.endsWith('/')
        ? remotePath.substring(0, remotePath.length - 1)
        : remotePath;
    final parts = trimmed.split('/');
    final last = parts.lastWhere((p) => p.isNotEmpty, orElse: () => '');
    return last.isEmpty ? '有声书' : last;
  }
}

/// WebDAV 书源持久化存储（SharedPreferences）
class WebDavSourceStore {
  static const String _storageKey = 'webdav_sources';

  /// 加载已保存的书源列表
  Future<List<WebDavSource>> loadSources() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) return [];

    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => WebDavSource.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// 保存书源（同 id 覆盖，插入到最前）
  Future<void> saveSource(WebDavSource source) async {
    final sources = await loadSources();
    sources.removeWhere((s) => s.id == source.id);
    sources.insert(0, source);
    await _persist(sources);
  }

  /// 删除书源
  Future<void> removeSource(String id) async {
    final sources = await loadSources();
    sources.removeWhere((s) => s.id == id);
    await _persist(sources);
  }

  Future<void> _persist(List<WebDavSource> sources) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _storageKey,
      jsonEncode(sources.map((s) => s.toJson()).toList()),
    );
  }
}

/// 自然排序比较函数（数字部分按数值比较）
int naturalCompare(String a, String b) {
  final regExp = RegExp(r'(\d+)|(\D+)');
  final partsA = regExp.allMatches(a).map((m) => m.group(0)!).toList();
  final partsB = regExp.allMatches(b).map((m) => m.group(0)!).toList();

  for (int i = 0; i < partsA.length && i < partsB.length; i++) {
    final partA = partsA[i];
    final partB = partsB[i];
    final numA = int.tryParse(partA);
    final numB = int.tryParse(partB);

    int cmp;
    if (numA != null && numB != null) {
      cmp = numA.compareTo(numB);
    } else {
      cmp = partA.toLowerCase().compareTo(partB.toLowerCase());
    }
    if (cmp != 0) return cmp;
  }
  return partsA.length.compareTo(partsB.length);
}
