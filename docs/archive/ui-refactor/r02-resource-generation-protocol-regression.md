# R02 Resource Generation Protocol Regression

## Root Cause

`PartGenerationPromptBuilder` required NDJSON Patch output, but the non-streaming
`PartGenerationCoordinator` branch parsed the collected response using the retired
single-object `PartGenerationParser`. A production response that followed the
prompt therefore reached an incompatible parser and failed before persistence.

## Broken Contract

The canonical protocol is version `1`. Every Patch is a top-level JSON object
with required integer `protocol_version`, `generation_id`, `resource_id`,
`section_id`, `part_id`, `attempt_id`, non-negative integer `sequence`, and
`op`. `append_text` carries `text_delta`; cursors are validated by the
accumulator. `start_part`, one or more `append_text`, then `complete_part` is
the accepted lifecycle.

## Actual LLM Response

The failing response shape was NDJSON, for example (identifiers and content
are redacted):

```json
{"protocol_version":1,"generation_id":"<redacted>","resource_id":"<redacted>","section_id":"<redacted>","part_id":"<redacted>","attempt_id":"<redacted>","sequence":0,"op":"start_part","cursor":0}
```

The old non-streaming path incorrectly expected a top-level `content` field.
No credentials, authorization headers, or user content are logged by this
diagnosis.

## Prompt Contract

The prompt now explicitly states that `protocol_version` is REQUIRED, must be
the JSON integer `1`, and must never be a string, `null`, or omitted. It also
pins all identity fields and requires NDJSON only.

## Schema Contract

`resourcePartGeneration` deliberately does not request `response_format`:
JSON-object mode cannot represent the required multi-line NDJSON response.
The prompt and strict Patch parser are the authoritative schema boundary.

## Parser Contract

`GenerationPatchParser` fail-closes on missing, `null`, string, floating-point,
or boolean protocol versions, unknown keys, invalid operations, and invalid
identity fields. `GenerationPatchAccumulator` validates identity, monotonic
sequence, cursor, capacity, and completion before a response can be persisted.

## Streaming Contract

The streaming branch buffers partial lines and only parses complete NDJSON
records; a final record without a newline is parsed after the stream closes.
The non-streaming branch now calls `parseNdjson` and feeds the same accumulator,
so transport delivery no longer changes protocol semantics.

## Fix

`PartGenerationCoordinator` now uses `GenerationPatchParser.parseNdjson` for
both delivery modes and derives its `PartGenerationResponse` only from the
validated accumulator. The legacy single-object parser is not on the production
Part-generation path.

## Retry Verification

On parser failure the attempt is recorded as failed. Retry builds a new prompt,
uses a new attempt id, preserves the resource and task identity, and validates
the new response against that id. The coordinator regression test starts with a
missing `protocol_version` Patch and completes successfully on the retry.

## Regression Tests

- `generation_patch_parser_test.dart`: canonical response and missing/null/string/float/bool versions.
- `part_generation_prompt_builder_test.dart`: required integer prompt wording.
- `part_generation_coordinator_test.dart`: NDJSON completion and malformed-version retry.
- Resource streaming service, controller, CAS, and section-regeneration tests:
  NDJSON fixtures exercise the normal Coordinator persistence path.

## Final Result

Both streaming and collected completions share the version-1 Patch contract;
invalid protocol versions remain rejected and never receive a default value.

## Final Verification Recovery

- Recovery HEAD: `b39b985570d9d6e966c28d0acbc5e88e1fb96592`.
- `b39b985` was inspected in full and passed `git show --check`; the recovery
  began from a clean worktree at that commit.
- Static production tracing confirms `PartGenerationCoordinator` routes both
  `PartGenerationStreamingGateway` chunks and collected `rawCompletion`
  responses through `GenerationPatchParser` and the same
  `GenerationPatchAccumulator`, before validation and persistence.
- Directed protocol, coordinator, streaming, lifecycle, CAS, and Resource
  Studio tests passed: 82 tests, exit code 0.
- `dart format --output=none --set-exit-if-changed .` passed with 0 changed
  files, and `flutter analyze` reported no issues.
- Full `flutter test` completed with exit code 0: 1,864 passed; no failed or
  skipped tests were reported by the runner.

Final verdict: **ACCEPTED**.

## Cursor Mismatch Regression

### Observation and Root Cause

The production report observed `PatchCursorMismatchException` for
`res_cre_1789875506797810_2_part_2`: the accumulator expected `2540`, while
the final model Patch reported `2387` (a delta of `153`). The expected value
was the UTF-16 code-unit length of text already accepted by
`GenerationPatchAccumulator`; the actual value was an LLM-supplied estimate
from `complete_part`. No production layer converted that value through UTF-8,
code points, grapheme clusters, or a Chinese-character counter. The mismatch
therefore came from asking the LLM to count a long body precisely, not from a
Chinese/Unicode conversion defect.

### Canonical Cursor Contract

The canonical cursor is the application-owned current Part body offset,
measured as Dart `String.length` (UTF-16 code units). The model now omits
`cursor` from every Patch. `GenerationPatchParser` preserves an omitted cursor
as absent rather than defaulting it to `0`, and
`GenerationPatchAccumulator` derives the position from accepted `text_delta`
values. A legacy supplied integer cursor is only a strict assertion: any
disagreement still throws `PatchCursorMismatchException`; it is never adopted,
tolerated, or used to overwrite the accumulator.

| Component | Cursor source | Unit | Validation |
| --- | --- | --- | --- |
| Prompt Builder | Declares model omission | N/A | Forbids estimated cursor output |
| LLM wire output | No cursor in canonical protocol | N/A | Parser rejects null/non-integer supplied legacy values |
| Parser | Preserves optional legacy assertion | UTF-16 integer when present | No implicit default |
| Accumulator | Accepted `text_delta` prefix | Dart UTF-16 code units | Legacy assertion must equal derived prefix |
| Validator | Final accumulated response | Dart `String.length` | Existing maximum-length boundary |
| Persistence | Validated final response only | Dart `String.length` | Atomic commit with attempt/source-token CAS |
| Retry / resume | Fresh attempt with fresh accumulator | Starts at zero | Attempt ID, lease, and CAS reject late/stale writes |

### Transport, Retry, and Integrity

Streaming continues to buffer NDJSON line fragments and processes a final line
without a newline. Collected and streaming responses both pass through the
same parser and accumulator. There is no persisted partial body to resume:
content is committed only after the full accumulator response validates, so a
retry starts a new attempt at cursor zero. Attempt identity and the repository
lease/CAS boundary prevent a late response from an older attempt from being
committed into the retry.

The Studio previously retained an uncommitted preview after validation failure,
which could make generated-looking text appear beside a failed session. Failed
Parts now discard their transient preview and restore the persisted body. The
progress metric remains completed-and-committed Parts divided by total Parts;
therefore zero percent before the first atomic Part commit is intentional, not
a second cursor or persistence defect.

### Regression Coverage

- Mixed ASCII, Chinese, Chinese punctuation, emoji, `𠮷`, LF, CRLF, and
  Markdown confirms the single UTF-16 unit.
- A >3000-unit Chinese/mixed-Unicode, three-Patch accumulation confirms exact
  ordering with no duplicates, omissions, or truncation.
- The reported `2540`/`2387` mismatch remains a strict rejection regression.
- Omitted-cursor collected and line-split/final-no-newline streaming coordinator
  paths complete through the production accumulator.
- Retry, interrupted recovery, late-attempt isolation, task persistence, and
  Studio failure-preview behavior are covered by directed tests.
