# ABO final review — reviewer agent prompt

Fill in `<RM RANGE>` and `<AREA>` per agent. Suggested splits: RM00–RM10, RM11–RM20,
RM21–RM30, RM31–RM38; give the backend/RLS agent the full range, since migrations
interact across phases. Use a final agent to merge the reports into
`docs/review/final-review/SUMMARY.md`.

## Prompt

```
You are an independent reviewer of the ABO remediation work on branch ai/abo-remediation (compare against master). This is a read-only review: do not edit any code or docs except your report file.

Scope: phases <RM RANGE, e.g. RM01–RM10> and the code areas they touch (<AREA>).

Sources:
- Plan and phase definitions: docs/review/abo-remediation-plan.md (phase overview, section 3 onward)
- Phase prompts: docs/review/abo-remediation-prompts.md
- Per-phase records: docs/review/abo-remediation/RMxx.md
- Original findings: docs/review/abo-integrated/
- Commits: `git log --oneline master..HEAD | grep RMxx`

Task A — Phase verification. For EACH RM in scope:
1. Identify the findings/requirements the phase was meant to resolve.
2. Verify in the code at the branch tip (not just the commit message or the RMxx.md claims) that each one is resolved. Cite file:line.
3. Assign a status: HANDLED / PARTIAL / NOT HANDLED / REGRESSED (fixed then undone by a later phase), plus a one-line justification.

Task B — Whole-code review. Treat the current code in <AREA> as if reviewing it fresh after all RMs. Look for CRITICAL and MAJOR defects only, e.g.: auth or authorization bypass, tenant/branch data leakage, RLS or RPC gaps, data loss or corruption, broken migrations or ordering, security flaws, race conditions, money/billing errors, crashes on main user flows, and cross-phase conflicts. Do not report minor, style, or test-coverage nits. Verify every claim by reading the code; do not speculate. If unsure, say so and lower the confidence.

Severity:
- Critical: exploitable security hole, data loss/corruption, or core flow broken.
- Major: significant incorrect behavior or risk that should block launch but has a workaround or limited blast radius.

For every Critical or Major finding, give: ID (C-1, M-1...), title, file:line, failure scenario (concrete inputs/state -> wrong outcome), confidence, and a proposed fix (specific enough to implement, naming the files and approach).

Output: write everything to docs/review/final-review/<AREA-or-RM-range>.md and nothing else. Structure:
1. Summary (counts: phases handled/partial/not handled; critical/major findings; verdict: PASS or FAIL)
2. Phase verification table (RM | requirement | status | evidence)
3. Critical findings
4. Major findings
5. Notes on anything you could not verify

If there are no Critical or Major findings, say so explicitly. Keep the file concise and evidence-based. In chat, reply only with the file path and the verdict.
```
