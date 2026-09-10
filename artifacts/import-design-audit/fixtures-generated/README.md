# Audit-only fixture notes

No persistent product fixtures were added. The capture used deterministic, in-memory DEBUG-only bytes with `AUDIT` markers to exercise duplicate, empty and invalid-encoding states. The temporary XCTest seam was removed after capture. Existing repository fixtures under `Fixtures/import/valid` and `Fixtures/import/edge` remain the parser source fixtures.
