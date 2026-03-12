#!/bin/bash
# Generate a Git commit message using Claude CLI

staged_check=$(git diff --cached --name-status)
if [ -z "$staged_check" ]; then
  echo "No staged changes"
  exit 1
fi

{
  echo "Staged files (git diff --cached --name-status):"
  echo "$staged_check"
  echo ""
  echo "Staged summary (git diff --cached --stat --summary):"
  git diff --cached --stat --summary
  echo ""
  echo "Staged patch (git diff --cached --unified=0):"
  git diff --cached --unified=0 --minimal
} | claude --no-session-persistence --print --tools "" --effort low \
  "Generate ONLY a one-line Git commit message in Japanese. Base it strictly on the staged diff supplied via stdin. Prefer the actual code changes over filenames. Do not add quotes, bullets, explanations, or a body. Output ONLY the commit summary line."
