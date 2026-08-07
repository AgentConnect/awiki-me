// [INPUT]: AWiki product identity and platform package version metadata.
// [OUTPUT]: SDK-independent client version values and the public HTTP header.
// [POS]: Application-owned version contract mapped by infrastructure adapters.

final class AwikiClientVersion {
  const AwikiClientVersion({
    required this.product,
    required this.release,
    required this.version,
    required this.build,
  });

  final String product;
  final String release;
  final String version;
  final int build;

  String get headerValue => '$product/$release/$version+$build';
}
