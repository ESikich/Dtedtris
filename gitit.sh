#!/bin/bash

# -------- CONFIGURATION --------
GITHUB_REMOTE_URL="https://github.com/ESikich/Dtedtris.git"
REMOTE_BRANCH="main"  # or 'master' if needed
LOCAL_BRANCH="local-code"
# --------------------------------

# Allow passing GitHub URL as an argument
if [ ! -z "$1" ]; then
  GITHUB_REMOTE_URL="$1"
fi

echo "Using GitHub remote URL: $GITHUB_REMOTE_URL"

# Initialize Git repo if not already
if [ ! -d ".git" ]; then
  echo "Initializing Git repository..."
  git init || { echo "Failed to initialize git"; exit 1; }
fi

# Add remote if not already added
if ! git remote get-url origin &>/dev/null; then
  echo "Adding remote origin..."
  git remote set-url origin https://github.com/ESikich/Dtedtris.git || { echo "Failed to set remote"; exit 1; }
  echo "Remote origin already set."
fi

# Fetch remote branch
echo "Fetching from remote..."
git fetch origin || { echo "Failed to fetch remote"; exit 1; }

# Create local branch from current state (backup)
echo "Creating backup branch '$LOCAL_BRANCH'..."
git checkout -b "$LOCAL_BRANCH" || git checkout "$LOCAL_BRANCH"

# Switch to remote branch and merge
echo "Checking out remote branch '$REMOTE_BRANCH'..."
git checkout "$REMOTE_BRANCH" 2>/dev/null || git checkout -b "$REMOTE_BRANCH" origin/"$REMOTE_BRANCH"

echo "Merging your local code into '$REMOTE_BRANCH'..."
git merge "$LOCAL_BRANCH" --no-edit || {
  echo "Merge failed. Please resolve conflicts manually.";
  exit 1;
}

# Show status and prompt to push
git status

read -p "Push merged code to GitHub? (y/n): " CONFIRM
if [[ "$CONFIRM" == "y" ]]; then
  echo "Pushing to GitHub..."
  git push origin "$REMOTE_BRANCH" || { echo "Push failed"; exit 1; }
else
  echo "Push skipped."
fi

echo "✅ Merge completed."
