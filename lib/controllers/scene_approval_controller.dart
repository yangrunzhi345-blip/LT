import 'package:flutter/foundation.dart';
import '../models/scene_dialogue.dart';
import '../providers/chat_provider.dart';

class SceneApprovalController extends ChangeNotifier {
  final ChatProvider Function() _chatProvider;

  bool _isSubmitting = false;
  String? _errorMessage;

  bool get isSubmitting => _isSubmitting;
  String? get errorMessage => _errorMessage;

  SceneApprovalController({required ChatProvider Function() chatProvider})
      : _chatProvider = chatProvider;

  Future<bool> approveWorldCandidate(SceneSettingCandidate candidate) async {
    if (_isSubmitting) return false;
    _isSubmitting = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final applied =
          await _chatProvider().approveSceneWorldCandidate(candidate);
      _isSubmitting = false;
      notifyListeners();
      return applied;
    } catch (e) {
      _isSubmitting = false;
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<void> rejectCandidate(SceneSettingCandidate candidate) async {
    if (_isSubmitting) return;
    _isSubmitting = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _chatProvider().rejectSceneCandidate(candidate);
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }

  Future<bool> approveNpc(SceneSettingCandidate candidate,
      {required String name}) async {
    if (_isSubmitting) return false;
    _isSubmitting = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _chatProvider().approveSceneNpc(candidate, name: name);
      _isSubmitting = false;
      notifyListeners();
      return true;
    } catch (e) {
      _isSubmitting = false;
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    }
  }
}
