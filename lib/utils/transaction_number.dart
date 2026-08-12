/// Derives a short, human-readable transaction reference from a request's
/// UUID primary key — e.g. "f759f42f-9ee9-4620-..." -> "PING-F759F42F".
///
/// Deliberately NOT a stored column: the UUID is already globally unique,
/// so this is a pure display-time transform. That means every ping, past
/// and future, has a reference number with zero migration and zero risk
/// of a generation race/collision.
String transactionNumber(dynamic requestId) {
  final id = requestId?.toString() ?? '';
  if (id.isEmpty) return 'PING-UNKNOWN';
  final head = id.split('-').first;
  return 'PING-${head.toUpperCase()}';
}
