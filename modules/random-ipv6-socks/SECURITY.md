# Security Policy

## Reporting a vulnerability

Please use GitHub private vulnerability reporting for security issues. Do not include credentials, public server addresses, or exploit details in a public issue.

Reports should include the affected version or commit, deployment environment, impact, and a minimal reproduction. You can expect an acknowledgement within seven days.

## Deployment warning

SOCKS5 authentication is not transport encryption. Use a strong unique password and restrict the listening port by source IP whenever possible. For untrusted networks, place the proxy behind WireGuard, an SSH tunnel, or another encrypted transport.

Anyone with Docker daemon or root access can inspect container environment variables, including SOCKS5 credentials.

