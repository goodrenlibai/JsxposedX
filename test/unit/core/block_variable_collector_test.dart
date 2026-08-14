import 'package:JsxposedX/core/utils/block_variable_collector.dart';
import 'package:JsxposedX/features/xposed/domain/models/block_node.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  BlockNode node({
    required String id,
    required BlockType type,
    Map<String, String> params = const {},
    Map<String, List<BlockNode>> slots = const {},
  }) =>
      BlockNode(id: id, type: type, params: params, slots: slots);

  group('BlockVariableCollector.collect', () {
    test('injects hook context vars and declared vars before target', () {
      final root = node(
        id: 'r1',
        type: BlockType.hookMethod,
        params: {'paramTypes': 'int, String'},
        slots: {
          'before': [
            node(id: 'b1', type: BlockType.varAssign, params: {'varName': 'pre'}),
          ],
          'after': [
            node(id: 'a1', type: BlockType.varAssign, params: {'varName': 'myVar'}),
            node(id: 'target', type: BlockType.log, params: {}),
          ],
        },
      );

      final vars = BlockVariableCollector.collect([root], 'target');
      final names = vars.map((v) => v.name).toList();
      expect(names, containsAll([
        'param',
        'param.thisObject',
        'param.getArg(0)',
        'param.getArg(1)',
        'param.getResult()',
        'param.getThrowable()',
        'pre',
        'myVar',
      ]));
      // getResult/getThrowable only appear in after context.
      final resultVars = vars.where((v) => v.name == 'param.getResult()').toList();
      expect(resultVars, hasLength(1));
    });

    test('defaults to getArg(0) when paramTypes empty', () {
      final root = node(
        id: 'r1',
        type: BlockType.hookBefore,
        slots: {
          'body': [
            node(id: 'target', type: BlockType.log, params: {}),
          ],
        },
      );
      final vars = BlockVariableCollector.collect([root], 'target');
      expect(vars.map((v) => v.name), contains('param.getArg(0)'));
      // hookBefore is not an after context → no result/throwable.
      expect(vars.map((v) => v.name), isNot(contains('param.getResult()')));
    });

    test('stops at target and ignores later siblings', () {
      final root = node(
        id: 'r1',
        type: BlockType.hookMethod,
        slots: {
          'after': [
            node(id: 'target', type: BlockType.log, params: {}),
            node(id: 'later', type: BlockType.varAssign, params: {'varName': 'laterVar'}),
          ],
        },
      );
      final vars = BlockVariableCollector.collect([root], 'target');
      expect(vars.map((v) => v.name), isNot(contains('laterVar')));
    });

    test('collects all visible vars when target not found', () {
      final root = node(
        id: 'r1',
        type: BlockType.hookMethod,
        slots: {'after': [node(id: 'x', type: BlockType.log, params: {})]},
      );
      final vars = BlockVariableCollector.collect([root], 'missing');
      // Context vars are still collected even when the target is absent.
      expect(vars.map((v) => v.name), contains('param'));
      expect(vars, isNotEmpty);
    });

    test('no context vars for non-hook trees', () {
      final root = node(
        id: 'r1',
        type: BlockType.varAssign,
        params: {'varName': 'a'},
        slots: {
          'body': [node(id: 'target', type: BlockType.log, params: {})],
        },
      );
      final vars = BlockVariableCollector.collect([root], 'target');
      final names = vars.map((v) => v.name).toList();
      expect(names, ['a']); // only the declared variable, no hook context.
    });
  });
}
