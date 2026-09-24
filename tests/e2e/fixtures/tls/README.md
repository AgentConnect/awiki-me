# Controlled TLS fixtures

Public test-only key and certificates for loopback TLS tests. Never deploy or import into OS trust stores. CA private key discarded. Valid and wrong-host leaves expire 2027-09-01 (renew the loopback fixtures before that date); expired leaf expired 2001-01-01. Only loopback IP/localhost is accepted by the valid leaf.
