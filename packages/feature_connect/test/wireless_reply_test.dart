import 'package:feature_connect/feature_connect.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('connect replies', () {
    test('a fresh connection succeeds', () {
      expect(
        wirelessReplyIsSuccess('connected to 192.168.1.104:5555', 'connected'),
        isTrue,
      );
    });

    test('an existing connection succeeds', () {
      expect(
        wirelessReplyIsSuccess(
          'already connected to 192.168.1.104:5555',
          'connected',
        ),
        isTrue,
      );
    });

    // The regression this whole file exists for. `host:connect` answers OKAY
    // even on failure, and the failure text contains the success word, so a
    // `contains` check reports every unreachable device as connected.
    test('a failure containing the success word is not a success', () {
      expect(
        wirelessReplyIsSuccess(
          'failed to connect to 192.168.1.104:5555',
          'connected',
        ),
        isFalse,
      );
    });

    test('a connection refused is not a success', () {
      expect(
        wirelessReplyIsSuccess(
          'unable to connect to 10.0.0.5:5555: Connection refused',
          'connected',
        ),
        isFalse,
      );
    });

    test('an empty reply is not a success', () {
      expect(wirelessReplyIsSuccess('', 'connected'), isFalse);
      expect(wirelessReplyIsSuccess('   ', 'connected'), isFalse);
    });
  });

  group('pair replies', () {
    test('a successful pairing is recognised', () {
      expect(
        wirelessReplyIsSuccess(
          'Successfully paired to 192.168.1.104:37115 [guid=adb-XXXX]',
          'paired',
        ),
        isTrue,
      );
    });

    test('a wrong code is not a success', () {
      expect(
        wirelessReplyIsSuccess(
          'Failed: wrong password or connection was dropped',
          'paired',
        ),
        isFalse,
      );
    });
  });

  test('surrounding whitespace and case do not matter', () {
    // adb terminates these messages with a newline.
    expect(
      wirelessReplyIsSuccess('Connected to 192.168.1.104:5555\n', 'connected'),
      isTrue,
    );
  });
}
