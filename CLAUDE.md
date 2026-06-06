# CLAUDE.md

Project instructions for AI agents (Claude Code) working in this repository.

## About this project

This is Seb's **personal website** — a small Next.js app living in `front/`.
It was bootstrapped with `create-next-app` and uses TypeScript, Tailwind CSS,
and shadcn/ui components. Pages include the home page plus `bio`, `projects`,
`blog`, and `software`, with a small CMS/constants layer and a markdown renderer.

There is currently **no in-repo CI/CD** (no GitHub Actions workflows, no
`vercel.json`). If the site is deployed, it is via Vercel's dashboard Git
integration (auto-deploy on push), which lives outside this repository.

## How I want agents to behave

### Small changes: just push

When I ask for a **small change**, don't stop to ask for confirmation before
shipping it. Make the change, commit it with a clear message, and push it.
"Just push it" is standing permission for small, low-risk edits.

What counts as small/low-risk (push without asking):
- Copy/text tweaks, typo fixes, styling and layout adjustments
- Content updates (bio, projects, blog, etc.)
- Small component or config edits that don't change app behavior broadly

When to pause and check with me first (don't auto-push):
- Anything that deletes significant content or files
- Dependency upgrades, build/config overhauls, or infra/deployment changes
- Anything touching secrets, auth, or the API route
- Large refactors or anything you're genuinely unsure about

### Git: pushing is committing, and history is preserved

Every push is built on commits. Pushing **never** rewrites or discards the
project's history — each change is a new commit stacked on top of the previous
ones, and the full git history is always retained. Do not force-push or rewrite
history on shared branches.

### Commit messages

Keep them short and descriptive — say what changed and why in plain language.

### Pull requests

Do **not** open a pull request unless I explicitly ask for one. Default to
committing and pushing to the working branch.
