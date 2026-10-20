# Security

CitrusDrop processes selected files locally. Initial engine downloads use HTTPS, pinned SHA-256 hashes and publisher signature checks. Vendor executables are not re-signed; system Gatekeeper protections remain enabled.

Report reproducible vulnerabilities through the repository's Security tab if private reporting is available; otherwise open an issue without private files or credentials. Include the app/macOS version, file type, operation and a minimal non-sensitive reproduction.

The application has an ad hoc signature; public builds are not Apple Developer ID notarized. Supported operating systems and external engine versions are documented in the README and engine manifest.
