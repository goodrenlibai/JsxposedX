import 'package:JsxposedX/features/ai/domain/environments/apk_reverse_chat_tools_spec.dart';
import 'package:JsxposedX/features/ai/domain/environments/apk_reverse_tool_definitions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ApkReverseToolDefinitions.all', () {
    test('contains the core reverse tools', () {
      final names = ApkReverseToolDefinitions.all.map((d) => d.name).toList();
      expect(names, containsAll([
        'get_manifest',
        'search_classes',
        'list_apk_files',
        'decompile_class',
        'get_smali',
        'list_packages',
        'list_classes',
      ]));
    });

    test('every definition has a name and description', () {
      for (final def in ApkReverseToolDefinitions.all) {
        expect(def.name, isNotEmpty);
        expect(def.description, isNotEmpty);
      }
    });

    test('search_classes declares required keyword', () {
      final def = ApkReverseToolDefinitions.all
          .firstWhere((d) => d.name == 'search_classes');
      expect(def.parameters['required'], contains('keyword'));
    });
  });

  group('ApkReverseToolDefinitions.allWithSo', () {
    test('is a superset that includes SO analysis tools', () {
      final names = ApkReverseToolDefinitions.allWithSo.map((d) => d.name).toList();
      expect(names, containsAll([
        'get_so_info',
        'search_so_symbols',
        'get_jni_functions',
        'search_so_strings',
        'generate_so_hook',
      ]));
    });

    test('includes all base tools', () {
      final allNames =
          ApkReverseToolDefinitions.all.map((d) => d.name).toSet();
      final soNames =
          ApkReverseToolDefinitions.allWithSo.map((d) => d.name).toSet();
      expect(soNames.containsAll(allNames), isTrue);
    });
  });

  group('ApkReverseChatToolsSpec', () {
    test('without SO tools only exposes base set', () {
      final spec = ApkReverseChatToolsSpec(includeSoTools: false);
      final names = spec.definitions.map((d) => d.name).toSet();
      expect(names, isNot(contains('get_so_info')));
      expect(names, contains('get_manifest'));
    });

    test('with SO tools exposes the full set', () {
      final spec = ApkReverseChatToolsSpec(includeSoTools: true);
      final names = spec.definitions.map((d) => d.name).toSet();
      expect(names, contains('get_so_info'));
    });
  });
}
