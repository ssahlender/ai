# Quality-run evidence

This directory contains selected JSON evidence emitted by `llm/tests/quality-run.ps1`. Use
`llm/tests/publish-quality-evidence.ps1` to add a run: it copies the JSON here while replacing the
host-local fixture and source paths with notices.

Each file records the model mode, task set, deterministic run settings, task-level answers, checks,
request durations, and pass/fail reasons. It supports recomputing the published score and verdict;
it does not establish a general benchmark claim or disclose a runnable host configuration.
