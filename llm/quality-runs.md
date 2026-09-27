# Quality-run record

Every quality run this project has made, with the harness revision it ran against and what was still broken
at that revision. **A score here means nothing without that last column** — the same model has scored 3/12 and
8/12 on the "same" task set, and the difference was the instrument, not the model.

Raw evidence JSONs (one per row) are not published. Each row carries the SHA-256 of its file, so the numbers
below can be matched against the data if it is ever produced. Regenerate a row with:

    llm/tests/quality-run.ps1 -Mode <model> -TaskSet <base|hard> -NoThinking

## The runs

| file | mode | set | score | time | harness (last `llm/tests` commit at that time) | still broken then | sha256[:16] |
|---|---|---|---|---|---|---|---|
| `quality-qwen36u35b-20260926-230802.json` | `qwen36u35b` | ? | **2/2** | 230802 | 0fc3f48 (23:07) | concat+quoting defects | `25ec56c1e06c9a22` |
| `quality-qwen36u35b-20260926-231011.json` | `qwen36u35b` | ? | **11/12** | 231011 | 0fc3f48 (23:07) | concat+quoting defects | `6d16d8e43f632061` |
| `quality-katcoder25-20260926-231329.json` | `katcoder25` | ? | **10/12** | 231329 | 0fc3f48 (23:07) | concat+quoting defects | `cbbc300cc8c6f3d3` |
| `quality-ornith15-20260926-231828.json` | `ornith15` | ? | **3/12** | 231828 | 3a53d87 (23:18) | concat defect | `b80cf119e64dd36f` |
| `quality-qwen36u35b-20260926-232402.json` | `qwen36u35b` | ? | **12/12** | 232402 | db52e0d (23:22) | clean | `17d7353d99085543` |
| `quality-katcoder25-20260926-232635.json` | `katcoder25` | ? | **12/12** | 232635 | db52e0d (23:22) | clean | `1aa21cd8bf4960cc` |
| `quality-ornith15-20260926-232952.json` | `ornith15` | ? | **2/12** | 232952 | db52e0d (23:22) | clean | `6d6a959ad8bffa74` |
| `quality-qwen36u35b_ml-20260926-235146.json` | `qwen36u35b_ml` | base | **5/12** | 235146 | efe9da5 (23:44) | unanswerable+verb+precision defects |
| `quality-qwen38distill-20260927-000023.json` | `qwen38distill` | base | **12/12** | 000023 | db52e0d (23:22) | unanswerable+verb+precision defects | `1e2c02880d79968b` |
| `quality-qwen38distill-20260927-000509.json` | `qwen38distill` | base | **12/12** | 000509 | db52e0d (23:22) | unanswerable+verb+precision defects | `92bda85ea296538c` |
| `quality-agentworld35b-20260927-000939.json` | `agentworld35b` | base | **5/12** | 000939 | db52e0d (23:22) | unanswerable+verb+precision defects | `4d1c79aecfbfdd78` |
| `quality-qwen36u35b_ml-20260927-002012.json` | `qwen36u35b_ml` | base | **12/12** | 002012 | efe9da5 (23:44) | unanswerable+verb+precision defects | `8b155840a0f8af98` |
| `quality-qwen38distill-20260927-002402.json` | `qwen38distill` | base | **11/12** | 002402 | efe9da5 (23:44) | unanswerable+verb+precision defects | `e58b10d579617cc6` |
| `quality-agentworld35b-20260927-002950.json` | `agentworld35b` | base | **9/12** | 002950 | efe9da5 (23:44) | unanswerable+verb+precision defects | `48d60aaf7cf23031` |
| `quality-qwen36u35b_ml-20260927-003413.json` | `qwen36u35b_ml` | hard | **3/12** | 003413 | efe9da5 (23:44) | unanswerable+verb+precision defects | `a4ccbf19b06dcb66` |
| `quality-qwen36u35b_ml-20260927-004222.json` | `qwen36u35b_ml` | hard | **3/12** | 004222 | 83ec4fa (00:13) | unanswerable+precision defects | `77be570fcef21dae` |
| `quality-qwen36u35b_ml-20260927-005310.json` | `qwen36u35b_ml` | hard | **4/12** | 005310 | afca451 (00:52) | non-derivable precision task | `6a93c66bc1b93ce0` |
| `quality-qwen36u35b_ml-20260927-012242.json` | `qwen36u35b_ml` | hard | **1/3** | 012242 | be26a6e (01:22) | precision + context fixtures too large | `52defbce90bda2ab` |
| `quality-qwen38distill-20260927-112834.json` | `qwen38distill` | hard | **7/12** | 112834 | afca451 (00:52) | non-derivable precision task | `5887c5da3f20e853` |
| `quality-qwen36u35b_ml-20260927-115034.json` | `qwen36u35b_ml` | hard | **3/3** | 115034 | afca451 (00:52) | non-derivable precision task | `e0af8c08ae270f8b` |
| `quality-qwen36u35b_ml-20260927-121556.json` | `qwen36u35b_ml` | hard | **1/1** | 121556 | 87f276e (12:15) | none known (Family A later found unsound) | `ccd799a73a613111` |
| `quality-qwen38distill-20260927-121827.json` | `qwen38distill` | hard | **1/1** | 121827 | 87f276e (12:15) | none known (Family A later found unsound) | `e19d6aaf4a37da2c` |
| `quality-qwen38distill-20260927-121926.json` | `qwen38distill` | base | **0/1** | 121926 | 87f276e (12:15) | none known (Family A later found unsound) | `78777ee1ffecadc5` |
| `quality-qwen36u35b_xs-20260927-181922.json` | `qwen36u35b_xs` | base | **12/12** | 181922 | 87f276e (12:15) | none known (Family A later found unsound) | `93e65623541c3e68` |

## Which numbers are supported

- **Long context** — sound from `e212398` (11:23) onward. Before that the fixtures were the wrong size: one
  was ~25.0 K tokens against the 32 K window, another needed ~400 s of prefill under a 300 s client timeout.
  Both produced confident failures that were the instrument's, not the model's.
- **Tool chains and instruction precision** — sound from `afca451` (00:52) and `87f276e` (12:15).
- **Multi-file editing (Family A) — not supported at any revision listed here.** Two of its four tasks never
  supplied the files they ask the model to repair, and the suite check can pass without the requested work
  (appending a symbol without renaming its call sites satisfies the rename task). The family could not
  discriminate, so no conclusion about models should be drawn from its 0/4. A repaired family has to be
  re-measured before that question is answered.
- **The KAT-Coder, Ornith and AgentWorld screenings** ran while the unanswerable-task and verb-blocklist
  defects were live, so their scores understate them and the resulting exclusion verdicts are not final.
  Ornith separately failed to serve at all (an upstream hybrid/recurrent defect, unrelated to the harness).

## The defects, in the order they were found

1. The code policy denied `>` as "output redirection" — ordinary in a script that writes a file. `83ec4fa`
2. The policy was a verb blocklist, making four multi-file tasks impossible to solve. `89d5efb`
3. Five tasks said "read <file>" while supplying neither the file nor a tool to read it. `afca451`
4. One task's expected value was not derivable from anything it was given. `87f276e`
5. The context fixtures did not fit the window — an instant HTTP 400, or a prefill longer than the client timeout. `be26a6e`, `e212398`
6. The answerability validator could not fail on non-derivability, and Family A had no answerability rule at all.
   Found by two independent auditors, not by the author.
7. Family A's discrimination holes: no fixture reset between candidates, and a tamperable canonical test copy.
   Found by the same audit.

## Why this file exists

An independent auditor's finding: *"Host paths are provenance, not evidence."* Every figure reported from this
project derived from files on a private machine that no reader could check. This file is the compromise: the
numbers, their instrument revision, and a hash to bind them to the raw data — without turning the repository
into a data store.
