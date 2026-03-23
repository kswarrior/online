#!/bin/bash
#===============================================================================
# 24/7 ETERNAL RUNNER - Ultra-Resilient Process Monitor
# Description: Keeps any process running 24/7 with advanced monitoring
# Version: 2.0
#===============================================================================

set -o pipefail
shopt -s checkwinsize 2>/dev/null || true

#-------------------------------------------------------------------------------
# CONFIGURATION
#-------------------------------------------------------------------------------
SCRIPT_NAME="24/7-Eternal"
VERSION="2.0"
PID_FILE="/tmp/${SCRIPT_NAME//\//-}.pid"
LOG_DIR="${HOME}/.24-7/logs"
LOG_FILE="${LOG_DIR}/runner-$(date +%Y%m%d).log"
MAX_RESTARTS=999999
RESTART_DELAY=1
HEALTH_CHECK_INTERVAL=5
CRASH_WINDOW=60
CRASH_THRESHOLD=5

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

#-------------------------------------------------------------------------------
# LOGGING SYSTEM
#-------------------------------------------------------------------------------
mkdir -p "$LOG_DIR" 2>/dev/null || LOG_DIR="/tmp"

log() {
    local level="$1"
    shift
    local message="[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*"
    echo "$message" >> "$LOG_FILE" 2>/dev/null
    case "$level" in
        "INFO")  echo -e "${GREEN}$message${NC}" ;;
        "WARN")  echo -e "${YELLOW}$message${NC}" ;;
        "ERROR") echo -e "${RED}$message${NC}" ;;
        "FATAL") echo -e "${RED}$message${NC}" ;;
        "DEBUG") echo -e "${BLUE}$message${NC}" ;;
        *)       echo -e "${CYAN}$message${NC}" ;;
    esac
}

#-------------------------------------------------------------------------------
# SIGNAL HANDLING
#-------------------------------------------------------------------------------
cleanup() {
    log "INFO" "Received shutdown signal. Cleaning up..."
    [[ -n "$CHILD_PID" ]] && kill -TERM "$CHILD_PID" 2>/dev/null
    rm -f "$PID_FILE"
    log "INFO" "Cleanup complete. Exiting."
    exit 0
}

trap cleanup SIGINT SIGTERM SIGQUIT SIGHUP
trap '' SIGPIPE

#-------------------------------------------------------------------------------
# PROCESS MANAGEMENT
#-------------------------------------------------------------------------------
declare -A CRASH_TIMES
restart_count=0
start_time=$(date +%s)

check_pid_file() {
    if [[ -f "$PID_FILE" ]]; then
        local old_pid=$(cat "$PID_FILE" 2>/dev/null)
        if kill -0 "$old_pid" 2>/dev/null; then
            log "FATAL" "Another instance is already running (PID: $old_pid)"
            exit 1
        fi
    fi
    echo $$ > "$PID_FILE"
}

health_check() {
    local pid=$1
    local checks=0
    while kill -0 "$pid" 2>/dev/null; do
        sleep "$HEALTH_CHECK_INTERVAL"
        ((checks++))
        # Log heartbeat every minute
        if (( checks % 12 == 0 )); then
            local uptime=$(( $(date +%s) - start_time ))
            log "DEBUG" "Health check OK - Uptime: ${uptime}s, Restarts: $restart_count"
        fi
    done
}

calculate_backoff() {
    local crashes=0
    local now=$(date +%s)
    for ts in "${CRASH_TIMES[@]}"; do
        (( now - ts < CRASH_WINDOW )) && ((crashes++))
    done
    if (( crashes >= CRASH_THRESHOLD )); then
        local backoff=$(( crashes * 2 ))
        [[ $backoff -gt 60 ]] && backoff=60
        log "WARN" "Crash threshold reached ($crashes in ${CRASH_WINDOW}s). Backing off ${backoff}s..."
        sleep "$backoff"
    fi
}

record_crash() {
    local now=$(date +%s)
    CRASH_TIMES["$now"]=$now
    # Clean old entries
    for key in "${!CRASH_TIMES[@]}"; do
        (( now - key > CRASH_WINDOW )) && unset CRASH_TIMES["$key"]
    done
}

#-------------------------------------------------------------------------------
# MAIN EXECUTION ENGINE
#-------------------------------------------------------------------------------
run_eternal() {
    local target_command="$1"
    shift
    
    log "INFO" "=== $SCRIPT_NAME v$VERSION Started ==="
    log "INFO" "Target: $target_command"
    log "INFO" "PID: $$ | Log: $LOG_FILE"
    
    check_pid_file
    
    while true; do
        if [[ $restart_count -ge $MAX_RESTARTS ]]; then
            log "FATAL" "Maximum restart limit reached ($MAX_RESTARTS)"
            exit 1
        fi
        
        calculate_backoff
        
        log "INFO" ">>> Starting process (Attempt #$((restart_count + 1)))"
        
        # Execute the target command
        if [[ -z "$target_command" ]]; then
            # Default 24/7 demo mode - CPU-friendly counter
            (
                counter=0
                while true; do
                    echo -ne "\r${CYAN}24/7 Eternal Runner: ${GREEN}$counter${NC} seconds $(date '+| %H:%M:%S') "
                    ((counter++))
                    sleep 1
                done
            ) &
        else
            eval "$target_command $*" &
        fi
        
        CHILD_PID=$!
        log "INFO" "Process started with PID: $CHILD_PID"
        
        # Monitor health in background
        health_check "$CHILD_PID" &
        local monitor_pid=$!
        
        # Wait for process
        if wait "$CHILD_PID"; then
            log "WARN" "Process exited cleanly (code: $?)"
        else
            local exit_code=$?
            log "ERROR" "Process crashed with code: $exit_code"
            record_crash
        fi
        
        # Clean up monitor
        kill "$monitor_pid" 2>/dev/null
        wait "$monitor_pid" 2>/dev/null
        
        CHILD_PID=""
        ((restart_count++))
        
        log "INFO" "Restarting in ${RESTART_DELAY}s... (Total restarts: $restart_count)"
        sleep "$RESTART_DELAY"
    done
}

#-------------------------------------------------------------------------------
# CLI INTERFACE
#-------------------------------------------------------------------------------
show_banner() {
    cat << 'EOF'
    ███████╗██████╗  ██╗██████╗ 
    ██╔════╝╚════██╗███║╚════██╗
    █████╗   █████╔╝╚██║ █████╔╝
    ██╔══╝   ╚═══██╗ ██║ ╚═══██╗
    ███████╗██████╔╝ ██║██████╔╝
    ╚══════╝╚═════╝  ╚═╝╚═════╝ 
    E T E R N A L   R U N N E R
EOF
    echo ""
}

show_usage() {
    show_banner
    echo "Usage: $0 [OPTIONS] [COMMAND]"
    echo ""
    echo "Options:"
    echo "  -h, --help          Show this help message"
    echo "  -v, --version       Show version"
    echo "  -s, --status        Check if runner is active"
    echo "  -k, --kill          Stop the runner"
    echo "  -l, --logs          Show recent logs"
    echo ""
    echo "Examples:"
    echo "  $0                  Run default 24/7 demo"
    echo "  $0 'python app.py'  Keep Python app running forever"
    echo "  $0 ./my-server      Keep server binary alive"
    echo ""
}

#-------------------------------------------------------------------------------
# COMMAND HANDLER
#-------------------------------------------------------------------------------
case "${1:-}" in
    -h|--help)
        show_usage
        exit 0
        ;;
    -v|--version)
        echo "$SCRIPT_NAME v$VERSION"
        exit 0
        ;;
    -s|--status)
        if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
            echo -e "${GREEN}✓ Runner is active (PID: $(cat "$PID_FILE"))${NC}"
            tail -5 "$LOG_FILE" 2>/dev/null || echo "No logs yet"
        else
            echo -e "${RED}✗ Runner is not running${NC}"
        fi
        exit 0
        ;;
    -k|--kill)
        if [[ -f "$PID_FILE" ]]; then
            pid=$(cat "$PID_FILE")
            kill -TERM "$pid" 2>/dev/null && echo "Stopped runner (PID: $pid)" || echo "Failed to stop"
            rm -f "$PID_FILE"
        else
            echo "No PID file found"
        fi
        exit 0
        ;;
    -l|--logs)
        [[ -f "$LOG_FILE" ]] && tail -f "$LOG_FILE" || echo "No logs found"
        exit 0
        ;;
esac

#-------------------------------------------------------------------------------
# BOOT SEQUENCE
#-------------------------------------------------------------------------------
show_banner
run_eternal "$@"
