#!/bin/bash
# logging.sh - Shared logging configuration for all scripts
# This file provides consistent logging functions across all scripts in this project

# =========================
# LOGGING CONFIGURATION
# =========================

# Check if colors are supported
if [[ -t 1 ]] && command -v tput &> /dev/null && tput colors &> /dev/null && [[ $(tput colors) -ge 8 ]]; then
    RED=$(tput setaf 1)
    GREEN=$(tput setaf 2)
    YELLOW=$(tput setaf 3)
    BLUE=$(tput setaf 4)
    CYAN=$(tput setaf 6)
    BOLD=$(tput bold)
    RESET=$(tput sgr0)
else
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    CYAN=""
    BOLD=""
    RESET=""
fi

# Logging functions
log_info() {
    echo "${BLUE}[INFO]${RESET} $1"
}

log_success() {
    echo "${GREEN}[SUCCESS]${RESET} $1"
}

log_warning() {
    echo "${YELLOW}[WARN]${RESET} $1"
}

log_error() {
    echo "${RED}[ERROR]${RESET} $1" >&2
}

log_section() {
    echo ""
    echo "${BOLD}${CYAN}=== $1 ===${RESET}"
}

# Export functions so they're available to sourcing scripts
export -f log_info log_success log_warning log_error log_section
