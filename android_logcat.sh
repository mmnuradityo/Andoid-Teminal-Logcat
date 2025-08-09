#!/bin/bash

PACKAGE=$1
DEVICE_ID=$2

if [[ -z "$PACKAGE" || -z "$DEVICE_ID" ]]; then
  echo "Usage: ./qa_logcat.sh <package_name> <device_serial>"
  exit 1
fi

# Colors (tetap seperti milikmu)
RED=$'\033[1;31m'
YELLOW=$'\033[1;33m'
ORANGE=$'\033[38;5;208m'
GREEN=$'\033[1;32m'
CYAN=$'\033[1;36m'
BLUE=$'\033[1;34m'
DARK_BLUE=$'\033[38;5;25m'
PURPLE=$'\033[1;35m'
BOLD=$'\033[1m'
NC=$'\033[0m'

# Filter file dan log file (pakai PID skrip agar gampang dipakai dari terminal lain)
CMD_IDENTIFIER=$$
FILTER_FILE="/tmp/android_logcat_filter_$CMD_IDENTIFIER"
LOG_FILE="/tmp/android_logcat_$CMD_IDENTIFIER"
FILTER_TERM=""
LAST_CMD=""
: > "$FILTER_FILE"
: > "$LOG_FILE"

# Helper: ambil mtime cross-platform (macOS stat -f %m, linux stat -c %Y)
get_mtime() {
  if stat -f %m "$1" >/dev/null 2>&1; then
    stat -f %m "$1" 2>/dev/null
  elif stat -c %Y "$1" >/dev/null 2>&1; then
    stat -c %Y "$1" 2>/dev/null
  else
    echo 0
  fi
}

FILTER_MTIME=$(get_mtime "$FILTER_FILE" 2>/dev/null || echo 0)

# Save clean logs tanpa kode warna
save_log_to_file() {
  local log_output="$1"
  local clean_output
  clean_output=$(printf '%b\n' "$log_output" | sed 's/\x1b\[[0-9;]*m//g')
  echo "$clean_output" >> "$LOG_FILE"
}

# Update FILTER_TERM hanya kalau file filter berubah (efisien)
update_filter_if_changed() {
  local cur
  cur=$(get_mtime "$FILTER_FILE" 2>/dev/null || echo 0)
  if [[ "$cur" != "$FILTER_MTIME" ]]; then
    FILTER_MTIME="$cur"
    local cmd
    cmd=$(tail -n 1 "$FILTER_FILE" 2>/dev/null | tr -d '\r' || true)
    if [[ -n "$cmd" && "$cmd" != "$LAST_CMD" ]]; then
      LAST_CMD="$cmd"
      case "$cmd" in
        "/filter "*)
          FILTER_TERM="${cmd#/filter }"
          FILTER_TERM="$(echo -n "$FILTER_TERM" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
          echo -e "${YELLOW}🔍 Filter: '$FILTER_TERM'${NC}" >&2
          ;;
        "/clear")
          FILTER_TERM=""
          echo -e "${GREEN}✅ Filter cleared - showing all logs${NC}" >&2
          ;;
        "/help")
          echo -e "${BOLD}Available commands:${NC}" >&2
          echo -e "${YELLOW}echo '/filter something' >> $FILTER_FILE${NC}" >&2
          echo -e "${YELLOW}echo '/clear' >> $FILTER_FILE${NC}" >&2
          echo -e "${YELLOW}echo '/help' >> $FILTER_FILE${NC}" >&2
          ;;
        *)
          # ignore other lines
          ;;
      esac
    fi
  fi
}

# Case-insensitive substring match without bash-4 ${,,}
ci_contains() {
  local hay="$1"
  local ned="$2"
  if [[ -z "$ned" ]]; then return 0; fi
  local hay_l=$(printf '%s' "$hay" | tr '[:upper:]' '[:lower:]')
  local ned_l=$(printf '%s' "$ned" | tr '[:upper:]' '[:lower:]')
  if [[ "$hay_l" == *"$ned_l"* ]]; then
    return 0
  else
    return 1
  fi
}

# Two helpers used later for filtering
should_display_log() {
  [[ -z "$FILTER_TERM" ]] && return 0
  ci_contains "$1" "$FILTER_TERM"
}

should_display_log_network() {
  [[ -z "$FILTER_TERM" ]] && return 0
  local clean_formatted
  clean_formatted=$(printf '%b' "$2" | sed 's/\x1b\[[0-9;]*m//g')
  if ci_contains "$1" "$FILTER_TERM" || ci_contains "$clean_formatted" "$FILTER_TERM"; then
    return 0
  else
    return 1
  fi
}

shoud_print_identifier() {
  local msg="$1"
  if [[ "$msg" == "<-- END"* ]]; then
      end_commands="--> ${CYAN}Commands Identifiers:${NC} ${BOLD}${YELLOW}$CMD_IDENTIFIER${NC}"
      echo -e "$end_commands"
  fi
}

# Cleanup
cleanup() {
  rm -f "$FILTER_FILE"
  echo -e "${CYAN}📁 Search logs saved at: $LOG_FILE${NC}"
  exit 0
}
trap cleanup EXIT

# Header
echo ""
echo -e "${BOLD}🔍 Android Logcat Monitor${NC}"
echo -e "${CYAN}📦 Package: $PACKAGE${NC}"
echo -e "${CYAN}📱 Device: $DEVICE_ID${NC}"
echo -e "${YELLOW}⏰ Started: $(date '+%Y-%m-%d %H:%M:%S')${NC}"
echo -e "${CYAN}📁 Logs saved to: $LOG_FILE${NC}"
echo -e "${CYAN}📄 Filter file (use this path): $FILTER_FILE${NC}"
echo ""
echo -e "${YELLOW}💡 Filter Commands (run in another terminal):${NC}"
echo -e "${YELLOW}   echo '/filter error' >> $FILTER_FILE${NC}"
echo -e "${YELLOW}   echo '/clear' >> $FILTER_FILE${NC}"
echo -e "${YELLOW}   echo '/help' >> $FILTER_FILE${NC}"
echo ""
echo -e "${CYAN}🔍 Search in saved logs:${NC}"
echo -e "${CYAN}   grep -i 'your_term' $LOG_FILE${NC}"
echo -e "${CYAN}   grep -i 'error' $LOG_FILE | tail -10${NC}"
echo ""
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Clear logcat first and limit
adb -s "$DEVICE_ID" logcat -c 2>/dev/null || true
adb -s "$DEVICE_ID" logcat -G 1M 2>/dev/null || true
sleep 1

# Get app PID
APP_PID=$(adb -s "$DEVICE_ID" shell pidof -s "$PACKAGE" | tr -d '\r')
if [[ -z "$APP_PID" ]]; then
  echo -e "${RED}❌ Failed to get PID for package $PACKAGE${NC}"
  exit 1
fi

echo -e "${GREEN}🎯 Monitoring PID: $APP_PID${NC}"
echo -e "${GREEN}🔄 Live logs start... Press Ctrl+C to stop${NC}"
echo ""

# We'll check filter file every N lines to avoid stat per line
FILTER_CHECK_INTERVAL=5
line_counter=0

LAST_CMD=""    # already set above
in_exception=0


tag_status=""
set_tag_status() {
    local tag="$1"
    local status="$2"
    tag_status="${tag_status}${tag}:${status};"
}
get_tag_status() {
    local tag="$1"
    echo "$tag_status" | grep -o "${tag}:[^;]*" | cut -d':' -f2
}

# Main reconnect loop
while true; do
  adb -s "$DEVICE_ID" logcat --pid=$APP_PID -v threadtime 2>/dev/null | while IFS= read -r line; do
    ((line_counter++))
    if (( line_counter % FILTER_CHECK_INTERVAL == 1 )); then
      update_filter_if_changed
    fi

    # Handle FATAL EXCEPTION
    if [[ "$line" == *"FATAL EXCEPTION"* ]]; then
      timestamp=$(echo "$line" | awk '{print $1, $2}')
      tag=$(echo "$line" | awk '{print $4}')
      msg=$(echo "$line" | cut -d' ' -f7-)

      if should_display_log "$line"; then
        fatal_header="${RED}╔════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════${NC}"
        fatal_title="${RED}║ ${BOLD}🚨 FATAL EXCEPTION DETECTED${NC}                                                                                    ${NC}"
        fatal_separator="${RED}╠════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════${NC}"
        fatal_time="${RED}║ ${CYAN}Time:${NC} $timestamp                                                                                               ${NC}"
        fatal_tag_line="${RED}║ ${CYAN}Tag:${NC} $tag                                                                                                      ${NC}"
        fatal_footer="${RED}╚════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════${NC}"
        fatal_details="${BOLD}📋 Exception Details:${NC}"
        fatal_msg="    ${RED}$msg${NC}"

        echo -e "$fatal_header"
        echo -e "$fatal_title"
        echo -e "$fatal_separator"
        echo -e "$fatal_time"
        echo -e "$fatal_tag_line"
        echo -e "$fatal_footer"
        echo ""
        echo -e "$fatal_details"
        echo -e "$fatal_msg"

        # Save to file (clean)
        save_log_to_file "$fatal_header"
        save_log_to_file "$fatal_title"
        save_log_to_file "$fatal_separator"
        save_log_to_file "$fatal_time"
        save_log_to_file "$fatal_tag_line"
        save_log_to_file "$fatal_footer"
        save_log_to_file ""
        save_log_to_file "$fatal_details"
        save_log_to_file "$fatal_msg"
      fi
      in_exception=1
      continue
    fi

    # Handle ERROR logs (optimized + correct colors)
    if [[ "$line" == *"$PACKAGE_NAME"* && "$line" =~ [[:space:]]E[[:space:]] ]]; then
        timestamp="${line:0:18}"
        tag=$(awk '{print $4}' <<< "$line")
        msg=$(sed -E 's/^[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3} +[0-9]+ +[0-9]+ //' <<< "$line")
        
        if [[ "$msg" =~ at[[:space:]]+.*\([A-Za-z0-9_]+\.(java|kt):[0-9]+\) ]]; then
            msg=$(sed -E "s/(E [^ ]*:)/${RED}\1${NC}/" <<< "$msg")
            msg=$(sed -E "s/\(([A-Za-z0-9_]+\.[a-z]+:[0-9]+)\)/${CYAN}(\1)${NC}/g; s/^([[:space:]]*)at([[:space:]]+)/\1${YELLOW}at${NC}\2/" <<< "$msg")
            echo -e "${RED}[ERROR]${NC}   ${BLUE}$timestamp${NC} ${PURPLE}[$tag]${NC}  $msg"

        elif [[ "$msg" =~ E[[:space:]]+[^:]+:[[:space:]]+at[[:space:]]+ ]]; then
          msg=$(sed -E "s/(E [^ ]*:)(.*)/${RED}\1${NC}\2/" <<< "$msg")
          echo -e "${RED}[ERROR]${NC}   ${BLUE}$timestamp${NC} ${PURPLE}[$tag]${NC}  $msg"

        elif [[ "$msg" =~ E[[:space:]]+[^:]+:[[:space:]]+[^:]+: ]]; then
            msg=$(sed -E "s/(E [^ ]*:)([^:]*:)(.*)/${RED}\1${NC}${YELLOW}\2${NC}\3/" <<< "$msg")
            echo -e "${RED}[ERROR]${NC}   ${BLUE}$timestamp${NC} ${PURPLE}[$tag]${NC}  $msg"

        else
            msg=$(sed -E "s/(E [^ ]*:)/${RED}\1${NC}/" <<< "$msg")
            echo -e "${RED}[ERROR]${NC}   ${BLUE}$timestamp${NC} ${PURPLE}[$tag]${NC}  $msg"
        fi
    fi

    # Handle NETWORK logs from OkHttp
    if [[ "$line" == *"okhttp.OkHttpClient"* ]]; then
      timestamp=$(echo "$line" | awk '{print $1, $2}')
      tag=$(echo "$line" | awk '{print $4}')
      msg=$(echo "$line" | sed 's/.*okhttp\.OkHttpClient:[[:space:]]*//')

      formatted_output=""

      if [[ "$msg" =~ ^\{\"(errors?)\": ]]; then
          formatted_output="${YELLOW}[NETWORK]${NC} ${BLUE}$timestamp${NC} ${PURPLE}[$tag]${NC}  ${RED}--> [ERROR] ${NC}${ORANGE}Result${NC}: ${RED}$msg${NC}"

      elif [[ "$msg" =~ ^\{.*\}[[:space:]]*$ ]]; then
          formatted_output="${YELLOW}[NETWORK]${NC} ${BLUE}$timestamp${NC} ${PURPLE}[$tag]${NC}  ${GREEN}--> [SUCCESS] ${NC}${ORANGE}Result${NC}: ${GREEN}$msg${NC}"

      elif [[ "$msg" =~ ^\{ ]]; then
          formatted_output="${YELLOW}[NETWORK]${NC} ${BLUE}$timestamp${NC} ${PURPLE}[$tag]${NC}  ${GREEN}--> [SUCCESS] ${NC}${ORANGE}Result${NC}: ${GREEN}$msg${NC}"

      elif [[ "$msg" == *'"'* && "$msg" == *":"* && ! "$msg" =~ ^(nel|report-to):[[:space:]]*\{ ]]; then
          formatted_output="${YELLOW}[NETWORK]${NC} ${BLUE}$timestamp${NC} ${PURPLE}[$tag]${NC}  ${GREEN}$msg${NC}"

      elif [[ "$msg" =~ ^[0-9a-zA-Z] && "$msg" == *'"'* && ! "$msg" =~ ^(nel|report-to):[[:space:]]*\{ ]]; then
          formatted_output="${YELLOW}[NETWORK]${NC} ${BLUE}$timestamp${NC} ${PURPLE}[$tag]${NC}  ${GREEN}$msg${NC}"

      elif [[ "$msg" == "-->"* ]]; then
          if [[ "$msg" == *"GET"* || "$msg" == *"POST"* || "$msg" == *"PUT"* || "$msg" == *"DELETE"* ]]; then
              tag_status[$tag]="REQUEST"
          fi
          formatted_output="${YELLOW}[NETWORK]${NC} ${BLUE}$timestamp${NC} ${PURPLE}[$tag]${NC}  ${YELLOW}$msg${NC}"

      elif [[ "$msg" == "<--"* ]]; then
          if [[ "$msg" == *"<-- 4"* || "$msg" == *"<-- 5"* ]]; then
              modified_msg=$(echo "$msg" | sed 's/<-- \([45][0-9][0-9]\)/<-- [ERROR] \1/')
              formatted_output="${YELLOW}[NETWORK]${NC} ${BLUE}$timestamp${NC} ${PURPLE}[$tag]${NC}  ${RED}$modified_msg${NC}"
              tag_status[$tag]="ERROR"

          elif [[ "$msg" == *"<-- 2"* || "$msg" == *"<-- 3"* ]]; then
              modified_msg=$(echo "$msg" | sed 's/<-- \([23][0-9][0-9]\)/<-- [SUCCESS] \1/')
              formatted_output="${YELLOW}[NETWORK]${NC} ${BLUE}$timestamp${NC} ${PURPLE}[$tag]${NC}  ${GREEN}$modified_msg${NC}"
              tag_status[$tag]="SUCCESS"

          else
              formatted_output="${YELLOW}[NETWORK]${NC} ${BLUE}$timestamp${NC} ${PURPLE}[$tag]${NC}  ${YELLOW}$msg${NC}"
          fi

      elif [[ "$msg" =~ ^[^:]+:[[:space:]]* ]]; then
          key=$(echo "$msg" | cut -d':' -f1)
          value=$(echo "$msg" | cut -d':' -f2-)
          
          if [[ "${tag_status[$tag]}" == "ERROR" ]]; then
              formatted_output="${YELLOW}[NETWORK]${NC} ${BLUE}$timestamp${NC} ${PURPLE}[$tag]${NC}      ${RED}[ERROR]${NC} ${YELLOW}$key${NC}:$value"
          elif [[ "${tag_status[$tag]}" == "SUCCESS" ]]; then
              formatted_output="${YELLOW}[NETWORK]${NC} ${BLUE}$timestamp${NC} ${PURPLE}[$tag]${NC}      ${GREEN}[SUCCESS]${NC} ${YELLOW}$key${NC}:$value"
          else
              formatted_output="${YELLOW}[NETWORK]${NC} ${BLUE}$timestamp${NC} ${PURPLE}[$tag]${NC}      ${YELLOW}$key${NC}:$value"
          fi

      else
          formatted_output="${YELLOW}[NETWORK]${NC} ${BLUE}$timestamp${NC} ${PURPLE}[$tag]${NC}  $msg"
      fi

      if should_display_log_network "$line" "$formatted_output"; then
          echo -e "$formatted_output"
          save_log_to_file "$formatted_output"
          shoud_print_identifier "$msg"
      fi
      continue
    fi

  done

  echo -e "${RED}⚠ logcat disconnected — reconnect...${NC}" >&2
  sleep 1
done
