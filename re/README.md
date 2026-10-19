# re — radare2 + r2ghidra on Windows

A Windows-native decompilation toolchain for binaries whose functions are **unreachable through
REA**. Two reasons a function needs this instead:

1. **REA's 120 s ceiling.** REA kills any rizin command after a hard 120 s (`provider_timeout`,
   `timeout_ms: 120000`, `SIGKILL`; `DEFAULT_TIMEOUT_MS` is a constant with no CLI flag and no env
   override). Calling radare2 directly has no such ceiling.
2. **Host RAM.** One measured function was 132,288 bytes and consumed more than 9 GiB before being
   killed on a 12 GiB host. That one has to run where the memory is.

Both tools ship native Windows builds, so no compiler, no MSYS2 and no WSL are needed.

## Install

```powershell
.\install-r2.ps1              # install, or no-op if already current
.\install-r2.ps1 -Check       # report installed vs latest; changes nothing
.\install-r2.ps1 -Force       # reinstall, keeping the previous tree as _backup-<tag>
```

* Installs to `C:\data\re\radare2` by default (`-InstallDir` to change).
* **Verifies what it downloads.** radare2 is checked against the release's own `checksums.txt`.
  r2ghidra publishes no checksums, so its digest is *pinned in the script* and verified on every
  install — a mismatch fails loudly rather than installing something unexpected.
* **Idempotent.** An up-to-date install is a no-op; the previous install is kept as
  `_backup-<tag>`. Originals are never deleted.
* **Smoke-tests before claiming success.** It decompiles a small system PE and requires C back.
* Writes `.tag` (version) and `.install.json` (versions, digests, plugin path, smoke result).

## Decompile one function

```powershell
.\decompile-function.ps1 -Binary C:\data\re\target\app.exe -Address 0x00424280
.\decompile-function.ps1 -Binary .\app.exe -Address entry0 -TimeoutMs 3000000 -OutFile .\entry.c
```

Exit codes: `0` = C produced, `3` = r2 ran but produced no C, `1` = r2 failed.

* Output is streamed to the file line by line, so a dropped session cannot erase what was written.
* Every run writes `<OutFile>.status.json` (`running`, then `ok` / `no_c` / `r2_failed`). A SYSTEM
  scheduled task discards the child's stdout, so that file is the evidence a long run produces —
  poll it, do not assume.
* `-Split` drops the function r2 found and re-analyses a fresh one at the address; use it when r2
  lumped a large region into one pseudo-function.

## Long runs

A multi-hour run must not be driven from a PSRP session — the session dies mid-load
(`WSManFault 1359`). Launch it as a SYSTEM scheduled task instead:

```powershell
& <repo>\llm\tests\run-as-system-task.ps1 `
    -Script C:\ProgramData\re\decompile-function.ps1 `
    -ScriptArgs "-Binary C:\data\re\target\app.exe -Address 0x00424280 -OutFile C:\data\re\out\app.c -TimeoutMs 3000000" `
    -TaskName re-decompile-app -TimeoutMinutes 240
```

## Facts this toolchain is built on (all verified, not assumed)

* `r2 -H` reports **two** plugin dirs: `R2_USER_PLUGINS` (under `C:\Users\<name>`) and
  **`R2_LIBR_PLUGINS`** (inside the install root, machine-wide). A SYSTEM task has its own profile
  and cannot see the user-scoped one, so the plugin is installed into `R2_LIBR_PLUGINS` — and only
  there: a second copy makes r2 log *"Not loading library because it has already been loaded"*.
* **`R2_USER_PLUGINS` as an environment variable is not honoured by r2 6.2.4.** The installer
  checks this rather than trusting it.
* The radare2 zip ships one top-level `radare2-<version>-w64\` folder; the installer flattens it so
  the binary is always at `<InstallDir>\bin\radare2.exe`.
* PowerShell 5.1 turns a **native command's stderr into an error record**, and r2 writes HINTs
  there on a normal run. Under `$ErrorActionPreference='Stop'` that aborts the pipeline and kills
  r2 mid-run, which looks exactly like a decompiler failure. The runner uses the Process API with
  `ReadToEndAsync()` on stderr instead of `&` + `2>`.
* Never judge a decompilation by its byte count — check the status. An error envelope can
  byte-count like C.
