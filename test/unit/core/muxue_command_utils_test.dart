import 'package:JsxposedX/core/utils/muxue_command_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MuxueCommandUtils.generated', () {
    test('encodes a post command to compact JSON', () {
      final json = MuxueCommandUtils.generated(command: MuxueCommand(id: 7, description: 'hit', type: MuxueCommandType.post),
      );
      expect(json, '{"id":7,"description":"hit","type":0}');
    });

    test('encodes an app command', () {
      final json = MuxueCommandUtils.generated(command: MuxueCommand(id: 1, description: 'open', type: MuxueCommandType.app),
      );
      expect(json, '{"id":1,"description":"open","type":1}');
    });

    test('preserves description characters', () {
      final json = MuxueCommandUtils.generated(command: MuxueCommand(id: 0, description: 'a"b', type: MuxueCommandType.post),
      );
      expect(json, contains('"a\\"b"'));
    });
  });
}
