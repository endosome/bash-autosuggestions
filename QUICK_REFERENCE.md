# bash-autosuggestions - Quick Reference

## Installation

```bash
git clone <your-repo-url>
cd bash-autosuggestions
./install.sh
```

Or manually add to `~/.bashrc`:
```bash
source ~/.local/share/bash-autosuggestions/bash-autosuggestions.sh
```

## Keybindings

| Key | Action |
|-----|--------|
| `→` (Right Arrow) | Accept full suggestion |
| `End` | Accept full suggestion |
| `Alt+→` or `Alt+F` | Accept next word |
| `↑` (Up Arrow) | Cycle to next suggestion |
| `↓` (Down Arrow) | Cycle to previous suggestion |
| `Ctrl+]` | Dismiss suggestion |
| `Enter` | Execute command (ghost auto-clears) |
| `Backspace` | Delete character & update suggestion |

## Configuration

Add **before** sourcing the script in `~/.bashrc`:

```bash
# Suggestion color (default: gray)
export BASH_AUTOSUGGEST_HIGHLIGHT="38;5;240"

# Matching strategy (default: history)
export BASH_AUTOSUGGEST_STRATEGY="match_prev_cmd"  # Context-aware
# or
export BASH_AUTOSUGGEST_STRATEGY="history"  # Most recent first

# Minimum characters before suggesting (default: 1)
export BASH_AUTOSUGGEST_MIN_LENGTH=2

# Ignore patterns (glob)
export BASH_AUTOSUGGEST_HISTORY_IGNORE="cd *:ls *"
```

## Runtime Commands

```bash
bash_autosuggest_disable  # Turn off suggestions
bash_autosuggest_enable   # Turn on suggestions
bash_autosuggest_toggle   # Toggle on/off
```

## Testing

```bash
# Build and run Docker test environment
docker build -t bash-autosuggestions-test .
docker run -it --rm bash-autosuggestions-test

# The test environment includes pre-seeded DevOps commands
# Try typing: kub, docker, git, terraform, etc.
```

## Troubleshooting

**Suggestions not appearing?**
- Check `echo $HISTFILE` has commands
- Verify `BASH_AUTOSUGGEST_MIN_LENGTH` isn't too high
- Run `bash_autosuggest_enable`

**Wrong color?**
- Set `BASH_AUTOSUGGEST_HIGHLIGHT` before sourcing
- Use ANSI SGR codes (e.g., "38;5;244" for gray)

**Vim mode not working?**
- Currently only supports emacs mode (default)
- Run `set -o emacs` to enable

## Color Reference

Common ANSI colors for `BASH_AUTOSUGGEST_HIGHLIGHT`:

```bash
export BASH_AUTOSUGGEST_HIGHLIGHT="38;5;244"  # Gray (default)
export BASH_AUTOSUGGEST_HIGHLIGHT="38;5;240"  # Darker gray
export BASH_AUTOSUGGEST_HIGHLIGHT="38;5;248"  # Lighter gray
export BASH_AUTOSUGGEST_HIGHLIGHT="38;5;242"  # Medium gray
export BASH_AUTOSUGGEST_HIGHLIGHT="2"         # Dim (uses terminal theme)
```

## Requirements

- Bash 4.0 or later
- Linux/macOS (terminal with ANSI support)
- History enabled (`HISTFILE` set)

## Uninstallation

```bash
cd bash-autosuggestions
./uninstall.sh
```

Or manually remove from `~/.bashrc`:
```bash
# Remove this line:
source ~/.local/share/bash-autosuggestions/bash-autosuggestions.sh
```

---

**Project**: bash-autosuggestions  
**Version**: 1.0.0  
**License**: MIT  
**Inspired by**: zsh-autosuggestions, fish shell
