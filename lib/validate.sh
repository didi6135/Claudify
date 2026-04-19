# lib/validate.sh — input format validators
#
# Pure functions: take a string, return 0 if valid, non-zero otherwise.
# No I/O, no side effects. Used by the *_validated prompt helpers.

validate_bot_token() { [[ "$1" =~ ^[0-9]+:[A-Za-z0-9_-]+$ ]]; }
validate_user_id()   { [[ "$1" =~ ^[0-9]+$ ]]; }
validate_workspace() { [[ "$1" =~ ^[A-Za-z0-9._-]+$ ]]; }
