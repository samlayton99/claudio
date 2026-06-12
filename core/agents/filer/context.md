# Filer context (deterministic pulls — resolved by run-worker.sh / main.py)

Active roles (set primary_role_id from these):
{get_context('role','general','{}')}

Open obligations (so you resolve instead of duplicate, and see what's already tracked):
{due_tasks('{}')}
{pending_expectations('{}')}
