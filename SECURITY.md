# Security

Browserdoor passes links from other apps to browsers as command-line arguments, so a link that slips past its checks could become a browser flag or open a local file. The rules are in [`URLPolicy`](Sources/BrowserdoorCore/URLPolicy.swift) and [SPEC.md](SPEC.md).

## Reporting a vulnerability

Please report it privately through [GitHub's private vulnerability reporting](https://github.com/schowave/browserdoor/security/advisories/new), not in a public issue. Include the Browserdoor version, your macOS version and the link or file that triggers it.

You'll get an answer within a week. A fix ships as a patch release, and the advisory is published once the release is out.

## Supported versions

Only the latest release gets fixes. `brew upgrade browserdoor` brings you there.
