# Git & GitHub Workflow Cheat Sheet

For feature‑branch development with clean merges into `develop`.

-------------------------------------------------------------------------------

## 1. Check Your Status

```bash
git status
```

-------------------------------------------------------------------------------

## 2. Create a New Feature Branch

(Always branch from `develop`)

```bash
git checkout develop
git pull
git checkout -b feature-your-branch-name
git branch -vv
```

-------------------------------------------------------------------------------

## 3. Stage & Commit Changes

(Repeat this step as you work)

```bash
git add .
git commit -m "Clear, descriptive commit message"
```

-------------------------------------------------------------------------------

## 4. Push Feature Branch to GitHub

(First time with -u, then just git push)

```bash
git push -u origin feature-your-branch-name
Later:
git push
```

-------------------------------------------------------------------------------

## 5. Create a Pull Request (PR)

On GitHub:

- Open your repo
- Switch to your feature branch
- Click “Compare & pull request”
- Target branch: develop
- Submit PR

-------------------------------------------------------------------------------

## 6. Merge the PR

On GitHub:

- Review PR
- Click “Merge pull request”
- Confirm merge
- (Optional) Delete branch on GitHub

-------------------------------------------------------------------------------

## 7. Tag a Milestone (Optional)

```bash
git tag -a milestone/your-tag -m "Description of milestone"
git push origin milestone/your-tag
```

-------------------------------------------------------------------------------

## 8. Return to Develop Locally

```bash
git checkout develop
git pull
```

-------------------------------------------------------------------------------

## 9. Delete Local Feature Branch (Optional)

(Only after PR is merged)

```bash
git branch -d feature-your-branch-name
```

-------------------------------------------------------------------------------

## 10. Start the Next Feature Branch

```bash
git checkout -b feature-next-thing
git status
git branch -vv
```

-------------------------------------------------------------------------------

## 11. The cycle now natually continues at step 3 above

## Useful Commands

### View Commit History

```bash
git log --oneline --graph --decorate
```

### Undo Last Commit (keep changes)

```bash
git reset --soft HEAD~1
```

### Discard Local Changes

```bash
git restore <file>
```

### Sync Local Branch With Remote

```bash
git pull
```

### Push All Tags

```bash
git push --tags
```

-------------------------------------------------------------------------------

## Branch Naming Convention

- `feature-<short-description>`
- `bugfix-<short-description>`
- `milestone/<name>`

-------------------------------------------------------------------------------

## Golden Rules

1. Never develop directly on develop or main.
2. Always merge via PR (never push directly).
3. Keep commits small and descriptive.
4. Tag meaningful milestones.
5. Delete feature branches after merging.

-------------------------------------------------------------------------------

## Git Rollback Strategies (Milestone Commits)

When you reach a known‑good commit (example: `ed1ca76`) and need to return to it later, use one of the following rollback strategies.

-------------------------------------------------------------------------------

## 1. Restore working tree to a past commit  

*Use when you want to undo file changes but keep your branch history intact.*

```bash
git checkout ed1ca76 -- .
```

- Safest option during development  
- Restores files only  
- Does **not** move the branch pointer  

-------------------------------------------------------------------------------

## 2. Hard‑reset the branch to a past commit  

*Use only when you want to discard later commits entirely.*

```bash
git reset --hard ed1ca76
```

- Moves branch pointer  
- Resets working tree  
- Permanently removes commits after `ed1ca76`  

-------------------------------------------------------------------------------

## 3. Create a new branch from the known‑good commit  

*Use when you want to preserve current work but branch off the stable point.*

```bash
git checkout -b rescue-transient-10 ed1ca76
```

- Keeps all existing commits  
- Creates a clean branch starting at the milestone  
- Ideal for experimentation or recovery  

-------------------------------------------------------------------------------

## When to Use Each

```text
| Situation | Best Command |
|-----------|--------------|
| “I messed up some files but want to keep my commits.” | `git checkout ed1ca76 -- .` |
| “I want to completely rewind the branch to the milestone.” | `git reset --hard ed1ca76` |
| “I want a clean branch from the milestone but keep my current work too.” | `git checkout -b rescue-transient-10 ed1ca76` |
```

-------------------------------------------------------------------------------

## Recommended Default for Your Workflow

Since you use disciplined milestone commits on feature branches:

**Preferred rollback:**

```bash
git checkout ed1ca76 -- .
```

This restores your project to the exact known‑good state without touching history.
