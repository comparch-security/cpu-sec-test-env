#!/usr/bin/env python3
"""Host-side console driver for the two CHERI lanes (plan 2026-10-14-cheri-lanes-bringup,
Step 8).  Promoted verbatim from the machine-local spike implementation at
build/cheri/scratch/console-driver.py once its properties were replay-verified.

Boots a CHERI QEMU under a pty, logs the console verbatim, logs in as root
(empty password), then runs a command script line-by-line.

Synchronisation is on a BARE-LINE TOKEN, never on a substring.  After each
command the driver sends `echo <TOKEN_n>` and waits until a line that is
EXACTLY `<TOKEN_n>` appears.  The pty echoes the input just sent
(`echo <TOKEN_n>`), which CONTAINS the token - so the old substring test
(`if PROMPT in buf`) self-matched its own echo and advanced early, before the
shell's first prompt even existed; an exact-line test cannot self-match.

PROMPT DETECTION (round 33).  The shell-state fallback `[#$] *$` accepted ANY
read chunk that ended on a `#` - the kernel banner's `FreeBSD ... #0` did
exactly that (byte offset 12300 of build/cheri/logs/spike-morello-ssh.log), so
the driver sent its first command MID-MOTD, `login` discarded the typeahead,
and every command then cost a full --sync-timeout.  Prompt detection now
requires a real prompt LINE anchored at a line start and at the end of the
buffer (`root@<host>:~ # `); the bare `[#$] *$` fallback is gone.  Nothing is
sent until the guest has been QUIESCENT for --settle seconds (no output).

THE DRIVER NEVER RE-SENDS A COMMAND.  Two live races taught this, both in the
2026-10-17 acceptance runs (evidence under ./tmp/logs/):
  (1) A bare timer cannot tell a DROPPED typeahead from a command that is still
      running: re-sending the pending command every 15 s regardless of guest
      state re-sent a `cp -a` and then a corpus run three times, queueing four
      runner invocations while the first was still executing; the fallback
      fired, QEMU was killed, and the lane lost the run.
  (2) Prompt-gating the re-send is NOT sufficient either.  In run 3, `cp`'s own
      completion prompt appeared before the typed token echo surfaced, so cmd 6
      was re-sent; the duplicate `cp`'s prompt then preceded the queued runner,
      so cmd 7 (the runner) was re-sent too - three runner invocations.  A
      prompt can also mean "an earlier queued command finished and the pending
      one has not started", and a typed line can carry line-editing control
      characters (`BENCH_D ^HIR`), so neither the prompt nor an exact-text echo
      match is a reliable discriminator.
Since every command is sent only at a prompt after the --settle quiescence
gate, the dropped-typeahead case the old re-send existed for cannot occur, so a
re-send can only duplicate work.  A missing token now waits to the
--sync-timeout deadline and takes the existing fallback: the run fails loudly
rather than duplicating.  The --sync-timeout default is 2700 s because run 3
measured one corpus run at about 1800 s.  The driver never depends on the
guest's shell honouring `PS1=` (it is not used).

argv:  --qemu PATH --log PATH [--cap SEC] [--cmd FILE] -- <qemu argv...>
"""
import argparse
import errno
import os
import pty
import re
import select
import signal
import subprocess
import sys
import time

# The guest's own shell prompt, e.g. "root@cheribsd-morello-purecap:~ # ".
# It must be a COMPLETE LINE at the end of the buffer: anchored at a line start
# AND at the buffer end, so neither a stray '#' inside ordinary output (the
# kernel banner's "#0") nor a prompt left over from an earlier command matches.
GUEST_PROMPT_RE = re.compile(r"(?:^|\r?\n)root@[^\r\n]*[#$][ \t]*$")
TOKEN_FMT = "SPIKE_SYNC_%d"


def has_bare_line(buf: str, token: str) -> bool:
    """True when some line of buf is EXACTLY token (self-match-proof).

    The echoed input line reads `echo <token>` and so contains the token as a
    substring; only the shell's own response line is the token alone.
    """
    return any(line.strip() == token for line in buf.splitlines())


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--qemu", required=True)
    ap.add_argument("--log", required=True)
    ap.add_argument("--cap", type=int, default=900)
    ap.add_argument("--cmd", default=None, help="file of console lines to run")
    ap.add_argument("--login-wait", type=int, default=600)
    ap.add_argument("--sync-timeout", type=int, default=2700,
                    help="seconds to wait for a sync token before falling back "
                         "(one command may legitimately run the whole corpus; "
                         "run 3 measured about 1800 s)")
    ap.add_argument("--settle", type=float, default=1.0,
                    help="seconds of output silence required before sending")
    ap.add_argument("--sentinel", default="SPIKE_SENTINEL_DONE")
    ap.add_argument("--poweroff", action="store_true")
    ap.add_argument("args", nargs=argparse.REMAINDER)
    ns = ap.parse_args()

    qemu_argv = list(ns.args)
    if qemu_argv and qemu_argv[0] == "--":
        qemu_argv = qemu_argv[1:]
    if qemu_argv and qemu_argv[0] == ns.qemu:
        # run.sh passes `-- "$QEMU" ...` and the `--` strip above leaves the
        # emulator path in the argument list; QEMU treats a bare positional
        # argument as a disk (softmmu/vl.c: drive_add(IF_DEFAULT, 0,
        # argv[optind])), so the path must be dropped here, in the driver.
        qemu_argv = qemu_argv[1:]
    if not qemu_argv:
        print("driver: no qemu argv given", file=sys.stderr)
        return 2

    cmd_lines = []
    if ns.cmd:
        with open(ns.cmd, "r", encoding="utf-8") as fh:
            cmd_lines = [ln.rstrip("\n") for ln in fh
                         if ln.strip() and not ln.lstrip().startswith("#")]

    master, slave = pty.openpty()
    proc = subprocess.Popen(
        [ns.qemu] + qemu_argv,
        stdin=slave, stdout=slave, stderr=slave,
        preexec_fn=os.setsid, close_fds=True,
    )
    os.close(slave)

    log = open(ns.log, "w", encoding="utf-8", errors="replace")
    log.write("# driver argv: %s\n" % " ".join([ns.qemu] + qemu_argv))
    log.flush()

    buf = ""
    state = "login"          # login -> shell -> commands <-> sync
    cmd_idx = 0
    started = time.time()
    token = None
    deadline = None
    last_output = started

    def emit(data: str) -> None:
        log.write(data)
        log.flush()
        sys.stdout.write(data)
        sys.stdout.flush()

    def send(line: str) -> None:
        os.write(master, (line + "\n").encode())

    def quiescent(now: float) -> bool:
        return now - last_output >= ns.settle

    try:
        while True:
            now = time.time()
            if now - started > ns.cap:
                emit("\n# driver: cap %ds reached; terminating guest\n" % ns.cap)
                break
            if state == "login" and now - started > ns.login_wait:
                emit("\n# driver: login not reached within %ds\n" % ns.login_wait)
                break

            r, _, _ = select.select([master], [], [], 1.0)
            if r:
                try:
                    chunk = os.read(master, 65536)
                except OSError as exc:
                    if exc.errno == errno.EIO:
                        break
                    raise
                if not chunk:
                    break
                text = chunk.decode("utf-8", "replace")
                buf = (buf + text)[-16384:]
                emit(text)
                last_output = time.time()
            now = time.time()

            if state == "login":
                if re.search(r"login: *$", buf) and quiescent(now):
                    send("root")
                    buf = ""
                    state = "shell"
            elif state == "shell":
                # An empty root password makes getty skip straight to the
                # shell, so accept either a password prompt or a prompt.
                if re.search(r"[Pp]assword: *$", buf):
                    if quiescent(now):
                        send("")            # empty root password
                        buf = ""
                elif GUEST_PROMPT_RE.search(buf) and quiescent(now):
                    # A real prompt LINE at the buffer end AND a quiet guest:
                    # never a lone '#' from ordinary output (that fallback is
                    # gone - see the module docstring), and never a prompt that
                    # is still being followed by motd output.
                    buf = ""
                    state = "commands"
            elif state == "commands":
                if quiescent(now):
                    if cmd_idx < len(cmd_lines):
                        send(cmd_lines[cmd_idx])
                        cmd_idx += 1
                        token = TOKEN_FMT % cmd_idx
                        send("echo %s" % token)
                    else:
                        token = ns.sentinel
                        send("echo %s" % token)
                    deadline = now + ns.sync_timeout
                    state = "sync"
            elif state == "sync":
                if has_bare_line(buf, token):
                    buf = ""
                    if token == ns.sentinel:
                        emit("\n# driver: sentinel seen; guest commands complete\n")
                        if ns.poweroff:
                            send("shutdown -p now")
                            time.sleep(8)
                        break
                    state = "commands"
                elif now > deadline:
                    # Every wait is bounded; a token that never echoes must not
                    # hang the run.  There is deliberately NO re-send: a missed
                    # token fails loudly here rather than duplicating a command
                    # (see the module docstring for both races that taught this).
                    emit("\n# driver: sync token %s not seen within %ds "
                         "(fallback; guest prompt %s)\n"
                         % (token, ns.sync_timeout,
                            "seen" if GUEST_PROMPT_RE.search(buf) else "not seen"))
                    buf = ""
                    if token == ns.sentinel:
                        break
                    state = "commands"
    finally:
        try:
            os.killpg(os.getpgid(proc.pid), signal.SIGTERM)
        except OSError:
            pass
        try:
            proc.wait(timeout=15)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(os.getpgid(proc.pid), signal.SIGKILL)
            except OSError:
                pass
        os.close(master)
        log.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
