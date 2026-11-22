# Archived Pre-6-Phase Plan (Superseded 7-Phase Program)

These documents describe the **superseded 7-Phase program** and are retained
only for historical traceability. They are NOT active planning documents and
must not be used for execution.

On 2026-09-19 the program was recompressed from 7 phases to **6 phases**
(7-Phase → 6-Phase Replanning, baseline
`9344ce60e3ad52ddb8425aa52eadf63910e1c437`, at which R01-R05 were all
`ACCEPTED` and Milestones A and B were both `COMPLETE`):

| Former phase (this archive) | Superseded by |
| --- | --- |
| R06 Migration, Serialization & Defensive Hardening | new R06-A / R06-B / R06-C in `../../remediation-phase-06-final-hardening-safe-cleanup.md` |
| R07 Cleanup & Code Slimming | new R06-D / R06-E / R06-F / R06-G in the same merged document, gated by the Hardening Internal Gate and the Protected Compatibility List |

The file names and internal phase numbers in this archive keep their original
7-Phase numbering on purpose. Do not renumber, rewrite or "fix" them - they
are the historical record of the 7-Phase planning state. The docs above are
moved verbatim (`git mv`); their content was not edited during the
recompression.

All findings, contracts and test requirements from these two documents were
fully carried over into the active merged R06 document (see the mapping table
in `remediation-master-plan.md`, section "7-Phase to 6-Phase Mapping");
nothing was dropped by the recompression. C14 was closed by R05 and is not
part of the merged R06 finding backlog; C7 was closed by R05's removal of the
dead import parameters.
