import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const WorkflowApp());
}

enum WorkflowActionType { deleteFolder, copyFolder, setSystemTime, openApp }

enum ExecutionFailurePolicy { stop, continueOnError }

extension ExecutionFailurePolicyX on ExecutionFailurePolicy {
  String get label {
    switch (this) {
      case ExecutionFailurePolicy.stop:
        return '失败即中断';
      case ExecutionFailurePolicy.continueOnError:
        return '失败后继续';
    }
  }
}

extension WorkflowActionTypeX on WorkflowActionType {
  String get label {
    switch (this) {
      case WorkflowActionType.deleteFolder:
        return '删除文件夹';
      case WorkflowActionType.copyFolder:
        return '复制文件夹';
      case WorkflowActionType.setSystemTime:
        return '设置系统时间';
      case WorkflowActionType.openApp:
        return '打开 App';
    }
  }
}

class WorkflowAction {
  const WorkflowAction({
    required this.id,
    required this.type,
    required this.params,
  });

  final String id;
  final WorkflowActionType type;
  final Map<String, dynamic> params;

  WorkflowAction copyWith({
    String? id,
    WorkflowActionType? type,
    Map<String, dynamic>? params,
  }) {
    return WorkflowAction(
      id: id ?? this.id,
      type: type ?? this.type,
      params: params ?? this.params,
    );
  }

  Map<String, dynamic> toJson() {
    return {'id': id, 'type': type.name, 'params': params};
  }

  factory WorkflowAction.fromJson(Map<String, dynamic> json) {
    return WorkflowAction(
      id: json['id'] as String,
      type: WorkflowActionType.values.byName(json['type'] as String),
      params: Map<String, dynamic>.from(json['params'] as Map),
    );
  }
}

class WorkflowDefinition {
  const WorkflowDefinition({
    required this.id,
    required this.name,
    required this.actions,
    required this.requireConfirmation,
    required this.failurePolicy,
  });

  final String id;
  final String name;
  final List<WorkflowAction> actions;
  final bool requireConfirmation;
  final ExecutionFailurePolicy failurePolicy;

  WorkflowDefinition copyWith({
    String? id,
    String? name,
    List<WorkflowAction>? actions,
    bool? requireConfirmation,
    ExecutionFailurePolicy? failurePolicy,
  }) {
    return WorkflowDefinition(
      id: id ?? this.id,
      name: name ?? this.name,
      actions: actions ?? this.actions,
      requireConfirmation: requireConfirmation ?? this.requireConfirmation,
      failurePolicy: failurePolicy ?? this.failurePolicy,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'actions': actions.map((e) => e.toJson()).toList(),
      'requireConfirmation': requireConfirmation,
      'failurePolicy': failurePolicy.name,
    };
  }

  factory WorkflowDefinition.fromJson(Map<String, dynamic> json) {
    return WorkflowDefinition(
      id: json['id'] as String,
      name: json['name'] as String,
      actions: (json['actions'] as List<dynamic>)
          .map(
            (e) => WorkflowAction.fromJson(Map<String, dynamic>.from(e as Map)),
          )
          .toList(),
      requireConfirmation: json['requireConfirmation'] as bool? ?? true,
      failurePolicy: ExecutionFailurePolicy.values.byName(
        json['failurePolicy'] as String? ?? ExecutionFailurePolicy.stop.name,
      ),
    );
  }
}

class WorkflowStorage {
  static const String _key = 'saved_workflows_v1';

  Future<List<WorkflowDefinition>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) {
      return const [];
    }

    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map(
          (e) =>
              WorkflowDefinition.fromJson(Map<String, dynamic>.from(e as Map)),
        )
        .toList();
  }

  Future<void> saveAll(List<WorkflowDefinition> workflows) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(workflows.map((e) => e.toJson()).toList()),
    );
  }
}

class WorkflowRunner {
  static const MethodChannel _channel = MethodChannel('workflow_tool/atomics');
  static const EventChannel _launchEventChannel = EventChannel(
    'workflow_tool/launch_events',
  );

  Future<String> runAction(WorkflowAction action) async {
    switch (action.type) {
      case WorkflowActionType.deleteFolder:
        await _ensureFileOperationPermission();
        return await _channel.invokeMethod<String>('deleteFolder', {
              'path': action.params['path'],
            }) ??
            '完成';
      case WorkflowActionType.copyFolder:
        await _ensureFileOperationPermission();
        return await _channel.invokeMethod<String>('copyFolder', {
              'sourcePath': action.params['sourcePath'],
              'targetPath': action.params['targetPath'],
            }) ??
            '完成';
      case WorkflowActionType.setSystemTime:
        final mode = action.params['mode'] as String;
        if (mode == 'auto') {
          return await _channel.invokeMethod<String>('setSystemTimeAuto', {
                'enabled': true,
              }) ??
              '完成';
        }
        return await _channel.invokeMethod<String>('setSystemTimeManual', {
              'epochMillis': action.params['epochMillis'],
            }) ??
            '完成';
      case WorkflowActionType.openApp:
        return await _channel.invokeMethod<String>('openApp', {
              'packageName': action.params['packageName'],
            }) ??
            '完成';
    }
  }

  Future<void> _ensureFileOperationPermission() async {
    final granted =
        await _channel.invokeMethod<bool>('canManageAllFilesAccess') ?? false;
    if (granted) {
      return;
    }
    await _channel.invokeMethod<String>('requestManageAllFilesAccess');
    throw PlatformException(
      code: 'FILE_PERMISSION_REQUIRED',
      message: '请先授予“所有文件访问权限”后再执行删除/复制操作。',
    );
  }

  Future<List<InstalledApp>> searchApps(String query) async {
    final result = await _channel.invokeMethod<List<dynamic>>('searchApps', {
      'query': query,
    });
    if (result == null) {
      return const [];
    }
    return result
        .map((e) => InstalledApp.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<String> createPinnedWorkflowShortcut({
    required String workflowId,
    required String workflowName,
  }) async {
    return await _channel.invokeMethod<String>('createPinnedWorkflowShortcut', {
          'workflowId': workflowId,
          'workflowName': workflowName,
        }) ??
        '已请求添加桌面快捷方式';
  }

  Future<String?> getInitialLaunchWorkflowId() async {
    final id = await _channel.invokeMethod<String>(
      'getInitialLaunchWorkflowId',
    );
    if (id == null || id.isEmpty) {
      return null;
    }
    return id;
  }

  Stream<String> get launchWorkflowStream {
    return _launchEventChannel
        .receiveBroadcastStream()
        .map((event) => event?.toString() ?? '')
        .where((id) => id.isNotEmpty);
  }
}

class InstalledApp {
  const InstalledApp({required this.appName, required this.packageName});

  final String appName;
  final String packageName;

  factory InstalledApp.fromJson(Map<String, dynamic> json) {
    return InstalledApp(
      appName: json['appName'] as String? ?? '',
      packageName: json['packageName'] as String? ?? '',
    );
  }
}

class WorkflowApp extends StatelessWidget {
  const WorkflowApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Android Workflow Tool',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF005F73)),
        useMaterial3: true,
      ),
      home: const WorkflowHomePage(),
    );
  }
}

class WorkflowHomePage extends StatefulWidget {
  const WorkflowHomePage({super.key});

  @override
  State<WorkflowHomePage> createState() => _WorkflowHomePageState();
}

class _WorkflowHomePageState extends State<WorkflowHomePage> {
  final WorkflowStorage _storage = WorkflowStorage();
  final WorkflowRunner _runner = WorkflowRunner();

  bool _isLoading = true;
  List<WorkflowDefinition> _workflows = const [];
  StreamSubscription<String>? _launchSub;
  bool _initialShortcutHandled = false;

  @override
  void initState() {
    super.initState();
    _launchSub = _runner.launchWorkflowStream.listen(
      _runWorkflowByIdFromShortcut,
    );
    _loadWorkflows();
  }

  @override
  void dispose() {
    _launchSub?.cancel();
    super.dispose();
  }

  Future<void> _loadWorkflows() async {
    final loaded = await _storage.loadAll();
    if (!mounted) {
      return;
    }
    setState(() {
      _workflows = loaded;
      _isLoading = false;
    });
    await _handleInitialShortcutLaunch();
  }

  Future<void> _handleInitialShortcutLaunch() async {
    if (_initialShortcutHandled) {
      return;
    }
    _initialShortcutHandled = true;
    final workflowId = await _runner.getInitialLaunchWorkflowId();
    if (!mounted || workflowId == null) {
      return;
    }
    await _runWorkflowByIdFromShortcut(workflowId);
  }

  Future<void> _saveWorkflows(List<WorkflowDefinition> workflows) async {
    setState(() {
      _workflows = workflows;
    });
    await _storage.saveAll(workflows);
  }

  Future<void> _createWorkflow() async {
    final created = await Navigator.of(context).push<WorkflowDefinition>(
      MaterialPageRoute(builder: (_) => const WorkflowEditorPage()),
    );
    if (created == null) {
      return;
    }
    final updated = [..._workflows, created];
    await _saveWorkflows(updated);
  }

  Future<void> _editWorkflow(WorkflowDefinition workflow) async {
    final edited = await Navigator.of(context).push<WorkflowDefinition>(
      MaterialPageRoute(builder: (_) => WorkflowEditorPage(initial: workflow)),
    );
    if (edited == null) {
      return;
    }

    final updated = _workflows
        .map((e) => e.id == edited.id ? edited : e)
        .toList(growable: false);
    await _saveWorkflows(updated);
  }

  Future<void> _deleteWorkflow(WorkflowDefinition workflow) async {
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('删除工作流'),
            content: Text('确认删除「${workflow.name}」吗？'),
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
        ) ??
        false;

    if (!confirmed) {
      return;
    }

    final updated = _workflows.where((e) => e.id != workflow.id).toList();
    await _saveWorkflows(updated);
  }

  Future<void> _runWorkflow(
    WorkflowDefinition workflow, {
    bool skipConfirmation = false,
  }) async {
    if (workflow.requireConfirmation && !skipConfirmation) {
      final confirmed =
          await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('执行确认'),
              content: Text(
                '确认执行「${workflow.name}」吗？\n共 ${workflow.actions.length} 个步骤。',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('执行'),
                ),
              ],
            ),
          ) ??
          false;
      if (!confirmed || !mounted) {
        return;
      }
    }

    final logs = <String>[];
    var hasError = false;

    for (var i = 0; i < workflow.actions.length; i++) {
      final action = workflow.actions[i];
      final stepName = action.type.label;
      try {
        final message = await _runner.runAction(action);
        logs.add('步骤 ${i + 1} - $stepName: $message');
      } on PlatformException catch (e) {
        hasError = true;
        logs.add('步骤 ${i + 1} - $stepName: 失败，${e.message ?? e.code}');
        if (workflow.failurePolicy == ExecutionFailurePolicy.stop) {
          logs.add('已按策略中断后续步骤。');
          break;
        }
      } catch (e) {
        hasError = true;
        logs.add('步骤 ${i + 1} - $stepName: 失败，$e');
        if (workflow.failurePolicy == ExecutionFailurePolicy.stop) {
          logs.add('已按策略中断后续步骤。');
          break;
        }
      }
    }

    if (!mounted) {
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          hasError ? '执行结果（部分失败）: ${workflow.name}' : '执行结果: ${workflow.name}',
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(child: Text(logs.join('\n'))),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Future<void> _runWorkflowByIdFromShortcut(String workflowId) async {
    final workflow = _workflows.where((e) => e.id == workflowId).firstOrNull;
    if (workflow == null) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('快捷方式对应的工作流不存在，可能已被删除。')));
      return;
    }
    await _runWorkflow(workflow, skipConfirmation: true);
  }

  Future<void> _addWorkflowToHome(WorkflowDefinition workflow) async {
    try {
      final message = await _runner.createPinnedWorkflowShortcut(
        workflowId: workflow.id,
        workflowName: workflow.name,
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } on PlatformException catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message ?? e.code)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Android Workflow Tool')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createWorkflow,
        label: const Text('新建工作流'),
        icon: const Icon(Icons.add),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _workflows.isEmpty
          ? const Center(child: Text('还没有工作流，点击右下角创建。'))
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _workflows.length,
              itemBuilder: (context, index) {
                final workflow = _workflows[index];
                return Card(
                  child: ListTile(
                    title: Text(workflow.name),
                    subtitle: Text(
                      '操作数: ${workflow.actions.length} · '
                      '确认: ${workflow.requireConfirmation ? "是" : "否"} · '
                      '策略: ${workflow.failurePolicy.label}',
                    ),
                    onTap: () => _runWorkflow(workflow),
                    trailing: Wrap(
                      spacing: 4,
                      children: [
                        IconButton(
                          onPressed: () => _runWorkflow(workflow),
                          tooltip: '执行',
                          icon: const Icon(Icons.play_arrow),
                        ),
                        IconButton(
                          onPressed: () => _addWorkflowToHome(workflow),
                          tooltip: '添加到桌面',
                          icon: const Icon(Icons.push_pin),
                        ),
                        IconButton(
                          onPressed: () => _editWorkflow(workflow),
                          tooltip: '编辑',
                          icon: const Icon(Icons.edit),
                        ),
                        IconButton(
                          onPressed: () => _deleteWorkflow(workflow),
                          tooltip: '删除',
                          icon: const Icon(Icons.delete),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class WorkflowEditorPage extends StatefulWidget {
  const WorkflowEditorPage({super.key, this.initial});

  final WorkflowDefinition? initial;

  @override
  State<WorkflowEditorPage> createState() => _WorkflowEditorPageState();
}

class _WorkflowEditorPageState extends State<WorkflowEditorPage> {
  final WorkflowRunner _runner = WorkflowRunner();
  late final TextEditingController _nameController;
  late List<WorkflowAction> _actions;
  late bool _requireConfirmation;
  late ExecutionFailurePolicy _failurePolicy;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initial?.name ?? '');
    _actions = widget.initial?.actions.toList() ?? [];
    _requireConfirmation = widget.initial?.requireConfirmation ?? true;
    _failurePolicy =
        widget.initial?.failurePolicy ?? ExecutionFailurePolicy.stop;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  String _newId() => DateTime.now().microsecondsSinceEpoch.toString();

  String _actionSummary(WorkflowAction action) {
    switch (action.type) {
      case WorkflowActionType.deleteFolder:
        return '路径: ${action.params['path']}';
      case WorkflowActionType.copyFolder:
        return '源: ${action.params['sourcePath']} -> 目标: ${action.params['targetPath']}';
      case WorkflowActionType.setSystemTime:
        final mode = action.params['mode'];
        if (mode == 'auto') {
          return '自动设置时间';
        }
        final epoch = action.params['epochMillis'] as int;
        return '手动时间: ${DateTime.fromMillisecondsSinceEpoch(epoch)}';
      case WorkflowActionType.openApp:
        final appName = action.params['appName'] as String?;
        final packageName = action.params['packageName'];
        if (appName != null && appName.isNotEmpty) {
          return '应用: $appName ($packageName)';
        }
        return '包名: $packageName';
    }
  }

  Future<void> _addAction() async {
    final type = await showModalBottomSheet<WorkflowActionType>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: WorkflowActionType.values
              .map(
                (type) => ListTile(
                  title: Text(type.label),
                  onTap: () => Navigator.pop(context, type),
                ),
              )
              .toList(),
        ),
      ),
    );

    if (type == null) {
      return;
    }

    final action = await _buildActionByType(type);
    if (action == null) {
      return;
    }

    setState(() {
      _actions = [..._actions, action];
    });
  }

  Future<void> _editAction(int index) async {
    final existing = _actions[index];
    final updated = await _buildActionByType(existing.type, existing: existing);
    if (updated == null) {
      return;
    }

    setState(() {
      _actions[index] = updated;
    });
  }

  Future<WorkflowAction?> _buildActionByType(
    WorkflowActionType type, {
    WorkflowAction? existing,
  }) async {
    switch (type) {
      case WorkflowActionType.deleteFolder:
        final path = await _askText(
          title: '删除文件夹',
          label: '文件夹路径',
          initial: existing?.params['path'] as String?,
        );
        if (path == null || path.trim().isEmpty) {
          return null;
        }
        return WorkflowAction(
          id: existing?.id ?? _newId(),
          type: type,
          params: {'path': path.trim()},
        );
      case WorkflowActionType.copyFolder:
        final source = await _askText(
          title: '复制文件夹',
          label: '源文件夹路径',
          initial: existing?.params['sourcePath'] as String?,
        );
        if (source == null || source.trim().isEmpty) {
          return null;
        }
        final target = await _askText(
          title: '复制文件夹',
          label: '目标文件夹路径',
          initial: existing?.params['targetPath'] as String?,
        );
        if (target == null || target.trim().isEmpty) {
          return null;
        }
        return WorkflowAction(
          id: existing?.id ?? _newId(),
          type: type,
          params: {'sourcePath': source.trim(), 'targetPath': target.trim()},
        );
      case WorkflowActionType.setSystemTime:
        return _pickSystemTimeAction(existing: existing);
      case WorkflowActionType.openApp:
        final selected = await _pickApp(existing: existing);
        if (selected == null) {
          return null;
        }
        return WorkflowAction(
          id: existing?.id ?? _newId(),
          type: type,
          params: {
            'packageName': selected.packageName,
            'appName': selected.appName,
          },
        );
    }
  }

  Future<InstalledApp?> _pickApp({WorkflowAction? existing}) async {
    final initialQuery =
        existing?.params['appName'] as String? ??
        existing?.params['packageName'] as String? ??
        '';
    final initialPackage = existing?.params['packageName'] as String?;

    return showDialog<InstalledApp>(
      context: context,
      builder: (context) => _AppPickerDialog(
        runner: _runner,
        initialQuery: initialQuery,
        initialPackage: initialPackage,
      ),
    );
  }

  Future<WorkflowAction?> _pickSystemTimeAction({
    WorkflowAction? existing,
  }) async {
    final mode = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('自动设置时间'),
              onTap: () => Navigator.pop(context, 'auto'),
            ),
            ListTile(
              title: const Text('手动设置时间'),
              onTap: () => Navigator.pop(context, 'manual'),
            ),
          ],
        ),
      ),
    );

    if (mode == null) {
      return null;
    }
    if (!mounted) {
      return null;
    }

    if (mode == 'auto') {
      return WorkflowAction(
        id: existing?.id ?? _newId(),
        type: WorkflowActionType.setSystemTime,
        params: {'mode': 'auto'},
      );
    }

    final initialEpoch = existing?.params['epochMillis'] as int?;
    final initialDate = initialEpoch != null
        ? DateTime.fromMillisecondsSinceEpoch(initialEpoch)
        : DateTime.now();

    final date = await showDatePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDate: initialDate,
    );
    if (date == null) {
      return null;
    }

    if (!mounted) {
      return null;
    }

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initialDate),
    );
    if (time == null) {
      return null;
    }

    final manualDateTime = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );

    return WorkflowAction(
      id: existing?.id ?? _newId(),
      type: WorkflowActionType.setSystemTime,
      params: {
        'mode': 'manual',
        'epochMillis': manualDateTime.millisecondsSinceEpoch,
      },
    );
  }

  Future<String?> _askText({
    required String title,
    required String label,
    String? initial,
  }) async {
    final controller = TextEditingController(text: initial ?? '');
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(labelText: label),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('确认'),
          ),
        ],
      ),
    );
    controller.dispose();
    return value;
  }

  void _save() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请填写工作流名称')));
      return;
    }
    if (_actions.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('至少添加一个原子操作')));
      return;
    }

    final workflow = WorkflowDefinition(
      id: widget.initial?.id ?? _newId(),
      name: name,
      actions: _actions,
      requireConfirmation: _requireConfirmation,
      failurePolicy: _failurePolicy,
    );
    Navigator.pop(context, workflow);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.initial == null ? '新建工作流' : '编辑工作流'),
        actions: [TextButton(onPressed: _save, child: const Text('保存'))],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addAction,
        icon: const Icon(Icons.add),
        label: const Text('添加操作'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: '工作流名称',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            value: _requireConfirmation,
            title: const Text('执行前确认'),
            subtitle: const Text('开启后，每次执行都先弹窗确认'),
            onChanged: (value) {
              setState(() {
                _requireConfirmation = value;
              });
            },
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('失败策略'),
                  const SizedBox(height: 8),
                  SegmentedButton<ExecutionFailurePolicy>(
                    segments: ExecutionFailurePolicy.values
                        .map(
                          (item) => ButtonSegment<ExecutionFailurePolicy>(
                            value: item,
                            label: Text(item.label),
                          ),
                        )
                        .toList(),
                    selected: {_failurePolicy},
                    onSelectionChanged: (selected) {
                      setState(() {
                        _failurePolicy = selected.first;
                      });
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (_actions.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('还没有原子操作，点击右下角添加。'),
              ),
            ),
          ..._actions.asMap().entries.map((entry) {
            final index = entry.key;
            final action = entry.value;
            return Card(
              child: ListTile(
                title: Text('${index + 1}. ${action.type.label}'),
                subtitle: Text(_actionSummary(action)),
                onTap: () => _editAction(index),
                trailing: IconButton(
                  tooltip: '删除',
                  icon: const Icon(Icons.delete),
                  onPressed: () {
                    setState(() {
                      _actions.removeAt(index);
                    });
                  },
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _AppPickerDialog extends StatefulWidget {
  const _AppPickerDialog({
    required this.runner,
    required this.initialQuery,
    this.initialPackage,
  });

  final WorkflowRunner runner;
  final String initialQuery;
  final String? initialPackage;

  @override
  State<_AppPickerDialog> createState() => _AppPickerDialogState();
}

class _AppPickerDialogState extends State<_AppPickerDialog> {
  late final TextEditingController _queryController;
  late final TextEditingController _packageController;
  List<InstalledApp> _results = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _queryController = TextEditingController(text: widget.initialQuery);
    _packageController = TextEditingController(
      text: widget.initialPackage ?? '',
    );
    _search();
  }

  @override
  void dispose() {
    _queryController.dispose();
    _packageController.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    setState(() {
      _loading = true;
    });
    try {
      final data = await widget.runner.searchApps(_queryController.text.trim());
      if (!mounted) {
        return;
      }
      setState(() {
        _results = data;
      });
    } on PlatformException {
      if (!mounted) {
        return;
      }
      setState(() {
        _results = const [];
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('选择 App'),
      content: SizedBox(
        width: double.maxFinite,
        height: 420,
        child: Column(
          children: [
            TextField(
              controller: _queryController,
              decoration: InputDecoration(
                labelText: '按应用名搜索',
                suffixIcon: IconButton(
                  onPressed: _search,
                  icon: const Icon(Icons.search),
                  tooltip: '搜索',
                ),
              ),
              onSubmitted: (_) => _search(),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _packageController,
              decoration: const InputDecoration(labelText: '包名（可手动输入）'),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _results.isEmpty
                  ? const Center(child: Text('没有搜索结果'))
                  : ListView.builder(
                      itemCount: _results.length,
                      itemBuilder: (context, index) {
                        final app = _results[index];
                        return ListTile(
                          dense: true,
                          title: Text(app.appName),
                          subtitle: Text(app.packageName),
                          onTap: () {
                            Navigator.pop(context, app);
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            final packageName = _packageController.text.trim();
            if (packageName.isEmpty) {
              return;
            }
            Navigator.pop(
              context,
              InstalledApp(appName: packageName, packageName: packageName),
            );
          },
          child: const Text('使用包名'),
        ),
      ],
    );
  }
}
