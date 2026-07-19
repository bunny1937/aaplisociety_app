/// Compact relative-time formatting for gate-log cards ("22m ago", "3h ago").
String timeAgo(DateTime from, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final diff = n.difference(from);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}
