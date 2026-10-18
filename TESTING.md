# bash-autosuggestions - Testing Guide

## Automated terminal regression tests

Run these on Linux or another POSIX system with Bash 4.4+ and Python 3.10+:

```bash
python3 -m venv .venv
.venv/bin/pip install -r requirements-test.txt
.venv/bin/python -m unittest discover -s tests -v
```

These tests launch real interactive Bash sessions in isolated pseudo-terminals,
seed temporary history files, emulate the screen with pyte, and send actual
keypresses. They check gray ghost text, cursor position, right-arrow acceptance,
one-Enter execution, unaccepted suggestions, editing, paste, prompt hooks, and
job control. They use bounded I/O waits rather than sleeps or production hosts.

The flicker regression records the emulated screen at the moment a history
lookup begins and requires the prompt/input to remain visible. Other checks
ensure typing launches no new `tac` process, history refreshes at the next prompt,
and deletion leaves no stale characters after the immediate input restore.
Prompt cases include `screen-256color` at 60 columns by 13 rows, nonprinting
terminal controls, Unicode display widths, and prompts that change after a
failed command. Diagnostic checks verify ready/disabled/unavailable states
without exposing history contents.
Typing checks cover every printable ASCII character, including quotes and
backslashes, and verify disable/re-enable restores a consistent loaded state.
Custom-binding checks cover restoring readline functions, macros, shell
callbacks, and previously unbound keys, including changes made between activations.

Set `BAS_TEST_RC` to an alternative startup script and `SSHHOME` to a transferred
payload to exercise SSHRC or its retained tmux payload through the same tests.

## Quick Start

### 1. Build and Run Docker Test Environment
```bash
# From project directory
docker build -t bash-autosuggestions-test .
docker run -it --rm bash-autosuggestions-test
```

You'll be dropped into a bash shell with:
- Pre-seeded history (19 DevOps commands)
- bash-autosuggestions already loaded
- User: tester (non-root)

## Test Scenarios

### Test 1: Basic Suggestion
**Objective**: Verify ghost text appears and is distinguishable from typed text

**Steps**:
1. Type: `kub`
2. **Expected**: See gray ghost text: `ectl get pods -n production -o wide`
3. **Pass if**: Ghost text is visibly dimmed/gray, distinct from white typed text

### Test 2: Accept Full Suggestion
**Objective**: Verify right arrow accepts entire suggestion

**Steps**:
1. Type: `doc`
2. See suggestion: `ker compose up -d`
3. Press: `→` (right arrow)
4. **Expected**: Full command appears on input line: `docker compose up -d`
5. **Pass if**: Entire suggestion is accepted, cursor at end

### Test 3: Accept by Word
**Objective**: Verify Alt+→ accepts one word at a time

**Steps**:
1. Type: `kub`
2. See suggestion: `ectl get pods -n production -o wide`
3. Press: `Alt+→`
4. **Expected**: Input line shows: `kubectl`
5. See new suggestion: ` get pods -n production -o wide`
6. Press: `Alt+→` again
7. **Expected**: Input line shows: `kubectl get`
8. **Pass if**: Words are accepted incrementally

### Test 4: Single Enter Execution (FIX VERIFICATION)
**Objective**: Verify Enter works on first press after accepting suggestion

**Steps**:
1. Type: `echo`
2. See suggestion: (may vary based on history)
3. Press: `→` to accept
4. Press: `Enter` **once**
5. **Expected**: Command executes immediately (prints "echo" or similar)
6. **Pass if**: No second Enter required ✅

### Test 5: Multiple Suggestion Cycling
**Objective**: Verify Up/Down arrows cycle through matches with counter

**Steps**:
1. Type: `docker`
2. **Expected**: See suggestion + counter like `[1/3]`
3. Press: `↑` (up arrow)
4. **Expected**: Suggestion changes, counter shows `[2/3]`
5. Press: `↑` again
6. **Expected**: Counter shows `[3/3]`
7. Press: `↑` again
8. **Expected**: Wraps to `[1/3]`
9. Press: `↓` (down arrow)
10. **Expected**: Goes back to `[3/3]`
11. **Pass if**: Cycling works smoothly with visible counter ✅

### Test 6: Ghost Text Color (FIX VERIFICATION)
**Objective**: Verify ghost text appears in distinct gray color

**Steps**:
1. Type: `git`
2. **Expected**: Suggestion appears in GRAY (not white like typed text)
3. Compare: Typed "git" should be white/default, suggestion gray/dim
4. **Pass if**: Clear visual distinction between typed and suggested text ✅

### Test 7: Dismiss Suggestion
**Objective**: Verify Ctrl+] dismisses ghost text

**Steps**:
1. Type: `ssh`
2. See suggestion appear
3. Press: `Ctrl+]`
4. **Expected**: Ghost text disappears
5. **Pass if**: Only "ssh" remains on input line

### Test 8: Backspace Updates Suggestion
**Objective**: Verify suggestion updates as you delete characters

**Steps**:
1. Type: `docker`
2. See suggestion: ` compose up -d` (or similar)
3. Press: `Backspace` (delete 'r')
4. **Expected**: New suggestion for "docke" appears
5. Press: `Backspace` again
6. **Expected**: Suggestion updates again or disappears
7. **Pass if**: Suggestions change dynamically

### Test 9: Empty Input (No Suggestion)
**Objective**: Verify no ghost text when input is empty

**Steps**:
1. Ensure input line is empty (press Ctrl+U if needed)
2. **Expected**: No ghost text appears
3. **Pass if**: Prompt is clean with no suggestions

### Test 10: History Navigation Fallback
**Objective**: Verify Up/Down work for history when no suggestions

**Steps**:
1. Type: `xyz123notinhistory`
2. Press: `↑` (up arrow)
3. **Expected**: (May need to press Up twice - known limitation)
4. **Pass if**: Can eventually navigate bash history

### Test 11: Toggle Commands
**Objective**: Verify runtime disable/enable

**Steps**:
1. Type: `doc` (see suggestion)
2. Press: `Ctrl+C` to cancel
3. Run: `bash_autosuggest_toggle`
4. **Expected**: Message "bash-autosuggestions disabled (temporary)."
5. Type: `doc` again
6. **Expected**: No suggestion appears
7. Run: `bash_autosuggest_toggle` again
8. **Expected**: Message "bash-autosuggestions enabled."
9. Type: `doc` again
10. **Expected**: Suggestion reappears
11. **Pass if**: Toggle works without errors ✅

### Test 12: Context-Aware Suggestions (NEW FEATURE)
**Objective**: Verify match_prev_cmd strategy

**Setup**:
```bash
# Exit current shell and restart with strategy enabled
exit
docker run -it --rm bash-autosuggestions-test bash -c '
export BASH_AUTOSUGGEST_STRATEGY="match_prev_cmd"
source ~/.local/share/bash-autosuggestions/bash-autosuggestions.sh
exec bash
'
```

**Steps**:
1. Run: `git add -A` (press Enter)
2. Type: `git c`
3. **Expected**: Suggestion prioritizes `git commit` (if in history) because it often follows `git add`
4. **Pass if**: Contextual match appears first ✨

### Test 13: Ignore Pattern Configuration
**Objective**: Verify BASH_AUTOSUGGEST_HISTORY_IGNORE works

**Setup**:
```bash
# Exit and restart with ignore pattern
exit
docker run -it --rm bash-autosuggestions-test bash -c '
export BASH_AUTOSUGGEST_HISTORY_IGNORE="cd *"
source ~/.local/share/bash-autosuggestions/bash-autosuggestions.sh
exec bash
'
```

**Steps**:
1. Type: `cd /`
2. **Expected**: No suggestions appear (cd commands are ignored)
3. **Pass if**: Pattern matching works

### Test 14: Min Length Configuration
**Objective**: Verify BASH_AUTOSUGGEST_MIN_LENGTH works

**Setup**:
```bash
# Exit and restart with min length = 3
exit
docker run -it --rm bash-autosuggestions-test bash -c '
export BASH_AUTOSUGGEST_MIN_LENGTH=3
source ~/.local/share/bash-autosuggestions/bash-autosuggestions.sh
exec bash
'
```

**Steps**:
1. Type: `gi`
2. **Expected**: No suggestion (only 2 chars)
3. Type: `t` (now "git")
4. **Expected**: Suggestion appears (3 chars reached)
5. **Pass if**: Suggestions only appear after min length

## Performance Tests

### Test P1: Large History Performance
**Objective**: Verify performance with large HISTFILE

**Steps**:
```bash
# Generate large history
for i in {1..5000}; do echo "test_command_$i" >> ~/.bash_history; done
history -r ~/.bash_history

# Type and time suggestion
time (type: `test`)
```
**Expected**: Suggestion appears in <50ms
**Pass if**: No perceptible lag

### Test P2: Rapid Typing
**Objective**: Verify no lag with fast typing

**Steps**:
1. Type quickly: `kubectl get pods -n production`
2. **Expected**: Suggestions keep up, no visual artifacts
3. **Pass if**: Smooth experience, no ghost text stuck on screen

## Bug Regression Tests

### Regression Test 1: Double-Enter Bug
**Verifies**: Issue #1 fix (double-Enter after arrow accept)

**Steps**:
1. Type: `echo hello`
2. Press: `→` to accept suggestion
3. Press: `Enter` **ONCE**
4. **Expected**: Command executes immediately
5. **Fail if**: Need to press Enter twice ❌

### Regression Test 2: Ghost Color Bug
**Verifies**: Issue #2 fix (ghost text coloring)

**Steps**:
1. Type: `docker`
2. **Expected**: Suggestion is visibly gray/dimmed
3. **Fail if**: Suggestion is same color as typed text ❌

### Regression Test 3: Cycling Counter Bug
**Verifies**: Issue #3 fix (multi-suggestion counter)

**Steps**:
1. Type: `docker`
2. Look for counter: `[N/M]`
3. **Expected**: Counter visible and accurate
4. **Fail if**: Counter missing or shows wrong numbers ❌

## Edge Cases

### Edge Case 1: Special Characters in Suggestion
**Steps**:
1. Add to history: `echo "hello world" && ls -la`
2. Type: `echo`
3. **Expected**: Suggestion includes quotes and special chars correctly

### Edge Case 2: Very Long Suggestion
**Steps**:
1. Add to history: (paste a 200+ char command)
2. Type first few chars
3. **Expected**: Long suggestion appears, no wrap issues

### Edge Case 3: Suggestion Longer Than Terminal Width
**Steps**:
1. Resize terminal to 40 columns
2. Type: `kubectl`
3. **Expected**: Long suggestion wraps or truncates gracefully

## Exit Test Environment
```bash
exit
# or
Ctrl+D
```

## Manual Test Checklist

After running all tests, verify:
- [ ] Test 1-14: All passed
- [ ] Performance tests: No lag
- [ ] Regression tests: No old bugs returned
- [ ] Edge cases: Handled gracefully
- [ ] Docker image builds without errors
- [ ] No memory leaks (check `ps aux` during use)
- [ ] No zombie processes (`ps aux | grep defunct`)

## Known Acceptable Failures

These are expected limitations (not bugs):
1. History navigation fallback may require pressing Up twice when no suggestions exist
2. Terminal resize mid-suggestion may leave artifacts (fixed with Ctrl+L)
3. Vim mode is unsupported (keybindings won't work)

## Other integration tests

For CI/CD integration, consider:
```bash
# Example expect script structure
#!/usr/bin/expect
spawn docker run -it bash-autosuggestions-test
send "kub\r"
expect "ectl get pods"
# ... etc
```

The Python suite above provides automated coverage without Docker or expect.

---

**All tests passing = Ready for production deployment** ✅
