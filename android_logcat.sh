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

# Handle FATAL EXCEPTION
show_display_fatal_header() {
  line="$1"
  if [[ "$line" == *"FATAL EXCEPTION"* ]]; then
    read -r timestamp_date timestamp_time pid tid level tag _ msg <<< "$line"
    local timestamp="$timestamp_date $timestamp_time"
    local fatal_header="${RED}╔════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════${NC}"
    local fatal_title="${RED}║ ${BOLD}🚨 FATAL EXCEPTION DETECTED${NC}                                                                                    ${NC}"
    local fatal_separator="${RED}╠════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════${NC}"
    local fatal_time="${RED}║ ${CYAN}Time:${NC} $timestamp                                                                                               ${NC}"
    local fatal_tag_line="${RED}║ ${CYAN}Tag:${NC} $tag                                                                                                      ${NC}"
    local fatal_footer="${RED}╚════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════${NC}"
    local fatal_details="${BOLD}📋 Exception Details:${NC}"
    local fatal_msg="    ${RED}${line#*FATAL EXCEPTION:*}${NC}"

    printf '%s\n' "$fatal_header" "$fatal_title" "$fatal_separator" "$fatal_time" "$fatal_tag_line" "$fatal_footer" "" "$fatal_details" "$fatal_msg"
    in_exception=1
    return 0
  fi

  return 1
}

# Handle ERROR logs
show_error() {
  line="$1"
  if [[ "$line" == *"$PACKAGE_NAME"* && "$line" =~ [[:space:]]E[[:space:]] ]]; then
    timestamp="${line:0:18}"
    read -r _ _ _ tag msg <<< "$line"

    if [[ "$msg" =~ at[[:space:]]+.*\([A-Za-z0-9_]+\.(java|kt):[0-9]+\) ]]; then
      msg=$(sed -E "
          s/(E [^ ]*:)/${RED}\1${NC}/
          s/\(([A-Za-z0-9_]+\.[a-z]+:[0-9]+)\)/${CYAN}(\1)${NC}/g
          s/^([[:space:]]*)at([[:space:]]+)/\1${YELLOW}at${NC}\2/
      " <<< "$msg")
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

    return 0
  fi

  return 1
}

# # Case-insensitive substring match without bash-4 ${,,}
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
shopt -s nocasematch

# Case-insensitive substring match tanpa tr
ci_contains() {
  local hay="$1" ned="$2"
  [[ -z "$ned" ]] && return 0
  [[ "$hay" == *"$ned"* ]]
}

strip_ansi() {
  local str="$1"
  str="${str//$'\x1b'[\[*([0-9;])m/}"
  printf '%s' "$str"
}

should_display_log_network() {
  [[ -z "$FILTER_TERM" ]] && return 0
  local clean_formatted
  clean_formatted=$(strip_ansi "$2")
  ci_contains "$1" "$FILTER_TERM" || ci_contains "$clean_formatted" "$FILTER_TERM"
}
should_display_log_network() {
  [[ -z "$FILTER_TERM" ]] && return 0
  local clean_formatted="$2"
  clean_formatted="${clean_formatted//$'\x1b'[\[*([0-9;])m/}"
  if ci_contains "$1" "$FILTER_TERM" || ci_contains "$clean_formatted" "$FILTER_TERM"; then
    return 0
  else
    return 1
  fi
}

# Handle NETWORK logs from OkHttp
tag_status=""

set_tag_status() { 
    local tag="$1"
    local status="$2"
    tag_status="${tag_status//${tag}:*;/}"
    tag_status="${tag_status}${tag}:${status};" 
}

get_tag_status() {
    local tag="$1"
    local temp="${tag_status#*${tag}:}"
    [[ "$temp" != "$tag_status" ]] && echo "${temp%%;*}"
}


excape_json_like() {
  local msg="$1"
  local key="${msg%%:*}"
  local value="${msg#*:}"
  status=$(get_tag_status "$tag")
    case "$status" in
      "ERROR")
        formatted_output="$network_prefix      ${RED}[ERROR]${NC} ${YELLOW}$key${NC}:$value"
      ;;
      
      "SUCCESS")
         formatted_output="$network_prefix      ${GREEN}[SUCCESS]${NC} ${YELLOW}$key${NC}:$value"
      ;;
    *)
      formatted_output="$network_prefix      ${YELLOW}$key${NC}:$value"
    ;;
    esac
}
show_network_log() {
  line="$1"
  [[ "$line" != *"okhttp.OkHttpClient"* ]] && return 1

  read -r date time pid tid level tag rest <<< "$line"
  timestamp="$date $time"
  msg="${line#*okhttp.OkHttpClient:}"
  msg="${msg#"${msg%%[![:space:]]*}"}" 
  network_prefix="${YELLOW}[NETWORK]${NC} ${BLUE}$timestamp${NC} ${PURPLE}[$tid]${NC}"
  
  case "$msg" in
    '{"error'*|'{"errors'*)
      formatted_output="$network_prefix  ${RED}--> [ERROR] ${NC}${ORANGE}Result${NC}: ${RED}$msg${NC}"
      ;;
    
    '{'*'}')
      formatted_output="$network_prefix  ${GREEN}--> [SUCCESS] ${NC}${ORANGE}Result${NC}: ${GREEN}$msg${NC}"
      ;;
    
     (\{* | *\} | *\}*)
      case "$msg" in
          'nel: {'*|'report-to: {'*)
              case "$msg" in
                  *':'*)
                      excape_json_like "$msg"
                      ;;
              esac
              ;;
            '{'*)
              formatted_output="$network_prefix  ${GREEN}--> [SUCCESS] ${NC}${ORANGE}Result${NC}: ${GREEN}$msg${NC}"
              ;;
            *)
              formatted_output="$network_prefix  ${GREEN}[SUCCESS]${NC} ${GREEN}$msg${NC}"
              ;;
      esac
      ;;
    
    '-->'*)
      case "$msg" in
        *'GET'*|*'POST'*|*'PUT'*|*'DELETE'*)
          set_tag_status "$tag" "REQUEST"
          ;;
      esac
      formatted_output="$network_prefix  ${YELLOW}$msg${NC}"
      ;;
    
    '<--'*)
      case "$msg" in
        *'<-- 4'*|*'<-- 5'*)
          modified_msg="${msg/<-- /<-- [ERROR] }"
          formatted_output="$network_prefix  ${RED}$modified_msg${NC}"
          set_tag_status "$tag" "ERROR"
          ;;
        *'<-- 2'*|*'<-- 3'*)
          modified_msg="${msg/<-- /<-- [SUCCESS] }"
          formatted_output="$network_prefix  ${GREEN}$modified_msg${NC}"
          set_tag_status "$tag" "SUCCESS"
          ;;
        *)
          formatted_output="$network_prefix  ${YELLOW}$msg${NC}"
          ;;
      esac
      ;;
    
    *':'*)
      case "$msg" in
        'nel: {'*|'report-to: {'*)
          return 1
          ;;
        *)
          excape_json_like "$msg"
          ;;
      esac
      ;;
    
    *'"'*)
      case "$msg" in
        'nel:'*|'report-to:'*)
          return 1
          ;;
        *)
          formatted_output="$network_prefix  ${GREEN}$msg${NC}"
          ;;
      esac
      ;;
    
    *)
      formatted_output="$network_prefix  $msg"
      ;;
  esac
  
  if should_display_log_network "$line" "$formatted_output"; then
    echo -e "$formatted_output"
    clean_output="${formatted_output//$'\x1b'[\[*([0-9;])m/}"
    echo "$clean_output" >> "$LOG_FILE"
    
    [[ "$msg" == "<-- END"* ]] && echo -e "--> ${CYAN}Commands Identifiers:${NC} ${BOLD}${YELLOW}$CMD_IDENTIFIER${NC}"
  fi
  
  return 0
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

# Main reconnect loop
while true; do
  adb -s "$DEVICE_ID" logcat --pid=$APP_PID -v threadtime 2>/dev/null | while IFS= read -r line; do
    ((line_counter++))
    if (( line_counter % FILTER_CHECK_INTERVAL == 1 )); then
      update_filter_if_changed
    fi

    show_display_fatal_header "$line" && continue
    show_error "$line" && continue
    show_network_log "$line"

  done

  echo -e "${RED}⚠ logcat disconnected — reconnect...${NC}" >&2
  sleep 1
done