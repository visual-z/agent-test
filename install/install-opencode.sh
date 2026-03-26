#!/usr/bin/env bash
# install-opencode.sh — Install agent-test for OpenCode
# Usage: bash install/install-opencode.sh [--project|--global|--uninstall]
set -euo pipefail

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
RESET='\033[0m'

# ── Helpers ───────────────────────────────────────────────────────────────────
info()    { printf "${BLUE}[info]${RESET}  %s\n" "$*"; }
success() { printf "${GREEN}[ok]${RESET}    %s\n" "$*"; }
warn()    { printf "${YELLOW}[warn]${RESET}  %s\n" "$*"; }
error()   { printf "${RED}[error]${RESET} %s\n" "$*" >&2; }
die()     { error "$*"; exit 1; }

# ── Resolve source directory (repo root containing this script) ───────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Verify repo structure exists
for required in skills prompts reference; do
    [ -d "$REPO_ROOT/$required" ] || die "Missing directory: $REPO_ROOT/$required — are you running from the agent-test repo?"
done

# ── Parse arguments ───────────────────────────────────────────────────────────
MODE=""
UNINSTALL=false

for arg in "$@"; do
    case "$arg" in
        --project) MODE="project" ;;
        --global)  MODE="global" ;;
        --uninstall) UNINSTALL=true ;;
        --help|-h)
            printf "Usage: %s [--project|--global|--uninstall]\n" "$(basename "$0")"
            printf "\n"
            printf "Options:\n"
            printf "  --project    Install into .opencode/ in the current project\n"
            printf "  --global     Install into ~/.config/opencode/ for all projects\n"
            printf "  --uninstall  Remove agent-test from both project and global locations\n"
            printf "  --help       Show this help message\n"
            exit 0
            ;;
        *) die "Unknown argument: $arg (use --help for usage)" ;;
    esac
done

# ── Uninstall ─────────────────────────────────────────────────────────────────
if [ "$UNINSTALL" = true ]; then
    printf "\n${BOLD}Uninstalling agent-test...${RESET}\n\n"
    removed=0

    # Project-level
    if [ -f ".opencode/plugins/monkey-test-loop.ts" ]; then
        rm -f ".opencode/plugins/monkey-test-loop.ts"
        success "Removed .opencode/plugins/monkey-test-loop.ts"
        removed=$((removed + 1))
    fi
    if [ -d ".opencode/skills/monkey-test" ]; then
        rm -rf ".opencode/skills/monkey-test"
        success "Removed .opencode/skills/monkey-test/"
        removed=$((removed + 1))
    fi

    # Global
    if [ -f "$HOME/.config/opencode/plugins/monkey-test-loop.ts" ]; then
        rm -f "$HOME/.config/opencode/plugins/monkey-test-loop.ts"
        success "Removed ~/.config/opencode/plugins/monkey-test-loop.ts"
        removed=$((removed + 1))
    fi
    if [ -d "$HOME/.config/opencode/skills/monkey-test" ]; then
        rm -rf "$HOME/.config/opencode/skills/monkey-test"
        success "Removed ~/.config/opencode/skills/monkey-test/"
        removed=$((removed + 1))
    fi

    if [ "$removed" -eq 0 ]; then
        warn "Nothing to uninstall — agent-test was not found in project or global locations."
    else
        success "Uninstall complete ($removed items removed)."
    fi
    exit 0
fi

# ── Detect project context ───────────────────────────────────────────────────
is_project=false
if [ -d ".opencode" ] || [ -f "opencode.json" ] || [ -f "package.json" ] || [ -f "Cargo.toml" ] || [ -f "go.mod" ] || [ -f "pyproject.toml" ]; then
    is_project=true
fi

# ── Prompt for install mode if not specified ──────────────────────────────────
if [ -z "$MODE" ]; then
    printf "\n${BOLD}agent-test installer for OpenCode${RESET}\n\n"

    if [ "$is_project" = true ]; then
        info "Detected project directory: $(pwd)"
        printf "\n"
        printf "  1) ${BOLD}Project-level${RESET}  — Install into .opencode/ in this project\n"
        printf "  2) ${BOLD}Global${RESET}          — Install into ~/.config/opencode/ for all projects\n"
        printf "\n"
        printf "Choose [1/2]: "
        read -r choice
        case "$choice" in
            1|project) MODE="project" ;;
            2|global)  MODE="global" ;;
            *) die "Invalid choice: $choice" ;;
        esac
    else
        warn "No project detected in current directory."
        info "Installing globally to ~/.config/opencode/"
        MODE="global"
    fi
fi

# ── Set target directories ───────────────────────────────────────────────────
if [ "$MODE" = "project" ]; then
    PLUGIN_DIR=".opencode/plugins"
    SKILL_DIR=".opencode/skills/monkey-test"
    PKG_DIR=".opencode"
    DISPLAY_PREFIX=".opencode"
else
    PLUGIN_DIR="$HOME/.config/opencode/plugins"
    SKILL_DIR="$HOME/.config/opencode/skills/monkey-test"
    PKG_DIR="$HOME/.config/opencode"
    DISPLAY_PREFIX="~/.config/opencode"
fi

# ── Check prerequisites ──────────────────────────────────────────────────────
if ! command -v jq >/dev/null 2>&1; then
    warn "jq is not installed. The Ralph Loop harness uses jq to parse state files."
    warn "Install it: brew install jq (macOS) or apt install jq (Linux)"
    printf "Continue anyway? [y/N]: "
    read -r proceed
    case "$proceed" in
        y|Y|yes) ;;
        *) die "Aborted. Install jq and re-run." ;;
    esac
fi

# ── Install ───────────────────────────────────────────────────────────────────
printf "\n${BOLD}Installing agent-test (${MODE})...${RESET}\n\n"

# 1. Plugin file
info "Installing plugin file..."
mkdir -p "$PLUGIN_DIR"

if [ -f "$REPO_ROOT/plugins/opencode/index.ts" ]; then
    cp "$REPO_ROOT/plugins/opencode/index.ts" "$PLUGIN_DIR/monkey-test-loop.ts"
    success "Copied index.ts -> monkey-test-loop.ts"
else
    warn "plugins/opencode/index.ts not found in repo — skipping"
fi

# 2. Merge or copy package.json
if [ -f "$REPO_ROOT/plugins/opencode/package.json" ]; then
    if [ -f "$PKG_DIR/package.json" ]; then
        info "Existing package.json found at $PKG_DIR/package.json — merging dependencies..."
        if command -v jq >/dev/null 2>&1; then
            # Merge: take existing as base, overlay dependencies from monkey-test
            EXISTING="$PKG_DIR/package.json"
            INCOMING="$REPO_ROOT/plugins/opencode/package.json"
            MERGED=$(jq -s '
                .[0] as $existing |
                .[1] as $incoming |
                $existing *
                { dependencies: (($existing.dependencies // {}) * ($incoming.dependencies // {})) } *
                { devDependencies: (($existing.devDependencies // {}) * ($incoming.devDependencies // {})) }
            ' "$EXISTING" "$INCOMING")
            printf '%s\n' "$MERGED" > "$PKG_DIR/package.json"
            success "Merged package.json dependencies"
        else
            warn "Cannot merge without jq — copying as package.json.monkey-test for manual merge"
            cp "$REPO_ROOT/plugins/opencode/package.json" "$PKG_DIR/package.json.monkey-test"
            success "Copied package.json.monkey-test (merge manually)"
        fi
    else
        mkdir -p "$PKG_DIR"
        cp "$REPO_ROOT/plugins/opencode/package.json" "$PKG_DIR/package.json"
        success "Copied package.json"
    fi
else
    warn "plugins/opencode/package.json not found in repo — skipping"
fi

# 3. Skill files — copy entire skill tree preserving structure
info "Installing skill files..."
mkdir -p "$SKILL_DIR"

# Copy root SKILL.md (main orchestrator)
if [ -f "$REPO_ROOT/SKILL.md" ]; then
    cp "$REPO_ROOT/SKILL.md" "$SKILL_DIR/SKILL.md"
    success "Copied SKILL.md (orchestrator)"
fi

# Copy skills/ subdirectories
for skill_dir in "$REPO_ROOT"/skills/*/; do
    if [ -d "$skill_dir" ]; then
        skill_name="$(basename "$skill_dir")"
        mkdir -p "$SKILL_DIR/skills/$skill_name"
        cp -R "$skill_dir"* "$SKILL_DIR/skills/$skill_name/" 2>/dev/null || true
        success "Copied skills/$skill_name/"
    fi
done

# Copy prompts/
mkdir -p "$SKILL_DIR/prompts"
for prompt_file in "$REPO_ROOT"/prompts/*; do
    if [ -f "$prompt_file" ]; then
        cp "$prompt_file" "$SKILL_DIR/prompts/"
    fi
done
success "Copied prompts/"

# Copy reference/
mkdir -p "$SKILL_DIR/reference"
for ref_file in "$REPO_ROOT"/reference/*; do
    if [ -f "$ref_file" ]; then
        cp "$ref_file" "$SKILL_DIR/reference/"
    fi
done
success "Copied reference/"

# ── Auto-discovery note ──────────────────────────────────────────────────────
# OpenCode automatically discovers plugins from {plugin,plugins}/*.{ts,js}
# inside .opencode/ directories. No manual registration is needed.
# OpenCode also auto-installs @opencode-ai/plugin dependency on startup
# when it detects the .opencode/ directory has a package.json.
info "Plugin will be auto-discovered by OpenCode from: $PLUGIN_DIR/monkey-test-loop.ts"

# ── Summary ───────────────────────────────────────────────────────────────────
printf "\n${GREEN}${BOLD}Installation complete!${RESET}\n\n"

printf "Installed to:\n"
printf "  Plugin:  ${BOLD}%s/plugins/monkey-test-loop.ts${RESET}\n" "$DISPLAY_PREFIX"
printf "  Skills:  ${BOLD}%s/skills/monkey-test/${RESET}\n" "$DISPLAY_PREFIX"

printf "\n${BOLD}Installed files:${RESET}\n"

# Count installed files
file_count=0
if [ -f "$PLUGIN_DIR/monkey-test-loop.ts" ]; then
    file_count=$((file_count + 1))
fi
if [ -d "$SKILL_DIR" ]; then
    skill_count=$(find "$SKILL_DIR" -type f | wc -l | tr -d ' ')
    file_count=$((file_count + skill_count))
fi
printf "  %s files total\n" "$file_count"

printf "\n${BOLD}Usage:${RESET}\n"
printf "  1. Open OpenCode in your project\n"
printf "  2. Say: ${BLUE}Run agent test on this project${RESET}\n"
printf "  3. The agent will discover routes, ask you which to test, and begin\n"
printf "  4. The Ralph Loop plugin keeps it running autonomously\n"

printf "\n${BOLD}Configuration:${RESET}\n"
printf "  The agent will ask for base_url, credentials, and batch size at startup.\n"
printf "  Set safe_to_mutate=true only if destructive UI actions are acceptable.\n"

if [ "$MODE" = "project" ]; then
    printf "\n${YELLOW}Tip:${RESET} Add .opencode/plugins/ and .opencode/skills/ to .gitignore\n"
    printf "     if you don't want to commit the agent-test plugin.\n"
fi

printf "\n"
