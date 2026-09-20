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
