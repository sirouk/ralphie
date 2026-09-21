# Git and engine source comprehension

Frozen source: `c21744b635e3b640aa6d65b6c36daa7dc0d8e1e90b7bf45fb09f8937055aa905`. Assigned lines **1697-3161**: **1,465 lines read**, **58 functions** (34 Git, 24 engine), **26 top-level declarations**, and **one embedded Python block**. Source has 5478 total lines.

This is a source map, not a production verdict. No engines, provider calls, tests, Git mutations, commits or pushes were run for this review. Only this report and its JSON companion were written. All function contracts are EXTRACTED from source unless a note says INFERRED. The parent review owns AST/call indexing and combined graph generation.

EXTRACTED means directly visible code, command, format or branch. INFERRED means an architectural consequence of cited code; external runtime behavior remains unverified here.

## Architectural constraints

- **EXTRACTED** One Bash3.2 process orchestrates all layers. Mutable globals and shell dynamic scope are integration contracts; child/subshell assignments do not persist unless stdout/files are used. [ralphie.sh:2003-2011](../ralphie.sh#L2003-L2011), [ralphie.sh:2075](../ralphie.sh#L2075-L2075), [ralphie.sh:2662-2668](../ralphie.sh#L2662-L2668), [ralphie.sh:2888-2895](../ralphie.sh#L2888-L2895)
- **EXTRACTED** Git paths must be repository-relative NUL records and all filesystem-derived pathspec writes literal; a project can be a subdirectory of a larger repository. [ralphie.sh:1733-1744](../ralphie.sh#L1733-L1744), [ralphie.sh:1783-1796](../ralphie.sh#L1783-L1796), [ralphie.sh:2177-2196](../ralphie.sh#L2177-L2196), [ralphie.sh:2391-2394](../ralphie.sh#L2391-L2394)
- **EXTRACTED** Automatic saving uses private staging but real-index reconciliation; pre-existing staged paths and protected work remain separate, with HEAD movement as final save postcondition. [ralphie.sh:2027-2034](../ralphie.sh#L2027-L2034), [ralphie.sh:2267-2296](../ralphie.sh#L2267-L2296), [ralphie.sh:2484-2502](../ralphie.sh#L2484-L2502), [ralphie.sh:4148-4155](../ralphie.sh#L4148-L4155)
- **EXTRACTED** The engine table is the extension point. Native capability reduces Ralphie duplication, while outer verification and operator provider choice stay under Ralphie control. [ralphie.sh:2505-2537](../ralphie.sh#L2505-L2537), [ralphie.sh:2611-2629](../ralphie.sh#L2611-L2629), [ralphie.sh:3882-3885](../ralphie.sh#L3882-L3885), [ralphie.sh:3131-3136](../ralphie.sh#L3131-L3136)
- **INFERRED** Durable local recovery is best effort under shared OS permissions; no source-level claim can guarantee hostile engine isolation, arbitrary project correctness or future CLI compatibility. [ralphie.sh:1798-1882](../ralphie.sh#L1798-L1882), [ralphie.sh:2211-2265](../ralphie.sh#L2211-L2265), [ralphie.sh:2891-2927](../ralphie.sh#L2891-L2927), [ralphie.sh:3031-3119](../ralphie.sh#L3031-L3119)

## Top-level registry and initialization

- **OWNED_FILE** [ralphie.sh:1732](../ralphie.sh#L1732-L1732): `OWNED_FILE=""`
- **SELF_HASH** [ralphie.sh:1930](../ralphie.sh#L1930-L1930): `SELF_HASH=""`
- **RESTORE_BRANCH** [ralphie.sh:2003](../ralphie.sh#L2003-L2003): `RESTORE_BRANCH=""`
- **PRE_DIRTY_FILE** [ralphie.sh:2004](../ralphie.sh#L2004-L2004): `PRE_DIRTY_FILE=""`
- **PRE_DIRTY_SEAL** [ralphie.sh:2005](../ralphie.sh#L2005-L2005): `PRE_DIRTY_SEAL=""`
- **GATES_FILE_BROKEN** [ralphie.sh:2006](../ralphie.sh#L2006-L2006): `GATES_FILE_BROKEN=0`
- **UNUSABLE_REPORTED** [ralphie.sh:2007](../ralphie.sh#L2007-L2007): `UNUSABLE_REPORTED=""`
- **GIT_MODE** [ralphie.sh:2008](../ralphie.sh#L2008-L2008): `GIT_MODE=repo`
- **GATE_NO_PIPEFAIL** [ralphie.sh:2009](../ralphie.sh#L2009-L2009): `GATE_NO_PIPEFAIL=0`
- **OPERATOR_STAGED** [ralphie.sh:2010](../ralphie.sh#L2010-L2010): `OPERATOR_STAGED=""`
- **PRE_DIRTY_N** [ralphie.sh:2011](../ralphie.sh#L2011-L2011): `PRE_DIRTY_N=0`
- **RISKY_PATHS** [ralphie.sh:2069](../ralphie.sh#L2069-L2069): `RISKY_PATHS='(^|/)[^/]*\.env($|\.)|(^|/)\.envrc$|[._-]env$|(^|/)id_(rsa|dsa|ecdsa|ed25519)$|\.(pem|p12|pfx|key|keystore|jks|ppk)$|(^|/)\.netrc$|(^|/)\.npmrc$|(^|/)\.pypirc$|(^|/)\.git-credentials$|(^|/)credentials(\.[a-z]+)?$|(^|/)\.aws/|(^|/)\.ssh/|(^|/)\.gnupg/|(^|/)secrets?([._-][^/]*)?\.(ya?ml|json|toml|ini|env)$|(^|/)service[-_]account[^/]*\.json$|\.tfstate(\.backup)?$|(^|/)\.terraform/|(^|/)kubeconfig$|(^|/)\.kube/config$|(^|/)\.dockercfg$|(^|/)\.docker/config\.json$|\.(jks|p8|pkcs12)$'`
- **BULK_PATHS** [ralphie.sh:2070](../ralphie.sh#L2070-L2070): `BULK_PATHS='(^|/)(node_modules|vendor|\.venv|venv|__pycache__|\.mypy_cache|\.pytest_cache|dist|build|target|\.next|coverage|\.terraform)/'`
- **GIT_TOP** [ralphie.sh:2152](../ralphie.sh#L2152-L2152): `GIT_TOP=""`
- **PROJECT_PREFIX** [ralphie.sh:2153](../ralphie.sh#L2153-L2153): `PROJECT_PREFIX=""`
- **CY_HEAD** [ralphie.sh:2205](../ralphie.sh#L2205-L2205): `CY_HEAD=""`
- **CY_REF** [ralphie.sh:2206](../ralphie.sh#L2206-L2206): `CY_REF=""`
- **CY_OLD_COMMITS** [ralphie.sh:2207](../ralphie.sh#L2207-L2207): `CY_OLD_COMMITS=""`
- **CY_HISTORY_CAPTURED** [ralphie.sh:2208](../ralphie.sh#L2208-L2208): `CY_HISTORY_CAPTURED=0`
- **CY_ENGINE_SAVED** [ralphie.sh:2209](../ralphie.sh#L2209-L2209): `CY_ENGINE_SAVED=0`
- **ENGINE_TABLE** [ralphie.sh:2533-2537](../ralphie.sh#L2533-L2537): `ENGINE_TABLE=' / prime-agent  | prime-agent | stdout | autonomy gates memory subagents resume skills json usage / claude       | claude      | stdout | subagents resume skills json / codex        | codex       | file   | resume json stream / '`
- **ENGINE_LIVE_CACHE** [ralphie.sh:2578](../ralphie.sh#L2578-L2578): `ENGINE_LIVE_CACHE=""`
- **ENGINE_ARGV** [ralphie.sh:2662](../ralphie.sh#L2662-L2662): `ENGINE_ARGV=()`
- **ENGINE_ENV** [ralphie.sh:2663](../ralphie.sh#L2663-L2663): `ENGINE_ENV=()`
- **FAIL_TRANSIENT** [ralphie.sh:2758](../ralphie.sh#L2758-L2758): `FAIL_TRANSIENT='rate.?limit|overloaded|too many requests|429|502|503|504|backend error|connection (refused|reset)|ECONNRESET|ETIMEDOUT|EAI_AGAIN|socket hang up|timed? ?out|temporarily unavailable|internal server error'`
- **FAIL_PERMANENT** [ralphie.sh:2759](../ralphie.sh#L2759-L2759): `FAIL_PERMANENT='invalid.{0,10}api.?key|authentication.{0,10}failed|unauthorized|401|403|permission denied|insufficient.{0,10}(quota|credit|balance)|model.{0,10}not.{0,10}found|no such model|account.{0,10}(suspended|disabled)'`

The native registry declares Prime Agent first with autonomy, gates, memory, subagents, resume, skills, json and usage. Claude declares subagents, resume, skills and json. Codex declares resume, json and stream. Declared capabilities are control inputs, not a runtime benchmark. Prime and Claude are not declared streaming.

## Complete function inventory

### git_ready — lines 1697-1702

Ask Git whether PROJECT belongs to a repository, including worktrees and submodules. [ralphie.sh:1697-1702](../ralphie.sh#L1697-L1702)

**Inputs**

- PROJECT
- Git executable and inherited Git environment/configuration

**Outputs**

- Exit status from git rev-parse --git-dir; output suppressed

**Side effects**

- Invokes Git metadata discovery

**Calls/callbacks:** No named Ralphie helper; shell/Git/standard utility commands are described above and in interfaces..

**Invariants**

- Does not assume .git is a directory

**Failure/recovery**

- Nonzero means the caller must choose initialization, refusal, or no-Git mode

**I/O interface IDs:** git-discovery.

### ensure_git — lines 1704-1710

Keep an existing repository or initialize one when allowed. [ralphie.sh:1704-1710](../ralphie.sh#L1704-L1710)

**Inputs**

- PROJECT
- RALPHIE_GIT_INIT default 1

**Outputs**

- 0 for ready/initialized repository; 1 when disabled or initialization fails

**Side effects**

- May create Git metadata; prints initialization notice; appends git/init event

**Calls/callbacks:** git_ready, is_true, info, event.

**Invariants**

- No initial product commit is made here

**Failure/recovery**

- Returns 1 without a fallback repository when init fails; caller records fixed run GIT_MODE

**I/O interface IDs:** git-init-config, ledger-human.

### git_identity — lines 1712-1718

Supply repository-local author defaults only when Git cannot resolve existing identity. [ralphie.sh:1712-1718](../ralphie.sh#L1712-L1718)

**Inputs**

- PROJECT
- Inherited Git user.email and user.name

**Outputs**

- Shell status of final user.name lookup/write; 0 if no repository

**Side effects**

- May set local user.email=ralphie@localhost and user.name=Ralphie

**Calls/callbacks:** git_ready.

**Invariants**

- Existing resolved identity wins; no global config writes

**Failure/recovery**

- Config write failures propagate through shell status; no explicit diagnostic or rollback here

**I/O interface IDs:** git-init-config.

### git_dirty — lines 1720-1720

Return whether Git porcelain status is nonempty without parsing its paths. [ralphie.sh:1720](../ralphie.sh#L1720-L1720)

**Inputs**

- PROJECT

**Outputs**

- Boolean exit status; Git diagnostics suppressed

**Side effects**

- Runs git status

**Calls/callbacks:** git_ready.

**Invariants**

- Porcelain output is used only as an emptiness test

**Failure/recovery**

- No repository or empty/failed status output is false

**I/O interface IDs:** git-discovery.

### git_branch — lines 1722-1730

Describe a symbolic branch, detached commit, or missing Git head. [ralphie.sh:1722-1730](../ralphie.sh#L1722-L1730)

**Inputs**

- PROJECT

**Outputs**

- stdout: short symbolic branch; otherwise short HEAD; otherwise none

**Side effects**

- Reads refs through Git

**Calls/callbacks:** No named Ralphie helper; shell/Git/standard utility commands are described above and in interfaces..

**Invariants**

- Symbolic-ref is attempted first, so unborn branches are representable

**Failure/recovery**

- Falls through to a literal none if both commands fail

**I/O interface IDs:** git-refs.

### nul_list_has — lines 1733-1744

Test exact membership in a NUL-delimited pathname file. [ralphie.sh:1733-1744](../ralphie.sh#L1733-L1744)

**Inputs**

- $1 file
- $2 exact path

**Outputs**

- 0 if any complete NUL record matches; 1 otherwise

**Side effects**

- Reads file bytes using read -r -d NUL

**Calls/callbacks:** No named Ralphie helper; shell/Git/standard utility commands are described above and in interfaces..

**Invariants**

- Spaces, tabs, newlines and glob characters remain literal data

**Failure/recovery**

- Missing/nonregular list or absent match returns 1

**I/O interface IDs:** ownership-files.

### path_fingerprint — lines 1745-1758

Fingerprint current readable regular-file bytes at a repository-relative path. [ralphie.sh:1745-1758](../ralphie.sh#L1745-L1758)

**Inputs**

- $1 repository-relative path
- PROJECT/GIT_TOP

**Outputs**

- stdout: sha_of output, or sentinel - for unavailable bytes

**Side effects**

- Reads file content, including a regular-file symlink referent

**Calls/callbacks:** git_top, sha_of.

**Invariants**

- Path resolution is anchored at Git root

**Failure/recovery**

- Absent, nonregular, unreadable, or failed hashing returns -

**I/O interface IDs:** ownership-files, git-discovery.

**Notes**

- INFERRED: This is a content fingerprint, not file-mode or symlink-target custody. sha_of may use cksum on minimal systems (168-177).

### owned_has — lines 1760-1780

Accept an ownership claim only when a matching path record has the current content fingerprint. [ralphie.sh:1760-1780](../ralphie.sh#L1760-L1780)

**Inputs**

- $1 exact repository-relative path
- OWNED_FILE

**Outputs**

- Boolean exit status

**Side effects**

- Reads ownership file and current file bytes

**Calls/callbacks:** path_fingerprint.

**Invariants**

- Checks every matching record; a stale duplicate cannot shadow a later valid claim

**Failure/recovery**

- Missing record file or no exact path/hash pair returns 1

**I/O interface IDs:** ownership-files.

### pre_dirty_has — lines 1781-1781

Test whether a path belongs to the protected initial-change set. [ralphie.sh:1781](../ralphie.sh#L1781-L1781)

**Inputs**

- $1 path
- PRE_DIRTY_FILE

**Outputs**

- Boolean exit status

**Side effects**

- Reads protected path list

**Calls/callbacks:** nul_list_has.

**Invariants**

- Membership uses NUL records, not line splitting

**Failure/recovery**

- Missing protection list returns false; callers requiring trust must separately call pre_dirty_intact

**I/O interface IDs:** ownership-files.

### dirty_paths_nul — lines 1783-1796

Emit changed tracked and untracked repository-relative paths, preserving rename endpoints. [ralphie.sh:1783-1796](../ralphie.sh#L1783-L1796)

**Inputs**

- Git root and HEAD/index state

**Outputs**

- stdout: NUL-separated paths; duplicates are possible; normally returns 0 even after Git errors

**Side effects**

- Reads working tree, index and ignore rules

**Calls/callbacks:** git_top.

**Invariants**

- --no-renames prevents source/destination collapse
- Unborn repositories include cached paths through ls-files --cached

**Failure/recovery**

- Each Git listing error is suppressed and converted to success

**I/O interface IDs:** git-discovery, ownership-files.

### release_owned_paths — lines 1798-1845

Retire claims outside the project, in runtime state, no longer dirty, or holding changed bytes. [ralphie.sh:1798-1845](../ralphie.sh#L1798-L1845)

**Inputs**

- Optional $1=after-cycle
- HOME_DIR/owned.nul
- RUN_DIR
- PRE_DIRTY_FILE and in-memory seal
- Project prefix

**Outputs**

- Updates OWNED_FILE global; returns 0 on normal/best-effort paths

**Side effects**

- Writes dirty-now.nul and owned.nul.tmp.PID; replaces owned.nul; removes scratch files
- May append changed formerly-owned paths to the protected list and reseal it

**Calls/callbacks:** git_ready, project_prefix, dirty_paths_nul, nul_list_has, path_fingerprint, pre_dirty_intact, pre_dirty_has, pre_dirty_seal.

**Invariants**

- Only same-content, still-dirty, in-project, non-runtime claims survive
- Never reseals an already-invalid protected list
- after-cycle suppresses transferring changed ownership into operator protection

**Failure/recovery**

- No Git or no claims is a no-op; failed listing leaves claims unchanged; failed rename removes temporary file

**I/O interface IDs:** ownership-files, git-discovery.

### record_owned_paths — lines 1847-1882

Remember uncommitted work for future runs without claiming protected or out-of-project paths. [ralphie.sh:1847-1882](../ralphie.sh#L1847-L1882)

**Inputs**

- HOME_DIR
- RUN_DIR
- PRE_DIRTY_FILE/PRE_DIRTY_SEAL
- Current Git-visible dirty paths

**Outputs**

- Sets OWNED_FILE; normal completion has success status

**Side effects**

- Writes dirty.nul; appends fingerprint TAB path NUL records to owned.nul; removes scratch file

**Calls/callbacks:** git_ready, pre_dirty_intact, dbg, project_prefix, dirty_paths_nul, pre_dirty_has, owned_has, path_fingerprint.

**Invariants**

- Invalid protection seal means claim nothing
- Excludes project runtime state, sibling paths, pre-existing paths, and already-valid claims

**Failure/recovery**

- No repository, invalid seal, or failed capture returns without new claims; filesystem append errors are not individually recovered here

**I/O interface IDs:** ownership-files.

### pre_dirty_count — lines 1884-1889

Produce a display/checksum-component count for the protected list. [ralphie.sh:1884-1889](../ralphie.sh#L1884-L1889)

**Inputs**

- PRE_DIRTY_FILE

**Outputs**

- stdout: nonnegative integer, default 0

**Side effects**

- Reads list and translates NULs to newlines

**Calls/callbacks:** is_int.

**Invariants**

- Sanitizes noninteger count output

**Failure/recovery**

- Missing/nonregular file or failed count yields 0

**I/O interface IDs:** ownership-files.

**Notes**

- INFERRED: A path containing embedded newlines can count as multiple lines. Exact membership still uses NUL records, and the seal also includes a full-byte checksum.

### use_branch — lines 1891-1915

Optionally select or create the requested work branch and remember its base. [ralphie.sh:1891-1915](../ralphie.sh#L1891-L1915)

**Inputs**

- $1 desired branch
- PROJECT
- Persisted base_branch

**Outputs**

- Sets RESTORE_BRANCH; 1 when checkout/create fails

**Side effects**

- Reads/updates state base_branch; git checkout changes refs/index/worktree; records git/branch event

**Calls/callbacks:** git_ready, warn, state_get, git_branch, state_set, dbg, err, info, event.

**Invariants**

- Empty requested branch is a no-op
- Retains a recorded base when already working on the same requested branch

**Failure/recovery**

- Missing repository warns and returns 0; checkout failure reports and returns 1 without reset

**I/O interface IDs:** git-refs, git-execution-policy, ledger-human.

### warn_detached_head — lines 1917-1928

Refuse a run on detached HEAD through status and nonblocking notification. [ralphie.sh:1917-1928](../ralphie.sh#L1917-L1928)

**Inputs**

- PROJECT

**Outputs**

- 0 for no repository or symbolic HEAD; 1 when detached

**Side effects**

- Emits errors, git/detached event and human question

**Calls/callbacks:** git_ready, err, event, ask_human.

**Invariants**

- Requires a branch for autonomous run commits

**Failure/recovery**

- Leaves history unchanged and asks for --branch or an operator checkout

**I/O interface IDs:** git-refs, ledger-human.

**Notes**

- INFERRED: The diagnostic describes detached commits as unreachable after checkout; reflog/object retention is not analyzed by this function.

### self_hash_record — lines 1931-1931

Save the current script byte fingerprint in process memory. [ralphie.sh:1931](../ralphie.sh#L1931-L1931)

**Inputs**

- SELF

**Outputs**

- SELF_HASH

**Side effects**

- Reads script file

**Calls/callbacks:** sha_of.

**Invariants**

- No product mutation

**Failure/recovery**

- Hash failure stores empty string, disabling later self comparison

**I/O interface IDs:** self-file.

### self_is_reviewed — lines 1933-1948

Warn when the tracked in-project script differs from its index copy at startup. [ralphie.sh:1933-1948](../ralphie.sh#L1933-L1948)

**Inputs**

- SELF
- PROJECT
- Git index

**Outputs**

- 0 if inapplicable/unchanged; 1 after warning

**Side effects**

- Reads tracking/diff; emits warning and self/uncommitted event

**Calls/callbacks:** git_ready, warn, dim, event.

**Invariants**

- Literal pathspec protects unusual script names
- Only applies when SELF is lexically within PROJECT and tracked

**Failure/recovery**

- No repository/untracked script is skipped; nonzero diff triggers warning; run_prepare deliberately ignores the return

**I/O interface IDs:** self-file, git-index, ledger-human.

**Notes**

- EXTRACTED: git diff --quiet has no HEAD argument (1943), so this compares worktree to index, despite the diagnostic saying committed copy.

### self_hash_check — lines 1950-1966

Detect changed or unreadable script bytes after a cycle and notify the operator. [ralphie.sh:1950-1966](../ralphie.sh#L1950-L1966)

**Inputs**

- SELF
- SELF_HASH

**Outputs**

- 0 if no baseline or unchanged; 1 on mismatch; stores new SELF_HASH

**Side effects**

- Reads script; emits self/modified event and question

**Calls/callbacks:** sha_of, err, dim, event, ask_human.

**Invariants**

- A changed script is reported; it is not automatically reverted

**Failure/recovery**

- Missing/unreadable script becomes an empty new hash and reports mismatch once

**I/O interface IDs:** self-file, ledger-human.

### record_recovery_point — lines 1968-1981

Persist a valid starting commit for later recovery instructions. [ralphie.sh:1968-1981](../ralphie.sh#L1968-L1981)

**Inputs**

- PROJECT
- HEAD

**Outputs**

- Updates state start_commit when hexadecimal HEAD is available

**Side effects**

- Reads HEAD; emits git/recovery event

**Calls/callbacks:** git_ready, dbg, state_set, event.

**Invariants**

- Uses --verify --quiet to avoid the literal HEAD artifact of an unborn repository
- Does not execute a reset or create a backup ref

**Failure/recovery**

- Missing or nonhex head is a no-op

**I/O interface IDs:** git-refs, ledger-human.

### pre_dirty_seal — lines 1983-1992

Seal the exact protection-file bytes plus the display count in memory. [ralphie.sh:1983-1992](../ralphie.sh#L1983-L1992)

**Inputs**

- PRE_DIRTY_FILE

**Outputs**

- PRE_DIRTY_SEAL=count:checksum

**Side effects**

- Reads protected list

**Calls/callbacks:** pre_dirty_count, sha_of.

**Invariants**

- Later custody checks compare against this process-memory value

**Failure/recovery**

- Hash failure uses the literal none suffix; this is not a security signature

**I/O interface IDs:** ownership-files.

### pre_dirty_intact — lines 1994-2001

Require the protection file and its current count/checksum to match the stored seal. [ralphie.sh:1994-2001](../ralphie.sh#L1994-L2001)

**Inputs**

- PRE_DIRTY_FILE
- PRE_DIRTY_SEAL

**Outputs**

- Boolean exit status

**Side effects**

- Reads protected list

**Calls/callbacks:** pre_dirty_count, sha_of.

**Invariants**

- No seal or no regular protection file fails closed

**Failure/recovery**

- Any unmatched count/hash returns 1; no repair or reseal occurs here

**I/O interface IDs:** ownership-files.

### snapshot_pre_dirty — lines 2012-2063

Capture original staged paths and all initial non-owned dirty paths before engine work. [ralphie.sh:2012-2063](../ralphie.sh#L2012-L2063)

**Inputs**

- PROJECT, RUN_DIR, HOME_DIR
- Current Git index/working tree
- Existing valid owned.nul claims
- CMD default run

**Outputs**

- PRE_DIRTY_FILE, OWNED_FILE, OPERATOR_STAGED, PRE_DIRTY_N, PRE_DIRTY_SEAL

**Side effects**

- Creates process-specific pre-dirty.PID.nul, operator-staged.nul and temporary raw list
- May warn/event about protected paths and unborn baseline

**Calls/callbacks:** git_ready, git_top, project_prefix, dirty_paths_nul, owned_has, pre_dirty_count, pre_dirty_seal, warn, event.

**Invariants**

- Protects all pre-existing changed paths except own runtime state and same-content owned work
- Captures operator staged names separately; no explicit HEAD is required on an unborn index

**Failure/recovery**

- No repository skips snapshot; failed Git listings become empty lists; caller creates RUN_DIR before this function; no initial baseline commit is manufactured

**I/O interface IDs:** ownership-files, git-index, git-discovery, ledger-human.

### unstage_risky — lines 2072-2146

Remove runtime, named secret, bulk, escaping-link and oversized paths from a private commit index. [ralphie.sh:2072-2146](../ralphie.sh#L2072-L2146)

**Inputs**

- $1 private index path
- RISKY_PATHS and BULK_PATHS regexes
- RALPHIE_MAX_COMMIT_BYTES default 1048576
- Working-tree file sizes/link targets

**Outputs**

- UNSTAGED_RISKY, UNSTAGED_BULK; explicit return 0

**Side effects**

- Creates/removes staged.PID.nul; performs literal per-path resets under GIT_INDEX_FILE
- Emits exclusion events and nonblocking question for risky/large paths

**Calls/callbacks:** git_top, project_prefix, file_bytes, dim, event, warn, trim, ask_human.

**Invariants**

- Filesystem-derived pathspecs are literal
- Only the passed private index is intentionally changed
- Product working-tree files remain on disk

**Failure/recovery**

- Failed staged listing becomes empty; reset errors are suppressed; returns success even when reset fails

**I/O interface IDs:** git-private-index, git-path-filter, ledger-human.

**Notes**

- EXTRACTED: Link filter here rejects /* and *../* (2120); committed-history filter additionally rejects exact .. and trailing /.. (2258).
- INFERRED: Path regex/size checks are not a content secret scan; working-tree content may differ from Git-clean-filter output.

### git_top — lines 2155-2175

Cache and return the repository root used for repository-relative path operations. [ralphie.sh:2155-2175](../ralphie.sh#L2155-L2175)

**Inputs**

- PROJECT
- GIT_TOP cache

**Outputs**

- stdout root; may set GIT_TOP

**Side effects**

- Calls git rev-parse --show-toplevel

**Calls/callbacks:** No named Ralphie helper; shell/Git/standard utility commands are described above and in interfaces..

**Invariants**

- Index/path inspection is anchored at repository root

**Failure/recovery**

- On failed discovery uses PROJECT; cache writes inside command substitutions do not persist into the parent shell

**I/O interface IDs:** git-discovery.

### project_prefix — lines 2177-2196

Resolve physical project/root paths and cache the project-relative staging prefix. [ralphie.sh:2177-2196](../ralphie.sh#L2177-L2196)

**Inputs**

- PROJECT
- GIT_TOP
- PROJECT_PREFIX cache

**Outputs**

- stdout prefix; may set PROJECT_PREFIX

**Side effects**

- Reads physical directories through cd and pwd -P

**Calls/callbacks:** git_top.

**Invariants**

- Normalizes macOS /tmp versus /private/tmp aliases
- Root project uses dot; contained subproject uses its relative path

**Failure/recovery**

- Failure or non-containment uses dot rather than reporting a separate error

**I/O interface IDs:** git-discovery, git-path-filter.

### commit_head — lines 2198-2202

Read a full valid HEAD object name or the explicit unborn/missing sentinel. [ralphie.sh:2198-2202](../ralphie.sh#L2198-L2202)

**Inputs**

- PROJECT

**Outputs**

- stdout commit hash or none

**Side effects**

- Reads Git refs

**Calls/callbacks:** No named Ralphie helper; shell/Git/standard utility commands are described above and in interfaces..

**Invariants**

- --verify --quiet avoids false literal HEAD output

**Failure/recovery**

- Failed lookup yields none

**I/O interface IDs:** git-refs.

### engine_history_is_safe — lines 2211-2265

Inspect every new engine-created commit against captured branch/history and project ownership constraints. [ralphie.sh:2211-2265](../ralphie.sh#L2211-L2265)

**Inputs**

- $1 proposed current head
- CY_HEAD, CY_REF, CY_OLD_COMMITS, CY_HISTORY_CAPTURED
- Protected path seal/list
- Project prefix; risk/bulk regexes; RALPHIE_MAX_COMMIT_BYTES

**Outputs**

- 0 if every inspected commit passes; 1 otherwise

**Side effects**

- Reads Git refs, ancestry, commit parents, tree names, blob types/sizes/targets
- Writes RUN_DIR/engine-commit-paths.PID.nul

**Calls/callbacks:** pre_dirty_intact, project_prefix, ensure_own_file, git_top, pre_dirty_has.

**Invariants**

- Requires same symbolic ref, captured history, valid protected-list seal and a new linear parent chain
- Rejects old commits, rewrite/non-ancestor history, empty net work, empty individual commits, out-of-project/runtime/protected/risky/bulk paths
- Added/modified committed objects must be small blobs; external/upward link targets are rejected

**Failure/recovery**

- Any failed prerequisite/read rejects; leaves invalid engine history untouched for review; does not reset or repair it

**I/O interface IDs:** git-history-validation, ownership-files, git-path-filter.

**Notes**

- EXTRACTED: The scratch list is retained, not deleted, by this function.
- INFERRED: Validation occurs after engine execution; it cannot prevent an engine from creating a rejected commit or making external side effects.

### git_commit_cycle — lines 2267-2296

Sequence commit authorization, private staging, commit execution, index resync and evidence. [ralphie.sh:2267-2296](../ralphie.sh#L2267-L2296)

**Inputs**

- $1 commit message
- RUN_DIR/index.PID
- Current Git/project/ownership state

**Outputs**

- 0 on many refusal paths as well as success; 1 if write_commit fails; uses COMMIT_* state for meaning

**Side effects**

- May create Git objects/ref updates and update selected real-index paths; emits commit evidence

**Calls/callbacks:** commit_is_permitted, git_identity, build_commit_index, index_holds_our_work_only, write_commit, resync_operator_index, good, event, warn_protected_unsaved.

**Invariants**

- The commit itself uses an alternate index
- record_outcome, outside this range, checks HEAD actually moved before declaring saved work

**Failure/recovery**

- Early refusals intentionally return 0; caller must inspect flags and HEAD postcondition

**I/O interface IDs:** git-private-index, git-commit, git-index, ledger-human.

### warn_protected_unsaved — lines 2298-2313

Tell the operator when protected paths remain dirty after a partial commit. [ralphie.sh:2298-2313](../ralphie.sh#L2298-L2313)

**Inputs**

- PRE_DIRTY_FILE
- Git status of each literal protected path

**Outputs**

- Always returns 0; at most one warning pair

**Side effects**

- Reads protected file and path-specific Git status

**Calls/callbacks:** git_top, warn.

**Invariants**

- Does not claim a partial save saved the whole working tree

**Failure/recovery**

- Missing/empty list or no remaining visible dirty path is silent; status failures are suppressed

**I/O interface IDs:** ownership-files, git-discovery, ledger-human.

### commit_is_permitted — lines 2315-2363

Refuse automatic commit when a repository disappeared, work is absent, or an operator Git operation is active. [ralphie.sh:2315-2363](../ralphie.sh#L2315-L2363)

**Inputs**

- PROJECT
- GIT_MODE fixed at run start
- MERGE_HEAD, CHERRY_PICK_HEAD, REVERT_HEAD, rebase-merge/rebase-apply

**Outputs**

- 0 permits staging; 1 refuses; sets COMMIT_FAILED/COMMIT_BLOCKED_WHY or COMMIT_SKIPPED

**Side effects**

- Reads Git status and operation metadata; appends refusal events/questions

**Calls/callbacks:** git_ready, git_dirty, err, event, ask_human, warn.

**Invariants**

- No-Git mode is distinguished from loss of an existing repository
- Does not conclude an operator merge/rebase/cherry-pick/revert

**Failure/recovery**

- Leaves work and operator operation in place; reports actionable reason

**I/O interface IDs:** git-discovery, git-operation-markers, ledger-human.

### build_commit_index — lines 2365-2427

Create a HEAD-seeded alternate index, stage only the project, and remove forbidden/protected paths. [ralphie.sh:2365-2427](../ralphie.sh#L2365-L2427)

**Inputs**

- $1 alternate index path
- HEAD and project prefix
- Protected list/seal
- Risk/bulk/size policy

**Outputs**

- 0 when construction path finishes; 1 on explicit read-tree, add, or custody failure; COMMIT_FAILED and reason on refusal

**Side effects**

- Removes old index, invokes private read-tree/add/reset, creates Git objects through add and filters; logs refusals

**Calls/callbacks:** git_top, project_prefix, unstage_risky, pre_dirty_intact, err, event, dim, ask_human.

**Invariants**

- Never seeds from the operator index
- Literal scoped add prevents pathspec magic or sibling-project staging
- Validates protected-list custody immediately before applying exclusions

**Failure/recovery**

- Deletes private index on read-tree/add/seal failure; preserves working tree; individual protected reset failures are suppressed

**I/O interface IDs:** git-private-index, git-execution-policy, ownership-files, ledger-human.

### index_holds_our_work_only — lines 2429-2454

Require a nonempty private-index change or explain why no independently committable work remains. [ralphie.sh:2429-2454](../ralphie.sh#L2429-L2454)

**Inputs**

- $1 index
- CY_ENGINE_SAVED

**Outputs**

- 0 for nonquiet cached diff; 1 for empty index; may set COMMIT_FAILED/reason

**Side effects**

- Reads/removes alternate index; emits overlap warning/event/question

**Calls/callbacks:** git_top, warn, event, ask_human.

**Invariants**

- An already-validated engine commit prevents empty remaining index from creating a new commit failure

**Failure/recovery**

- Empty unsaved index blocks promotion; a nonzero diff command status, including an error, currently takes the nonempty branch

**I/O interface IDs:** git-private-index, ledger-human.

### write_commit — lines 2456-2482

Run Git commit with the alternate index and a bounded child-process watchdog. [ralphie.sh:2456-2482](../ralphie.sh#L2456-L2482)

**Inputs**

- $1 alternate index
- $2 message
- RUN_DIR
- COMMIT_TIMEOUT default 120; invalid/nonpositive becomes 120
- Inherited Git hooks/signing/identity configuration

**Outputs**

- 0 on Git success; 1 on failure; sets COMMIT_FAILED

**Side effects**

- Launches background git commit with stdin /dev/null and merged capture; updates Git objects/ref/reflog
- Tracks child PID, may TERM/KILL tree; removes private index/error capture
- On failure relays bounded error excerpts to output, events and question

**Calls/callbacks:** is_int, git_top, track_pid, watchdog_wait, untrack_pid, err, dim, tail_of, event, ask_human.

**Invariants**

- Repository hooks/signing policy remains active
- Finite commit timeout is independent of engine-call timeout

**Failure/recovery**

- Timeout adds a diagnostic; any failure preserves worktree and reports not saved; no history rollback is attempted

**I/O interface IDs:** git-commit, git-execution-policy, process-supervision, ledger-human.

### resync_operator_index — lines 2484-2502

Refresh committed real-index paths against new HEAD while preserving initially staged paths. [ralphie.sh:2484-2502](../ralphie.sh#L2484-L2502)

**Inputs**

- OPERATOR_STAGED NUL list
- New HEAD
- RUN_DIR

**Outputs**

- Normally success; no status flag for a per-path reset failure

**Side effects**

- Writes/removes committed.PID.nul; literal git reset updates the real index for nonprotected committed paths

**Calls/callbacks:** git_top, nul_list_has.

**Invariants**

- Never intentionally resets a path recorded as initially staged
- --root and -m provide path enumeration for first/merge commits

**Failure/recovery**

- Failed enumeration becomes empty; individual reset errors are ignored; no worktree reset

**I/O interface IDs:** git-index, ownership-files.

**Notes**

- EXTRACTED: The real index is involved in this resynchronization, despite the broad private-index comment at 2273-2274.

### engine_names — lines 2539-2539

Enumerate table engine names and configured custom engine. [ralphie.sh:2539](../ralphie.sh#L2539-L2539)

**Inputs**

- ENGINE_TABLE
- RALPHIE_ENGINE_CMD

**Outputs**

- stdout one name per line

**Side effects**

- Only pipeline/string output

**Calls/callbacks:** No named Ralphie helper; shell/Git/standard utility commands are described above and in interfaces..

**Invariants**

- Custom appears only for a nonempty configured command

**Failure/recovery**

- Ends with success even when custom is absent

**I/O interface IDs:** engine-table.

### engine_field — lines 2541-2555

Resolve command, answer destination or capability field for an engine. [ralphie.sh:2541-2555](../ralphie.sh#L2541-L2555)

**Inputs**

- $1 name
- $2 field index 1/2/3
- ENGINE_TABLE
- RALPHIE_ENGINE_CMD/ANSWER/CAPS

**Outputs**

- stdout selected field; 1 for absent builtin row

**Side effects**

- Reads environment/table; runs grep/head/cut/trim pipeline

**Calls/callbacks:** trim.

**Invariants**

- Custom command is verbatim; custom answer defaults stdout; custom caps default empty

**Failure/recovery**

- Unknown builtin row returns 1; unknown custom field prints nothing and returns 0

**I/O interface IDs:** engine-table.

### engine_cmd — lines 2557-2557

Return engine command field. [ralphie.sh:2557](../ralphie.sh#L2557-L2557)

**Inputs**

- $1 engine

**Outputs**

- stdout command/status from engine_field

**Side effects**

- None.

**Calls/callbacks:** engine_field.

**Invariants**

- Field index is 1

**Failure/recovery**

- Delegates failure unchanged

**I/O interface IDs:** engine-table.

### engine_answer — lines 2558-2558

Return engine answer destination field. [ralphie.sh:2558](../ralphie.sh#L2558-L2558)

**Inputs**

- $1 engine

**Outputs**

- stdout stdout or file (custom value is unconstrained here)

**Side effects**

- None.

**Calls/callbacks:** engine_field.

**Invariants**

- Field index is 2

**Failure/recovery**

- Delegates failure unchanged

**I/O interface IDs:** engine-table.

### engine_caps — lines 2559-2559

Return space-delimited declared engine capabilities. [ralphie.sh:2559](../ralphie.sh#L2559-L2559)

**Inputs**

- $1 engine

**Outputs**

- stdout capability string/status

**Side effects**

- None.

**Calls/callbacks:** engine_field.

**Invariants**

- Field index is 3

**Failure/recovery**

- Delegates failure unchanged

**I/O interface IDs:** engine-table.

### engine_has — lines 2560-2560

Test a capability as an exact space-bounded word. [ralphie.sh:2560](../ralphie.sh#L2560-L2560)

**Inputs**

- $1 engine
- $2 capability

**Outputs**

- Boolean exit status

**Side effects**

- None.

**Calls/callbacks:** engine_caps.

**Invariants**

- Does not use substring-only capability matching

**Failure/recovery**

- Absent declaration returns 1

**I/O interface IDs:** engine-table.

### engine_score — lines 2561-2561

Count declared capability words for engine ranking. [ralphie.sh:2561](../ralphie.sh#L2561-L2561)

**Inputs**

- $1 engine

**Outputs**

- stdout integer word count

**Side effects**

- None.

**Calls/callbacks:** engine_caps.

**Invariants**

- Score is declaration count, not quality, cost or benchmark performance

**Failure/recovery**

- No separate external capability validation

**I/O interface IDs:** engine-table.

### engine_exe — lines 2563-2569

Resolve a literal executable path, including spaces, or the first space-delimited command token. [ralphie.sh:2563-2569](../ralphie.sh#L2563-L2569)

**Inputs**

- $1 command string

**Outputs**

- stdout executable string

**Side effects**

- Filesystem executable test

**Calls/callbacks:** No named Ralphie helper; shell/Git/standard utility commands are described above and in interfaces..

**Invariants**

- Whole executable pathname takes precedence over splitting

**Failure/recovery**

- No quote/escape parser; nonliteral strings fall back to text before the first space

**I/O interface IDs:** engine-discovery, custom-command.

### engine_present — lines 2571-2576

Check configured executable path or command availability without provider authentication. [ralphie.sh:2571-2576](../ralphie.sh#L2571-L2576)

**Inputs**

- $1 engine
- PATH/table/custom command

**Outputs**

- Boolean exit status

**Side effects**

- Filesystem executable check; command -v lookup

**Calls/callbacks:** engine_cmd, have, engine_exe.

**Invariants**

- Does not spend provider tokens or check login/model access

**Failure/recovery**

- Missing command/config returns 1

**I/O interface IDs:** engine-discovery.

### engine_live — lines 2579-2589

Memoize successful and failed engine version probes within its shell process. [ralphie.sh:2579-2589](../ralphie.sh#L2579-L2589)

**Inputs**

- $1 engine
- ENGINE_LIVE_CACHE

**Outputs**

- Boolean status; appends ok:name or dead:name cache entry

**Side effects**

- May execute version probe

**Calls/callbacks:** engine_live_probe.

**Invariants**

- Both success and failure are cached

**Failure/recovery**

- Cache contains only command responsiveness, not provider health; subshell-local updates do not escape

**I/O interface IDs:** engine-discovery.

### engine_live_probe — lines 2591-2599

Execute the selected engine binary with --version and suppress output. [ralphie.sh:2591-2599](../ralphie.sh#L2591-L2599)

**Inputs**

- $1 engine
- Available timeout/gtimeout
- PATH/custom command

**Outputs**

- Exit status from executable/version wrapper

**Side effects**

- Executes installed binary, optionally under timeout 15

**Calls/callbacks:** engine_cmd, timeout_cmd, engine_present, engine_exe.

**Invariants**

- No prompt or model call is deliberately requested
- Only executable is used, not additional custom command arguments

**Failure/recovery**

- Absent executable returns 1; without timeout/gtimeout the version command has no watchdog here

**I/O interface IDs:** engine-discovery, process-supervision.

### engine_check_model — lines 2601-2609

Leave model selector resolution to the engine and optionally log the Prime selector. [ralphie.sh:2601-2609](../ralphie.sh#L2601-L2609)

**Inputs**

- $1 engine
- $2 model selector
- VERBOSE

**Outputs**

- Always returns 0

**Side effects**

- Optional debug output

**Calls/callbacks:** dbg.

**Invariants**

- No mutation/substitution of the requested selector
- No model-catalog/provider request

**Failure/recovery**

- Invalid selector is deferred to engine invocation

**I/O interface IDs:** engine-argv.

### engine_pick — lines 2611-2647

Honor explicit engine/custom choice; otherwise prefer responsive Prime and rank alternatives. [ralphie.sh:2611-2647](../ralphie.sh#L2611-L2647)

**Inputs**

- Optional $1 explicit name
- RALPHIE_ENGINE_CMD
- Installed engines, declared capabilities and responsiveness

**Outputs**

- stdout selected engine; 1 if explicit missing or no installed candidate

**Side effects**

- May execute version probes; emits explicit-choice installation error

**Calls/callbacks:** engine_present, err, engine_live, engine_score, engine_names.

**Invariants**

- Explicit named engine wins without automatic substitution
- Configured custom command beats builtin ranking
- Responsive Prime is first default regardless of capability score

**Failure/recovery**

- If no engine responds but one is installed, chooses the highest-scoring installed candidate; provider auth is not verified

**I/O interface IDs:** engine-selection, engine-discovery.

### engine_fallbacks — lines 2649-2656

List other installed engines in descending declared-capability score. [ralphie.sh:2649-2656](../ralphie.sh#L2649-L2656)

**Inputs**

- $1 active engine
- Engine registry/environment

**Outputs**

- stdout ordered engine names

**Side effects**

- Command availability checks; sort pipeline

**Calls/callbacks:** engine_names, engine_present, engine_score.

**Invariants**

- Active engine excluded; no liveness probe here

**Failure/recovery**

- Unavailable engines omitted; equal scores follow sort behavior

**I/O interface IDs:** engine-selection.

### engine_build — lines 2665-2751

Rebuild invocation argv/env for Prime, Claude, Codex or custom command. [ralphie.sh:2665-2751](../ralphie.sh#L2665-L2751)

**Inputs**

- $1 engine
- $2 requested mode
- $3 output file
- PROJECT, RUN_DIR, preferred ENGINE, MODEL, THINKING, YOLO
- Native limits/session and deadline settings; gates_list

**Outputs**

- ENGINE_ARGV and ENGINE_ENV arrays; 0 success, 1 unknown engine

**Side effects**

- Reads state run_id and gates; emits optional debug diagnostics; no engine is launched here

**Calls/callbacks:** engine_cmd, is_true, dbg, state_get, budget_cap, is_int, gates_list, err.

**Invariants**

- Model selector is cleared for a borrowed provider
- Prime timeout/gate limits are positive, capped by host allowance; fully unbounded requested mode uses ordinary tool loop
- Explicit return 0 prevents false failure from absent optional flags

**Failure/recovery**

- Unknown name returns 1; external CLI decides unsupported models/thinking/flags; custom command word splitting does not implement shell quoting

**I/O interface IDs:** engine-argv, prime-native, custom-command, engine-environment, engine-session.

### classify_failure — lines 2761-2772

Map resource/deadline exits and bounded diagnostic text to retry classes. [ralphie.sh:2761-2772](../ralphie.sh#L2761-L2772)

**Inputs**

- $1 exit code
- $2 log
- FAIL_PERMANENT and FAIL_TRANSIENT regexes

**Outputs**

- stdout resource-limit, transient, permanent or unknown; success return

**Side effects**

- Reads final 20000 log bytes at most per regex pass

**Calls/callbacks:** No named Ralphie helper; shell/Git/standard utility commands are described above and in interfaces..

**Invariants**

- 125 resource limit and 124/137/143 transient precede text matching
- Permanent text wins before transient text

**Failure/recovery**

- Unknown is the default, not a successful attempt

**I/O interface IDs:** engine-failure.

### answer_is_usable — lines 2774-2788

Require substantive answer bytes and reject obvious HTML/login output. [ralphie.sh:2774-2788](../ralphie.sh#L2774-L2788)

**Inputs**

- $1 output file
- MIN_ANSWER_BYTES default 2

**Outputs**

- Boolean status

**Side effects**

- Reads file size, first nonspace byte and first 2000 bytes

**Calls/callbacks:** file_bytes.

**Invariants**

- Whitespace-only answers fail
- Usability is not proof of solved work or gate success

**Failure/recovery**

- Missing/small/blank/login-page content returns 1

**I/O interface IDs:** engine-output.

### engine_run — lines 2792-2851

Execute bounded retry policy for one engine, retaining actionable final reason and capture path. [ralphie.sh:2792-2851](../ralphie.sh#L2792-L2851)

**Inputs**

- $1 name
- $2 mode
- $3 prompt file
- $4 log file
- $5 answer file
- ENGINE_RETRIES default 3, ENGINE_BACKOFF default 5, run deadline

**Outputs**

- 0 answer; 1 attempts exhausted; 2 cannot start; 3 permanent; 4 out of time; 5 output resource limit
- ENGINE_REASON and ENGINE_RESOURCE_LIMIT

**Side effects**

- Invokes engine repeatedly; emits start/fail/limit events; trims captures; sleeps between attempts

**Calls/callbacks:** engine_present, ensure_dirs, budget_expired, event, engine_build, now_epoch, engine_invoke, secs_since, engine_answered, classify_failure, warn, retain_engine_output.

**Invariants**

- Checks budget before every attempt
- Resource limit is never retried and flags no fallback
- Permanent failure is not retried; unexplained nonzero failure remains failure

**Failure/recovery**

- Unknown/transient retry up to configured max; final/permanent reason includes attempt count and retained log path; resource reason has separate wording

**I/O interface IDs:** engine-retries, engine-failure, process-supervision, engine-output, ledger-human.

### engine_invoke — lines 2853-2928

Launch one engine attempt in PROJECT with prompt stdin and durable raw capture, then collect its answer. [ralphie.sh:2853-2928](../ralphie.sh#L2853-L2928)

**Inputs**

- $1 name
- $2 prompt
- $3 cycle log
- $4 answer path
- ENGINE_ARGV/ENV
- ENGINE_TIMEOUT default 2400, ENGINE_IDLE_TIMEOUT default 600, ENGINE_OUTPUT_MAX_BYTES default 16777216
- TMPDIR default /tmp; remaining run budget

**Outputs**

- Engine or watchdog exit code; writes cycle log and answer

**Side effects**

- Truncates log/answer, launches process group/direct exec, tracks PID, writes external raw temp
- May terminate process tree; recreates runtime dirs; copies raw output, removes raw temp

**Calls/callbacks:** is_int, ensure_dirs, warn, err, dbg, budget_cap, track_pid, engine_has, watchdog_wait, untrack_pid, retain_engine_output, ensure_own_file, engine_answer.

**Invariants**

- Prompt is stdin; process cwd is PROJECT
- stdout-answer engines receive merged stdout/stderr with leading blank lines removed
- Only declared stream engines get idle timeout
- Oversized capture clears answer and cannot promote partial output

**Failure/recovery**

- Unwritable log falls back locally to /dev/null; unwritable answer fails before launch; raw mktemp failure uses PID filename; capture copy errors are suppressed

**I/O interface IDs:** engine-execution, engine-output, process-supervision, engine-environment.

### engine_answered — lines 2930-2953

Recognize a usable successful result or only Prime native bounded-stop diagnostics after exit 1. [ralphie.sh:2930-2953](../ralphie.sh#L2930-L2953)

**Inputs**

- $1 engine
- $2 mode
- $3 exit
- $4 log
- $5 answer
- $6 elapsed seconds

**Outputs**

- Boolean status; engine ok or stopped event

**Side effects**

- Reads answer and final nonblank log line

**Calls/callbacks:** answer_is_usable, event, human_secs, dbg.

**Invariants**

- Exit 0 still requires usable answer
- Nonzero exception is limited to Prime autonomous exit 1 with exact known terminal prefixes
- Outer gates remain authoritative after a stopped attempt

**Failure/recovery**

- Other codes/text/modes return 1 for retry classification

**I/O interface IDs:** engine-failure, engine-output, prime-native, ledger-human.

### watchdog_wait — lines 2955-3015

Wait for a tracked child with optional silence, elapsed-poll and combined-output ceilings. [ralphie.sh:2955-3015](../ralphie.sh#L2955-L3015)

**Inputs**

- $1 PID
- $2 raw log
- $3 idle seconds default 0
- $4 hard seconds default 0
- $5 label default engine
- $6 byte ceiling default 0
- $7 answer default /dev/null

**Outputs**

- Child status; 124 for idle/hard timeout; 125 for output resource limit

**Side effects**

- Polls process existence and file sizes; sleeps; sends TERM/KILL through terminate_tree; waits/reaps

**Calls/callbacks:** is_int, file_bytes, warn, terminate_tree, human_secs.

**Invariants**

- All disabled limits use plain wait
- Output ceiling checks raw plus answer both during process and after exit
- Buffered engines can use hard timeout without idle timeout

**Failure/recovery**

- Invalid numeric limits become 0 here; kill/reap is best effort; nominal timeout has polling and termination-grace overhead

**I/O interface IDs:** process-supervision, engine-output.

### retain_engine_output — lines 3017-3029

Keep a marked bounded tail of consumed captures larger than 256 KiB. [ralphie.sh:3017-3029](../ralphie.sh#L3017-L3029)

**Inputs**

- $1 capture file
- TMPDIR default /tmp

**Outputs**

- Always returns 0; file becomes marker plus last 262080 bytes when trimming succeeds

**Side effects**

- Creates external temp; overwrites original capture through existing path; removes temp

**Calls/callbacks:** file_bytes, ensure_own_file, warn.

**Invariants**

- Does not trim prompt or provider-session records
- Keeps original inode/path semantics by writing through it

**Failure/recovery**

- Absent/small file, temp creation failure, or write failure is best effort; write failure warns

**I/O interface IDs:** engine-output.

### read_engine_usage — lines 3031-3119

Replay current-run Prime session usage, replacing cumulative child attribution and adding separate summary/compaction calls. [ralphie.sh:3031-3119](../ralphie.sh#L3031-L3119)

**Inputs**

- Preferred ENGINE usage capability
- RUN_DIR/sessions/state.run_id
- Optional python3
- JSONL entry schema and previous run_tokens

**Outputs**

- Updates tokens_spent by nonnegative delta, run_tokens, run_cost; prints USAGE_NOTE

**Side effects**

- Recursively reads JSONL sessions in embedded Python; updates persisted state and terminal output

**Calls/callbacks:** engine_has, state_get, have, dbg, is_int, json_num, state_bump, state_set, dim.

**Invariants**

- Does not estimate tokens from text size
- Session IDs/attribution are local to each file; latest aggregate replaces target usage
- Lifetime total receives only nonnegative increase since last run total

**Failure/recovery**

- No capability/directory/Python or parse-process failure leaves counters untouched; malformed JSON and OSError files are skipped; negative/noninteger aggregate token text is rejected

**I/O interface IDs:** engine-session, usage-python, ledger-human.

**Notes**

- EXTRACTED: This helper is called only after successful engine_run_with_fallback in cycle_act (3895-3922); an isolated failed attempt can leave usage unaccounted until a later successful read.

### engine_run_with_fallback — lines 3121-3159

Borrow an installed alternate only for an implicitly selected engine and only for the current cycle. [ralphie.sh:3121-3159](../ralphie.sh#L3121-L3159)

**Inputs**

- $1 mode
- $2 prompt
- $3 log
- $4 answer
- Preferred ENGINE and ENGINE_EXPLICIT
- Deadline/resource failure status

**Outputs**

- 0 if a primary/alternate attempt is usable; 1 otherwise
- CYCLE_ENGINE names successful engine; preferred ENGINE is preserved; ENGINE_REASON kept/restored

**Side effects**

- Runs engines; emits fallback/borrowed events; may overwrite shared cycle capture on later attempt

**Calls/callbacks:** engine_run, budget_expired, is_true, dbg, warn, event, engine_has, engine_fallbacks.

**Invariants**

- Explicit engine/custom choice prevents provider change
- Output resource exhaustion and expired budget prevent fallback
- Alternate lacking autonomy or gates is downgraded to oneshot
- Successful alternate never becomes next cycle preferred provider

**Failure/recovery**

- After all alternatives fail restores the first failure reason; same log/output path may now hold a later attempt

**I/O interface IDs:** engine-selection, engine-retries, engine-output, ledger-human.

## External I/O and execution contracts

### git-discovery

**EXTRACTED; external-process/read** — Git repository, dirty-path and root discovery. [ralphie.sh:1697-1730](../ralphie.sh#L1697-L1730), [ralphie.sh:1783-1796](../ralphie.sh#L1783-L1796), [ralphie.sh:2155-2196](../ralphie.sh#L2155-L2196)

- git -C PROJECT rev-parse --git-dir/--show-toplevel; symbolic-ref --quiet [--short] HEAD; rev-parse --short HEAD
- git status --porcelain is only an emptiness check, never parsed as filenames
- Dirty names: git diff --name-only -z --no-renames HEAD, or unborn git ls-files --cached -z; append git ls-files --others --exclude-standard -z
- All path lists are repository-relative NUL records; status/list diagnostics are frequently suppressed

**Side effects**

- Invokes inherited Git configuration/environment; status may refresh index or invoke configured helpers

**External unknowns and limits**

- Exact Git version, global config, fsmonitor and external-diff behavior are not established by this static range.

### git-init-config

**EXTRACTED; external-process/write** — Initialize local Git metadata and supply missing local identity. [ralphie.sh:1704-1718](../ralphie.sh#L1704-L1718)

- RALPHIE_GIT_INIT defaults 1; no repository plus false disables initialization
- git init -q in PROJECT; git config user.email/name read inherited values and set local defaults only on failed lookup

**Side effects**

- Creates Git metadata/config; event writes follow successful init

**External unknowns and limits**

- Initial branch/template behavior is determined by installed Git and its configuration.

### git-refs

**EXTRACTED; external-process/read-write** — Branch selection and recovery identity. [ralphie.sh:1722-1730](../ralphie.sh#L1722-L1730), [ralphie.sh:1891-1928](../ralphie.sh#L1891-L1928), [ralphie.sh:1968-1981](../ralphie.sh#L1968-L1981), [ralphie.sh:2198-2209](../ralphie.sh#L2198-L2209)

- Existing refs/heads/name: git show-ref --verify --quiet then checkout -q name; otherwise checkout -q -b name
- State base_branch and RESTORE_BRANCH remember source branch; start_commit stores verified hexadecimal HEAD
- No push, fetch, reset-hard, checkout restoration, or backup ref is performed by these assigned helpers

**Side effects**

- Checkout can change refs, index and working-tree files and invoke Git extension points

**External unknowns and limits**

- A branch is not a separate worktree; concurrent edits remain shared.

### git-index

**EXTRACTED; external-process/read-write** — Operator staging capture and limited postcommit resynchronization. [ralphie.sh:2027-2034](../ralphie.sh#L2027-L2034), [ralphie.sh:2484-2502](../ralphie.sh#L2484-L2502), [ralphie.sh:1933-1948](../ralphie.sh#L1933-L1948)

- operator-staged.nul captures git diff --cached --name-only -z --no-renames without explicit HEAD
- After commit enumerate git diff-tree -m --root --no-commit-id --name-only -r -z HEAD
- Skip exact originally-staged names; literal git reset -q -- path refreshes other committed real-index paths
- self_is_reviewed uses literal ls-files and unstaged git diff --quiet

**Side effects**

- Real index is read at startup and intentionally updated for nonprotected committed paths after save

**External unknowns and limits**

- Operator index changes during a cycle are not distinguishable from engine changes; the protected name list is not a byte-for-byte index backup.

### ownership-files

**EXTRACTED; filesystem/read-write** — NUL path custody and process-memory seals. [ralphie.sh:1732-1889](../ralphie.sh#L1732-L1889), [ralphie.sh:1983-2063](../ralphie.sh#L1983-L2063)

- HOME_DIR/owned.nul: checksum TAB repository-relative path NUL; duplicate records are searched completely
- RUN_DIR/pre-dirty.PID.nul and operator-staged.nul: raw path NUL; runtime own-state paths excluded from pre-dirty capture
- Scratch: dirty-now.nul, dirty.nul, pre-dirty.raw.PID, owned.nul.tmp.PID
- PRE_DIRTY_SEAL stores display count plus sha_of bytes checksum; sha_of may fall back to cksum (168-177)
- Fingerprint - means not readable regular-file bytes; ownership is checked against current content and dirtiness

**Side effects**

- Appends/replaces ownership records; may append/reseal changed operator paths; removes scratch files

**External unknowns and limits**

- No authorship oracle for simultaneous edits; no atomic filesystem snapshot; mode/target identity is outside byte fingerprint.

### self-file

**EXTRACTED; filesystem/read** — Running-source change detection. [ralphie.sh:1930-1966](../ralphie.sh#L1930-L1966)

- SELF_HASH is process-memory fingerprint from SELF stdin
- Startup warning compares tracked in-project worktree file to index; cycle check compares bytes to saved fingerprint

**Side effects**

- Mismatch writes event/question and updates hash; no source rollback

**External unknowns and limits**

- Static code cannot guarantee protection from an engine with equivalent OS write/process privileges.

### git-private-index

**EXTRACTED; external-process/write** — Scoped alternate-index staging and filtering. [ralphie.sh:2072-2146](../ralphie.sh#L2072-L2146), [ralphie.sh:2267-2296](../ralphie.sh#L2267-L2296), [ralphie.sh:2365-2454](../ralphie.sh#L2365-L2454)

- RUN_DIR/index.PID is passed using GIT_INDEX_FILE to read-tree HEAD, literal add -A -- project_prefix, cached diff and literal per-path reset
- Unborn index starts without read-tree HEAD
- Protected/risky/bulk/runtime paths are removed from alternate index before git commit
- Temporary path files: staged.PID.nul and private index

**Side effects**

- Creates Git blobs/index entries; deletes temporary index after outcome

**External unknowns and limits**

- Filters may change blob bytes from inspected working-tree bytes; ignored reset errors are not separately verified in this helper.

### git-path-filter

**EXTRACTED; filesystem-and-pattern-policy** — Literal path scope and automatic-commit exclusion rules. [ralphie.sh:2069-2070](../ralphie.sh#L2069-L2070), [ralphie.sh:2098-2127](../ralphie.sh#L2098-L2127), [ralphie.sh:2177-2196](../ralphie.sh#L2177-L2196), [ralphie.sh:2244-2259](../ralphie.sh#L2244-L2259), [ralphie.sh:2391-2424](../ralphie.sh#L2391-L2424)

- RISKY_PATHS and BULK_PATHS exact source declarations are preserved in globals below
- Maximum automatic path size defaults 1048576 bytes
- Working-tree link readlink filter rejects absolute target or text containing ../; committed-object link filter rejects absolute, exact .. and upward path segments
- Physical project_prefix anchors root/subproject boundaries; --literal-pathspecs avoids wildcard/magic expansion

**Side effects**

- Exclusion resets affect only staging, not file content; rejected paths remain on disk

**External unknowns and limits**

- This is a filename/size/link heuristic, not content-based secret detection or an OS boundary.

### git-operation-markers

**EXTRACTED; filesystem/read** — Preserve an operator Git operation in progress. [ralphie.sh:2344-2361](../ralphie.sh#L2344-L2361)

- Resolve git-dir relative to PROJECT when necessary
- Check MERGE_HEAD, CHERRY_PICK_HEAD, REVERT_HEAD, rebase-merge and rebase-apply before creating a commit

**Side effects**

- Refusal flags/events/questions

**External unknowns and limits**

- No claim is made to detect every possible Git extension/sequencer or concurrent operation.

### git-history-validation

**EXTRACTED; external-process/read** — Validate engine-created history from committed objects rather than mutable worktree. [ralphie.sh:2205-2265](../ralphie.sh#L2205-L2265), [ralphie.sh:3810-3813](../ralphie.sh#L3810-L3813), [ralphie.sh:4110-4128](../ralphie.sh#L4110-L4128)

- Cycle captures HEAD, symbolic ref, and rev-list --all before gate/engine work
- Use merge-base --is-ancestor, rev-list --reverse old..new (or entire new root history), net diff, show -s --format=%P, diff-tree --root -z
- For each added/modified object cat-file -e/-t/-s; require blob and size limit; literal ls-tree detects 120000 mode; cat-file blob reads symlink target
- Every new commit must be linear, nonempty, previously unseen, project-local and free of excluded paths

**Side effects**

- Writes engine-commit-paths.PID.nul; invalid history is left untouched

**External unknowns and limits**

- Rejecting history after execution does not undo commits or other external actions.

### git-commit

**EXTRACTED; external-process/write** — Git save operation with alternate index and bounded failure evidence. [ralphie.sh:2456-2482](../ralphie.sh#L2456-L2482)

- Background subshell cd git_top; export GIT_INDEX_FILE; exec git commit -q -m message
- stdin /dev/null; stdout and stderr merged into RUN_DIR/commit-error.PID
- COMMIT_TIMEOUT default120, invalid/nonpositive reset120; watchdog idle0/hardsecs with no byte cap here
- On success remove index/error capture; on failure bounded error tails go to dim/event/ask_human

**Side effects**

- Writes Git objects/HEAD/reflogs; invokes configured commit hooks/signing; process tree may be terminated

**External unknowns and limits**

- A hook can have arbitrary side effects before failure; no transaction rolls those back.

### git-execution-policy

**INFERRED; arbitrary-command-boundary** — Inherited Git hooks, filters and helpers execute within repository policy. [ralphie.sh:1904-1908](../ralphie.sh#L1904-L1908), [ralphie.sh:2273-2277](../ralphie.sh#L2273-L2277), [ralphie.sh:2394-2402](../ralphie.sh#L2394-L2402), [ralphie.sh:2460-2478](../ralphie.sh#L2460-L2478)

- Git is invoked directly; no hook/filter/signing disable flag is added
- Add may execute clean/process filters; checkout may execute checkout/filter hooks; commit may execute hooks/signing helpers
- GIT_INDEX_FILE isolates staging content, not the capabilities of Git subprocesses

**Side effects**

- Git-launched commands run under inherited host permissions/environment

**External unknowns and limits**

- Actual configured helper commands, time/resource behavior and network use remain external unknowns.

### engine-table

**EXTRACTED; configuration/read** — Declarative engine adapter registry and capability routing. [ralphie.sh:2505-2561](../ralphie.sh#L2505-L2561)

- prime-agent|prime-agent|stdout|autonomy gates memory subagents resume skills json usage
- claude|claude|stdout|subagents resume skills json
- codex|codex|file|resume json stream
- custom comes from RALPHIE_ENGINE_CMD; answer defaults stdout; capabilities default empty
- Capabilities control orchestration rather than proving runtime/model quality

**External unknowns and limits**

- Capability declarations can drift from installed engine releases; no runtime introspection verifies them.

### engine-discovery

**EXTRACTED; external-process/read** — Engine path and liveness checks. [ralphie.sh:2563-2599](../ralphie.sh#L2563-L2599)

- Literal executable path wins; otherwise executable token is first text before a space
- command -v uses inherited PATH
- --version is invoked with no prompt; timeout/gtimeout15 when available, plain command otherwise
- ENGINE_LIVE_CACHE stores ok/dead by engine in the current shell process

**Side effects**

- Executes arbitrary configured executable even during discovery

**External unknowns and limits**

- A custom --version implementation could have side effects or hang without timeout utility; responsiveness is not authentication.

### engine-selection

**EXTRACTED; control-policy** — Prime default priority, explicit choice and cycle-local fallback. [ralphie.sh:2611-2656](../ralphie.sh#L2611-L2656), [ralphie.sh:3121-3159](../ralphie.sh#L3121-L3159), [ralphie.sh:5086-5089](../ralphie.sh#L5086-L5089), [ralphie.sh:5160](../ralphie.sh#L5160-L5160)

- Priority: explicit name; configured custom; responsive Prime; most-capable responsive installed; most-capable installed
- Fallback enumerates other installed adapters by capability count without liveness probes
- ENGINE_EXPLICIT, expired budget and output resource limit prohibit fallback
- Borrowed provider receives no preferred-provider model ID; mode drops to oneshot without both autonomy and gates
- CYCLE_ENGINE changes only for successful borrowed attempt; ENGINE remains preferred

**Side effects**

- May invoke another provider only on implicit selection

**External unknowns and limits**

- Equal-score sort ties are incidental, not a declared quality ranking; engine cost/privacy behavior is external.

### engine-argv

**EXTRACTED; process-argv** — Adapter command-line construction. [ralphie.sh:2662-2751](../ralphie.sh#L2662-L2751)

- Prime: prime-agent -p --mode text --cwd PROJECT --offline; optional --model MODEL --thinking THINKING; session and native limits below
- Claude: claude -p [--model MODEL]; default YOLO adds --dangerously-skip-permissions and IS_SANDBOX=1
- Codex: codex exec [--model MODEL] [-c model_reasoning_effort="THINKING"] [--dangerously-bypass-approvals-and-sandbox] - --output-last-message OUT
- Custom: literal executable or shell word-split/glob-expanded command string; no eval
- MODEL cleared only for borrowed engine; THINKING is forwarded for Prime/Codex; Claude ignores THINKING

**External unknowns and limits**

- External engine validates flags, model namespace, credentials, tool/sandbox/approval behavior and outputs.

### prime-native

**EXTRACTED; external-engine-contract** — Prime ordinary/autonomous native orchestration and bounded-stop recognition. [ralphie.sh:2675-2716](../ralphie.sh#L2675-L2716), [ralphie.sh:2940-2950](../ralphie.sh#L2940-L2950), [ralphie.sh:3960-3964](../ralphie.sh#L3960-L3964)

- --offline suppresses startup release-manifest fetch according to adapter comment; it is not local/offline inference
- Session default --session-dir RUN_DIR/sessions/run_id; RALPHIE_ENGINE_SESSION false uses --no-session
- Autonomous requires requested mode autonomous and positive budget_cap(ENGINE_TIMEOUT default2400)
- Pass every gates_list line separately via --autonomous-gate; max-turns24, max-continuations6; optional max-tokens
- Gate timeout defaults900s, invalid/zero or larger than call clamps to call; both timeout flags passed as positive milliseconds
- With engine timeout0 and no run deadline omit native autonomous flags; Ralphie supplies continuation
- Exit1 only accepted for usable answer plus final nonblank line matching known Autonomous quality gate/terminal-limit prefixes
- Gate command text is passed unchanged as one argv value per gate; the selected Prime executable owns its command-execution semantics. Ralphie also verifies through its separate gate runner.

**External unknowns and limits**

- Current assigned code does not inspect Prime source at runtime or negotiate versions. Exact stop text remains a versioned external contract.
- Prime has no adapter permission-bypass flag; --no-yolo produces only a debug explanation and does not constrain Prime tool permissions.

### custom-command

**EXTRACTED; arbitrary-command-boundary** — Operator-specified executable adapter. [ralphie.sh:2544-2549](../ralphie.sh#L2544-L2549), [ralphie.sh:2563-2575](../ralphie.sh#L2563-L2575), [ralphie.sh:2735-2742](../ralphie.sh#L2735-L2742), [ralphie.sh:2891-2896](../ralphie.sh#L2891-L2896)

- RALPHIE_ENGINE_CMD literal executable is one argv element even with spaces
- Otherwise unquoted array assignment performs shell field splitting and pathname expansion, not shell grammar/quote parsing
- Direct exec argv with prompt stdin in PROJECT; operators needing complex syntax must provide a real executable wrapper
- RALPHIE_ENGINE_ANSWER defaults stdout; file mode has no generic output-filename argument added by this branch

**Side effects**

- Executes arbitrary operator-designated command with host rights and inherited environment

**External unknowns and limits**

- External wrapper must implement intended completion and file-output contract; same-user safety cannot be inferred from capability labels.

### engine-environment

**EXTRACTED; process-environment** — Inherited context and bounded adapter defaults. [ralphie.sh:2544-2549](../ralphie.sh#L2544-L2549), [ralphie.sh:2665-2751](../ralphie.sh#L2665-L2751), [ralphie.sh:2801-2805](../ralphie.sh#L2801-L2805), [ralphie.sh:2843-2846](../ralphie.sh#L2843-L2846), [ralphie.sh:2858-2907](../ralphie.sh#L2858-L2907), [ralphie.sh:2955-2971](../ralphie.sh#L2955-L2971)

- Inherited environment/PATH/HOME/provider config remains available to child; ENGINE_ENV adds only IS_SANDBOX=1 for Claude YOLO
- PROJECT cwd; prompt/log/out arguments supplied by cycle caller; root canonical RALPHIE_PROJECT binding is outside assigned range
- Defaults: YOLO1; session1; call2400s; gate900s; turns24; continuations6; retries3; backoff5s; idle600s; output16777216 bytes; answer minimum2 bytes; TMPDIR /tmp
- ENGINE_MAX_TOKENS only passed when nonempty; no default dollar budget; COMMIT_TIMEOUT120 separate
- Positive byte ceiling and commit timeout are validated; watchdog integer checks convert invalid idle/hard to0; retry/backoff/answer-min/native-turn settings are trusted or deferred

**External unknowns and limits**

- Provider credentials are inherited, never explicitly opened by this range. A selected engine/helper may read them.

### engine-session

**EXTRACTED; filesystem/engine-output** — Per-run Prime sessions and usage schema source. [ralphie.sh:2685-2692](../ralphie.sh#L2685-L2692), [ralphie.sh:3031-3050](../ralphie.sh#L3031-L3050)

- Prime writes JSONL under RUN_DIR/sessions/state.run_id; default fallback run_id is run
- No --resume or --continue flag is passed in this adapter even though resume is declared capability
- No-session suppresses new session record creation; usage parser requires an existing current-run directory
- Session retention/pruning is handled outside this range

**Side effects**

- Engine-owned session files contain prompts/tool output/model usage; parser reads them

**External unknowns and limits**

- Engine session naming, retention, permissions, schema migration and subagent persistence are external versioned behavior.

### engine-execution

**EXTRACTED; arbitrary-command-boundary** — Direct engine child process with prompt input and combined output capture. [ralphie.sh:2853-2928](../ralphie.sh#L2853-L2928)

- ENGINE_ARGV guarded array expansion preserves argv under Bash3.2 set -u; ENGINE_ENV passed through env when nonempty
- exec selected argv < prompt in PROJECT; stdout and stderr share raw temp outside project
- Try job-control process group; track child PID for cleanup; answer-file engine writes known out path itself
- No eval and no terminal read in this range

**Side effects**

- Selected engine can read/write project and host resources allowed by OS/provider policy; paid inference occurs in external engine, not shell accounting

**External unknowns and limits**

- No universal sandbox, provider billing guarantee, or complete detached-child containment is established by this code.

### engine-output

**EXTRACTED; filesystem/read-write** — Prompt, raw logs, answer files and bounded retention. [ralphie.sh:2774-2788](../ralphie.sh#L2774-L2788), [ralphie.sh:2858-2881](../ralphie.sh#L2858-L2881), [ralphie.sh:2904-2927](../ralphie.sh#L2904-L2927), [ralphie.sh:2944-2947](../ralphie.sh#L2944-L2947), [ralphie.sh:2985-3012](../ralphie.sh#L2985-L3012), [ralphie.sh:3017-3029](../ralphie.sh#L3017-L3029)

- Prompt input must be regular file; answer file must be writable before launch; cycle log is optional
- Raw temp is TMPDIR/ralphie.raw.XXXXXX, fallback ralphie.raw.PID; merged stdout/stderr copied to log
- stdout engine answer strips leading blank lines; file engine keeps its own out contents
- Finite default output ceiling sums raw log plus answer bytes during/after invocation; limit returns125 and clears answer
- Usability: min bytes2, non-whitespace, no obvious HTML/login strings in first2000; no solved-work claim
- Consumed captures above262144 bytes become marker plus262080-byte tail through TMPDIR/ralphie.tail.XXXXXX
- Retries and alternates reuse the same cycle log/answer pathname, overwriting earlier complete captures

**Side effects**

- Writes/truncates/copies/removes temp/capture files; terminal debug can show argv; raw log text is not echoed by engine failure reason

**External unknowns and limits**

- Session files and engine filesystem output are not capped by capture ceiling; a custom executable can print sensitive content into retained logs.

### engine-failure

**EXTRACTED; exit-and-text-protocol** — Failure classification and narrow Prime exit1 exception. [ralphie.sh:2758-2788](../ralphie.sh#L2758-L2788), [ralphie.sh:2824-2850](../ralphie.sh#L2824-L2850), [ralphie.sh:2930-2953](../ralphie.sh#L2930-L2953)

- 125 resource-limit; 124/137/143 transient; then permanent regex before transient regex over last20000 log bytes; unknown otherwise
- Only rc0+usable answer or exact Prime autonomous rc1 terminal prefix is accepted
- Permanent reason keeps class/exit, not-retrying, attempts and retained log path; exhaustion keeps final reason plus max attempts and path
- Resource failure sets ENGINE_RESOURCE_LIMIT=1 and stops retries/fallback

**Side effects**

- Emits bounded reason events; no arbitrary nonzero output promotes success

**External unknowns and limits**

- Classification is text heuristic; a matching substring does not prove external failure cause. Native diagnostics are version-sensitive.

### engine-retries

**EXTRACTED; control-policy** — Bounded attempts, increasing sleep and operator-provider custody. [ralphie.sh:2792-2851](../ralphie.sh#L2792-L2851), [ralphie.sh:3121-3159](../ralphie.sh#L3121-L3159)

- Default3 attempts; retries rebuild argv and reread remaining deadline each time
- After failed attempt N, next sleep N*ENGINE_BACKOFF(default5) if another attempt and budget not already expired
- Permanent/resource/cannot-start/time-limit paths return distinct engine_run statuses
- Outer fallback uses same prompt/files, honors explicit choice and maintains preferred engine across cycles

**Side effects**

- May incur multiple provider calls and shared output replacement

**External unknowns and limits**

- Backoff sleep is not clamped to the remaining deadline; budget is checked again before launching the next attempt.

### process-supervision

**EXTRACTED; process-control** — Portable polling watchdog plus cross-layer descendant termination. [ralphie.sh:2456-2468](../ralphie.sh#L2456-L2468), [ralphie.sh:2591-2599](../ralphie.sh#L2591-L2599), [ralphie.sh:2887-2908](../ralphie.sh#L2887-L2908), [ralphie.sh:2955-3015](../ralphie.sh#L2955-L3015), [ralphie.sh:831-847](../ralphie.sh#L831-L847), [ralphie.sh:247-279](../ralphie.sh#L247-L279)

- budget_cap clamps positive/zero local allowance to run deadline; floor1 avoids accidental unlimited expired timeout
- Watchdog polls kill -0 and file sizes; first tick0.05+0.95s, later1s; elapsed counter is polling iterations
- Idle depends on growth of raw log only, not file-engine answer growth; combined byte cap counts both
- On timeout/limit terminate_tree snapshots descendants, sends group/PID TERM, waits2s then KILL; watcher waits child
- watchdog returns124 deadline/idle,125 oversize, otherwise exact child status

**Side effects**

- Signals/reaps descendants; process-group creation is best effort

**External unknowns and limits**

- Polling overhead/grace can exceed nominal deadlines; detached descendants created outside captured lineage/group are not proven contained; liveness probe is unbounded when timeout utility is absent.

### usage-python

**EXTRACTED; embedded-language/filesystem-read** — Embedded Python JSONL replay and shell-state accounting. [ralphie.sh:3050-3119](../ralphie.sh#L3050-L3119)

- Python receives current-run directory as argv1, code through stdin heredoc; stderr suppressed
- os.walk recursively scans filenames ending .jsonl; UTF-8 errors replaced; blank/non-JSON/nondict rows ignored; OSError skips file
- Load records for one whole file; map assistant message entries by string id
- Replay child_usage_attributed rows in file order, assigning aggregateUsage to matching targetId assistant; last attribution wins
- Sum usage.totalTokens and usage.cost.total for message-containing rows, plus entry-level usage for compaction/branch_summary
- Only exact numeric int/float accepted, bool excluded; output integer token total and six-decimal cost separated by space
- Shell validates unsigned integer token result, adds only positive/nonnegative delta to lifetime tokens, always stores current run totals

**Side effects**

- Reads potentially large session records into memory; persists tokens_spent/run_tokens/run_cost

**External unknowns and limits**

- No Python means no usage update, not estimated usage. Missing/partial/unsupported records can make totals incomplete.
- Engine-reported cost is metadata, not an independently reconciled invoice; numerical NaN/infinity or malformed aggregates can make the Python process fail and be silently skipped.
- No global deduplication across different session files is performed. Child attribution does not add its own standalone total.

### ledger-human

**EXTRACTED; cross-layer/filesystem-and-output** — State, append-only event and nonblocking human-channel side effects. [ralphie.sh:1707-1709](../ralphie.sh#L1707-L1709), [ralphie.sh:1899-1914](../ralphie.sh#L1899-L1914), [ralphie.sh:1917-1928](../ralphie.sh#L1917-L1928), [ralphie.sh:1959-1965](../ralphie.sh#L1959-L1965), [ralphie.sh:1979-1980](../ralphie.sh#L1979-L1980), [ralphie.sh:2134-2142](../ralphie.sh#L2134-L2142), [ralphie.sh:2331-2359](../ralphie.sh#L2331-L2359), [ralphie.sh:2475-2478](../ralphie.sh#L2475-L2478), [ralphie.sh:2813-2850](../ralphie.sh#L2813-L2850), [ralphie.sh:3113-3118](../ralphie.sh#L3113-L3118), [ralphie.sh:3140-3150](../ralphie.sh#L3140-L3150), [ralphie.sh:296-381](../ralphie.sh#L296-L381)

- state_get reads state; state_set/state_bump write allowed keys under HOME_DIR with temporary rename/mutex
- event appends JSONL including in-memory cycle/run identity and updates state timestamp
- ask_human queues a question; no terminal response is read in this range
- info/good/dim honor quiet conventions; warn/err/debug use output streams per core helpers

**Side effects**

- Writes own runtime state/events/questions; prints human-facing outcomes

**External unknowns and limits**

- Cross-layer state/event recovery semantics are not reimplemented here; engine tool writes may damage these paths.

## Critical control and data relationships

- **EXTRACTED — run_prepare to Git boundary and ownership snapshot (ordering).** Resolve/cache Git root and physical project prefix; initialize or select fixed no-Git mode; release old claims, snapshot protection, choose branch, then refuse detached HEAD. [ralphie.sh:5258-5283](../ralphie.sh#L5258-L5283)
- **EXTRACTED — path_fingerprint to owned_has/release_owned_paths/record_owned_paths (dataflow).** Current file bytes bind persistent ownership to exact repository-relative path; changed bytes revoke a claim and may transfer path to protected list. [ralphie.sh:1745-1758](../ralphie.sh#L1745-L1758), [ralphie.sh:1760-1780](../ralphie.sh#L1760-L1780), [ralphie.sh:1798-1845](../ralphie.sh#L1798-L1845), [ralphie.sh:1847-1882](../ralphie.sh#L1847-L1882)
- **EXTRACTED — pre_dirty_seal to pre_dirty_intact (custody).** Count/checksum captured in process memory is checked before new claims, before commit exclusions and when validating engine history. [ralphie.sh:1852-1865](../ralphie.sh#L1852-L1865), [ralphie.sh:1983-2001](../ralphie.sh#L1983-L2001), [ralphie.sh:2220](../ralphie.sh#L2220-L2220), [ralphie.sh:2411-2418](../ralphie.sh#L2411-L2418)
- **EXTRACTED — project_prefix to ownership and private index (scope).** Physical containment controls ownership and engine history; literal add/reset operations constrain private staging to the selected project. [ralphie.sh:1811-1821](../ralphie.sh#L1811-L1821), [ralphie.sh:1868-1877](../ralphie.sh#L1868-L1877), [ralphie.sh:2177-2196](../ralphie.sh#L2177-L2196), [ralphie.sh:2244-2248](../ralphie.sh#L2244-L2248), [ralphie.sh:2391-2394](../ralphie.sh#L2391-L2394)
- **EXTRACTED — snapshot_pre_dirty to resync_operator_index (staging-preservation).** Snapshot of originally staged exact pathnames makes postcommit real-index refresh skip those paths. [ralphie.sh:2027-2034](../ralphie.sh#L2027-L2034), [ralphie.sh:2484-2502](../ralphie.sh#L2484-L2502)
- **EXTRACTED — dirty_paths_nul to snapshot/ownership lists (serialization).** Git -z and disabled rename collapsing preserve unusual path bytes and both rename endpoints; lists travel via files instead of command substitution. [ralphie.sh:1733-1744](../ralphie.sh#L1733-L1744), [ralphie.sh:1783-1796](../ralphie.sh#L1783-L1796), [ralphie.sh:2037-2053](../ralphie.sh#L2037-L2053), [ralphie.sh:2079-2087](../ralphie.sh#L2079-L2087)
- **EXTRACTED — git_commit_cycle to record_outcome (postcondition).** Commit helpers may return0 after refusal, so record_outcome checks COMMIT flags and actual HEAD movement before pass_count increments. [ralphie.sh:2281-2290](../ralphie.sh#L2281-L2290), [ralphie.sh:4108-4155](../ralphie.sh#L4108-L4155), [ralphie.sh:4157-4180](../ralphie.sh#L4157-L4180)
- **EXTRACTED — cycle_begin to engine_history_is_safe (pre-execution-evidence).** Captures HEAD/ref/all reachable commit IDs before engine/gate effects; later validation requires exact branch and new linear project-only history. [ralphie.sh:3808-3813](../ralphie.sh#L3808-L3813), [ralphie.sh:2205-2265](../ralphie.sh#L2205-L2265)
- **EXTRACTED — engine_history_is_safe to record_outcome (history-acceptance).** HEAD movement caused by engine is inspected commit by commit; invalid history blocks without reset, valid history sets CY_ENGINE_SAVED. [ralphie.sh:2211-2265](../ralphie.sh#L2211-L2265), [ralphie.sh:4114-4130](../ralphie.sh#L4114-L4130)
- **INFERRED — build_commit_index to Git filters (arbitrary-execution).** Even with a private index, git add can execute configured clean/process filters before exclusions; filtering controls saved paths, not command authority. [ralphie.sh:2374-2404](../ralphie.sh#L2374-L2404)
- **EXTRACTED — write_commit to watchdog_wait/terminate_tree (bounded-callbacks).** Git hooks/signing are child execution, bounded by COMMIT_TIMEOUT and the same process-tree watchdog used by engines. [ralphie.sh:2456-2480](../ralphie.sh#L2456-L2480), [ralphie.sh:2955-3015](../ralphie.sh#L2955-L3015), [ralphie.sh:831-847](../ralphie.sh#L831-L847)
- **EXTRACTED — ENGINE_TABLE to engine_has/engine_score (declarative-routing).** Table capabilities select native complement, liveness ranking, idle monitoring and usage parsing; capability count is only ranking metadata. [ralphie.sh:2516-2561](../ralphie.sh#L2516-L2561), [ralphie.sh:2628-2646](../ralphie.sh#L2628-L2646), [ralphie.sh:2904-2907](../ralphie.sh#L2904-L2907), [ralphie.sh:3040-3049](../ralphie.sh#L3040-L3049)
- **EXTRACTED — engine_pick to engine_run_with_fallback (operator-custody).** Explicit name/custom wins initial selection; ENGINE_EXPLICIT forbids alternate provider execution if that choice later fails. [ralphie.sh:2615-2627](../ralphie.sh#L2615-L2627), [ralphie.sh:3131-3136](../ralphie.sh#L3131-L3136), [ralphie.sh:5086-5089](../ralphie.sh#L5086-L5089), [ralphie.sh:5160](../ralphie.sh#L5160-L5160)
- **EXTRACTED — cycle_act to engine_build (native-complement).** Mode is autonomous only for engine declaring both autonomy and gates and a nonempty gate set; Prime then receives those gate commands. [ralphie.sh:3882-3885](../ralphie.sh#L3882-L3885), [ralphie.sh:2693-2715](../ralphie.sh#L2693-L2715)
- **EXTRACTED — RUN_DEADLINE/budget_cap to Prime native flags and host watchdog (deadline).** Remaining run allowance caps both native call/gate timeout construction and host child supervision; zero-unbounded uses ordinary Prime loop. [ralphie.sh:247-279](../ralphie.sh#L247-L279), [ralphie.sh:2693-2715](../ralphie.sh#L2693-L2715), [ralphie.sh:2884-2907](../ralphie.sh#L2884-L2907)
- **EXTRACTED — engine_build to engine_invoke (argv-dataflow).** Rebuilt guarded Bash arrays become direct exec argv/environment in PROJECT; prompt is stdin and output is external temp capture. [ralphie.sh:2662-2668](../ralphie.sh#L2662-L2668), [ralphie.sh:2675-2744](../ralphie.sh#L2675-L2744), [ralphie.sh:2881-2898](../ralphie.sh#L2881-L2898)
- **EXTRACTED — engine_has(stream) to watchdog_wait idle (capability-boundary).** Only stream-declared engine receives idle timeout; buffered Prime/Claude are supervised by wall-clock/output bounds. [ralphie.sh:2534-2536](../ralphie.sh#L2534-L2536), [ralphie.sh:2900-2907](../ralphie.sh#L2900-L2907)
- **EXTRACTED — engine_invoke to engine_answered/classify_failure (exit-and-output).** Host exit and collected files feed strict usable-answer acceptance before retry classification; output limit clears answer and stops retries. [ralphie.sh:2913-2927](../ralphie.sh#L2913-L2927), [ralphie.sh:2824-2841](../ralphie.sh#L2824-L2841), [ralphie.sh:2930-2953](../ralphie.sh#L2930-L2953)
- **EXTRACTED — Prime native exit1 to independent outer verification (trust-boundary).** Recognized native boundary can finish an attempt but never proves gate success; cycle_act then parses report and cycle_verify independently runs checks. [ralphie.sh:2940-2950](../ralphie.sh#L2940-L2950), [ralphie.sh:3922-3929](../ralphie.sh#L3922-L3929), [ralphie.sh:3960-3964](../ralphie.sh#L3960-L3964)
- **EXTRACTED — engine_run to retained engine reason (diagnostics).** Final attempt exit/class and log path survive exhaustion or permanent failure without copying raw provider output into terminal reason. [ralphie.sh:2826-2850](../ralphie.sh#L2826-L2850)
- **EXTRACTED — engine_run_with_fallback to ENGINE vs CYCLE_ENGINE (ephemeral-borrowing).** Alternate success changes only CYCLE_ENGINE; preferred MODEL is cleared in alternate argv, preferred ENGINE remains for next cycle. [ralphie.sh:2672-2673](../ralphie.sh#L2672-L2673), [ralphie.sh:3124-3158](../ralphie.sh#L3124-L3158)
- **INFERRED — fallback shared log path to first_reason restoration (evidence-limitation).** All attempts/alternates reuse one log path; after all fallbacks fail the restored first reason may name a path whose current bytes came from a later attempt. [ralphie.sh:2867-2869](../ralphie.sh#L2867-L2869), [ralphie.sh:2921-2924](../ralphie.sh#L2921-L2924), [ralphie.sh:3123-3126](../ralphie.sh#L3123-L3126), [ralphie.sh:3145-3157](../ralphie.sh#L3145-L3157)
- **EXTRACTED — Prime JSONL child attribution to usage totals (replay).** Latest aggregateUsage replaces corresponding assistant usage rather than adding attribution records as new charges; compaction/branch_summary usage is separate. [ralphie.sh:3070-3103](../ralphie.sh#L3070-L3103)
- **EXTRACTED — read_engine_usage to state lifetime/run totals (accounting).** Current-run session sum minus prior run_tokens is the only lifetime increment; current sum/cost replaces run counters. [ralphie.sh:3047-3050](../ralphie.sh#L3047-L3050), [ralphie.sh:3107-3118](../ralphie.sh#L3107-L3118)
- **INFERRED — successful cycle_act to usage visibility (accounting-limitation).** Usage is reread only after engine_run_with_fallback succeeds; final blocked attempts can have unrecorded session usage until a later successful read. [ralphie.sh:3895-3922](../ralphie.sh#L3895-L3922), [ralphie.sh:3031-3119](../ralphie.sh#L3031-L3119)
- **INFERRED — SELF_HASH to cycle trust (source-custody).** A byte mismatch returns1 and queues a review question; caller records self-edit state rather than allowing a silent next-run verifier change. [ralphie.sh:1950-1966](../ralphie.sh#L1950-L1966), [ralphie.sh:3903](../ralphie.sh#L3903-L3903), [ralphie.sh:3990-4005](../ralphie.sh#L3990-L4005)

## Limitations and review cautions

- **static-only (EXTRACTED).** This review read every assigned source line and selected cross-layer references. It did not execute engines, tests, Git mutations or provider calls. It describes this frozen source, not a runtime production certification. [ralphie.sh:1697-3161](../ralphie.sh#L1697-L3161)
- **trusted-execution (INFERRED).** Git policy helpers and engine tools can execute arbitrary commands with inherited host authority. Private index, path filters, gates, and process cleanup do not form an OS sandbox. --no-yolo changes only supported adapter flags. [ralphie.sh:2394-2402](../ralphie.sh#L2394-L2402), [ralphie.sh:2461](../ralphie.sh#L2461-L2461), [ralphie.sh:2682](../ralphie.sh#L2682-L2682), [ralphie.sh:2723-2742](../ralphie.sh#L2723-L2742), [ralphie.sh:2891-2896](../ralphie.sh#L2891-L2896)
- **ownership-granularity (INFERRED).** Custody is per path and readable file content, not per hunk, actor, mode, or unique symlink identity. During-cycle concurrent operator edits cannot be distinguished from engine edits. NUL membership is exact, while display counts can overcount embedded newlines. [ralphie.sh:1733-1758](../ralphie.sh#L1733-L1758), [ralphie.sh:1760-1780](../ralphie.sh#L1760-L1780), [ralphie.sh:1884-1889](../ralphie.sh#L1884-L1889), [ralphie.sh:2012-2063](../ralphie.sh#L2012-L2063)
- **best-effort-git-errors (EXTRACTED).** Dirty/staged listing errors may become empty lists; individual exclusion/resync resets ignore errors; cached-diff errors take the nonempty branch. Downstream Git/HEAD postconditions catch some failures, but these helpers do not prove every exclusion succeeded. [ralphie.sh:1793-1796](../ralphie.sh#L1793-L1796), [ralphie.sh:2033](../ralphie.sh#L2033-L2033), [ralphie.sh:2087](../ralphie.sh#L2087-L2087), [ralphie.sh:2099-2126](../ralphie.sh#L2099-L2126), [ralphie.sh:2423](../ralphie.sh#L2423-L2423), [ralphie.sh:2434](../ralphie.sh#L2434-L2434), [ralphie.sh:2495-2499](../ralphie.sh#L2495-L2499), [ralphie.sh:4148-4155](../ralphie.sh#L4148-L4155)
- **startup-self-claim (EXTRACTED).** self_is_reviewed checks unstaged differences against the index, despite wording about the committed copy; a staged-only script change is outside that check. [ralphie.sh:1939-1946](../ralphie.sh#L1939-L1946)
- **link-filter-difference (EXTRACTED).** Working-tree exclusion uses /*|*../*, while committed-history validation also checks exact .. and trailing /..; neither is a full symlink-chain resolver. [ralphie.sh:2117-2122](../ralphie.sh#L2117-L2122), [ralphie.sh:2255-2258](../ralphie.sh#L2255-L2258)
- **deadlines (INFERRED).** Host watchdog is polling-based with TERM grace; backoff is not clamped to remaining seconds; version probe has no watchdog if timeout/gtimeout is missing. Deadline limits are not a strict end-to-end wall-clock bound. [ralphie.sh:2597-2598](../ralphie.sh#L2597-L2598), [ralphie.sh:2843-2846](../ralphie.sh#L2843-L2846), [ralphie.sh:2955-3015](../ralphie.sh#L2955-L3015), [ralphie.sh:831-847](../ralphie.sh#L831-L847)
- **provider-version (EXTRACTED).** Table declarations, CLI flags and terminal text assume compatible installed engines. This code does not negotiate versions or verify credentials/capabilities; model selectors are delegated unchanged. README pins prior Prime/Codex source studies, not all future binaries. [ralphie.sh:2533-2537](../ralphie.sh#L2533-L2537), [ralphie.sh:2591-2609](../ralphie.sh#L2591-L2609), [ralphie.sh:2665-2751](../ralphie.sh#L2665-L2751), [ralphie.sh:2944-2947](../ralphie.sh#L2944-L2947)
- **usage-completeness (INFERRED).** Usage needs Python and supported current-run session files, is reread after successful attempts only, and trusts engine-provided totals/cost. It is not an independently reconciled billing ledger or universal provider budget control. [ralphie.sh:3031-3050](../ralphie.sh#L3031-L3050), [ralphie.sh:3051-3119](../ralphie.sh#L3051-L3119), [ralphie.sh:3895-3922](../ralphie.sh#L3895-L3922)
- **session-resources (EXTRACTED).** Capture byte caps cover raw/output files only; sessions, other engine files and per-file Python JSONL memory are not bounded here. Prompt and provider session records are deliberately excluded from capture tail trimming. [ralphie.sh:2985-2986](../ralphie.sh#L2985-L2986), [ralphie.sh:3010](../ralphie.sh#L3010-L3010), [ralphie.sh:3017-3024](../ralphie.sh#L3017-L3024), [ralphie.sh:3053-3069](../ralphie.sh#L3053-L3069)
- **custom-argv (EXTRACTED).** A nonliteral custom command undergoes shell word splitting/pathname expansion, not quoted command-line parsing. File-answer mode does not receive a generic output-path argument from custom engine_build. [ralphie.sh:2544-2549](../ralphie.sh#L2544-L2549), [ralphie.sh:2735-2742](../ralphie.sh#L2735-L2742), [ralphie.sh:2920-2924](../ralphie.sh#L2920-L2924)
- **diagnostic-custody (INFERRED).** Retry/fallback captures are reused; restored first failure reason may point to later output. Generic engine errors avoid echoing raw text, but verbose argv and commit diagnostic tails can still expose values supplied by external programs. [ralphie.sh:2475-2478](../ralphie.sh#L2475-L2478), [ralphie.sh:2840-2849](../ralphie.sh#L2840-L2849), [ralphie.sh:2867-2869](../ralphie.sh#L2867-L2869), [ralphie.sh:2882](../ralphie.sh#L2882-L2882), [ralphie.sh:2921](../ralphie.sh#L2921-L2921), [ralphie.sh:3157](../ralphie.sh#L3157-L3157)
- **no-history-undo (EXTRACTED).** Engine-created unsafe history is rejected after the fact and left in place. Starting HEAD is recorded for recovery, but this range does not create a backup reference, undo changes, or publish anything. [ralphie.sh:1968-1981](../ralphie.sh#L1968-L1981), [ralphie.sh:2211-2215](../ralphie.sh#L2211-L2215), [ralphie.sh:4114-4122](../ralphie.sh#L4114-L4122)
