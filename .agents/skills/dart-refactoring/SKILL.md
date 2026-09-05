---
name: dart-refactoring
description: "Use when refactoring Dart and Flutter code — decomposing large widgets, extracting business logic into services/notifiers, eliminating code smells, upgrading to Dart 3 idioms, or improving maintainability and testability."
---

# Dart & Flutter Code Refactoring Skill

A structured guide for safely refactoring Dart and Flutter codebases without introducing regressions or altering functional behavior.

---

## When to Use This Skill

- Refactoring large "God" widgets or monolith `build()` methods (> 100 lines).
- Decoupling business logic and database/API calls from UI presentation.
- Migrating imperative code to modern Dart 3 features (Records, Pattern Matching, Sealed Classes).
- Cleaning up code smells (duplicate logic, mutable state leaks, missing `dispose`).
- Preparing legacy code for unit and widget testing by introducing dependency injection and interfaces.

---

## Refactoring Workflow

Follow this 5-step loop for all non-trivial refactorings:

```
[1. Baseline Check] -> [2. Plan & Isolate] -> [3. Incremental Change] -> [4. Analyze & Test] -> [5. Format]
```

### Step 1 — Baseline Check
Before modifying any code:
1. Run static analysis: `flutter analyze`
2. Run existing tests: `flutter test`
3. If no tests exist for the target logic, write baseline tests first (refer to the `testing` skill) to capture expected behaviors.

### Step 2 — Plan & Isolate
Identify the specific smell:
- **Presentation mixed with Logic**: Widget calls database/HTTP directly -> Extract to Repository/Notifier.
- **Deep Widget Nesting**: Single `build()` has 5+ levels of indentation -> Extract subwidgets.
- **Helper Method Widget Building**: Using `Widget _buildItem()` instead of classes -> Convert to dedicated `StatelessWidget`.
- **Stringly-typed APIs**: Loose strings or magic numbers -> Convert to Enums or Sealed Classes.

### Step 3 — Incremental Refactoring

#### Pattern A: Extract Widget vs Helper Method
❌ **Bad (Helper Method)**:
```dart
// Rebuilds entire widget tree whenever parent rebuilds; loses const benefits.
Widget _buildHeader(String title) {
  return Container(
    padding: const EdgeInsets.all(16),
    child: Text(title, style: Theme.of(context).textTheme.titleLarge),
  );
}
```

✅ **Good (Dedicated StatelessWidget)**:
```dart
// Allows independent rebuild scope, enables const constructor, reusable.
class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Text(title, style: Theme.of(context).textTheme.titleLarge),
    );
  }
}
```

#### Pattern B: Extract State & Business Logic (Clean Architecture / Riverpod)
❌ **Bad (Logic coupled in StatefulWidget)**:
```dart
class _ChatPageState extends State<ChatPage> {
  List<Message> messages = [];
  bool isLoading = false;

  void sendMessage(String text) async {
    setState(() => isLoading = true);
    final response = await http.post(...); // Network coupled inside UI
    setState(() {
      messages.add(...);
      isLoading = false;
    });
  }
}
```

✅ **Good (StateNotifier / AsyncNotifier with Repository)**:
```dart
// Logic lives in a testable notifier/controller
class ChatNotifier extends AutoDisposeAsyncNotifier<List<Message>> {
  @override
  Future<List<Message>> build() async => ref.read(chatRepositoryProvider).fetchMessages();

  Future<void> sendMessage(String text) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await ref.read(chatRepositoryProvider).sendMessage(text);
      return ref.read(chatRepositoryProvider).fetchMessages();
    });
  }
}
```

#### Pattern C: Modern Dart 3 Idioms
Use Pattern Matching and Sealed Classes for state representation:
```dart
sealed class AuthState {}
class AuthInitial extends AuthState {}
class AuthLoading extends AuthState {}
class Authenticated extends AuthState { final User user; Authenticated(this.user); }
class AuthError extends AuthState { final String message; AuthError(this.message); }

// Exhaustive switch expression ensures all cases handled at compile time
Widget build(BuildContext context, AuthState state) => switch (state) {
  AuthInitial() => const SizedBox.shrink(),
  AuthLoading() => const CircularProgressIndicator(),
  Authenticated(:final user) => UserProfileView(user: user),
  AuthError(:final message) => ErrorBanner(message: message),
};
```

---

## Step 4 — Verification
After every refactoring unit:
```bash
flutter analyze
flutter test
```
Ensure zero new warnings or errors.

## Step 5 — Clean & Format
```bash
dart fix --apply
dart format .
```
