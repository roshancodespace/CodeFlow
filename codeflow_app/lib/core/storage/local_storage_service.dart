import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/project.dart';
import '../../models/workflow_checkpoint.dart';

/// Service managing persistent key-value and local project settings.
class LocalStorageService {
  final SharedPreferences _prefs;

  LocalStorageService(this._prefs);

  static const String _keyThemeMode = 'codeflow_theme_mode';
  static const String _keyCompanionHost = 'codeflow_companion_host';
  static const String _keyCompanionPort = 'codeflow_companion_port';
  static const String _keyCompanionToken = 'codeflow_companion_token';
  static const String _keyTypingSpeed = 'codeflow_typing_speed';
  static const String _keyFocusDelay = 'codeflow_focus_delay';
  static const String _keyNewlinePause = 'codeflow_newline_pause';
  static const String _keyHumanJitter = 'codeflow_human_jitter';
  static const String _keyHumanMistakes = 'codeflow_human_mistakes';
  static const String _keyMistakeProbability = 'codeflow_mistake_probability';
  static const String _keyThinkingPauses = 'codeflow_thinking_pauses';
  static const String _keyProjects = 'codeflow_projects_list';
  static const String _keyCheckpointsPrefix = 'codeflow_checkpoint_';
  static const String _keyAutomationMode = 'codeflow_automation_mode';
  static const String _keySpooferProfile = 'codeflow_spoofer_profile';
  static const String _keyPostRunCommand = 'codeflow_post_run_command';

  // --- Automation & Spoofer Preferences ---
  String get automationMode {
    final mode = _prefs.getString(_keyAutomationMode);
    if (mode == null || mode == 'hidHumanTyping') {
      return 'vscodeEditor';
    }
    return mode;
  }

  Future<void> setAutomationMode(String mode) async =>
      _prefs.setString(_keyAutomationMode, mode);

  String get spooferProfile =>
      _prefs.getString(_keySpooferProfile) ?? 'Logitech MX Keys';
  Future<void> setSpooferProfile(String profile) async =>
      _prefs.setString(_keySpooferProfile, profile);

  String get postRunCommand => _prefs.getString(_keyPostRunCommand) ?? '';
  Future<void> setPostRunCommand(String cmd) async =>
      _prefs.setString(_keyPostRunCommand, cmd.trim());

  // --- Theme Mode ---
  String get themeMode => _prefs.getString(_keyThemeMode) ?? 'system';
  Future<void> setThemeMode(String mode) async =>
      _prefs.setString(_keyThemeMode, mode);

  // --- Companion Connection Preferences ---
  String get companionHost =>
      _prefs.getString(_keyCompanionHost) ?? '127.0.0.1';
  Future<void> setCompanionHost(String host) async =>
      _prefs.setString(_keyCompanionHost, host.trim());

  int get companionPort => _prefs.getInt(_keyCompanionPort) ?? 8090;
  Future<void> setCompanionPort(int port) async =>
      _prefs.setInt(_keyCompanionPort, port);

  String? get companionToken => _prefs.getString(_keyCompanionToken);
  Future<void> setCompanionToken(String? token) async {
    if (token == null || token.isEmpty) {
      await _prefs.remove(_keyCompanionToken);
    } else {
      await _prefs.setString(_keyCompanionToken, token.trim());
    }
  }

  // --- Typing Cadence & Humanization Preferences ---
  int get typingSpeedCps => _prefs.getInt(_keyTypingSpeed) ?? 6;
  Future<void> setTypingSpeedCps(int cps) async =>
      _prefs.setInt(_keyTypingSpeed, cps);

  int get focusDelaySeconds => _prefs.getInt(_keyFocusDelay) ?? 3;
  Future<void> setFocusDelaySeconds(int seconds) async =>
      _prefs.setInt(_keyFocusDelay, seconds);

  int get newlinePauseMs => _prefs.getInt(_keyNewlinePause) ?? 350;
  Future<void> setNewlinePauseMs(int ms) async =>
      _prefs.setInt(_keyNewlinePause, ms);

  bool get humanJitterEnabled => _prefs.getBool(_keyHumanJitter) ?? true;
  Future<void> setHumanJitterEnabled(bool enabled) async =>
      _prefs.setBool(_keyHumanJitter, enabled);

  bool get humanMistakesEnabled => _prefs.getBool(_keyHumanMistakes) ?? true;
  Future<void> setHumanMistakesEnabled(bool enabled) async =>
      _prefs.setBool(_keyHumanMistakes, enabled);

  int get mistakeProbabilityPercent =>
      _prefs.getInt(_keyMistakeProbability) ?? 3;
  Future<void> setMistakeProbabilityPercent(int prob) async =>
      _prefs.setInt(_keyMistakeProbability, prob);

  bool get thinkingPausesEnabled => _prefs.getBool(_keyThinkingPauses) ?? true;
  Future<void> setThinkingPausesEnabled(bool enabled) async =>
      _prefs.setBool(_keyThinkingPauses, enabled);

  // --- Projects Persistence ---
  List<Project> getProjects() {
    final raw = _prefs.getString(_keyProjects);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((item) => Project.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('Error parsing stored projects: $e');
      return [];
    }
  }

  Future<void> saveProjects(List<Project> projects) async {
    final raw = jsonEncode(projects.map((p) => p.toJson()).toList());
    await _prefs.setString(_keyProjects, raw);
  }

  Future<void> saveProject(Project project) async {
    final projects = getProjects();
    final index = projects.indexWhere((p) => p.id == project.id);
    if (index >= 0) {
      projects[index] = project;
    } else {
      projects.insert(0, project);
    }
    await saveProjects(projects);
  }

  Future<void> deleteProject(String projectId) async {
    final projects = getProjects().where((p) => p.id != projectId).toList();
    await saveProjects(projects);
    await deleteCheckpoint(projectId);
  }

  // --- Checkpoints Persistence ---
  WorkflowCheckpoint? getCheckpoint(String projectId) {
    final raw = _prefs.getString('$_keyCheckpointsPrefix$projectId');
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return WorkflowCheckpoint.fromJson(json);
    } catch (e) {
      debugPrint('Error parsing checkpoint: $e');
      return null;
    }
  }

  Future<void> saveCheckpoint(WorkflowCheckpoint checkpoint) async {
    final raw = jsonEncode(checkpoint.toJson());
    await _prefs.setString(
      '$_keyCheckpointsPrefix${checkpoint.projectId}',
      raw,
    );
  }

  Future<void> deleteCheckpoint(String projectId) async {
    await _prefs.remove('$_keyCheckpointsPrefix$projectId');
  }
}
