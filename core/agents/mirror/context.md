# Mirror — context construction

NOT YET BUILT as a worker: this folder has prompt.md + context.md only (no main.sh/test.sh);
the mirror runs as Sam-present panel sessions until its P4 build.

Deterministic pulls assembled by `run-worker.sh` (P1+). Pre-P1 (the first elicitation session), the pulls resolve to the seed files noted in brackets.

You are the mirror. Today is {today}.

The purpose contract as it stands:
{purpose_contract()}            [pre-P1: core/l1/seeds/purpose-contract.md]

Roles and user-set weights:
{roles()}                       [pre-P1: core/l1/seeds/roles.json]

Alignment state (observational mode only, P5+):
{v_purpose_alignment}

Recent daily reflections (observational mode only):
{recent_reflections(days=30)}

Active directives in scope:
{directives(scope='global')}
