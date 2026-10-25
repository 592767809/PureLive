/// The input passed to libmpv for a prepared media source.
///
/// The bundled mpv otherwise probes RTP datagrams as a byte stream, leaving
/// their packet headers in the TS payload. Its opaque avdevice input opens
/// FFmpeg's RTP demuxer directly, preserving packet boundaries and jitter
/// handling (G02.6). Other protocols retain their ordinary source URI.
String mpvMediaInput(Uri source) => source.isScheme('rtp') ? 'av://rtp:$source' : source.toString();
