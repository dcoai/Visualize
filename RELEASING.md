# Releasing Visualize

How a release is cut, and why the steps are shaped the way they are.

This is a maintainer document. It is deliberately **not** in `docs: extras:`, not in the
package `files:` list, and not linked from `README.md` or from anything else that ships — the
README ships in the package and renders as the docs front page, so a link to a file that does
not ship would 404 in the published docs. That is the whole reason this document is kept out
of both lists rather than merely left out of one.

The tool is `~/Projects/claude-tools/release.exs`, and `release.exs --help` carries this same
model in short form. It is project-agnostic; nothing in it is specific to Visualize.

## 1. Two kinds of release, and only one is automated

**Minor** — `v0.2.0`, `v0.3.0`. A judgement call: someone decides the public surface moved.
Always explicit, via `--minor`.

The judgement is about the surface, not the size of the diff. New API, a removed function, or
a tightened contract makes a release a minor however small the change — and this library has
had all three in a week. A patch number promises backwards-compatible fixes only, so a release
that would make `spec/13-decisions.md` gain a **Consequences** paragraph beginning "callers
that…" is a minor.

**Patch** — `v0.1.7`. Not a judgement call at all. The number is a function of the history, so
nobody has to remember what the last one was and two people cannot pick the same one.

## 2. Where the patch number comes from

```
git describe --match 'v[0-9]*.[0-9]*.0' --long   →   v0.1.0-17-gabc1234
                                                               │
                                                         patch = 17  →  v0.1.17
```

`n` is the commit count since the **minor base tag**. The `--match` glob is the whole point:
it selects only `.0` tags.

### 2.1. The trap it avoids

Plain `git describe` counts from the **last** tag, so the count resets at every patch tag:

| history | `git describe` | naive reading |
|---|---|---|
| tag `v0.1.0`, then 5 commits | `v0.1.0-5-g…` | `v0.1.5` ✅ |
| tag `v0.1.5`, then 3 commits | `v0.1.5-3-g…` | `v0.1.3` ❌ **backwards** |

Matching only `.0` tags pins the count to `v0.1.0` however many patch tags sit in between, and
re-bases by itself when `v0.2.0` is opened.

### 2.2. What the numbering promises

- **Monotonic and unique.** Guaranteed.
- **Not dense.** Merge commits count. Every work item lands through a merge request and the
  merge adds a commit of its own, so a single-commit work item advances `n` by two and patch
  numbers skip.
- **Not an invariant of the tagged commit.** The release commit lands *after* the count is
  taken, so `git rev-list --count <base>..<tag>` reads one or two higher than the patch number
  in the tag. Monotonicity is the property that matters; density is not.

Counting `--no-merges` would give a denser number and is deliberately not done: it would no
longer match what `git describe` reports, and `git describe` is what someone types by hand. A
tool and a command that disagree about `n` is a worse trap than a number that skips.

### 2.3. The first tag

There is nothing to count from until a `vX.Y.0` tag exists, and `--minor` cannot help — it
reads the base tag to find the line to open. The first one is cut explicitly:

```bash
elixir ~/Projects/claude-tools/release.exs --version 0.1.0 --tag
```

`v0.1.0` is cut that way (#108, #110). Everything after it is derived.

## 3. The lifecycle

Between releases `mix.exs` reads `X.Y.Z-dev`. The suffix is what keeps a commit from claiming
to be the release it merely follows. The tool moves the `@version` **module attribute** — an
inline `version: "…"` in `project/0` is not found, and the `mix.exs carries @version` gate
*skips* rather than fails on that, so the run would report success and write nothing. That is
why `mix.exs` here declares `@version` at the top of the module.

| Step | What happens | How it lands |
|---|---|---|
| *(work)* | Work items merge to `main` as usual | MR + green pipeline |
| `release.exs` | Dry run: the version it would cut and every gate. Acts on nothing. | — |
| `--prepare` | Writes the version into `mix.exs`, closes `[Unreleased]` → `[X.Y.Z] — date`, points the link reference at the tag, commits | MR |
| *(by hand, in `--prepare`'s MR)* | Bumps the tag in `README.md`'s Installation snippet to the version being cut | same MR |
| `--tag` | Annotated tag on the merged commit, pushes it, creates the GitLab release | direct |
| `--post-bump` | `mix.exs` → `X.Y.(Z+1)-dev`, reopens `[Unreleased]` | MR |

### 3.1. The README's pinned tag is a step, not a memory

`README.md`'s Installation snippet names a tag (`tag: "v0.1.0"`), because the README ships in
`files:` and renders as the docs front page — it is the first thing a consumer copies, and a
snippet saying `branch: "main"` hands them a dependency that takes whatever `main` happens to
be. A placeholder like `tag: "vX.Y.Z"` was rejected for the same reason: what is written is
what gets copied.

A number in prose drifts, so a step owns it. `release.exs` does not touch the README and
should not — it is project-agnostic, and no other project it serves has that snippet. The bump
therefore rides in `--prepare`'s merge request, beside the `mix.exs` version and the closed
changelog section, where a reviewer sees the three move together. Nothing enforces it
mechanically; the table above is the record that it is a step.

### 3.2. Why `--prepare` and `--tag` are separate

This looks like ceremony and is not. The tag must point at a commit that **carries** the
version: a tag on a tree still reading `-dev` is worse than no tag, because the artefact then
disagrees with the ref that names it. But `main` is protected behind the merge gate, so that
version commit cannot be pushed to it directly. Hence: commit → merge → tag the merge commit.
One tool invocation cannot span a merge request, so it is two.

### 3.3. Tag the commit whose own pipeline is green

The `--tag` gate asks the GitLab API for the newest pipeline on `HEAD`'s **sha**, not on a ref.
Under a squash-and-merge the run that proved the work sits on a branch ref that
`--remove-source-branch` has since deleted, and a push to `main` may create no pipeline at all;
`?ref=main` finds nothing, or finds a stale run of an earlier commit. Asking by sha finds the
pipeline that ran on *this object*, whatever ref it ran under — a stronger claim than "main was
green", not a weaker one. So: **wait for the merge commit's pipeline before tagging.**

The newest run wins, a scheduled one included. A nightly that failed on the same commit is the
latest word on it, and refusing to release on that is the gate working; the line names the run
(id, source, ref) so a red nightly can be told from a red branch build.

## 4. The gates

All six are reported together rather than failing at the first, so one dry run lists everything
that needs fixing:

```
[PASS] working tree clean
[PASS] patch number is not zero
[PASS] tag v0.1.7 does not exist
[FAIL] HEAD pipeline is green          ← via the GitLab API, on HEAD's sha
[PASS] CHANGELOG has a release entry   ← [Unreleased], or [X.Y.Z] after --prepare
[PASS] mix.exs carries @version
```

`--tag` additionally prompts before acting, because a tag is permanent. The escapes are
`--no-ci-check`, `--no-changelog`, `--no-push` and `--yes`; each one removes evidence, so
reach for it only when you can say what stands in its place.

These are the *release* gates. They sit on top of, and do not replace, the eleven gates every
change already passes — `mix vis.check`, which is the local mirror of `.gitlab-ci.yml` in CI's
order and must print `vis.check: every gate green`. The pipeline gate above is what connects
the two: it is how a tag inherits the evidence of `vis.check` rather than restating it.

## 5. When an entry gets written: at the change, not at the release

**A merge that changes behaviour or the public surface writes its `[Unreleased]` entry in the
same merge request.** What changed and why it matters is not derivable from the diff, and it is
least derivable months later, which is exactly when a release would be assembling it.

A change with nothing to say to anyone outside the repository — a pure refactor, an internal
rename, a regenerated golden — writes nothing, and says so in the commit message rather than
silently:

```
Changelog-none: internal rename, no behaviour or API change
```

The reason goes in the commit message so it lands in the history beside the diff, where a
reviewer reads it.

This is a convention here, not yet a CI job. ExTLA enforces the same rule with a `changelog`
job in its `check` stage (`bin/changelog_guard.exs`), which compares the merge base against the
branch and fails when `lib/` moved and `CHANGELOG.md` did not, honouring the `Changelog-none:`
trailer. Porting it is the obvious next step and wants its own proposal; until then, the
`[0.1.0]` entry stands as the demonstration of what the section is for, and the release gate
that refuses an empty entry is the only mechanical backstop.

## 6. What stays a human decision

- **The CHANGELOG content.** The tool closes a section; it never writes one, and an empty entry
  is refused. This is the argument for §5: write it while the work is in hand.
- **Minor versus patch.** `--minor` is always explicit.
- **A minor's tag message.** Patch tags take the changelog section automatically; a minor's is
  written by hand.
- **Publishing to Hex.** Since 0.2.1 (#516) every release is published, as the last step
  of §7. A published version is permanent: it can be reverted only within an hour, and a
  consumer may have fetched it before then. So `mix hex.publish` runs only with the
  maintainer's explicit go-ahead for that version, never as a side effect of tagging.
  `mix hex.build` beforehand shows exactly what will ship.
- **The public home.** <https://github.com/dcoai/Visualize> is a GitLab **push mirror** of
  the protected branches and the tags (Settings → Repository → Mirroring repositories,
  authenticated by a fine-grained GitHub token with Contents read/write on that repository
  only). The package's `source_url`, its links and the README's issue link point there,
  and the docs' `source_ref` is the version's tag, so the tag must have reached GitHub
  before the docs are read. **The token expires.** When it does, the mirror stops without
  failing any pipeline. Check GitHub's main against GitLab's before a publish.

## 7. A release, end to end

```bash
elixir ~/Projects/claude-tools/release.exs               # says v0.1.<n>, checks the gates
elixir ~/Projects/claude-tools/release.exs --prepare     # then MR that commit and merge it
elixir ~/Projects/claude-tools/release.exs --tag         # on main, at the merged commit
elixir ~/Projects/claude-tools/release.exs --post-bump   # then MR that commit too
```

Then publish the tag, with the go-ahead (§6), from a clean checkout of it:

```bash
git ls-remote https://github.com/dcoai/Visualize.git refs/tags/v<X.Y.Z>   # the mirror has it
git worktree add --detach ../visualize-publish v<X.Y.Z> && cd ../visualize-publish
mix deps.get && mix hex.build      # read the file list and the dependencies
mix hex.publish                    # the package and its docs, to hexdocs.pm
```

Opening a new minor line is the same sequence with `--minor` on every invocation.

## 8. History

- **v0.1.0** — the first tag (#108, #110), across ten completed milestones: the repository foundation, the
  scale and shape correctness sweeps, the metresis dashboard marks, the rendering follow-ons,
  the declarative chart layer, client-side interaction, and the fragment algebra and builder.
