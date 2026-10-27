# Security policy

This policy applies to every repository in the Verdict organisation unless a repository carries its own.

## Reporting a vulnerability

Use GitHub private vulnerability reporting on the affected repository ("Report a vulnerability" under the Security tab). Do not open a public issue for a security problem. Include the repository, the version or commit, the test framework and build tool in use, and a minimal reproduction.

## What counts

A Verdict reporter reads test output and renders it for a coding agent, so the relevant failure modes are: test-produced text that forges a verdict line or a section header, secrets that survive into a report or sidecar file, a report written outside the configured directory or through a symbolic link, and a reporter failure that hides a test failure. Reports of any of these are treated as defects of the highest priority.

## Supported versions

Until the first tagged release of a repository, only its default branch is supported.
