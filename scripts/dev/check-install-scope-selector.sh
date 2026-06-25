#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=scripts/core/common.sh
source "$PROJECT_DIR/scripts/core/common.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

PROJECT_DIR="$tmp_dir/project"
mkdir -p "$PROJECT_DIR"
touch "$PROJECT_DIR/install.sh"

reset_scope_state() {
  INSTALL_SCOPE=""
  INSTALL_HOME=""
  RUNTIME_DIR=""
  BIN_DIR=""
  LOG_DIR=""
  SELECTOR_PROMPTED="false"
  RERUN_AS_ROOT="false"
  MOCK_IS_ROOT="false"
  MOCK_SUDO_AVAILABLE="false"
  MOCK_TTY="false"
  MOCK_SELECTED_SCOPE="user"
  : > "$tmp_dir/prompted"
  : > "$tmp_dir/rerun"
}

id() {
  if [ "${1:-}" = "-u" ]; then
    if [ "$MOCK_IS_ROOT" = "true" ]; then
      printf '0\n'
    else
      printf '1000\n'
    fi
    return 0
  fi

  command id "$@"
}

install_sudo_available() {
  [ "$MOCK_SUDO_AVAILABLE" = "true" ]
}

install_scope_choice_tty() {
  [ "$MOCK_TTY" = "true" ]
}

install_prompt_scope_choice() {
  printf 'prompted\n' >> "$tmp_dir/prompted"
  if ! install_scope_choice_tty; then
    printf 'user\n'
    return 0
  fi

  printf '%s\n' "$MOCK_SELECTED_SCOPE"
}

rerun_install_as_root_system() {
  printf 'rerun\n' >> "$tmp_dir/rerun"
  return 77
}

assert_equal() {
  local name="$1"
  local actual="$2"
  local expected="$3"

  if [ "$actual" != "$expected" ]; then
    echo "not ok - $name: got '$actual', expected '$expected'" >&2
    return 1
  fi

  echo "ok - $name"
}

reset_scope_state
detect_install_scope user
assert_equal "explicit user selects user scope" "$INSTALL_SCOPE" "user"
assert_equal "explicit user does not prompt" "$(wc -l < "$tmp_dir/prompted" | tr -d ' ')" "0"

reset_scope_state
detect_install_scope system
assert_equal "explicit system selects system scope" "$INSTALL_SCOPE" "system"
assert_equal "explicit system does not prompt" "$(wc -l < "$tmp_dir/prompted" | tr -d ' ')" "0"

reset_scope_state
MOCK_IS_ROOT="true"
detect_install_scope auto
assert_equal "root auto selects system scope" "$INSTALL_SCOPE" "system"
assert_equal "root auto does not prompt" "$(wc -l < "$tmp_dir/prompted" | tr -d ' ')" "0"

reset_scope_state
detect_install_scope auto
assert_equal "non-root without sudo selects user scope" "$INSTALL_SCOPE" "user"
assert_equal "non-root without sudo does not prompt" "$(wc -l < "$tmp_dir/prompted" | tr -d ' ')" "0"

reset_scope_state
MOCK_SUDO_AVAILABLE="true"
detect_install_scope auto
assert_equal "non-root sudo non-tty prompts through default path" "$(wc -l < "$tmp_dir/prompted" | tr -d ' ')" "1"
assert_equal "non-root sudo non-tty selects user scope" "$INSTALL_SCOPE" "user"

reset_scope_state
MOCK_SUDO_AVAILABLE="true"
MOCK_TTY="true"
MOCK_SELECTED_SCOPE="user"
detect_install_scope auto
assert_equal "non-root sudo tty user choice prompts" "$(wc -l < "$tmp_dir/prompted" | tr -d ' ')" "1"
assert_equal "non-root sudo tty user choice selects user scope" "$INSTALL_SCOPE" "user"

reset_scope_state
MOCK_SUDO_AVAILABLE="true"
MOCK_TTY="true"
MOCK_SELECTED_SCOPE="system"
set +e
detect_install_scope auto
rc=$?
set -e
assert_equal "non-root sudo tty system choice calls root rerun" "$(wc -l < "$tmp_dir/rerun" | tr -d ' ')" "1"
assert_equal "non-root sudo tty system choice stops current flow" "$rc" "77"
