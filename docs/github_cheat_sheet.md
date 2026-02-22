# Git & GitHub Workflow Cheat Sheet
For feature‑branch development with clean merges into `develop`.

-------------------------------------------------------------------------------
## 1. Check Your Status
```
git status
```
-------------------------------------------------------------------------------
## 2. Create a New Feature Branch
(Always branch from `develop`)
```
git checkout develop
git pull
git checkout -b feature-your-branch-name
git branch -vv
```
-------------------------------------------------------------------------------
## 3. Stage & Commit Changes
(Repeat this step as you work)
```
git add .
git commit -m "Clear, descriptive commit message"
```
-------------------------------------------------------------------------------
## 4. Push Feature Branch to GitHub
(First time with -u, then just git push)
```
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
```
git tag -a milestone/your-tag -m "Description of milestone"
git push origin milestone/your-tag
```
-------------------------------------------------------------------------------
## 8. Return to Develop Locally
```
git checkout develop
git pull
```
-------------------------------------------------------------------------------
## 9. Delete Local Feature Branch (Optional)
(Only after PR is merged)
```
git branch -d feature-your-branch-name
```
-------------------------------------------------------------------------------
## 10. Start the Next Feature Branch
```
git checkout -b feature-next-thing
git status
git branch -vv
```
-------------------------------------------------------------------------------
## 11. The cycle now natually continues at step 3 above.

## Useful Commands

### View Commit History
```
git log --oneline --graph --decorate
```
### Undo Last Commit (keep changes)
```
git reset --soft HEAD~1
```
### Discard Local Changes
```
git restore <file>
```
### Sync Local Branch With Remote
```
git pull
```
### Push All Tags
```
git push --tags
```
-------------------------------------------------------------------------------
## Branch Naming Convention
feature-<short-description>
bugfix-<short-description>
milestone/<name>

-------------------------------------------------------------------------------
## Golden Rules
1. Never develop directly on develop or main.
2. Always merge via PR (never push directly).
3. Keep commits small and descriptive.
4. Tag meaningful milestones.
5. Delete feature branches after merging.

-------------------------------------------------------------------------------
