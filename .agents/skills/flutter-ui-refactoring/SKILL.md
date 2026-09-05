---
name: flutter-ui-refactoring
description: "Use when refactoring Flutter UI code, decomposing large widgets, eliminating helper build methods (_buildX), isolating rebuild scopes, fixing layout overflow, or enforcing design system and themes."
---

# Flutter UI & Widget Refactoring Skill

A practical, production-grade guide for refactoring Flutter UI code. Focuses on widget decomposition, render performance, rebuild scope isolation, and responsive design systems.

---

## When to Use This Skill

- Breaking down large monolithic `build()` methods (> 80 lines).
- Eliminating helper method antipatterns (`Widget _buildCard()`, `Widget _buildItem()`).
- Fixing layout overflow errors (`RenderFlex overflowed by ... pixels`).
- Isolating rebuild scopes so that state changes (`setState`, animations, text input) don't rebuild the entire screen.
- Replacing hardcoded colors, sizes, and fonts with unified `Theme.of(context)` tokens.
- Refactoring imperative animations or controllers into modular widgets.

---

## 1. Widget Decomposition & The "Helper Method" Antipattern

### ❌ The Antipattern: Helper Methods (`_buildX`)
```dart
class UserProfilePage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildAvatar(), // BAD: Helper method
        _buildStats(),  // BAD: Tied to parent BuildContext, rebuilds with parent
      ],
    );
  }

  Widget _buildAvatar() => CircleAvatar(...);
  Widget _buildStats() => Row(...);
}
```
**Why this is bad**:
- Flutter cannot optimize or short-circuit rebuilds for helper methods (no separate `Element` in the tree).
- Cannot use `const` constructor optimizations.
- InheritedWidgets accessed inside the helper method will cause the entire parent widget to rebuild.

### ✅ The Solution: Dedicated Widgets
```dart
class UserProfilePage extends StatelessWidget {
  const UserProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        UserAvatarWidget(), // Good: Separate Element, const optimization
        UserStatsWidget(),  // Good: Isolated rebuild scope
      ],
    );
  }
}

class UserAvatarWidget extends StatelessWidget {
  const UserAvatarWidget({super.key});
  @override
  Widget build(BuildContext context) => const CircleAvatar(...);
}
```

---

## 2. Rebuild Scope Isolation

Always push state changes down to leaf nodes:

### ❌ Bad: Top-level setState rebuilds the entire page
```dart
class _ChatPageState extends State<ChatPage> {
  bool isRecording = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ComplexChatHistoryView(), // Rebuilds every time recording state changes!
      bottomNavigationBar: RecordButton(
        onToggle: () => setState(() => isRecording = !isRecording),
      ),
    );
  }
}
```

### ✅ Good: Localized State or Scoped Consumer
```dart
// The chat history stays const and is never re-evaluated
class ChatPage extends StatelessWidget {
  const ChatPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: ComplexChatHistoryView(),
      bottomNavigationBar: RecordingControlBar(), // State is managed internally inside this leaf widget
    );
  }
}
```

---

## 3. Layout Refactoring & Overflow Prevention

1. **Flexible Text & Content**:
   Always wrap variable-length text in `Expanded` or `Flexible` when placed inside a `Row`:
   ```dart
   // Prevents Right Overflowed by X Pixels
   Row(
     children: [
       const Icon(Icons.info),
       const SizedBox(width: 8),
       Expanded(
         child: Text(longUserMessage, overflow: TextOverflow.ellipsis),
       ),
     ],
   )
   ```
2. **Scrollable Viewports**:
   When content can exceed vertical space, wrap in `SingleChildScrollView` or `ListView`, never rely on unbounded `Column` inside a dialog or bottom sheet:
   ```dart
   LayoutBuilder(
     builder: (context, constraints) {
       return SingleChildScrollView(
         child: ConstrainedBox(
           constraints: BoxConstraints(minHeight: constraints.maxHeight),
           child: IntrinsicHeight(child: Column(...)),
         ),
       );
     },
   )
   ```

---

## 4. Design System & Theme Refactoring

Eliminate hardcoded values:
- **Colors**: Replace `Color(0xFF333333)` with `Theme.of(context).colorScheme.onSurface` or `surfaceContainer`.
- **Text Styles**: Replace `TextStyle(fontSize: 16, fontWeight: FontWeight.bold)` with `Theme.of(context).textTheme.titleMedium`.
- **Spacings & Radii**: Replace magic numbers with standard spacing constants or theme tokens (e.g. `BorderRadius.circular(12)` -> `Theme.of(context).cardTheme.shape`).

---

## 5. Standard UI Refactoring Checklist

When refactoring any UI file:
- [ ] Are all `_buildX()` methods converted to standalone `StatelessWidget` / `StatefulWidget` classes?
- [ ] Are all eligible constructors marked `const`?
- [ ] Is dynamic state (`setState`, text controllers, animations) scoped to the smallest possible sub-tree?
- [ ] Are variable-width elements in `Row`s protected by `Expanded` / `Flexible`?
- [ ] Are colors and typography derived from `Theme.of(context)` rather than hardcoded hex values?
- [ ] Does `flutter analyze` report zero linter warnings on the refactored files?
