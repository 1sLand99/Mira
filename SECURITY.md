# Security Policy

Mira welcomes security research, hardening reports, and defensive code review for the project itself.

## Supported Scope

Security reports are useful when they affect code, build scripts, release artifacts, or documented workflows in this repository.

Good reports include at least one of these areas:

1. Memory safety issues in native Android, iOS, or shared shell code.
2. Unsafe parsing, buffer growth, integer overflow, or lifetime bugs.
3. Relay, MCP, or local service exposure that weakens the documented trust boundary.
4. Build, release, dependency, or GitHub Actions weaknesses.
5. Documentation that could cause unsafe deployment or accidental overexposure.

## Out of Scope

The following are normally not treated as Mira security vulnerabilities:

1. Reports that require controlling the user's own Mira host app sandbox without crossing a documented trust boundary.
2. Root, jailbreak, emulator, or Frida detection bypasses in unrelated third-party apps.
3. Generic scanner output without a reachable path in this repository.
4. Findings only affecting vendored third-party code when the fix belongs upstream.
5. Social engineering, spam, account takeover attempts, or testing against infrastructure that is not part of Mira.

## How to Report

For non-sensitive hardening reports, open a GitHub issue or pull request.

For sensitive reports that should not be public yet, use GitHub private vulnerability reporting if it is available for this repository, or contact the maintainer through the GitHub profile linked from the repository owner.

A strong report should include:

1. Affected file and function.
2. Impact and realistic attacker or input model.
3. Reproduction steps, proof of concept, or reasoning path.
4. Expected behavior and actual behavior.
5. Suggested fix or pull request when possible.

## Automated Scanner Reports

Automated security pull requests are welcome, but they must be reviewable.

Please include:

1. The exact rule, tool, or model that produced the finding.
2. Why the finding is reachable in Mira's actual runtime flow.
3. Why the proposed patch preserves behavior.
4. Any build, test, or manual verification performed.

Reports that only restate generic CWE text without repository-specific reasoning may be closed as not actionable.

## Disclosure Expectations

Mira is a research workbench, not a commercial security response program. The project aims to respond in good faith, but does not guarantee a fixed SLA.

Please avoid public exploit amplification before a maintainer has had a reasonable chance to review a sensitive issue.
