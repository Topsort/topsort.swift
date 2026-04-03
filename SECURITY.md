# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability in the Topsort Swift SDK, please report it responsibly.

**Do not open a public GitHub issue for security vulnerabilities.**

Instead, please email **security@topsort.com** with:

- A description of the vulnerability
- Steps to reproduce or a proof of concept
- The affected version(s)
- Any potential impact assessment

## Response Timeline

- **Acknowledgment**: within 3 business days
- **Initial assessment**: within 10 business days
- **Fix or mitigation**: timeline depends on severity, communicated after assessment

## Scope

The following are in scope:

- Authentication/authorization bypass in API key handling
- Data leakage (e.g., event data sent to unintended endpoints)
- Denial of service through SDK misuse (e.g., unbounded retries, memory leaks)
- Insecure data storage (e.g., API keys or user IDs stored insecurely)

The following are out of scope:

- Issues in dependencies (we have zero external dependencies)
- Issues requiring physical access to the device
- Social engineering attacks

## Supported Versions

| Version | Supported |
|---------|-----------|
| 1.0.x   | Yes       |
| < 1.0   | No        |
