#!/usr/bin/env bash
set -euo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source the helper function to find project workers
source "$SCRIPT_DIR/find-project-workers.sh"

# Environment variables with defaults
CLAUDE_TEMPORAL_PID_DIR="${CLAUDE_TEMPORAL_PID_DIR:-${TMPDIR:-/tmp}/claude-temporal-pids}"

# Check if PID directory exists
if [[ ! -d "$CLAUDE_TEMPORAL_PID_DIR" ]]; then
  echo "No PID directory found: $CLAUDE_TEMPORAL_PID_DIR"
  exit 0
fi

# Function to get process uptime
get_uptime() {
  local pid=$1
  if [[ "$(uname)" == "Darwin" ]]; then
    # macOS
    local start_time=$(ps -o lstart= -p "$pid" 2>/dev/null | xargs -I{} date -j -f "%c" "{}" "+%s" 2>/dev/null || echo "0")
  else
    # Linux
    local start_time=$(ps -o etimes= -p "$pid" 2>/dev/null | tr -d ' ' || echo "0")
  fi

  if [[ "$start_time" == "0" ]]; then
    echo "-"
    return
  fi

  local now=$(date +%s)
  local elapsed=$((now - start_time))

  # For Linux, etimes already gives elapsed seconds
  if [[ "$(uname)" != "Darwin" ]]; then
    elapsed=$start_time
  fi

  local hours=$((elapsed / 3600))
  local minutes=$(((elapsed % 3600) / 60))
  local seconds=$((elapsed % 60))

  if (( hours > 0 )); then
    printf "%dh %dm" "$hours" "$minutes"
  elif (( minutes > 0 )); then
    printf "%dm %ds" "$minutes" "$seconds"
  else
    printf "%ds" "$seconds"
  fi
}

# Function to get process command
get_command() {
  local pid=$1
  ps -o command= -p "$pid" 2>/dev/null | cut -c1-50 || echo "-"
}

# Print header
printf "%-20s %-8s %-10s %-10s %-10s %s\n" "PROJECT" "PID" "STATUS" "TRACKED" "UPTIME" "COMMAND"
printf "%-20s %-8s %-10s %-10s %-10s %s\n" "--------------------" "--------" "----------" "----------" "----------" "-----"

# Find all PID files
found_any=false

# Track all PIDs we've seen to detect orphans later
declare -A tracked_pids

# List server if exists
SERVER_PID_FILE="$CLAUDE_TEMPORAL_PID_DIR/server.pid"
if [[ -f "$SERVER_PID_FILE" ]]; then
  found_any=true
  SERVER_PID=$(cat "$SERVER_PID_FILE")
  tracked_pids[$SERVER_PID]=1
  if kill -0 "$SERVER_PID" 2>/dev/null; then
    uptime=$(get_uptime "$SERVER_PID")
    command=$(get_command "$SERVER_PID")
    printf "%-20s %-8s %-10s %-10s %-10s %s\n" "server" "$SERVER_PID" "running" "yes" "$uptime" "$command"
  else
    printf "%-20s %-8s %-10s %-10s %-10s %s\n" "server" "$SERVER_PID" "dead" "yes" "-" "-"
  fi
fi

# List all worker PID files
shopt -s nullglob
PID_FILES=("$CLAUDE_TEMPORAL_PID_DIR"/worker-*.pid)
shopt -u nullglob

# Store project directories for orphan detection
declare -A project_dirs

for pid_file in "${PID_FILES[@]}"; do
  found_any=true
  # Extract project name from filename
  filename=$(basename "$pid_file")
  project="${filename#worker-}"
  project="${project%.pid}"

  # Read PID
  worker_pid=$(cat "$pid_file")
  tracked_pids[$worker_pid]=1

  # Check if process is running
  if kill -0 "$worker_pid" 2>/dev/null; then
    uptime=$(get_uptime "$worker_pid")
    command=$(get_command "$worker_pid")
    printf "%-20s %-8s %-10s %-10s %-10s %s\n" "$project" "$worker_pid" "running" "yes" "$uptime" "$command"

    # Try to determine project directory from the command
    # Look for project directory in the command path
    if [[ "$command" =~ ([^[:space:]]+/${project})[/[:space:]] ]]; then
      project_dir="${BASH_REMATCH[1]}"
      project_dirs[$project]="$project_dir"
    fi
  else
    printf "%-20s %-8s %-10s %-10s %-10s %s\n" "$project" "$worker_pid" "dead" "yes" "-" "-"
  fi
done

# Now check for orphaned workers for each project we know about
for project in "${!project_dirs[@]}"; do
  project_dir="${project_dirs[$project]}"

  # Find all workers for this project
  while IFS= read -r pid; do
    [[ -z "$pid" ]] && continue

    # Skip if we already tracked this PID
    if [[ -n "${tracked_pids[$pid]:-}" ]]; then
      continue
    fi

    # This is an orphaned worker
    found_any=true
    if kill -0 "$pid" 2>/dev/null; then
      uptime=$(get_uptime "$pid")
      command=$(get_command "$pid")
      printf "%-20s %-8s %-10s %-10s %-10s %s\n" "$project" "$pid" "running" "ORPHAN" "$uptime" "$command"
      tracked_pids[$pid]=1
    fi
  done < <(find_project_workers "$project_dir" 2>/dev/null || true)
done

# Also scan for workers that have no PID file at all (completely orphaned)
# Find all Python worker processes and group by project
if [[ "$(uname)" == "Darwin" ]]; then
  # macOS
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue

    pid=$(echo "$line" | awk '{print $1}')
    command=$(echo "$line" | cut -d' ' -f2-)

    # Skip if already tracked
    if [[ -n "${tracked_pids[$pid]:-}" ]]; then
      continue
    fi

    # Extract project name from path
    if [[ "$command" =~ /([^/]+)/\.venv/bin/ ]]; then
      project="${BASH_REMATCH[1]}"
      found_any=true
      uptime=$(get_uptime "$pid")
      cmd_display=$(echo "$command" | cut -c1-50)
      printf "%-20s %-8s %-10s %-10s %-10s %s\n" "$project" "$pid" "running" "ORPHAN" "$uptime" "$cmd_display"
      tracked_pids[$pid]=1
    fi
  done < <(ps ax -o pid,command | grep -E "\.venv/bin/(python[0-9.]*|worker)" | grep -v grep)

  # Also check for "uv run worker" processes
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue

    pid=$(echo "$line" | awk '{print $1}')

    # Skip if already tracked
    if [[ -n "${tracked_pids[$pid]:-}" ]]; then
      continue
    fi

    # Get the working directory for this process
    cwd=$(lsof -a -p "$pid" -d cwd -Fn 2>/dev/null | grep ^n | cut -c2- || echo "")
    if [[ -n "$cwd" ]]; then
      project=$(basename "$cwd")
      found_any=true
      uptime=$(get_uptime "$pid")
      printf "%-20s %-8s %-10s %-10s %-10s %s\n" "$project" "$pid" "running" "ORPHAN" "$uptime" "uv run worker"
      tracked_pids[$pid]=1
    fi
  done < <(ps ax -o pid,command | grep "uv run worker" | grep -v grep | awk '{print $1}')
else
  # Linux - similar logic using /proc
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue

    pid=$(echo "$line" | awk '{print $1}')
    command=$(echo "$line" | cut -d' ' -f2-)

    # Skip if already tracked
    if [[ -n "${tracked_pids[$pid]:-}" ]]; then
      continue
    fi

    # Extract project name from path
    if [[ "$command" =~ /([^/]+)/\.venv/bin/ ]]; then
      project="${BASH_REMATCH[1]}"
      found_any=true
      uptime=$(get_uptime "$pid")
      cmd_display=$(echo "$command" | cut -c1-50)
      printf "%-20s %-8s %-10s %-10s %-10s %s\n" "$project" "$pid" "running" "ORPHAN" "$uptime" "$cmd_display"
      tracked_pids[$pid]=1
    fi
  done < <(ps ax -o pid,cmd | grep -E "\.venv/bin/(python[0-9.]*|worker)" | grep -v grep)
fi

if [[ "$found_any" == false ]]; then
  echo "No workers or server found"
fi
