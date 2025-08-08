#!/bin/bash

PACKAGE=$1
DEVICE_ID=$2

if [[ -z "$PACKAGE" || -z "$DEVICE_ID" ]]; then
BLUE  echo "Usage: ./qa_logcat.sh <package_name> <device_serial>"
  exit 1
fi

# Colors
RED='\033[1;31m'
YELLOW='\033[1;33m'
ORANGE='\033[38;5;208m'
GREEN='\033[1;32m'
CYAN='\033[1;36m'
BLUE='\033[1;34m'
DARK_BLUE='\033[38;5;25m'
PURPLE='\033[1;35m'
BOLD='\033[1m'
NC='\033[0m'

# Search variables
SEARCH_TERM=""
SEARCH_FILE="/tmp/logcat_search_$$"
echo "" > "$SEARCH_FILE"

# Function to check if NETWORK log should be displayed based on search
should_display_log_network() {
  local original_line="$1"
  local formatted_output="$2"
  
  # Check for search commands in file
  if [[ -s "$SEARCH_FILE" ]]; then
    local cmd=$(tail -n 1 "$SEARCH_FILE" 2>/dev/null)
    if [[ "$cmd" != "$LAST_CMD" ]]; then
      LAST_CMD="$cmd"
      case "$cmd" in
        "/search "*)
          SEARCH_TERM="${cmd#/search }"
          echo -e "${YELLOW}🔍 Search filter: '$SEARCH_TERM'${NC}" >&2
          echo -e "${YELLOW}📝 Now showing only logs containing: '$SEARCH_TERM'${NC}" >&2
          ;;
        "/clear")
          SEARCH_TERM=""
          echo -e "${GREEN}✅ Search filter cleared - showing all logs${NC}" >&2
          ;;
        "/help")
          echo -e "${BOLD}Available commands:${NC}" >&2
          echo -e "${YELLOW}echo '/search error' >> $SEARCH_FILE${NC}" >&2
          echo -e "${YELLOW}echo '/clear' >> $SEARCH_FILE${NC}" >&2
          echo -e "${YELLOW}echo '/help' >> $SEARCH_FILE${NC}" >&2
          ;;
      esac
    fi
  fi
  
  # If no search term, display everything
  if [[ -z "$SEARCH_TERM" ]]; then
    return 0
  fi
  
  # Remove ANSI color codes from formatted output for clean search
  local clean_formatted=$(echo "$formatted_output" | sed 's/\x1b\[[0-9;]*m//g')
  
  # Convert both to lowercase for case-insensitive search
  local original_lower=$(echo "$original_line" | tr '[:upper:]' '[:lower:]')
  local formatted_lower=$(echo "$clean_formatted" | tr '[:upper:]' '[:lower:]')
  local search_lower=$(echo "$SEARCH_TERM" | tr '[:upper:]' '[:lower:]')
  
  # Check if search term exists in either original line OR formatted output
  if echo "$original_lower" | grep -q "$search_lower" || echo "$formatted_lower" | grep -q "$search_lower"; then
    return 0
  else
    return 1
  fi
}

# Header
echo ""
echo -e "${BOLD}🔍 Android Logcat Monitor${NC}"
echo -e "${CYAN}📦 Package: $PACKAGE${NC}"
echo -e "${CYAN}📱 Device: $DEVICE_ID${NC}"
echo -e "${YELLOW}⏰ Started: $(date '+%Y-%m-%d %H:%M:%S')${NC}"
echo ""
echo -e "${YELLOW}💡 Search Commands (run in another terminal):${NC}"
echo -e "${YELLOW}   echo '/search error' >> $SEARCH_FILE${NC}"
echo -e "${YELLOW}   echo '/search network' >> $SEARCH_FILE${NC}"
echo -e "${YELLOW}   echo '/clear' >> $SEARCH_FILE${NC}"
echo ""
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Clear logcat
adb -s "$DEVICE_ID" logcat -c
sleep 1

# Get PID
APP_PID=$(adb -s "$DEVICE_ID" shell pidof -s "$PACKAGE" | tr -d '\r')

if [[ -z "$APP_PID" ]]; then
  echo -e "${RED}❌ Failed to get PID for package $PACKAGE${NC}"
  exit 1
fi

echo -e "${GREEN}🎯 Monitoring PID: $APP_PID${NC}"
echo -e "${GREEN}🔄 Live logs start... Press Ctrl+C to stop${NC}"
echo ""

# Cleanup function
cleanup() {
  rm -f "$SEARCH_FILE"
  exit 0
}
trap cleanup EXIT

LAST_CMD=""
in_exception=0

adb -s "$DEVICE_ID" logcat --pid=$APP_PID -v threadtime | while IFS= read -r line; do
  
  # Handle FATAL EXCEPTION
  if echo "$line" | grep -q "FATAL EXCEPTION"; then
    timestamp=$(echo "$line" | awk '{print $1, $2}')
    tag=$(echo "$line" | awk '{print $4}')
    msg=$(echo "$line" | cut -d' ' -f7-)

    if should_display_log "$line"; then
      echo -e "${RED}╔════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════${NC}"
      echo -e "${RED}║ ${BOLD}🚨 FATAL EXCEPTION DETECTED${NC}                                                                                    ${NC}"
      echo -e "${RED}╠════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════${NC}"
      echo -e "${RED}║ ${CYAN}Time:${NC} $timestamp                                                                                               ${NC}"
      echo -e "${RED}║ ${CYAN}Tag:${NC} $tag                                                                                                      ${NC}"
      echo -e "${RED}╚════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════${NC}"
      echo ""
      echo -e "${BOLD}📋 Exception Details:${NC}"
      echo -e "    ${RED}$msg${NC}"
    fi
    in_exception=1
    continue
  fi

  # Handle ERROR logs
  if echo "$line" | grep -q "$PACKAGE_NAME" && echo "$line" | grep -qE "\sE\s"; then
    timestamp=$(echo "$line" | awk '{print $1, $2}')
    tag=$(echo "$line" | awk '{print $4}')
    # Remove "E AndroidRuntime: " from the message
    msg=$(echo "$line" | sed 's/.*E AndroidRuntime:[[:space:]]*//')
  
    if should_display_log "$line"; then
      # Check for "Process:" pattern and make it red
      if echo "$msg" | grep -qE "at[[:space:]]+.*\([^)]+\.(java|kt):[0-9]+\)"; then
        # First, color the file reference (java/kt files) with cyan
        msg=$(echo "$msg" | sed -E "s/\(([A-Za-z0-9_]+\.[a-z]+:[0-9]+)\)/$(printf "%s${CYAN}%s${NC}%s" "(" "\1" ")")/g")
        # Then, color the "at" keyword with yellow
        msg=$(echo "$msg" | sed -E "s/^([[:space:]]*)at([[:space:]]+)/\1$(printf "${YELLOW}%s${NC}" "at")\2/")
        echo -e "${RED}[ERROR]${NC}   ${BLUE}$timestamp${NC} ${PURPLE}[$tag]${NC}      $msg"

      elif echo "$msg" | grep -qE "^[[:space:]]*at[[:space:]]+"; then
        # Handle any other "at" lines that don't match the previous pattern
        msg=$(echo "$msg" | sed -E "s/^([[:space:]]*)at([[:space:]]+)/\1$(printf "${YELLOW}%s${NC}" "at")\2/")
        echo -e "${RED}[ERROR]${NC}   ${BLUE}$timestamp${NC} ${PURPLE}[$tag]${NC}      $msg"

      elif echo "$msg" | grep -qE '^[^:]+:[[:space:]]*'; then
       # Special handling for "Caused by:" pattern
       if echo "$msg" | grep -q "^Caused by:"; then
         # Split the message by colons
         caused_by_part="Caused by"
         
         # Get everything after "Caused by:"
         after_caused_by=$(echo "$msg" | sed 's/^Caused by:[[:space:]]*//')
      
         # Check if there's another colon in the remaining text
         if echo "$after_caused_by" | grep -q ":"; then
           # Split at the next colon
           exception_part=$(echo "$after_caused_by" | cut -d':' -f1)
           final_part=$(echo "$after_caused_by" | cut -d':' -f2-)
           echo -e "${RED}[ERROR]${NC}   ${BLUE}$timestamp${NC} ${PURPLE}[$tag]${NC}  ${YELLOW}$caused_by_part${NC}: ${RED}$exception_part${NC}:${ORANGE}$final_part${NC}"
      
        else
          # No additional colon, just color the exception part red
          echo -e "${RED}[ERROR]${NC}   ${BLUE}$timestamp${NC} ${PURPLE}[$tag]${NC}  ${YELLOW}$caused_by_part${NC}: ${RED}$after_caused_by${NC}"
        fi

    else
      # Default handling for other patterns with colons
      process_part=$(echo "$msg" | cut -d':' -f1)
      rest_part=$(echo "$msg" | cut -d':' -f2-)
      echo -e "${RED}[ERROR]${NC}   ${BLUE}$timestamp${NC} ${PURPLE}[$tag]${NC}  ${YELLOW}$process_part${NC}:$rest_part"
    fi

      else
        echo -e "${RED}[ERROR]${NC}   ${BLUE}$timestamp${NC} ${PURPLE}[$tag]${NC}  $msg"
      fi
    fi
  fi
  
  # Handle NETWORK logs from OkHttp
  if echo "$line" | grep -q "okhttp.OkHttpClient"; then
    timestamp=$(echo "$line" | awk '{print $1, $2}')
    tag=$(echo "$line" | awk '{print $4}')
    # Extract message after "okhttp.OkHttpClient: "
    msg=$(echo "$line" | sed 's/.*okhttp\.OkHttpClient:[[:space:]]*//')
 
    # Create the formatted output first to check against search
    formatted_output=""
    
    # Check for JSON error patterns
    if echo "$msg" | grep -qE '^\{"(errors?)":[[:space:]]*'; then
      formatted_output="${YELLOW}[NETWORK]${NC} ${BLUE}$timestamp${NC} ${PURPLE}[$tag]${NC}  ${RED}--> [ERROR] ${NC}${ORANGE}Result${NC}: ${RED}$msg${NC}"

    # Check for complete JSON patterns (starts with { and ends with })
    elif echo "$msg" | grep -qE '^\{.*\}[[:space:]]*$'; then
      formatted_output="${YELLOW}[NETWORK]${NC} ${BLUE}$timestamp${NC} ${PURPLE}[$tag]${NC}  ${GREEN}--> [SUCCESS] ${NC}${ORANGE}Result${NC}: ${GREEN}$msg${NC}"

    # Check for any JSON that starts with { (including incomplete ones)
    elif echo "$msg" | grep -qE '^\{'; then
      formatted_output="${YELLOW}[NETWORK]${NC} ${BLUE}$timestamp${NC} ${PURPLE}[$tag]${NC}  ${GREEN}--> [SUCCESS] ${NC}${ORANGE}Result${NC}: ${GREEN}$msg${NC}"

    # SIMPLIFIED: Check if contains quotes AND any JSON character
    elif echo "$msg" | grep -q '"' && echo "$msg" | grep -q ':' && ! echo "$msg" | grep -qE '^(nel|report-to):[[:space:]]*\{'; then
      formatted_output="${YELLOW}[NETWORK]${NC} ${BLUE}$timestamp${NC} ${PURPLE}[$tag]${NC}  ${GREEN}$msg${NC}"

    # SIMPLIFIED: Check if starts with number/letter and contains quotes
    elif echo "$msg" | grep -qE '^[0-9a-zA-Z]' && echo "$msg" | grep -q '"' && ! echo "$msg" | grep -qE '^(nel|report-to):[[:space:]]*\{'; then
      formatted_output="${YELLOW}[NETWORK]${NC} ${BLUE}$timestamp${NC} ${PURPLE}[$tag]${NC}  ${GREEN}$msg${NC}"
   
    # Check for --> or <-- patterns
    elif echo "$msg" | grep -qE "^(-->|<--)"; then
      if echo "$msg" | grep -qE "<-- [45][0-9][0-9]"; then          
        # Menambahkan tag [ERROR] setelah <-- dan sebelum angka
        modified_msg=$(echo "$msg" | sed 's/<-- \([45][0-9][0-9]\)/<-- [ERROR] \1/')
        formatted_output="${YELLOW}[NETWORK]${NC} ${BLUE}$timestamp${NC} ${PURPLE}[$tag]${NC}  ${RED}$modified_msg${NC}"
        
      elif echo "$msg" | grep -qE "<-- [23][0-9][0-9]"; then
        # Menambahkan tag [SUCCESS] setelah <-- dan sebelum angka untuk 2xx dan 3xx
        modified_msg=$(echo "$msg" | sed 's/<-- \([23][0-9][0-9]\)/<-- [SUCCESS] \1/')
        formatted_output="${YELLOW}[NETWORK]${NC} ${BLUE}$timestamp${NC} ${PURPLE}[$tag]${NC}  ${GREEN}$modified_msg${NC}"
        
      else
        # Untuk kasus lain (1xx atau --> request)
        formatted_output="${YELLOW}[NETWORK]${NC} ${BLUE}$timestamp${NC} ${PURPLE}[$tag]${NC}  ${YELLOW}$msg${NC}"
      fi
   
    # Check for header patterns first (key: value) - make key yellow
    elif echo "$msg" | grep -qE '^[^:]+:[[:space:]]*'; then
      key=$(echo "$msg" | cut -d':' -f1)
      value=$(echo "$msg" | cut -d':' -f2-)
      formatted_output="${YELLOW}[NETWORK]${NC} ${BLUE}$timestamp${NC} ${PURPLE}[$tag]${NC}      ${YELLOW}$key${NC}:$value"
    
    # Default case
    else
      formatted_output="${YELLOW}[NETWORK]${NC} ${BLUE}$timestamp${NC} ${PURPLE}[$tag]${NC}  $msg"
    fi

    # Now check if should display - check both original line AND formatted output
    if should_display_log_network "$line" "$formatted_output"; then
      echo -e "$formatted_output"
      
      # Check if this is an END message and display search commands
      if echo "$msg" | grep -qE "^<-- END"; then
        echo -e "--> ${CYAN}Search Commands Identifiers:${NC} ${BOLD}${YELLOW}$SEARCH_FILE${NC}"
      fi
    fi
    continue 
  fi

done