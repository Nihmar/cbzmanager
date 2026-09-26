import 'dart:typed_data';

import 'package:cbzmanager/src/engine/image_search.dart';
import 'package:cbzmanager/src/features/image_search/image_search_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  // Regression: the 20 MB cap was checked after `response.bodyBytes`, i.e.
  // after the whole body had been buffered in RAM.  The download now streams
  // and aborts as soon as the running total exceeds the cap.
  test('download aborts a body over the 20 MB cap', () async {
    final megabyte = Uint8List(1024 * 1024);
    final service = ImageSearchService(
      client: MockClient.streaming((request, bodyStream) async {
        Stream<List<int>> body() async* {
          for (var i = 0; i < 21; i++) {
            yield megabyte;
          }
        }

        return http.StreamedResponse(body(), 200);
      }),
    );
    addTearDown(service.dispose);

    await expectLater(
      service.download('https://example.test/huge.jpg'),
      throwsA(predicate((e) => '$e'.contains('20 MB'))),
    );
  });

  test(
    'download rejects a declared oversize body without reading it',
    () async {
      final service = ImageSearchService(
        client: MockClient.streaming((request, bodyStream) async {
          return http.StreamedResponse(
            const Stream<List<int>>.empty(),
            200,
            contentLength: 21 * 1024 * 1024,
          );
        }),
      );
      addTearDown(service.dispose);

      await expectLater(
        service.download('https://example.test/huge.jpg'),
        throwsA(predicate((e) => '$e'.contains('20 MB'))),
      );
    },
  );

  test('download returns a small body unchanged', () async {
    final payload = Uint8List.fromList(
      List<int>.generate(1024, (i) => i % 251),
    );
    final service = ImageSearchService(
      client: MockClient.streaming((request, bodyStream) async {
        return http.StreamedResponse(
          Stream<List<int>>.value(payload),
          200,
          contentLength: payload.length,
        );
      }),
    );
    addTearDown(service.dispose);

    expect(await service.download('https://example.test/ok.jpg'), payload);
  });

  test('search requests carry a timeout and surface HTTP errors', () async {
    final service = ImageSearchService(
      client: MockClient((request) async => http.Response('nope', 500)),
    );
    addTearDown(service.dispose);

    await expectLater(
      service.search(ImageProvider.openverse, 'cats'),
      throwsA(predicate((e) => '$e'.contains('500'))),
    );
  });
}
