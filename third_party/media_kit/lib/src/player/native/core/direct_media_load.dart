/// Inputs that must be opened individually rather than through a playlist.
///
/// Descriptor inputs retain the existing path. The app's internal RTP
/// demuxer address is also rejected by mpv's playlist protocol policy;
/// opening it directly avoids broadening that policy for other av inputs.
bool needsDirectMediaLoad(String uri) =>
    uri.startsWith('fd://') || uri.startsWith('av://rtp:rtp://');
