#!/usr/bin/env bash
# install-claude-code.sh — Install agent-test for Claude Code
# Usage: bash install/install-claude-code.sh [--project|--global|--uninstall]
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
for required in skills prompts reference plugins/claude-code; do
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
            printf "  --project    Install into .claude/ in the current project\n"
            printf "  --global     Install into ~/.claude/ for all projects\n"
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
    if [ -d ".claude/plugins/monkey-test" ]; then
        rm -rf ".claude/plugins/monkey-test"
        success "Removed .claude/plugins/monkey-test/"
        removed=$((removed + 1))
    fi
    if [ -d ".claude/skills/monkey-test" ]; then
        rm -rf ".claude/skills/monkey-test"
        success "Removed .claude/skills/monkey-test/"
        removed=$((removed + 1))
    fi

    # Global
    if [ -d "$HOME/.claude/plugins/monkey-test" ]; then
        rm -rf "$HOME/.claude/plugins/monkey-test"
        success "Removed ~/.claude/plugins/monkey-test/"
        removed=$((removed + 1))
    fi
    if [ -d "$HOME/.claude/skills/monkey-test" ]; then
        rm -rf "$HOME/.claude/skills/monkey-test"
        success "Removed ~/.claude/skills/monkey-test/"
        removed=$((removed + 1))
    fi

    if [ "$removed" -eq 0 ]; then
        warn "Nothing to uninstall — agent-test was not found in project or global locations."
    else
        success "Uninstall complete ($removed directories removed)."
    fi
    exit 0
fi

# ── Detect project context ───────────────────────────────────────────────────
is_project=false
if [ -d ".claude" ] || [ -f "package.json" ] || [ -f "Cargo.toml" ] || [ -f "go.mod" ] || [ -f "pyproject.toml" ] || [ -f "Makefile" ]; then
    is_project=true
fi

# ── Prompt for install mode if not specified ──────────────────────────────────
if [ -z "$MODE" ]; then
    printf "\n${BOLD}agent-test installer for Claude Code${RESET}\n\n"

    if [ "$is_project" = true ]; then
        info "Detected project directory: $(pwd)"
        printf "\n"
        printf "  1) ${BOLD}Project-level${RESET}  — Install into .claude/ in this project\n"
        printf "  2) ${BOLD}Global${RESET}          — Install into ~/.claude/ for all projects\n"
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
        info "Installing globally to ~/.claude/"
        MODE="global"
    fi
fi

# ── Set target directories ───────────────────────────────────────────────────
if [ "$MODE" = "project" ]; then
    PLUGIN_DIR=".claude/plugins/monkey-test"
    SKILL_DIR=".claude/skills/monkey-test"
    DISPLAY_PREFIX=".claude"
else
    PLUGIN_DIR="$HOME/.claude/plugins/monkey-test"
    SKILL_DIR="$HOME/.claude/skills/monkey-test"
    DISPLAY_PREFIX="~/.claude"
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

# 1. Plugin files (official plugin format: .claude-plugin/plugin.json at root)
info "Installing plugin files..."
mkdir -p "$PLUGIN_DIR/.claude-plugin"
mkdir -p "$PLUGIN_DIR/hooks"
mkdir -p "$PLUGIN_DIR/scripts"
mkdir -p "$PLUGIN_DIR/skills"

if [ -f "$REPO_ROOT/plugins/claude-code/.claude-plugin/plugin.json" ]; then
    cp "$REPO_ROOT/plugins/claude-code/.claude-plugin/plugin.json" "$PLUGIN_DIR/.claude-plugin/plugin.json"
    success "Copied .claude-plugin/plugin.json (manifest)"
else
    warn ".claude-plugin/plugin.json not found in repo — skipping"
fi

if [ -f "$REPO_ROOT/plugins/claude-code/hooks/hooks.json" ]; then
    cp "$REPO_ROOT/plugins/claude-code/hooks/hooks.json" "$PLUGIN_DIR/hooks/hooks.json"
    success "Copied hooks/hooks.json"
else
    warn "hooks/hooks.json not found in repo — skipping"
fi

if [ -f "$REPO_ROOT/plugins/claude-code/scripts/ralph-loop.sh" ]; then
    cp "$REPO_ROOT/plugins/claude-code/scripts/ralph-loop.sh" "$PLUGIN_DIR/scripts/ralph-loop.sh"
    chmod +x "$PLUGIN_DIR/scripts/ralph-loop.sh"
    success "Copied scripts/ralph-loop.sh (executable)"
else
    warn "scripts/ralph-loop.sh not found in repo — skipping"
fi

# 2. Skill files — copy entire skill tree preserving structure
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

# ── Summary ───────────────────────────────────────────────────────────────────
printf "\n${GREEN}${BOLD}Installation complete!${RESET}\n\n"

printf "Installed to:\n"
printf "  Plugin:  ${BOLD}%s/plugins/monkey-test/${RESET}\n" "$DISPLAY_PREFIX"
printf "  Skills:  ${BOLD}%s/skills/monkey-test/${RESET}\n" "$DISPLAY_PREFIX"

printf "\n${BOLD}Installed files:${RESET}\n"

# Count installed files
file_count=0
if [ -d "$PLUGIN_DIR" ]; then
    plugin_count=$(find "$PLUGIN_DIR" -type f | wc -l | tr -d ' ')
    file_count=$((file_count + plugin_count))
fi
if [ -d "$SKILL_DIR" ]; then
    skill_count=$(find "$SKILL_DIR" -type f | wc -l | tr -d ' ')
    file_count=$((file_count + skill_count))
fi
printf "  %s files total\n" "$file_count"

printf "\n${BOLD}Usage:${RESET}\n"
printf "  1. Open Claude Code in your project\n"
printf "  2. Say: ${BLUE}Run agent test on this project${RESET}\n"
printf "  3. The agent will discover routes, ask you which to test, and begin\n"
printf "  4. The Ralph Loop harness keeps it running autonomously\n"

printf "\n${BOLD}Configuration:${RESET}\n"
printf "  The agent will ask for base_url, credentials, and batch size at startup.\n"
printf "  Set safe_to_mutate=true only if destructive UI actions are acceptable.\n"

if [ "$MODE" = "project" ]; then
    printf "\n${YELLOW}Tip:${RESET} Add .claude/plugins/ and .claude/skills/ to .gitignore\n"
    printf "     if you don't want to commit the agent-test plugin.\n"
fi

printf "\n"
