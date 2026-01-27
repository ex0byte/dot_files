#!/usr/bin/env bash

# Disable colors if not a TTY or if NO_COLOR is set
if [[ -t 1 && -z "$NO_COLOR" ]]; then
  RED=$'\e[31m'
  GREEN=$'\e[32m'
  YELLOW=$'\e[33m'
  BLUE=$'\e[34m'
  BOLD=$'\e[1m'
  RESET=$'\e[0m'
else
  RED="" GREEN="" YELLOW="" BLUE="" BOLD="" RESET=""
fi

# ASCII symbols
OK="[OK]"
FAIL="[FAIL]"
WARN="[WARN]"
INFO="[INFO]"
ARROW="->"

# Helper functions
ok() {
  echo -e "${GREEN}${OK} $*${RESET}"
}

info() {
  echo -e "${BLUE}${INFO} $*${RESET}"
}

warn() {
  echo -e "${YELLOW}${WARN} $*${RESET}"
}

fail() {
  echo -e "${RED}${FAIL} $*${RESET}"
}

die() {
  echo -e "${RED}${FAIL} $*${RESET}"
  exit 1
}

prompt_read() {
  local var="$1"; shift
  if ! read -rp "${BLUE}${ARROW} $* ${RESET}" "$var"; then
    die "Input aborted"
  fi
}

prompt_read_password() {
  local var="$1"; shift
  if ! read -rsp "${BLUE}${ARROW} $* ${RESET}" "$var"; then
    echo
    die "Input aborted"
  fi
  echo
}

confirm() {
  local reply
  while true; do
    prompt_read reply "$1 (y/n):"
    case "$reply" in
      [Yy]* ) return 0 ;;
      [Nn]* ) return 1 ;;
      * ) warn "Please answer y or n" ;;
    esac
  done
}
