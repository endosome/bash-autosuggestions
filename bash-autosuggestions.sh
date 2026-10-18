#!/usr/bin/env bash
# ============================================================================
# bash-autosuggestions.sh - Fish-like autosuggestions for Bash
# ============================================================================
#
# KEYBINDINGS:
#   → (Right Arrow) / End    Accept full suggestion
#   Alt+→ / Alt+F            Accept next word
#   ↑ (Up Arrow)             Next suggestion (cycle)
#   ↓ (Down Arrow)           Previous suggestion (cycle)
#   Ctrl+]                   Dismiss suggestion
#   Enter                    Execute typed text (ghost is stripped)
#
# CONFIGURATION (set before sourcing):
#   BASH_AUTOSUGGEST_HIGHLIGHT  - ANSI SGR code (default: "38;5;244")
#   BASH_AUTOSUGGEST_STRATEGY   - "history" (default) or "match_prev_cmd"
#   BASH_AUTOSUGGEST_MIN_LENGTH - min chars before suggesting (default: 1)
#   BASH_AUTOSUGGEST_HISTORY_IGNORE - glob pattern to skip
#
# REQUIREMENTS: Bash 4.4+ (prompt expansion for synchronous rendering)
# ============================================================================

[[ $- != *i* ]] && return
(( BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 4) )) || return 0
[[ -t 0 && -t 1 && ${TERM:-dumb} != dumb ]] || return 0
[[ -o emacs ]] || return 0
[[ -n "${_BASH_AUTOSUGGEST_LOADED:-}" ]] && return 0
_BASH_AUTOSUGGEST_LOADED=1
_bas_source_file="${BASH_SOURCE[0]}"
shopt -s extglob

: "${BASH_AUTOSUGGEST_HIGHLIGHT:=38;5;244}"
: "${BASH_AUTOSUGGEST_STRATEGY:=history}"
: "${BASH_AUTOSUGGEST_MIN_LENGTH:=1}"
: "${BASH_AUTOSUGGEST_HISTORY_IGNORE:=}"
: "${BASH_AUTOSUGGEST_MAX_CANDIDATES:=50}"

# --- Internal state ---
_bas_typed=""             # What the user actually typed
_bas_ghost=""             # The ghost suffix currently displayed
_bas_history=()           # History snapshot, rebuilt at each prompt
_bas_candidates=()        # All matching history entries
_bas_cand_idx=-1          # Current index in candidates (-1 = none)
_bas_showing=0            # Whether ghost text is on screen
_bas_prev_cmd=""          # Previous command (for match_prev_cmd strategy)
_bas_enabled=1            # Whether autosuggestions are enabled
_bas_pending_ghost=""     # Ghost text to display after readline redraws
_bas_pending_counter=""   # Counter text to display

# ============================================================================
# History: collect ALL matches (deduplicated, most recent first)
# ============================================================================
_bas_collect_candidates() {
    local input="$1"
    _bas_candidates=()
    _bas_cand_idx=-1

    (( ${#input} < BASH_AUTOSUGGEST_MIN_LENGTH )) && return

    local -A seen=()
    local line prev_line=""
    local contextual_matches=()
    local regular_matches=()
    
    # The prompt hook already parsed history; typing never forks or calls tac.
    for line in "${_bas_history[@]}"; do
        # Check if this line matches our input prefix
        if [[ "$line" == "$input"* && "$line" != "$input" && -z "${seen[$line]+x}" ]]; then
            if [[ -n "$BASH_AUTOSUGGEST_HISTORY_IGNORE" ]]; then
                # The configured value is a glob pattern, never shell code.
                # shellcheck disable=SC2053
                [[ "$line" == $BASH_AUTOSUGGEST_HISTORY_IGNORE ]] && continue
            fi
            seen[$line]=1
            
            # For match_prev_cmd strategy: check if prev_line matches _bas_prev_cmd
            if [[ "$BASH_AUTOSUGGEST_STRATEGY" == "match_prev_cmd" && -n "$_bas_prev_cmd" ]]; then
                if [[ "$prev_line" == "$_bas_prev_cmd" ]]; then
                    # This is a contextual match - add to priority list
                    contextual_matches+=("$line")
                else
                    regular_matches+=("$line")
                fi
            else
                # Regular history strategy
                _bas_candidates+=("$line")
                (( ${#_bas_candidates[@]} >= BASH_AUTOSUGGEST_MAX_CANDIDATES )) && break
            fi
        fi
        
        # Track previous line for context matching
        if [[ -n "$line" ]]; then
            prev_line="$line"
        fi
    done
    
    # For match_prev_cmd: combine contextual matches first, then regular
    if [[ "$BASH_AUTOSUGGEST_STRATEGY" == "match_prev_cmd" ]]; then
        _bas_candidates=("${contextual_matches[@]}" "${regular_matches[@]}")
        # Truncate to max candidates
        if (( ${#_bas_candidates[@]} > BASH_AUTOSUGGEST_MAX_CANDIDATES )); then
            _bas_candidates=("${_bas_candidates[@]:0:$BASH_AUTOSUGGEST_MAX_CANDIDATES}")
        fi
    fi
}

# ============================================================================
# Display: foreground rendering at the end of the typed input.
# Bash clears the last prompt line before a bind -x handler, then redraws it
# afterwards. Draw the suffix at its final column and restore column zero;
# readline's redraw fills in the prompt/input without overwriting the suffix.
# No background writer can race with typing, command output, or Ctrl-C.
# ============================================================================
_bas_cache_prompt() {
    _bas_prompt_text=${1-${PS1@P}}
    _bas_prompt_text="${_bas_prompt_text##*$'\n'}"
    local prompt="$_bas_prompt_text" ansi
    # \[...\] in PS1 becomes readline's SOH/STX nonprinting region. Trust
    # those regions as readline does: charset selectors, tput resets and other
    # terminal controls inside them all contribute zero visible columns.
    ansi=$'\001[^\002]*\002'
    while [[ $prompt =~ $ansi ]]; do
        prompt="${prompt/"${BASH_REMATCH[0]}"/}"
    done
    _bas_prompt_text="${_bas_prompt_text//$'\001'/}"
    _bas_prompt_text="${_bas_prompt_text//$'\002'/}"
    ansi=$'\e''].*'$'\a'
    while [[ $prompt =~ $ansi ]]; do
        prompt="${prompt/"${BASH_REMATCH[0]}"/}"
    done
    ansi=$'\e].*\e\\\\'
    while [[ $prompt =~ $ansi ]]; do
        prompt="${prompt/"${BASH_REMATCH[0]}"/}"
    done
    ansi=$'\e''\[[0-?]*[ -/]*[@-~]'
    while [[ $prompt =~ $ansi ]]; do
        prompt="${prompt/"${BASH_REMATCH[0]}"/}"
    done
    local LC_ALL=C
    _bas_prompt_width=-1
    if [[ $prompt != *[!\ -~]* ]]; then
        _bas_prompt_width=${#prompt}
    else
        # Non-ASCII prompt text is common (directories, branch names, themes).
        # Count display columns, including wide glyphs, once per prompt. GNU
        # coreutils is already used for tac; older/non-GNU wc can fail safely.
        local display_width
        if display_width=$(printf '%s' "$prompt" | LC_ALL=C.UTF-8 command wc --max-line-length 2>/dev/null); then
            display_width="${display_width//[[:space:]]/}"
            if [[ $display_width =~ ^[0-9]+$ ]]; then
                _bas_prompt_width=$display_width
            fi
        fi
    fi
}

_bas_refresh_history() {
    _bas_history=()
    local line
    while IFS='' read -r line; do
        line="${line#"${line%%[! ]*}"}"
        line="${line##+([0-9])}"
        line="${line#"${line%%[! ]*}"}"
        _bas_history+=("$line")
    done < <(HISTTIMEFORMAT='' builtin history | tac)
}

_bas_dispatch() {
    # Bash clears the input before entering bind -x. Restore it immediately,
    # before looking at history, so a slow lookup never leaves a blank prompt.
    local LC_ALL=C restored=0 old_length=${#READLINE_LINE}
    if ((_bas_prompt_width >= 0 && _bas_prompt_width + ${#READLINE_LINE} < ${COLUMNS:-80})) &&
        [[ $READLINE_LINE != *[!\ -~]* ]]; then
        printf '%s%s' "$_bas_prompt_text" "$READLINE_LINE" >/dev/tty
        restored=1
    fi
    "$@"
    local handler_status=$?
    # The temporary restore must not leave deleted characters behind when
    # readline redraws a shorter buffer over what it believes is a blank line.
    if ((restored && ${#READLINE_LINE} < old_length)); then
        printf '\r\e[%dC\e[K' "$((_bas_prompt_width + ${#READLINE_LINE}))" >/dev/tty
        if ((_bas_showing)); then
            _bas_show_ghost "$_bas_ghost"
        fi
    fi
    # Readline believes the cursor is still at column zero after its clear.
    printf '\r' >/dev/tty
    return "$handler_status"
}

_bas_show_ghost() {
    local suffix="$1" LC_ALL=C
    [[ -n "$suffix" && $READLINE_LINE != *[!\ -~]* && $suffix != *[!\ -~]* ]] || return 0
    ((_bas_prompt_width >= 0)) || return 0
    local width=${COLUMNS:-80}
    ((width > 0)) || return 0
    local offset=$((_bas_prompt_width + ${#READLINE_LINE}))
    local row=$((offset / width)) column=$((offset % width))
    local available=$((width - column - 1))
    ((available > 0)) || return 0
    local counter="" count=${#_bas_candidates[@]}
    if ((count > 1)); then
        counter=" [$((_bas_cand_idx + 1))/$count]"
    fi
    if ((${#suffix} + ${#counter} > available)); then
        counter=""
    fi
    _bas_ghost="$suffix"
    _bas_showing=1
    # Readline clears wrapped input back to the first physical prompt row.
    # Position relative to that origin rather than suppressing wrapped lines.
    {
        printf '\e7\r'
        if ((row > 0)); then printf '\e[%dB' "$row"; fi
        if ((column > 0)); then printf '\e[%dC' "$column"; fi
        printf '\e[%sm%s\e[0m\e[2m%s\e[0m\e8' \
            "$BASH_AUTOSUGGEST_HIGHLIGHT" "${suffix:0:available}" "$counter"
    } >/dev/tty
}

_bas_clear_ghost() {
    # Readline already erased the previous suffix before calling bind -x.
    # A second erase would blank the input restored by _bas_dispatch.
    _bas_ghost=""
    _bas_showing=0
    # Also clear any pending ghost that hasn't been displayed yet
    _bas_pending_ghost=""
    _bas_pending_counter=""
}


# ============================================================================
# Core: update suggestion after a keystroke
# ============================================================================
_bas_update() {
    local typed="$1"
    _bas_typed="$typed"

    READLINE_LINE="$typed"
    READLINE_POINT=${#typed}

    _bas_clear_ghost

    # Skip if disabled
    if (( ! _bas_enabled )); then
        return
    fi

    if [[ -z "$typed" ]]; then
        _bas_candidates=()
        _bas_cand_idx=-1
        return
    fi

    _bas_collect_candidates "$typed"

    if (( ${#_bas_candidates[@]} > 0 )); then
        _bas_cand_idx=0
        local suffix="${_bas_candidates[0]:${#typed}}"
        _bas_show_ghost "$suffix"
    fi
}

# Show candidate at current index
_bas_show_current_candidate() {
    _bas_clear_ghost
    if (( _bas_cand_idx >= 0 && _bas_cand_idx < ${#_bas_candidates[@]} )); then
        local suffix="${_bas_candidates[$_bas_cand_idx]:${#_bas_typed}}"
        
        # Prepare the foreground display.
        _bas_pending_ghost="$suffix"
        _bas_pending_counter=""
        if (( ${#_bas_candidates[@]} > 1 )); then
            _bas_pending_counter=" [$((_bas_cand_idx+1))/${#_bas_candidates[@]}]"
        fi
        
        _bas_show_ghost_after_redisplay
    fi
}

# ============================================================================
# Key handlers
#
# IMPORTANT: bind -x replaces the normal key action.
# We must manually insert the character into READLINE_LINE.
# ============================================================================
_bas_show_ghost_after_redisplay() {
    if [[ -n "$_bas_pending_ghost" ]]; then
        _bas_show_ghost "$_bas_pending_ghost"
        _bas_pending_ghost=""
        _bas_pending_counter=""
    fi
}

_bas_self_insert_and_update() {
    local char="$1"
    _bas_clear_ghost
    _bas_candidates=()
    _bas_cand_idx=-1
    
    # Insert character at cursor position
    local line="$READLINE_LINE"
    local pos="$READLINE_POINT"
    local before="${line:0:$pos}"
    local after="${line:$pos}"
    
    local new_line="${before}${char}${after}"
    local new_point=$((pos + 1))
    
    # Only show suggestions if typing at end of line and enabled
    if [[ -z "$after" ]] && (( _bas_enabled )); then
        local typed="${before}${char}"
        _bas_typed="$typed"
        
        if [[ -n "$typed" && ${#typed} -ge $BASH_AUTOSUGGEST_MIN_LENGTH ]]; then
            _bas_collect_candidates "$typed"
            
            if (( ${#_bas_candidates[@]} > 0 )); then
                _bas_cand_idx=0
                local suffix="${_bas_candidates[0]:${#typed}}"
                
                # Draw at the final input column before readline redraws.
                _bas_pending_ghost="$suffix"
                _bas_pending_counter=""
                if (( ${#_bas_candidates[@]} > 1 )); then
                    _bas_pending_counter=" [$((_bas_cand_idx+1))/${#_bas_candidates[@]}]"
                fi
                
                # Update readline variables - this causes a redisplay
                READLINE_LINE="$new_line"
                READLINE_POINT=$new_point
                
                _bas_show_ghost_after_redisplay
                return
            fi
        fi
    else
        # Typing in middle of line - no suggestions
        _bas_candidates=()
        _bas_cand_idx=-1
        _bas_typed="${before}${char}"
    fi
    
    # Update readline variables
    READLINE_LINE="$new_line"
    READLINE_POINT=$new_point
}

_bas_backspace_handler() {
    # Delete character before cursor
    local line="$READLINE_LINE"
    local pos="$READLINE_POINT"
    
    if (( pos > 0 )); then
        local before="${line:0:$((pos-1))}"
        local after="${line:$pos}"
        
        READLINE_LINE="${before}${after}"
        READLINE_POINT=$((pos - 1))
        
        # Clear state immediately - call _bas_clear_ghost to clear visible ghost
        _bas_clear_ghost
        
        # Only show suggestions if at end of line and enabled
        if [[ -z "$after" ]] && (( _bas_enabled )); then
            local typed="$before"
            _bas_typed="$typed"
            
            if [[ -n "$typed" && ${#typed} -ge $BASH_AUTOSUGGEST_MIN_LENGTH ]]; then
                _bas_collect_candidates "$typed"
                
                if (( ${#_bas_candidates[@]} > 0 )); then
                    _bas_cand_idx=0
                    local suffix="${_bas_candidates[0]:${#typed}}"
                    
                    # Prepare the foreground display.
                    _bas_pending_ghost="$suffix"
                    _bas_pending_counter=""
                    if (( ${#_bas_candidates[@]} > 1 )); then
                        _bas_pending_counter=" [1/${#_bas_candidates[@]}]"
                    fi
                    _bas_show_ghost_after_redisplay
                else
                    _bas_candidates=()
                    _bas_cand_idx=-1
                fi
            else
                _bas_candidates=()
                _bas_cand_idx=-1
                # Clear any pending ghost and cancel any scheduled display
                _bas_pending_ghost=""
                _bas_pending_counter=""
            fi
        else
            _bas_candidates=()
            _bas_cand_idx=-1
            _bas_typed="$before"
            # Clear any pending ghost and cancel any scheduled display
            _bas_pending_ghost=""
            _bas_pending_counter=""
        fi
    else
        # At start of line - clear everything
        _bas_candidates=()
        _bas_cand_idx=-1
        _bas_pending_ghost=""
        _bas_pending_counter=""
    fi
}

_bas_delete_handler() {
    if (( READLINE_POINT < ${#READLINE_LINE} )); then
        READLINE_LINE="${READLINE_LINE:0:READLINE_POINT}${READLINE_LINE:READLINE_POINT+1}"
    fi
    _bas_clear_ghost
    _bas_candidates=()
    _bas_cand_idx=-1
    _bas_typed="$READLINE_LINE"
}

_bas_kill_word_handler() {
    _bas_clear_ghost
    
    # Kill word backward from cursor
    local line="$READLINE_LINE"
    local pos="$READLINE_POINT"
    local before="${line:0:$pos}"
    local after="${line:$pos}"
    
    # Remove trailing spaces then word
    before="${before%"${before##*[! ]}"}"
    before="${before%"${before##* }"}"
    
    READLINE_LINE="${before}${after}"
    READLINE_POINT=${#before}
    
    # Only show suggestions if at end of line and enabled
    if [[ -z "$after" ]] && (( _bas_enabled )); then
        local typed="$before"
        _bas_typed="$typed"
        
        if [[ -n "$typed" && ${#typed} -ge $BASH_AUTOSUGGEST_MIN_LENGTH ]]; then
            _bas_collect_candidates "$typed"
            
            if (( ${#_bas_candidates[@]} > 0 )); then
                _bas_cand_idx=0
                local suffix="${_bas_candidates[0]:${#typed}}"
                
                # Prepare the foreground display.
                _bas_pending_ghost="$suffix"
                _bas_pending_counter=""
                if (( ${#_bas_candidates[@]} > 1 )); then
                    _bas_pending_counter=" [1/${#_bas_candidates[@]}]"
                fi
                _bas_show_ghost_after_redisplay
            else
                _bas_candidates=()
                _bas_cand_idx=-1
            fi
        else
            _bas_candidates=()
            _bas_cand_idx=-1
        fi
    else
        _bas_candidates=()
        _bas_cand_idx=-1
        _bas_typed="$before"
    fi
}

_bas_kill_line_handler() {
    _bas_clear_ghost
    
    READLINE_LINE=""
    READLINE_POINT=0
    _bas_typed=""
    _bas_candidates=()
    _bas_cand_idx=-1
}

# ============================================================================
# Suggestion cycling (Up / Down arrows)
# ============================================================================
_bas_cycle_next() {
    if (( ${#_bas_candidates[@]} > 1 )); then
        # Multiple suggestions available - cycle through them
        _bas_cand_idx=$(( (_bas_cand_idx + 1) % ${#_bas_candidates[@]} ))
        _bas_clear_ghost
        
        # Prepare ghost for display
        local suffix="${_bas_candidates[$_bas_cand_idx]:${#_bas_typed}}"
        _bas_pending_ghost="$suffix"
        _bas_pending_counter=""
        if (( ${#_bas_candidates[@]} > 1 )); then
            _bas_pending_counter=" [$((_bas_cand_idx+1))/${#_bas_candidates[@]}]"
        fi
        
        # Render before readline redraws the input.
        _bas_show_ghost_after_redisplay
    elif (( ${#_bas_candidates[@]} == 1 )); then
        # Only one suggestion - do nothing (or could fall back to history)
        :
    else
        # No suggestions - fall back to normal history navigation
        _bas_clear_ghost
        _bas_typed="$READLINE_LINE"
        # Use readline's built-in previous-history function
        bind '"\e[A": previous-history'
        bind '"\eOA": previous-history'
        # Trigger the history command by simulating the keypress
        # (this won't work perfectly, but better than nothing)
        # User can press Up again for history navigation
    fi
}

_bas_cycle_prev() {
    if (( ${#_bas_candidates[@]} > 1 )); then
        # Multiple suggestions available - cycle through them
        _bas_cand_idx=$(( (_bas_cand_idx - 1 + ${#_bas_candidates[@]}) % ${#_bas_candidates[@]} ))
        _bas_clear_ghost
        
        # Prepare ghost for display
        local suffix="${_bas_candidates[$_bas_cand_idx]:${#_bas_typed}}"
        _bas_pending_ghost="$suffix"
        _bas_pending_counter=""
        if (( ${#_bas_candidates[@]} > 1 )); then
            _bas_pending_counter=" [$((_bas_cand_idx+1))/${#_bas_candidates[@]}]"
        fi
        
        # Render before readline redraws the input.
        _bas_show_ghost_after_redisplay
    elif (( ${#_bas_candidates[@]} == 1 )); then
        # Only one suggestion - do nothing
        :
    else
        # No suggestions - fall back to normal history navigation
        _bas_clear_ghost
        _bas_typed="$READLINE_LINE"
        bind '"\e[B": next-history'
        bind '"\eOB": next-history'
    fi
}

# ============================================================================
# Accept / dismiss
# ============================================================================
_bas_accept_full() {
    if (( _bas_showing )) && (( READLINE_POINT == ${#READLINE_LINE} )) &&
        [[ $READLINE_LINE == "$_bas_typed" ]] && (( ${#_bas_candidates[@]} > 0 )); then
        _bas_clear_ghost
        READLINE_LINE="${_bas_candidates[$_bas_cand_idx]}"
        READLINE_POINT=${#READLINE_LINE}
        _bas_typed="$READLINE_LINE"  # Update typed to match accepted line
        _bas_showing=0
        _bas_candidates=()
        _bas_cand_idx=-1
    else
        # Default: move cursor right
        (( READLINE_POINT < ${#READLINE_LINE} )) && (( READLINE_POINT++ ))
    fi
}

_bas_accept_end() {
    if (( _bas_showing )) && (( READLINE_POINT == ${#READLINE_LINE} )) &&
        [[ $READLINE_LINE == "$_bas_typed" ]] && (( ${#_bas_candidates[@]} > 0 )); then
        _bas_clear_ghost
        READLINE_LINE="${_bas_candidates[$_bas_cand_idx]}"
        READLINE_POINT=${#READLINE_LINE}
        _bas_typed="$READLINE_LINE"  # Update typed to match accepted line
        _bas_showing=0
        _bas_candidates=()
        _bas_cand_idx=-1
    else
        READLINE_POINT=${#READLINE_LINE}
    fi
}

_bas_accept_word() {
    if (( _bas_showing )) && (( READLINE_POINT == ${#READLINE_LINE} )) &&
        [[ $READLINE_LINE == "$_bas_typed" ]] && (( ${#_bas_candidates[@]} > 0 )); then
        _bas_clear_ghost
        local full="${_bas_candidates[$_bas_cand_idx]}"
        local remaining="${full:${#_bas_typed}}"

        local word="" i=0 len=${#remaining}
        while (( i < len )) && [[ "${remaining:$i:1}" == " " ]]; do
            word+="${remaining:$i:1}"; (( i++ ))
        done
        while (( i < len )) && [[ "${remaining:$i:1}" != " " ]]; do
            word+="${remaining:$i:1}"; (( i++ ))
        done

        if [[ -n "$word" ]]; then
            _bas_typed+="$word"
            READLINE_LINE="$_bas_typed"
            READLINE_POINT=${#_bas_typed}
        fi

        # Re-collect candidates for the new typed prefix and show ghost
        _bas_collect_candidates "$_bas_typed"
        if (( ${#_bas_candidates[@]} > 0 )); then
            _bas_cand_idx=0
            local suffix="${_bas_candidates[0]:${#_bas_typed}}"
            if [[ -n "$suffix" ]]; then
                _bas_show_ghost "$suffix"
            else
                _bas_showing=0
            fi
        fi
    else
        local pos=$READLINE_POINT len=${#READLINE_LINE}
        while (( pos < len )) && [[ "${READLINE_LINE:$pos:1}" != " " ]]; do (( pos++ )); done
        while (( pos < len )) && [[ "${READLINE_LINE:$pos:1}" == " " ]]; do (( pos++ )); done
        READLINE_POINT=$pos
    fi
}

_bas_dismiss() {
    _bas_clear_ghost
    _bas_candidates=()
    _bas_cand_idx=-1
}

# ============================================================================
# Enter handler
#
# If ghost is showing, we just clear it — READLINE_LINE already contains
# only the typed text (ghost is purely visual via ANSI).
# Then we rebind Enter to accept-line and reinject it.
# ============================================================================
_bas_enter_handler() {
    # Only intercept if there's a ghost to clear
    # Otherwise, let Enter work normally by not rebinding
    if (( _bas_showing )); then
        _bas_clear_ghost
        _bas_candidates=()
        _bas_cand_idx=-1
    fi
    
    # Save current command for match_prev_cmd strategy
    _bas_prev_cmd="$READLINE_LINE"

    # Unbind our handler and rebind to accept-line for THIS press
    bind '"\C-m": accept-line'
    bind '"\C-j": accept-line'
    
    # Inject Enter to trigger the now-bound accept-line
    # Use ANSI sequence to inject key into input buffer
    # \x1b[200~ starts bracketed paste, then send \r, then \x1b[201~ ends it
    printf '\r' >&2
}

_bas_rebind_enter() {
    bind -x '"\C-m": _bas_dispatch _bas_enter_handler'
    bind -x '"\C-j": _bas_dispatch _bas_enter_handler'
}

# ============================================================================
# Setup
# ============================================================================
_bas_setup() {
    # Keep readline's own reusable syntax; restoring a shell binding must not
    # execute it. Snapshot again on every activation to respect later changes.
    _bas_saved_bindings=()
    _bas_saved_shell_bindings=()
    _bas_bound_keys=()
    local binding key
    while IFS= read -r binding; do
        [[ $binding == \"* ]] && _bas_saved_bindings+=("$binding")
    done < <(bind -p; bind -s)
    mapfile -t _bas_saved_shell_bindings < <(bind -X)

    # Readline otherwise replaces our backspace/kill bindings with the tty's
    # erase/kill actions when it prepares the first interactive input line.
    local option value
    while read -r _ option value; do
        if [[ $option == bind-tty-special-chars ]]; then
            _bas_saved_bind_tty_special_chars="$value"
            break
        fi
    done < <(bind -v)
    bind 'set bind-tty-special-chars off'
    
    # Accept / dismiss
    bind -x '"\e[C":    _bas_dispatch _bas_accept_full'
    bind -x '"\eOC":    _bas_dispatch _bas_accept_full'
    bind -x '"\e[F":    _bas_dispatch _bas_accept_end'
    bind -x '"\eOF":    _bas_dispatch _bas_accept_end'
    bind -x '"\e[4~":   _bas_dispatch _bas_accept_end'
    bind -x '"\e[1;3C": _bas_dispatch _bas_accept_word'
    bind -x '"\e\e[C":  _bas_dispatch _bas_accept_word'
    bind -x '"\ef":     _bas_dispatch _bas_accept_word'
    bind -x '"\C-]":    _bas_dispatch _bas_dismiss'

    # Suggestion cycling
    bind -x '"\e[A": _bas_dispatch _bas_cycle_next'       # Up arrow
    bind -x '"\eOA": _bas_dispatch _bas_cycle_next'       # Up arrow (alt seq)
    bind -x '"\e[B": _bas_dispatch _bas_cycle_prev'       # Down arrow
    bind -x '"\eOB": _bas_dispatch _bas_cycle_prev'       # Down arrow (alt seq)

    # Editing keys
    bind -x '"\C-?": _bas_dispatch _bas_backspace_handler'
    bind -x '"\C-h": _bas_dispatch _bas_backspace_handler'
    bind -x '"\e[3~": _bas_dispatch _bas_delete_handler'
    bind -x '"\C-w": _bas_dispatch _bas_kill_word_handler'
    bind -x '"\C-u": _bas_dispatch _bas_kill_line_handler'

    # Printable characters (ASCII 32-126)
    local code char funcname octal
    for code in $(seq 32 126); do
        printf -v octal '%03o' "$code"
        printf -v char '%b' "\\$octal"
        funcname="_bas_k${code}"
        eval "${funcname}() { _bas_self_insert_and_update $(printf '%q' "$char"); }"
        case "$code" in
            34) bind -x '"\"": _bas_dispatch _bas_k34' ;;
            39) bind -x "\"'\": _bas_dispatch _bas_k39" ;;
            92) bind -x '"\\": _bas_dispatch _bas_k92' ;;
            *)  bind -x "\"${char}\": _bas_dispatch ${funcname}" ;;
        esac
    done

    # bind -X normalizes escape spellings to match bind -p/-s. Only these
    # keys belong to us; unrelated bindings added while active stay intact.
    while IFS= read -r binding; do
        [[ $binding == *'"_bas_dispatch '* ]] || continue
        key=${binding#\"}
        _bas_bound_keys+=("${key%%\" *}")
    done < <(bind -X)
    _bas_bindings_active=1

    # Enter - DON'T bind Enter to avoid double-press issue
    # Ghost will be cleared by PROMPT_COMMAND after command executes
    # _bas_rebind_enter

    # Bash reads HISTFILE after startup files; reading it here duplicates it.

    # PROMPT_COMMAND
    _bas_prompt_hook() {
        # Expand before any command changes $?: status-dependent prompt text
        # must have the same width here as in readline's subsequent expansion.
        local command_status=$? expanded_prompt=${PS1@P}
        _bas_cache_prompt "$expanded_prompt"
        _bas_refresh_history
        _bas_showing=0
        _bas_ghost=""
        _bas_typed=""
        _bas_candidates=()
        _bas_cand_idx=-1
        # _bas_rebind_enter  # Not binding Enter anymore
        # Rebind arrows in case they were temporarily rebound for history nav
        bind -x '"\e[A": _bas_dispatch _bas_cycle_next'
        bind -x '"\eOA": _bas_dispatch _bas_cycle_next'
        bind -x '"\e[B": _bas_dispatch _bas_cycle_prev'
        bind -x '"\eOB": _bas_dispatch _bas_cycle_prev'
        return "$command_status"
    }

    if [[ $(declare -p PROMPT_COMMAND 2>/dev/null) == "declare -a "* ]]; then
        local hook
        for hook in "${PROMPT_COMMAND[@]}"; do
            [[ $hook == _bas_prompt_hook ]] && return 0
        done
        PROMPT_COMMAND+=(_bas_prompt_hook)
    elif [[ -z "${PROMPT_COMMAND:-}" ]]; then
        PROMPT_COMMAND="_bas_prompt_hook"
    elif [[ "$PROMPT_COMMAND" != *"_bas_prompt_hook"* ]]; then
        PROMPT_COMMAND="$PROMPT_COMMAND;_bas_prompt_hook"
    fi
}

# ============================================================================
# Runtime diagnostics and controls
# ============================================================================
bash_autosuggest_status() {
    local rendering=ready
    if (( ! _bas_enabled )); then
        rendering=disabled
    elif [[ ! -o emacs ]]; then
        rendering='unsupported-editing-mode'
    elif (( ${_bas_prompt_width:--1} < 0 )); then
        rendering='prompt-width-unavailable'
    elif (( ${#_bas_history[@]} == 0 )); then
        rendering='no-history'
    fi
    printf 'enabled=%s bash=%s term=%s size=%sx%s prompt_width=%s history=%s\n' \
        "$_bas_enabled" "$BASH_VERSION" "${TERM:-unset}" "${COLUMNS:-unset}" \
        "${LINES:-unset}" "${_bas_prompt_width:-unset}" "${#_bas_history[@]}"
    printf 'rendering=%s source=%s\n' "$rendering" "$_bas_source_file"
}

bash_autosuggest_disable() {
    _bas_clear_ghost
    _bas_enabled=0
    bind "set bind-tty-special-chars ${_bas_saved_bind_tty_special_chars:-on}"
    if [[ $(declare -p PROMPT_COMMAND 2>/dev/null) == "declare -a "* ]]; then
        local hook hooks=()
        for hook in "${PROMPT_COMMAND[@]}"; do
            [[ $hook == _bas_prompt_hook ]] || hooks+=("$hook")
        done
        PROMPT_COMMAND=("${hooks[@]}")
    else
        # PROMPT_COMMAND can be either a scalar or an array; this is the scalar branch.
        # shellcheck disable=SC2178
        PROMPT_COMMAND="${PROMPT_COMMAND//;_bas_prompt_hook/}"
        # shellcheck disable=SC2178
        PROMPT_COMMAND="${PROMPT_COMMAND//_bas_prompt_hook;/}"
        # shellcheck disable=SC2178
        PROMPT_COMMAND="${PROMPT_COMMAND//_bas_prompt_hook/}"
    fi

    local code binding key
    local -A owned_keys=()
    if (( ${_bas_bindings_active:-0} )); then
        for key in "${_bas_bound_keys[@]}"; do
            owned_keys["$key"]=1
            bind -r "$key"
        done
        for binding in "${_bas_saved_bindings[@]}"; do
            key=${binding#\"}
            key=${key%%\": *}
            [[ -n ${owned_keys[$key]+x} ]] && bind "$binding"
        done
        for binding in "${_bas_saved_shell_bindings[@]}"; do
            key=${binding#\"}
            key=${key%%\" *}
            [[ -n ${owned_keys[$key]+x} ]] && bind -x "$binding"
        done
        _bas_bindings_active=0
    fi
    for code in $(seq 32 126); do
        unset -f "_bas_k${code}" 2>/dev/null
    done

    _BASH_AUTOSUGGEST_LOADED=""
    echo "bash-autosuggestions disabled."
}

bash_autosuggest_enable() {
    if (( _bas_enabled )); then
        echo "bash-autosuggestions already enabled."
        return
    fi
    _bas_enabled=1
    if (( ! ${_bas_bindings_active:-0} )); then
        _bas_setup
    fi
    _BASH_AUTOSUGGEST_LOADED=1
    echo "bash-autosuggestions enabled."
}

bash_autosuggest_toggle() {
    if (( _bas_enabled )); then
        _bas_enabled=0
        _bas_clear_ghost
        echo "bash-autosuggestions disabled (temporary)."
    else
        bash_autosuggest_enable
    fi
}

# ============================================================================
_bas_setup
