"""Exercise real Bash/readline through a pseudo-terminal and terminal emulator."""

import errno
import fcntl
import os
import pty
import select
import shutil
import signal
import struct
import tempfile
import termios
import time
import unittest
from collections.abc import Callable
from pathlib import Path

import pyte


class ProbeScreen(pyte.Screen):
    """Record the visible input at the start of a history lookup."""

    def __init__(self, columns: int, lines: int) -> None:
        super().__init__(columns, lines)
        self.lookup_lines: list[str] = []

    def set_title(self, param: str) -> None:
        if param == "lookup-probe":
            self.lookup_lines.append(self.display[self.cursor.y])
        super().set_title(param)


class InteractiveTests(unittest.TestCase):
    """Check what is displayed and what readline actually accepts."""

    def setUp(self) -> None:
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        home = Path(self.directory.name)
        (home / "history").write_text(
            "echo autosuggest-ready\necho another-match\n"
            + "echo long-"
            + "x" * 150
            + "\n"
            + "echo wrap-"
            + "x" * 70
            + "Zsuffix\n"
        )
        plugin = Path(__file__).resolve().parents[1] / "bash-autosuggestions.sh"
        mock_bin = home / "bin"
        mock_bin.mkdir()
        self.tac_log = home / "tac.log"
        real_tac = shutil.which("tac")
        self.assertIsNotNone(real_tac)
        tac = mock_bin / "tac"
        tac.write_text(
            '#!/bin/sh\nprintf "x\\n" >> "$BAS_TEST_TAC_LOG"\n'
            'exec "$BAS_TEST_REAL_TAC" "$@"\n'
        )
        tac.chmod(0o755)
        rc = home / "rc"
        prompt_prefix = ""
        self.prompt_width = len("BAS> ")
        if "genesis" in self._testMethodName:
            prompt_prefix = r"\[\e(B\017\]" + "żółć "
            self.prompt_width += 5
        elif "nonprinting_region" in self._testMethodName:
            prompt_prefix = r"\[\e(B\017\]"
        elif "unicode_prompt" in self._testMethodName:
            prompt_prefix = "żółć "
            self.prompt_width += 5
        elif "wide_prompt" in self._testMethodName:
            prompt_prefix = "猫 "
            self.prompt_width += 3
        if "unavailable_width" in self._testMethodName:
            wc = mock_bin / "wc"
            wc.write_text("#!/bin/sh\nexit 1\n")
            wc.chmod(0o755)
        rc.write_text(
            "PS1='\\[\\e]0;fixture\\a\\]\\[\\e[32m\\]"
            + prompt_prefix
            + ("p" * 80 if "wrapped_prompt" in self._testMethodName else "")
            + "BAS> \\[\\e[0m\\]'\n"
            'PROMPT_COMMAND=\'printf "\\033]0;bas-status:%s\\007" "$?"\'\n'
            + (
                "PROMPT_COMMAND=(\"$PROMPT_COMMAND\" ':')\n"
                if "array" in self._testMethodName
                else ""
            )
            + (
                "PS1='$(if [[ $? == 0 ]]; then printf OK; else printf FAILED; fi) BAS> '\n"
                "PROMPT_COMMAND=''\n"
                if "status_dependent" in self._testMethodName
                else ""
            )
            + (
                'bind \'"~": "CUSTOM-MACRO"\'\n'
                "bind '\"\\e[F\": backward-char'\n"
                "bind -x '\"\\e[C\": READLINE_LINE+=CUSTOM; READLINE_POINT=${#READLINE_LINE}'\n"
                "bind -r '\\C-]'\n"
                if "custom_bindings" in self._testMethodName
                else ""
            )
            + 'source "$BAS_TEST_RC"\n'
            + (
                "_bas_collect_candidates() { printf '\\033]0;lookup-probe\\007'; }\n"
                if "flicker" in self._testMethodName
                else ""
            )
            + 'bind -x \'"\\C-x\\C-b": printf "\\nBUFFER:%s:END\\n" "$READLINE_LINE"\'\n'
        )
        environment = {
            "HOME": str(home),
            "HISTFILE": str(home / "history"),
            "PATH": str(mock_bin) + os.pathsep + os.environ["PATH"],
            "BAS_TEST_REAL_TAC": real_tac,
            "BAS_TEST_TAC_LOG": str(self.tac_log),
            "TERM": "screen-256color" if prompt_prefix else "xterm-256color",
            "LC_ALL": "C.UTF-8",
            "INPUTRC": "/dev/null",
            "BAS_TEST_RC": os.environ.get("BAS_TEST_RC", str(plugin)),
            "SSHHOME": os.environ.get("SSHHOME", str(home)),
        }
        columns = (
            60
            if "genesis" in self._testMethodName
            else 40
            if "narrow" in self._testMethodName
            else 100
        )
        rows = 13 if "genesis" in self._testMethodName else 24
        self.pid, self.terminal = pty.fork()
        if self.pid == 0:
            fcntl.ioctl(0, termios.TIOCSWINSZ, struct.pack("HHHH", rows, columns, 0, 0))
            os.chdir(home)
            os.execvpe(
                "bash", ["bash", "--noprofile", "--rcfile", str(rc), "-i"], environment
            )
        self.addCleanup(self.close_shell)
        self.screen = ProbeScreen(columns, rows)
        self.stream = pyte.ByteStream(self.screen)
        self.output = b""
        self.until(lambda: "BAS> " in self.screen.display[self.screen.cursor.y])

    def close_shell(self) -> None:
        os.close(self.terminal)
        try:
            os.kill(self.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        os.waitpid(self.pid, 0)

    def until(self, predicate: Callable[[], bool]) -> None:
        deadline = time.monotonic() + 4
        while not predicate():
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                self.fail(
                    f"Terminal timed out:\n{self.screen.display}\n{self.output!r}"
                )
            readable, _, _ = select.select([self.terminal], [], [], remaining)
            if not readable:
                continue
            try:
                data = os.read(self.terminal, 65536)
            except OSError as error:
                if error.errno != errno.EIO:
                    raise
                self.fail(f"Shell exited: {self.output!r}")
            self.output += data
            self.stream.feed(data)

    def send(self, data: bytes) -> None:
        os.write(self.terminal, data)

    def buffer_is(self, expected: str) -> None:
        self.output = b""
        self.send(b"\x18\x02")
        self.until(lambda: b":END\r\n" in self.output)
        self.assertIn(f"BUFFER:{expected}:END".encode(), self.output)

    def suggestion(
        self, prefix: bytes = b"echo au", expected: str = "echo autosuggest-ready"
    ) -> None:
        self.send(prefix)
        self.until(
            lambda: (
                f"BAS> {expected}" in self.screen.display[self.screen.cursor.y]
                and self.screen.cursor.x == self.prompt_width + len(prefix)
            )
        )
        self.assertEqual(self.screen.cursor.x, self.prompt_width + len(prefix))
        self.assertEqual(
            self.screen.buffer[self.screen.cursor.y][
                self.prompt_width + len(prefix)
            ].fg,
            "808080",
        )

    def test_ghost_and_right_arrow(self) -> None:
        self.suggestion()
        self.send(b"\x1b[C")
        self.buffer_is("echo autosuggest-ready")

    def test_prompt_with_readline_nonprinting_region(self) -> None:
        self.test_ghost_and_right_arrow()

    def test_unicode_prompt(self) -> None:
        self.test_ghost_and_right_arrow()

    def test_wide_prompt(self) -> None:
        self.test_ghost_and_right_arrow()

    def test_genesis_prompt_at_60_columns_13_rows(self) -> None:
        self.test_ghost_and_right_arrow()

    def test_status_dependent_prompt(self) -> None:
        self.send(b"false\r")
        self.until(
            lambda: self.screen.display[self.screen.cursor.y].rstrip() == "FAILED BAS>"
        )
        self.prompt_width = len("FAILED BAS> ")
        self.test_ghost_and_right_arrow()

    def test_status_reports_ready_without_history_contents(self) -> None:
        self.output = b""
        self.send(b"bash_autosuggest_status\r")
        self.until(lambda: b"rendering=ready source=" in self.output)
        self.assertIn(b"enabled=1 bash=", self.output)
        self.assertIn(b"prompt_width=5 history=", self.output)
        self.assertNotIn(b"autosuggest-ready", self.output)
        self.assertNotIn(b"another-match", self.output)

    def test_status_reports_disabled(self) -> None:
        self.send(b"bash_autosuggest_toggle; bash_autosuggest_status\r")
        self.until(lambda: b"rendering=disabled source=" in self.output)

    def test_disable_enable_restores_loaded_state(self) -> None:
        self.send(
            b"bash_autosuggest_disable; bash_autosuggest_enable; printf 'LOADED:%s\\n' \"$_BASH_AUTOSUGGEST_LOADED\"\r"
        )
        self.until(lambda: b"LOADED:1\r\n" in self.output)
        self.until(lambda: self.screen.display[self.screen.cursor.y].rstrip() == "BAS>")
        self.test_ghost_and_right_arrow()

    def test_disable_restores_custom_bindings(self) -> None:
        self.send(b"bash_autosuggest_disable\r")
        self.until(lambda: b"bash-autosuggestions disabled.\r\n" in self.output)
        self.until(lambda: self.screen.display[self.screen.cursor.y].rstrip() == "BAS>")
        self.send(b"~\x1b[C\x1b[F!")
        self.buffer_is("CUSTOM-MACROCUSTO!M")

    def test_custom_bindings_snapshot_refreshes_on_enable(self) -> None:
        self.send(
            b'bash_autosuggest_disable; bind \'"~": "NEW-MACRO"\'; '
            b"bash_autosuggest_enable; bash_autosuggest_disable\r"
        )
        self.until(
            lambda: self.output.count(b"bash-autosuggestions disabled.\r\n") == 2
        )
        self.until(lambda: self.screen.display[self.screen.cursor.y].rstrip() == "BAS>")
        self.send(b"~\x1d")
        self.buffer_is("NEW-MACRO")

    def test_custom_bindings_survive_toggle_then_enable(self) -> None:
        self.send(
            b"bash_autosuggest_toggle; bash_autosuggest_enable; bash_autosuggest_disable\r"
        )
        self.until(lambda: b"bash-autosuggestions disabled.\r\n" in self.output)
        self.until(lambda: self.screen.display[self.screen.cursor.y].rstrip() == "BAS>")
        self.send(b"~\x1b[C")
        self.buffer_is("CUSTOM-MACROCUSTOM")

    def test_toggle_after_disable_reinstalls_bindings(self) -> None:
        self.send(b"bash_autosuggest_disable; bash_autosuggest_toggle\r")
        self.until(lambda: b"bash-autosuggestions enabled.\r\n" in self.output)
        self.until(lambda: self.screen.display[self.screen.cursor.y].rstrip() == "BAS>")
        self.test_ghost_and_right_arrow()

    def test_unicode_prompt_unavailable_width_status(self) -> None:
        self.send(b"bash_autosuggest_status\r")
        self.until(lambda: b"rendering=prompt-width-unavailable source=" in self.output)
        self.assertIn(b"prompt_width=-1 history=", self.output)

    def test_narrow_pane_wrapped_input(self) -> None:
        prefix = "echo wrap-" + "x" * 70 + "Z"
        self.send(prefix.encode())
        column = (len("BAS> ") + len(prefix)) % 40
        self.until(
            lambda: (
                self.screen.cursor.x == column
                and self.screen.buffer[self.screen.cursor.y][column - 1].data == "Z"
                and self.screen.buffer[self.screen.cursor.y][column].fg == "808080"
            )
        )
        self.send(b"\x1b[C")
        self.buffer_is(prefix + "suffix")

    def test_narrow_pane_wrapped_prompt(self) -> None:
        self.send(b"echo au")
        column = (80 + len("BAS> echo au")) % 40
        self.until(
            lambda: (
                self.screen.cursor.x == column
                and self.screen.buffer[self.screen.cursor.y][column - 1].data == "u"
                and self.screen.buffer[self.screen.cursor.y][column].fg == "808080"
            )
        )
        self.send(b"\x1b[C")
        self.buffer_is("echo autosuggest-ready")

    def test_no_blank_line_flicker_during_history_lookup(self) -> None:
        self.send(b"cd ")
        self.until(lambda: len(self.screen.lookup_lines) == 3)
        for line in self.screen.lookup_lines:
            self.assertTrue(line.startswith("BAS> "), repr(line))
        self.assertTrue(self.screen.lookup_lines[-1].startswith("BAS> cd"))
        self.buffer_is("cd ")

    def test_history_is_cached_while_typing(self) -> None:
        initial_calls = self.tac_log.read_text()
        self.suggestion()
        self.assertEqual(self.tac_log.read_text(), initial_calls)
        self.assertEqual(initial_calls, "x\n")

    def test_history_cache_refreshes_at_next_prompt(self) -> None:
        self.send(b"history -s 'echo fresh-entry'\r")
        self.until(lambda: self.tac_log.read_text().count("x\n") == 2)
        self.until(lambda: self.screen.display[self.screen.cursor.y].rstrip() == "BAS>")
        self.suggestion(b"echo fr", "echo fresh-entry")
        self.send(b"\x1b[C")
        self.buffer_is("echo fresh-entry")

    def test_deletion_without_suggestion_leaves_no_stale_characters(self) -> None:
        self.send(b"xyz\x7f")
        self.until(
            lambda: self.screen.display[self.screen.cursor.y].rstrip() == "BAS> xy"
        )
        self.assertEqual(self.screen.cursor.x, len("BAS> xy"))
        self.send(b"\x15")
        self.until(lambda: self.screen.display[self.screen.cursor.y].rstrip() == "BAS>")
        self.assertEqual(self.screen.cursor.x, len("BAS> "))

    def test_enter_only_executes_typed_text(self) -> None:
        self.suggestion()
        self.output = b""
        self.send(b"\r")
        self.until(lambda: b"\r\nau\r\n" in self.output or b"\rau\r\n" in self.output)

    def test_one_enter_after_acceptance(self) -> None:
        self.suggestion()
        self.send(b"\x1bOC\r")
        self.output = b""
        self.until(
            lambda: (
                b"\rautosuggest-ready\r\n" in self.output
                or b"\r\nautosuggest-ready\r\n" in self.output
            )
        )

    def test_job_control_and_prompt_status(self) -> None:
        self.send(b"[[ $- == *m* ]] && echo MONITOR_OK\r")
        self.until(
            lambda: (
                b"\r\nMONITOR_OK\r\n" in self.output
                or b"\rMONITOR_OK\r\n" in self.output
            )
        )
        self.output = b""
        self.send(b"false\r")
        self.until(lambda: b"bas-status:1\x07" in self.output)

    def test_array_prompt_hook(self) -> None:
        self.suggestion()
        self.send(b"\x1b[C")
        self.buffer_is("echo autosuggest-ready")

    def test_backspace_updates_suggestion(self) -> None:
        self.suggestion()
        self.send(b"\x7f\x1b[C")
        self.buffer_is("echo another-match")

    def test_dismiss(self) -> None:
        self.suggestion()
        self.send(b"\x1d\x1b[C")
        self.buffer_is("echo au")

    def test_accept_word(self) -> None:
        self.suggestion(b"echo an", "echo another-match")
        self.send(b"\x1bf")
        self.buffer_is("echo another-match")

    def test_long_suggestion_stays_on_one_row(self) -> None:
        self.send(b"echo long-")
        self.until(
            lambda: (
                "BAS> echo long-" + "x" * 84
                in self.screen.display[self.screen.cursor.y]
            )
        )
        self.assertEqual(self.screen.cursor.y, 0)
        self.assertEqual(self.screen.cursor.x, len("BAS> echo long-"))
        self.send(b"\x1b[C")
        self.buffer_is("echo long-" + "x" * 150)

    def test_bracketed_paste(self) -> None:
        self.send(b"\x1b[200~echo pasted\x1b[201~")
        self.buffer_is("echo pasted")

    def test_quotes_and_backslashes_are_inserted_literally(self) -> None:
        line = r"""printf "%s\n" '$HOME' \\tail"""
        self.send(line.encode())
        self.buffer_is(line)

    def test_all_printable_ascii_characters_are_inserted_literally(self) -> None:
        line = "".join(chr(code) for code in range(32, 127))
        self.send(line.encode())
        self.buffer_is(line)

    def test_stale_suggestion_is_not_accepted(self) -> None:
        self.suggestion()
        self.send(b"z\x1b[C")
        self.buffer_is("echo auz")

    def test_editing_in_middle_does_not_accept(self) -> None:
        self.suggestion()
        self.send(b"\x1b[D\x1b[C")
        self.buffer_is("echo au")

    def test_delete_key(self) -> None:
        self.send(b"zzxy\x1b[D\x1b[3~")
        self.buffer_is("zzx")

    def test_reload_does_not_duplicate_history(self) -> None:
        self.send(
            b"source \"$BAS_TEST_RC\"; history | grep -c '^ *[0-9]* *echo autosuggest-ready$'\r"
        )
        self.until(lambda: b"\r\n1\r\n" in self.output or b"\r1\r\n" in self.output)


if __name__ == "__main__":
    unittest.main()
