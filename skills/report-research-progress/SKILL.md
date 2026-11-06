---
name: report-research-progress
description: Use when a check or observation changes the current assessment or the next action of an open research thread. Not for stray notes, not for failed tool calls that do not change the assessment. Produces an evidence file under the thread and updates the thread's index.md.
---

# report-research-progress

When an observation genuinely moves a thread forward (or back), record it so a
later session can reconstruct what you learned without re-running the work.

## Steps

1. **Identify the thread.**
   - `ls threads/active/` → pick the thread whose question the observation
     actually bears on.
   - If no thread fits: do not force-fit. Either open a new thread
     (`cp -r threads/_templates thread/active/thr-NNN`) or drop the note.

2. **Write the evidence file.**
   - `cp threads/_templates/evidence.md threads/active/thr-NNN/evidence/E-MMM.md`
   - Fill in Conditions, Request, Observed response, Target-state check, Limit.
   - Paste the actual command and the actual response bytes. Do not paraphrase.

3. **Update the thread's `index.md`.**
   - Append a row to `## Evidence`: `- E-MMM: <short label> → evidence/E-MMM.md`
   - Rewrite `## Current assessment` if the evidence changed it.
   - Rewrite `## Next action` to the single next concrete step.
   - If the thread's question is answered under this revision AND config,
     set `status: closed` and fill in `## Reopen condition`.

4. **Append one ledger line.**
   - `just ledger thread.updated '"thread":"thr-NNN","evidence":"E-MMM"'`

## Rules

- `index.md` reflects where the work stands now; it can change.
- `evidence/E-MMM.md` reflects what happened in that one check; it does not change.
- A failed tool call that teaches you nothing new is not evidence. Don't record it.
- Closing the tested path does not close the broader question. If the question
  is broader than what you tested, keep the thread open with a narrower next action.
