# bash-autosuggestions

**Fish-like autosuggestions for Bash** — suggests commands as you type based on history.

Inspired by [zsh-autosuggestions](https://github.com/zsh-users/zsh-autosuggestions) and [fish shell](https://fishshell.com/), this pure-Bash script shows inline "ghost text" suggestions from your command history as you type.

## How It Works

As you type, a dimmed suggestion appears after your cursor showing the most recent matching command from history. The suggestion is non-intrusive — it won't execute unless you explicitly accept it.

```
$ kubectl get po▌ds -n production -o wide
              ↑ ghost text (dimmed gray)
```

## Keybindings

| Key | Action |
|---|---|
| `→` (Right Arrow) | Accept full suggestion |
| `End` | Accept full suggestion |
| `Alt+→` / `Alt+F` | Accept next word |
| `↑` (Up Arrow) | Cycle to next suggestion (or history if no suggestions) |
| `↓` (Down Arrow) | Cycle to previous suggestion (or history if no suggestions) |
| `Ctrl+]` | Dismiss suggestion |
| Any typing | Suggestion updates live |

## Requirements

- **Bash 4.0+** (check with `bash --version`)
- Terminal with ANSI color support (virtually all modern terminals)

## Installation

### Quick Install

```bash
git clone https://github.com/YOUR_USER/bash-autosuggestions.git
cd bash-autosuggestions
bash install.sh
source ~/.bashrc
```

### Manual Install

```bash
# Copy the script somewhere permanent
mkdir -p ~/.local/share/bash-autosuggestions
cp bash-autosuggestions.sh ~/.local/share/bash-autosuggestions/

# Add to your .bashrc
echo 'source ~/.local/share/bash-autosuggestions/bash-autosuggestions.sh' >> ~/.bashrc

# Reload
source ~/.bashrc
```

### One-liner (download + install)

```bash
curl -sL https://raw.githubusercontent.com/YOUR_USER/bash-autosuggestions/main/bash-autosuggestions.sh \
  -o ~/.local/share/bash-autosuggestions/bash-autosuggestions.sh --create-dirs && \
  echo 'source ~/.local/share/bash-autosuggestions/bash-autosuggestions.sh' >> ~/.bashrc && \
  source ~/.bashrc
```

## Configuration

Set these variables **before** sourcing the script in your `.bashrc`:

```bash
# Color of the ghost suggestion (ANSI SGR code)
# Default: "38;5;244" (medium gray)
# Examples:
#   "38;5;240"         - darker gray
#   "38;5;248"         - lighter gray
#   "38;2;100;100;100" - 24-bit RGB gray
#   "2"                - dim text
BASH_AUTOSUGGEST_HIGHLIGHT="38;5;244"

# Strategy for finding suggestions
# "history"        - most recent history match (default)
# "match_prev_cmd" - match conditioned on previous command
BASH_AUTOSUGGEST_STRATEGY="history"

# Ignore history entries matching this glob pattern
# Example: "cd *" to never suggest cd commands
BASH_AUTOSUGGEST_HISTORY_IGNORE=""

# Minimum input length before suggesting (default: 1)
BASH_AUTOSUGGEST_MIN_LENGTH=1

# Maximum number of candidates to collect (default: 50)
BASH_AUTOSUGGEST_MAX_CANDIDATES=50

source ~/.local/share/bash-autosuggestions/bash-autosuggestions.sh
```

## Strategies

### `history` (default)
Suggests the most recent command from history that starts with your current input.

### `match_prev_cmd`
Like `history`, but prioritizes matches whose *preceding* history entry matches the command you just ran. This provides context-aware suggestions — e.g., after running `git add .`, it'll suggest `git commit -m "..."` if that's what you typically do next.

Falls back to `history` strategy if no contextual match is found.

## Disabling at Runtime

```bash
# Disable autosuggestions in the current shell (removes all bindings)
bash_autosuggest_disable

# Re-enable autosuggestions
bash_autosuggest_enable

# Toggle on/off (lightweight - keeps bindings)
bash_autosuggest_toggle
```

## Uninstalling

```bash
bash uninstall.sh
```

Or manually:

```bash
# Remove from .bashrc (delete the source line)
# Remove installed files
rm -rf ~/.local/share/bash-autosuggestions
```

## Comparison with Alternatives

| Feature | bash-autosuggestions | [ble.sh](https://github.com/akinomyoga/ble.sh) | zsh-autosuggestions |
|---|---|---|---|
| Shell | Bash | Bash | Zsh |
| Inline suggestions | ✅ | ✅ | ✅ |
| Multiple suggestions cycling | ✅ (Up/Down arrows) | ✅ | ❌ |
| Suggestion counter [N/M] | ✅ | ❌ | ❌ |
| Syntax highlighting | ❌ | ✅ | ❌ (separate plugin) |
| Partial accept (word) | ✅ | ✅ | ✅ |
| History strategy | ✅ | ✅ | ✅ |
| Completion strategy | ❌ | ✅ | ✅ |
| match_prev_cmd | ✅ | ❌ | ✅ |
| Pure Bash | ✅ | ✅ | N/A (Zsh) |
| Lightweight | ✅ (~470 LOC) | ❌ (large) | ✅ |
| Vim mode | ❌ | ✅ | ❌ |
| Install complexity | Low | Medium | Low |

**When to use this**: You want a lightweight, single-file, drop-in solution that adds fish-like history suggestions to Bash without replacing the entire line editor.

**When to use ble.sh instead**: You want a full-featured Bash line editor with syntax highlighting, advanced completion, vim modes, and more. ble.sh is a much larger and more capable project.

## Troubleshooting

### Suggestions don't appear
- Ensure Bash 4.0+: `echo $BASH_VERSION`
- Check your history is non-empty: `history | wc -l`
- Ensure `HISTFILE` is set and readable
- Make sure the script is sourced (not executed): `source bash-autosuggestions.sh`

### Ghost text artifacts remain on screen
- Run `reset` or press `Ctrl+L` to refresh the terminal
- This can happen if the terminal is resized during a suggestion

### Conflicts with other readline customizations
- Source `bash-autosuggestions.sh` **after** other `.inputrc` or `bind` customizations
- If using `fzf`, source fzf's keybindings first

### Arrow keys produce garbage text
- Your terminal may use different escape sequences
- Check with `cat -v` then press the arrow key
- Adjust the `bind -x` entries in `_bas_setup` if needed

## How It Works (Technical)

The script uses Bash's `bind` command to create macros for every printable character. Each macro inserts the character normally, then triggers an internal function (`_bas_update`) via `Ctrl+_`. This function:

1. Reads the current `READLINE_LINE` (what the user has typed)
2. Searches history in reverse for the most recent match
3. Renders the untyped suffix as "ghost text" using ANSI escape codes (save cursor → print dimmed text → restore cursor)

Accept keys (`→`, `End`, `Alt+→`) modify `READLINE_LINE` and `READLINE_POINT` directly to insert the suggestion.

## License

MIT
