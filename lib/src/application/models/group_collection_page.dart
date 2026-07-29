class GroupCollectionPage<T> {
  const GroupCollectionPage({
    required this.items,
    required this.hasMore,
    this.nextCursor,
    this.pageGroupDid,
    this.groupStateVersion,
  });

  final List<T> items;
  final bool hasMore;
  final String? nextCursor;
  final String? pageGroupDid;
  final String? groupStateVersion;
}
