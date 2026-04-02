# Digital-Audio-Assets-Protocol-DAAP---packaging Authority Integrator
Specification + implementation for DAAP’s commercial manifest layer. Provides schemas, canonical form, cryptographic signing boundaries, validation, and golden fixtures to ensure consistent licensing/entitlement behavior across players, exchanges, and tooling.

DAAP Manifest Commercial Code

Specification + reference implementation for DAAP’s commercial manifest layer.

This repository defines how licensing, entitlements, and provenance become enforceable rules inside the manifest itself—with a deterministic canonical form, cryptographic signing boundaries, validation tooling, and golden fixtures that keep behavior consistent across implementations.

What this repo is

Manifest commercial specification (normative rules + field semantics)
Canonicalization rules to produce deterministic, signable payloads
Signing / verification boundaries (what must be signed, what must not)
Validation toolchain (schema + rule validation)
Golden fixtures (known-good manifests + expected results)
CI-backed tests so changes don’t drift the protocol

Why it exists

Metadata-only approaches fail because they’re optional, fragile, and externalized. DAAP’s manifest commercial layer makes identity + rights logic intrinsic to the asset, so distribution and playback can enforce the same rules everywhere.

Core guarantees (design goals)

Determinism: same inputs → same canonical bytes
Verifiability: signatures validate unambiguously
Portability: rules behave consistently across platforms/players
Backwards compatibility: older manifests remain parseable and safe
Auditability: fixtures + tests prove expected outcomes

Repository layout (recommended)

spec/ — normative spec + glossary + decision log
schemas/ — JSON Schema / equivalents
src/ — reference implementation
fixtures/ — golden manifests + signatures + expected validation outputs
tests/ — unit + integration tests
tools/ — CLI utilities (validate, canon, sign, verify, diff)
.github/ — CI workflows

Quick start

Install dependencies
Run the validator on fixtures
Run the test suite
Generate canonical form + verify signatures
(Replace these with real commands once your language/tooling is set.)
Working rules (non-negotiables)
Changes that affect canonicalization must update fixtures and tests.
Any modification to signed fields must fail verification unless resigned.

New fields require:

spec entry (spec/)
schema update (schemas/)
fixtures demonstrating behavior (fixtures/)
tests proving invariants (tests/)
Contributing

This is a protocol-critical repo. PRs should include:

What invariant is being added/changed
The fixture(s) demonstrating the expected behavior
Test coverage that fails before the change and passes after

Status

Early-stage spec + implementation. Expect rapid iteration until v1.0 of the commercial layer is pinned.
