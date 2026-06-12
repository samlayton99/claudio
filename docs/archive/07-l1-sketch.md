# L1 Sketch

L1 is core, built deliberately at MVP step 1. These are the candidate functions to start from — added as consumers need them, never speculatively. (It is the **outer circle** that starts empty, not L1 — see `04`.)

## Write candidates

- `capture(adapter, raw)` — the one universal intake insert
- `create_task(...)`, `create_expectation(...)`, `log_entry(...)`
- `upsert_person(...)`, `add_handle(person, source, handle)`, `propose_merge(a, b, evidence)`
- `set_directive(statement, scope)`
- `register_page(kind, title, anchor, ...)` / `rename_page(...)` — file writes through L1 (see `05`)
- `register_component(kind, definition_path, ...)` — adapters/workflows/tools into the registry
- `post_message(queue, payload)`, `claim_message(id)`, `complete_message(id, result)` — the queue lifecycle
- `propose(kind, payload)`, `approve(id)`, `reject(id)`
- `record_run(component, outcome, tokens, ...)`

## Read candidates

- `get_context(anchor, budget)` — **the** function. Returns the context packet: `{state, taste, obligations, capabilities}`, every entry cited with `{source, locator, tool}` refs. Executed by the assembler (procedure in `05`).
- `search_people(filter)`, `what_happened(range, filters)`
- `due_tasks(scope)`, `pending_expectations(scope)`
- `queue_status(agent)` — my mailbox + what I'm waiting on

## View candidates

`stale_expectations` · `unfiled_intake` · `run_misses` (watchdog source) · `unread_proposals` · `orphan_documents`
