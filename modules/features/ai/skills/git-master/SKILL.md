---
name: git-master
description: Git operations and workflow patterns
globs:
  - ".git/**"
  - ".gitignore"
  - ".gitattributes"
---

# Git Master Skill

Expert knowledge for git operations in this repository.

## Branch Strategy

- `main` - Production branch
- `develop` - Development branch
- Feature branches from develop

## Commit Conventions

- Use conventional commits: `feat:`, `fix:`, `chore:`, `docs:`, `refactor:`
- Keep commits atomic and focused
- Write meaningful commit messages

## Common Operations

```bash
# Check status
git status

# Stage and commit
git add -A && git commit -m "type: description"

# Create feature branch
git checkout -b feature/name develop

# Rebase on develop
git fetch origin && git rebase origin/develop
```

## Protected Files

- Never commit secrets or `.env` files
- Check `.gitignore` before adding new file types
