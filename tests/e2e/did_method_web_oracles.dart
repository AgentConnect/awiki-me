import 'dart:convert';

import 'package:awiki_me/src/domain/entities/identity_method.dart';

/// Core sorts service entries by id when publishing a document update. Compare
/// every protected field and preserve multiplicity independently of list order.
String canonicalProtectedWebServices(List<IdentityDocumentService> services) {
  final rows = [
    for (final s in services.where((s) => s.isProtected))
      jsonEncode([
        s.id,
        s.type,
        s.endpoint,
        s.serviceDid,
        s.profiles,
        s.securityProfiles,
      ]),
  ]..sort();
  return jsonEncode(rows);
}
