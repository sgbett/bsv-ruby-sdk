<!-- vendored from sgbett/dotfiles-claude profiles/git-workflow/setup.md -->
<!-- profiles/git-workflow/setup.md — one-time setup and apply procedure for the git-workflow enforcement assets -->

# Git workflow: setup

This runbook covers a collaborator's one-time setup and the procedure an admin follows to apply the enforcement assets to a repository. It does not restate the rules: those are the profile's, `profiles/git-workflow.md` in sgbett/dotfiles-claude, vendored as `.claude/rules/git-workflow.md`. For the rebase procedure, see the profile's "Keeping a branch current" line.

## What is here

| File | What it is | Where it goes |
| --- | --- | --- |
| `ruleset.json` | Body of the ruleset request that binds the default branch | Not vendored; applied by an admin |
| `repository.json` | Body of the repository-settings request that fixes the merge methods | Not vendored; applied by an admin |
| `hooks/push-guard`, `hooks/push-guard.rb` | The push-guard hook, a `PreToolUse` hook on the agent's Bash commands | Copied to the repository's `.claude/hooks/` |
| `hooks.json` | The hook's `PreToolUse` entry | Merged into the repository's `.claude/settings.json` |
| `setup.md` | This file | The repository's contributor docs, for example `docs/` |

Every vendored copy carries a first line (or first comment line, for a script) reading `vendored from sgbett/dotfiles-claude <path>`, for example `vendored from sgbett/dotfiles-claude profiles/git-workflow/hooks/push-guard`. The rules text's two-line header in `.claude/rules/git-workflow.md` is the same convention. Change the source first, then every copy.

This file is vendored into contributor docs, never into `.claude/rules/`, which loads into every agent session.

## A collaborator's one-time setup

Three global git settings:

```sh
git config --global pull.rebase true
git config --global push.useForceIfIncludes true
git config --global rebase.autoStash true
```

- `pull.rebase true`: a `git pull` rebases your branch instead of creating a merge from the base.
- `push.useForceIfIncludes true`: a lease push also checks that the remote tip was seen locally, so a background fetch cannot defeat the lease.
- `rebase.autoStash true`: a rebase over a dirty tree stashes your changes and restores them afterwards.

Then the trust dialog: the first interactive Claude Code session in the checkout asks whether to trust the workspace and lists the project's hooks. The push-guard hook is what it lists.

## The push-guard hook, what it is and is not

The hook reads the literal text of each Bash command the agent runs. It denies a bare force-push, and any force or deletion aimed at a base branch (`master`, `project/*`, `releases/*`); it asks before a lease push to a branch another author has commits on; otherwise it says nothing. It reads only what the Bash tool is given: a push inside a script, a Makefile or a git alias, a ref update through the GitHub API, or a word it cannot see in the text (`pu''sh`, an escaped or quoted word) is invisible to it, so the hook guards habit and the default branch's ruleset is the server-side control. Project and release branches have the hook alone until a repository adds a ruleset for them.

The hook runs code from the checkout on every Bash command, so collaborators review it as they would any code in the repository before trusting the workspace, and review the `.claude/` part of a pull request's diff before checking that branch out, since the next Bash command runs whatever `push-guard` the branch carries. A collaborator who prefers not to run code from the checkout can point a user-level `PreToolUse` hook at a copy of the two files kept outside it.

## Applying the template to a repository (admin)

Run these from `profiles/git-workflow/` in a checkout of sgbett/dotfiles-claude, replacing `OWNER/REPO`, in this order.

**Repository settings first.** Merge methods and the update-branch button; squash goes off and merge commits on in one request, so no intermediate state has neither.

```sh
gh api -X PATCH repos/OWNER/REPO --input repository.json
```

**Create the ruleset.** It binds the default branch, whatever its name.

```sh
gh api -X POST repos/OWNER/REPO/rulesets --input ruleset.json
```

To update an existing ruleset instead, look up its id, then replace it whole: a `PUT` does not merge.

```sh
gh api repos/OWNER/REPO/rulesets
gh api -X PUT repos/OWNER/REPO/rulesets/ID --input ruleset.json
```

**Check the effective rules.** Confirm `pull_request`, `non_fast_forward` and `deletion` are listed before going on.

```sh
gh api repos/OWNER/REPO/rules/branches/master
```

**Remove a classic branch protection, only where one exists and adds nothing the template lacks** (no required reviews, status checks or push restrictions). Deletion is irreversible. A ruleset and a classic protection coexist, so with the ruleset created first there is no unprotected window.

```sh
gh api -X DELETE repos/OWNER/REPO/branches/master/protection
```

Why the template is shaped as it is:

- No bypass actors: an admin bypass exempts the account the agent pushes as, which is what the rule exists to bind.
- `require_extra_approval_for_unattributed_changes` false, said outright: GitHub fills it with true when it is left out, and with no required approvals a commit whose author maps to no GitHub account would then need an approval a sole owner cannot give.
- No `required_status_checks`: each repository's CI ruleset is its own.
- Never `required_linear_history` on the default branch: on GitHub it bans merge commits.
- `~DEFAULT_BRANCH` rather than a branch name: the rule survives a rename, and a repository still on `main` is covered.

Rulesets on a private repository need a paid plan. The `git-settings audit` script under the `repo-consistency` skill in sgbett/dotfiles-claude reports what differs from the template.

## Releases

A version bump is a change like any other and lands by PR. The tag is pushed directly afterwards, since branch rules do not target tags; nothing here stops a tag being moved or deleted, which a tag ruleset would.
