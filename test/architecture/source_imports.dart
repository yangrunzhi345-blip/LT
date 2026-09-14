import 'dart:io';

import 'package:path/path.dart' as p;

/// A single `import` directive discovered while scanning source files.
class SourceImport {
  /// Package-relative path of the importing file, e.g. `lib/models/foo.dart`.
  final String importer;

  /// The raw URI written in the directive.
  final String uri;

  /// The lib-relative path the URI resolves to, or `null` when it points
  /// outside `lib/` (`dart:*` or a third-party `package:*`).
  final String? target;

  const SourceImport({
    required this.importer,
    required this.uri,
    required this.target,
  });

  /// `importer -> target`, used as a stable allowlist key.
  String get edge => '$importer -> $target';
}

final RegExp _importDirective =
    RegExp(r'''^\s*import\s+['"]([^'"]+)['"]''', multiLine: true);

/// Recursively collects every `.dart` file under [directory] (package root
/// relative), returning lib-relative normalized paths.
List<String> dartFilesUnder(String directory) {
  final root = Directory(directory);
  return root
      .listSync(recursive: true, followLinks: false)
      .whereType<File>()
      .map((file) => p.normalize(file.path))
      .where((path) => path.endsWith('.dart'))
      .toList()
    ..sort();
}

/// Resolves an import [uri] written in [importer] to a lib-relative path.
///
/// Returns `null` for `dart:*` and non-`lt_dialogue` `package:*` URIs.
String? resolveImportTarget(String importer, String uri) {
  const packagePrefix = 'package:lt_dialogue/';
  if (uri.startsWith('dart:')) return null;
  if (uri.startsWith(packagePrefix)) {
    return p.normalize(p.join('lib', uri.substring(packagePrefix.length)));
  }
  if (uri.startsWith('package:')) return null;
  return p.normalize(p.join(p.dirname(importer), uri));
}

/// Scans all Dart sources under [directory] and returns every `import`.
List<SourceImport> collectImports(String directory) {
  final imports = <SourceImport>[];
  for (final importer in dartFilesUnder(directory)) {
    final source = File(importer).readAsStringSync();
    for (final match in _importDirective.allMatches(source)) {
      final uri = match.group(1)!;
      imports.add(SourceImport(
        importer: importer,
        uri: uri,
        target: resolveImportTarget(importer, uri),
      ));
    }
  }
  return imports;
}
