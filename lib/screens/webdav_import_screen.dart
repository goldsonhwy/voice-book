import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/book_provider.dart';
import '../services/webdav_service.dart';
import '../utils/helpers.dart';

/// WebDAV 网盘导入页面
///
/// 支持：
/// 1. 配置并保存多个 WebDAV 书源（服务器地址、用户名、密码）
/// 2. 浏览 WebDAV 网盘目录结构
/// 3. 勾选音频文件，下载到本地并导入为书籍
class WebDavImportScreen extends StatefulWidget {
  const WebDavImportScreen({super.key});

  @override
  State<WebDavImportScreen> createState() => _WebDavImportScreenState();
}

class _WebDavImportScreenState extends State<WebDavImportScreen> {
  final _service = WebDavService();
  final _sourceStore = WebDavSourceStore();

  // 配置表单
  final _nameController = TextEditingController();
  final _urlController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  // 书籍信息
  final _bookNameController = TextEditingController();
  final _authorController = TextEditingController();

  // 已保存书源
  List<WebDavSource> _sources = [];
  WebDavSource? _currentSource;

  // 目录浏览状态
  String _currentPath = '/';
  List<WebDavFileInfo> _entries = [];
  final Set<String> _selectedPaths = {};

  bool _busy = false;
  String _statusMessage = '准备就绪';

  @override
  void initState() {
    super.initState();
    _loadSources();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _bookNameController.dispose();
    _authorController.dispose();
    super.dispose();
  }

  Future<void> _loadSources() async {
    final sources = await _sourceStore.loadSources();
    if (mounted) {
      setState(() => _sources = sources);
    }
  }

  /// 连接书源并进入目录浏览
  Future<void> _connect(WebDavSource? existing) async {
    final url = _urlController.text.trim();
    if (existing == null && url.isEmpty) {
      _showSnack('请输入服务器地址');
      return;
    }

    setState(() {
      _busy = true;
      _statusMessage = '正在连接 WebDAV 服务器...';
    });

    try {
      final source = existing ??
          WebDavSource(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            name: _nameController.text.trim().isEmpty
                ? _urlHost(url)
                : _nameController.text.trim(),
            serverUrl: url,
            username: _usernameController.text.trim(),
            password: _passwordController.text,
          );

      // 读取根目录验证连接
      final entries = await _service.listDirectory(source, '/');

      // 连接成功，保存书源
      await _sourceStore.saveSource(source);
      await _loadSources();

      if (!mounted) return;
      setState(() {
        _currentSource = source;
        _currentPath = '/';
        _entries = entries;
        _selectedPaths.clear();
        _bookNameController.text = '';
        _statusMessage = '连接成功';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _statusMessage = '连接失败: $e';
      });
      _showSnack('连接失败: $e');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  /// 断开书源，返回配置页
  void _disconnect() {
    setState(() {
      _currentSource = null;
      _currentPath = '/';
      _entries = [];
      _selectedPaths.clear();
      _statusMessage = '准备就绪';
    });
  }

  /// 进入子目录
  Future<void> _enterDirectory(WebDavFileInfo dir) async {
    final source = _currentSource;
    if (source == null) return;

    setState(() {
      _busy = true;
      _statusMessage = '正在读取目录...';
    });

    try {
      final entries = await _service.listDirectory(source, dir.path);
      if (!mounted) return;
      setState(() {
        _currentPath = dir.path;
        _entries = entries;
        _statusMessage = '已加载 ${entries.length} 个项目';
        // 自动用目录名作为书籍名称（可修改）
        _bookNameController.text = WebDavService.bookNameFromPath(dir.path);
      });
    } catch (e) {
      if (mounted) _showSnack('读取目录失败: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 返回上级目录
  Future<void> _goUp() async {
    final source = _currentSource;
    if (source == null || _currentPath == '/') return;

    final parent = _parentPath(_currentPath);

    setState(() {
      _busy = true;
      _statusMessage = '正在读取目录...';
    });

    try {
      final entries = await _service.listDirectory(source, parent);
      if (!mounted) return;
      setState(() {
        _currentPath = parent;
        _entries = entries;
        _bookNameController.text = WebDavService.bookNameFromPath(parent);
      });
    } catch (e) {
      if (mounted) _showSnack('读取目录失败: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 刷新当前目录
  Future<void> _refresh() async {
    final source = _currentSource;
    if (source == null) return;

    setState(() {
      _busy = true;
      _statusMessage = '正在刷新...';
    });

    try {
      final entries = await _service.listDirectory(source, _currentPath);
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _statusMessage = '已刷新';
      });
    } catch (e) {
      if (mounted) _showSnack('刷新失败: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 勾选/取消音频文件
  void _toggleSelect(WebDavFileInfo file) {
    setState(() {
      if (_selectedPaths.contains(file.path)) {
        _selectedPaths.remove(file.path);
      } else {
        _selectedPaths.add(file.path);
      }
    });
  }

  /// 导入选中的音频文件到书架（只记录远程路径，播放时按需从网盘拉取缓存）
  Future<void> _importSelected() async {
    final source = _currentSource;
    if (source == null) return;

    final bookName = _bookNameController.text.trim();
    if (bookName.isEmpty) {
      _showSnack('请输入书籍名称');
      return;
    }
    if (_selectedPaths.isEmpty) {
      _showSnack('请先勾选要导入的音频文件');
      return;
    }

    setState(() {
      _busy = true;
      _statusMessage = '正在创建书籍...';
    });

    try {
      // 按自然排序
      final selected = _entries
          .where((e) => _selectedPaths.contains(e.path))
          .toList()
        ..sort((a, b) => naturalCompare(a.name, b.name));

      // 只记录远程路径，不下载；播放时自动从网盘拉取到本地缓存
      final bookProvider = context.read<BookProvider>();
      final createdBook = await bookProvider.createWebDavBook(
        title: bookName,
        author: _authorController.text.trim().isEmpty
            ? null
            : _authorController.text.trim(),
        webdavSourceId: source.id,
        files: selected
            .map((e) => WebDavRemoteFileInfo(
                  remotePath: e.path,
                  fileName: e.name,
                  fileSize: e.size,
                ))
            .toList(),
      );

      if (createdBook == null) {
        throw Exception('创建书籍失败');
      }

      if (!mounted) return;
      setState(() {
        _statusMessage = '导入完成！';
      });
      _showSnack('成功导入《$bookName》，共 ${selected.length} 个音频文件（在线播放，自动缓存）');

      // 延迟返回书架
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted) Navigator.pop(context);
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusMessage = '导入失败: $e';
        });
        _showSnack('导入失败: $e');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 删除已保存的书源
  Future<void> _removeSource(WebDavSource source) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除书源'),
        content: Text('确定删除书源「${source.name}」吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await _sourceStore.removeSource(source.id);
    if (_currentSource?.id == source.id) {
      _disconnect();
    } else {
      await _loadSources();
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  /// 从 URL 提取主机名作为默认书源名称
  String _urlHost(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.host.isEmpty ? url : uri.host;
    } catch (_) {
      return url;
    }
  }

  /// 上级目录路径
  String _parentPath(String current) {
    final trimmed = current.endsWith('/')
        ? current.substring(0, current.length - 1)
        : current;
    final index = trimmed.lastIndexOf('/');
    if (index <= 0) return '/';
    return trimmed.substring(0, index + 1);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          appBar: AppBar(
            title: Text(
              _currentSource == null ? 'WebDAV 网盘导入' : _currentSource!.name,
            ),
            actions: [
              if (_currentSource != null)
                IconButton(
                  tooltip: '切换书源',
                  icon: const Icon(Icons.swap_horiz),
                  onPressed: _busy ? null : _disconnect,
                ),
            ],
          ),
          body: _currentSource == null ? _buildConfigView() : _buildBrowserView(),
        ),
        // Loading 遮罩层
        if (_busy)
          Positioned.fill(
            child: Container(
              color: Colors.black54,
              child: Center(
                child: Card(
                  margin: const EdgeInsets.all(32),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 24),
                        Text(
                          _statusMessage,
                          style: Theme.of(context).textTheme.titleMedium,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '请稍候，正在处理中...',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: Colors.grey[600]),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// 配置视图：已保存书源 + 新建书源表单
  Widget _buildConfigView() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_sources.isNotEmpty) ...[
          Text(
            '已保存的书源',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          for (final source in _sources)
            Card(
              child: ListTile(
                leading: const Icon(Icons.cloud_outlined),
                title: Text(source.name),
                subtitle: Text(
                  '${source.serverUrl}\n'
                  '${source.username.isEmpty ? '无需认证' : source.username}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: IconButton(
                  tooltip: '删除书源',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: _busy ? null : () => _removeSource(source),
                ),
                onTap: _busy ? null : () => _connect(source),
              ),
            ),
          const SizedBox(height: 16),
        ],
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '添加新书源',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: '书源名称（可选）',
                    hintText: '如：我的网盘',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.label_outline),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _urlController,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: '服务器地址 *',
                    hintText: 'https://dav.example.com',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.link),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _usernameController,
                  decoration: const InputDecoration(
                    labelText: '用户名（可选）',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: '密码（可选）',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.lock_outline),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _busy ? null : () => _connect(null),
                  icon: const Icon(Icons.cloud_done_outlined),
                  label: const Text('连接并浏览'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.all(16),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              '使用说明：\n'
              '• 服务器地址填写 WebDAV 服务根地址（如 https://dav.jianguoyun.com/dav）\n'
              '• 连接成功后可在网盘目录中浏览并勾选音频文件\n'
              '• 导入后在线播放：点击播放时自动从网盘拉取到本地缓存\n'
              '• 自动预取后续 2 个文件，停止播放超过 1 天自动清除缓存',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey[600],
                    height: 1.5,
                  ),
            ),
          ),
        ),
      ],
    );
  }

  /// 目录浏览视图
  Widget _buildBrowserView() {
    return Column(
      children: [
        // 路径栏
        Card(
          margin: const EdgeInsets.all(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                IconButton(
                  tooltip: '返回上级',
                  icon: const Icon(Icons.arrow_upward),
                  onPressed: (_busy || _currentPath == '/') ? null : _goUp,
                ),
                IconButton(
                  tooltip: '刷新',
                  icon: const Icon(Icons.refresh),
                  onPressed: _busy ? null : _refresh,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    _currentPath,
                    style: Theme.of(context).textTheme.bodyMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
        // 目录内容
        Expanded(
          child: _entries.isEmpty
              ? const Center(child: Text('目录为空'))
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: _entries.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 4),
                  itemBuilder: (context, index) {
                    final entry = _entries[index];
                    if (entry.isDirectory) {
                      return Card(
                        child: ListTile(
                          leading: Icon(
                            Icons.folder,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          title: Text(
                            entry.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: _busy ? null : () => _enterDirectory(entry),
                        ),
                      );
                    }
                    // 仅展示音频文件
                    if (!_service.isAudioFile(entry.name)) {
                      return const SizedBox.shrink();
                    }
                    final selected = _selectedPaths.contains(entry.path);
                    return Card(
                      child: CheckboxListTile(
                        value: selected,
                        onChanged: _busy ? null : (_) => _toggleSelect(entry),
                        secondary: Icon(
                          Icons.audiotrack,
                          color: selected
                              ? Theme.of(context).colorScheme.primary
                              : Colors.grey[500],
                        ),
                        title: Text(
                          entry.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(Helpers.formatFileSize(entry.size)),
                        controlAffinity: ListTileControlAffinity.trailing,
                      ),
                    );
                  },
                ),
        ),
        // 底部导入面板
        SafeArea(
          child: Card(
            margin: const EdgeInsets.all(12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '已选 ${_selectedPaths.length} 个音频文件',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _bookNameController,
                    decoration: const InputDecoration(
                      labelText: '书籍名称 *',
                      isDense: true,
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.book),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _authorController,
                    decoration: const InputDecoration(
                      labelText: '作者（可选）',
                      isDense: true,
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.person),
                    ),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: (_busy || _selectedPaths.isEmpty)
                        ? null
                        : _importSelected,
                    icon: const Icon(Icons.library_add_outlined),
                    label: const Text('导入书架'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
