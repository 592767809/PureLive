import 'package:flutter_test/flutter_test.dart';
import 'package:live_player/src/mpv_input.dart';
import 'package:media_kit/media_kit.dart';
// Test the fork boundary that decides between loadfile and loadlist.
import 'package:media_kit/src/player/native/core/direct_media_load.dart';

void main() {
  test('content descriptors retain their existing direct load path', () {
    expect(needsDirectMediaLoad('fd://42'), isTrue);
  });
  test('arbitrary avdevice inputs do not bypass playlist restrictions', () {
    expect(needsDirectMediaLoad('av://lavfi:testsrc'), isFalse);
    expect(needsDirectMediaLoad('av://rtp:https://fixture.invalid/live'), isFalse);
  });
  for (final address in [
    'rtp://239.255.54.15:49816',
    'rtp://127.0.0.1:49817',
    'rtp://239.255.54.15:49816?localaddr=127.0.0.1&buffer_size=8388608',
    'rtp://[ff15::5415]:49816?source=fixture%20only',
  ]) {
    test('RTP reaches the packet demuxer without changing $address', () {
      final input = mpvMediaInput(Uri.parse(address));
      expect(input, 'av://rtp:$address');
      // The internal mpv syntax is opaque, not an ordinary Dart authority.
      // Media normalization must leave it intact, including the endpoint.
      expect(Media.normalizeURI(input), input);
      expect(Media(input).uri, input);
      expect(needsDirectMediaLoad(input), isTrue);
    });
  }

  for (final address in [
    'https://fixture.invalid/live.m3u8?source=fixture%20only',
    'http://127.0.0.1:49815/fixture.ts',
    'rtsp://fixture.invalid:8554/live',
    'udp://239.255.54.15:49816',
    'file:///tmp/purelive-fixture.ts',
    'data:application/octet-stream;base64,AA==',
  ]) {
    test('other source schemes keep their existing input: $address', () {
      final source = Uri.parse(address);
      expect(mpvMediaInput(source), source.toString());
      expect(needsDirectMediaLoad(source.toString()), isFalse);
    });
  }
}
