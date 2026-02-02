#!/usr/bin/env bash
# Helper function to find all worker processes for a specific project
# This can be sourced by other scripts or run directly

# Usage: find_project_workers PROJECT_DIR
# Returns: PIDs of all worker processes for the project (one per line)
find_project_workers() {
  local project_dir="$1"

  # Normalize the project directory path (resolve symlinks, remove trailing slash)
  project_dir="$(cd "$project_dir" 2>/dev/null && pwd)" || {
    echo "Error: Invalid project directory: $project_dir" >&2
    return 1
  }

  # Find all processes where:
  # 1. Command contains the project directory path
  # 2. Command contains "worker" (either .venv/bin/worker or "uv run worker")
  # We need to be specific to avoid killing unrelated processes

  # Strategy: Find both parent "uv run worker" processes and child Python worker processes
  # We'll use the project directory in the path as the key identifier

  local pids=()

  # Use ps to get all processes with their commands
  if [[ "$(uname)" == "Darwin" ]]; then
    # macOS - find Python workers
    while IFS= read -r pid; do
      [[ -n "$pid" ]] && pids+=("$pid")
    done < <(ps ax -o pid,command | grep -E "\.venv/bin/(python[0-9.]*|worker)" | grep -E "${project_dir}" | grep -v grep | awk '{print $1}')

    # Also find "uv run worker" processes in this directory
    while IFS= read -r pid; do
      [[ -n "$pid" ]] && pids+=("$pid")
    done < <(ps ax -o pid,command | grep "uv run worker" | grep -v grep | awk -v dir="$project_dir" '{
      # Check if process is running from the project directory by checking cwd
      cmd = "lsof -a -p " $1 " -d cwd -Fn 2>/dev/null | grep ^n | cut -c2-"
      cmd | getline cwd
      close(cmd)
      if (index(cwd, dir) > 0) print $1
    }')
  else
    # Linux - find Python workers
    while IFS= read -r pid; do
      [[ -n "$pid" ]] && pids+=("$pid")
    done < <(ps ax -o pid,cmd | grep -E "\.venv/bin/(python[0-9.]*|worker)" | grep -E "${project_dir}" | grep -v grep | awk '{print $1}')

    # Also find "uv run worker" processes in this directory
    while IFS= read -r pid; do
      [[ -n "$pid" ]] && pids+=("$pid")
    done < <(ps ax -o pid,cmd | grep "uv run worker" | grep -v grep | awk -v dir="$project_dir" '{
      # Check if process is running from the project directory
      cmd = "readlink -f /proc/" $1 "/cwd 2>/dev/null"
      cmd | getline cwd
      close(cmd)
      if (index(cwd, dir) > 0) print $1
    }')
  fi

  # Print unique PIDs
  printf "%s\n" "${pids[@]}" | sort -u
}

# If script is executed directly (not sourced), run the function
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  if [[ $# -eq 0 ]]; then
    # Default to current directory
    find_project_workers "$(pwd)"
  else
    find_project_workers "$1"
  fi
fi
