#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counter
SUCCESS=0
FAILED=0
FAILED_REPOS=()

# Directory where all repos are
BACK_DIR="${1:-.}"

echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"
echo -e "${BLUE}Starting git pull for all repositories${NC}"
echo -e "${BLUE}Working directory: $BACK_DIR${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════${NC}\n"

# Loop through all directories
for repo in $(ls -d */ 2>/dev/null); do
    repo=${repo%/}  # Remove trailing slash

    # Skip 'out' directory if it exists
    if [ "$repo" = "out" ]; then
        continue
    fi

    echo -e "${YELLOW}→ Updating: $repo${NC}"

    if [ -d "$repo/.git" ]; then
        cd "$repo"

        # Get current branch
        current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)

        # Try to pull
        if git pull 2>&1 | grep -q "Already up to date\|Fast-forward"; then
            echo -e "${GREEN}  ✓ Success ($current_branch)${NC}\n"
            ((SUCCESS++))
        else
            pull_output=$(git pull 2>&1)
            if echo "$pull_output" | grep -q "fatal\|error"; then
                echo -e "${RED}  ✗ Failed ($current_branch)${NC}"
                echo -e "${RED}  Error: $(echo $pull_output | head -1)${NC}\n"
                ((FAILED++))
                FAILED_REPOS+=("$repo")
            else
                echo -e "${GREEN}  ✓ Success ($current_branch)${NC}\n"
                ((SUCCESS++))
            fi
        fi

        cd ..
    else
        echo -e "${RED}  ✗ Not a git repository${NC}\n"
        ((FAILED++))
        FAILED_REPOS+=("$repo")
    fi
done

# Summary
echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"
echo -e "${GREEN}✓ Successful: $SUCCESS${NC}"
echo -e "${RED}✗ Failed: $FAILED${NC}"

if [ $FAILED -gt 0 ]; then
    echo -e "\n${RED}Failed repositories:${NC}"
    for failed_repo in "${FAILED_REPOS[@]}"; do
        echo -e "  ${RED}• $failed_repo${NC}"
    done
fi

echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"
