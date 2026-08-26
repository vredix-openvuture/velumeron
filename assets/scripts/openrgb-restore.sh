#!/usr/bin/env bash
# openrgb-restore.sh — bring OpenRGB up in a state where profiles actually apply.
#
# Background: since OpenRGB 1.0rc3 (upgraded 2026-07-01) the RGB Fusion 2 USB
# driver enumerates the B660M GAMING X DDR4 (IT5701) with a generic 4-zone
# layout, and the two addressable headers D_LED1/D_LED2 come up sized to
# 0 LEDs. A zone of length 0 accepts no colours, so loading a profile reports
# "Profile loaded successfully" while the ARGB fans stay dark. sizes.ors is no
# longer restored for this device either, so the size has to be forced on every
# start, BEFORE the profile is loaded.
#
# Order matters: server up -> zones resized -> profile loaded. Loading the
# profile first is what the old `sleep 30 && openrgb -p ...` retry was working
# around; it never actually fixed the zone size.
#
# That workaround is ONE board's. This script is the login path for every
# machine now (Settings -> OpenRGB -> apply at login), so the resize step is
# best-effort: a machine without that controller waits a few seconds, finds
# nothing to resize, and loads the profile regardless. It used to spend the full
# timeout looking and then exit WITHOUT loading the profile, which on any other
# board meant no lighting at all.
#
#   openrgb-restore.sh [profile]     default profile: purple-blizzard
#
# Overridable per machine (Settings writes the first two into settings.json):
#   openrgb_zone_board / $VELUMERON_OPENRGB_BOARD      controller name substring
#   openrgb_zone_size  / $VELUMERON_OPENRGB_ZONE_SIZE  LEDs per ARGB header
#   empty board                                        skip the resize entirely

set -uo pipefail

_dir="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)"
source "$_dir/lib/env.sh"

_setting() {  # $1 key, $2 default — from the shell's settings.json
    local v="" gs="$VELUMERON_USER_DIR/gui/settings.json"
    [[ -f "$gs" ]] && command -v jq >/dev/null 2>&1 &&
        v=$(jq -r --arg k "$1" '.[$k] // empty' "$gs" 2>/dev/null)
    printf '%s' "${v:-$2}"
}

PROFILE="${1:-purple-blizzard}"
BOARD="${VELUMERON_OPENRGB_BOARD:-$(_setting openrgb_zone_board "")}"
ZONE_SIZE="${VELUMERON_OPENRGB_ZONE_SIZE:-$(_setting openrgb_zone_size 15)}"
PORT=6742
TIMEOUT=60
RESIZE_TIMEOUT=20               # the resize is a workaround, not the point — don't sit on it

log() { printf '[openrgb-restore] %s\n' "$*"; }

# 1. Make sure exactly one instance with an SDK server is running. Extra
#    instances fight over the same i2c/hidraw handles and clobber each other.
if ! pgrep -x openrgb >/dev/null 2>&1; then
    log "starting OpenRGB (server, minimised)"
    setsid -f openrgb --server --startminimized >/dev/null 2>&1
fi

# 2. Wait for the SDK server. Detection of all buses takes a few seconds.
for ((i = 0; i < TIMEOUT; i++)); do
    if ss -ltn 2>/dev/null | grep -q ":${PORT}\b"; then break; fi
    sleep 1
done
if ! ss -ltn 2>/dev/null | grep -q ":${PORT}\b"; then
    log "SDK server never came up on ${PORT} — aborting"
    exit 1
fi

# 3. Force the ARGB zone sizes over the SDK.
PORT="$PORT" BOARD="$BOARD" ZONE_SIZE="$ZONE_SIZE" TIMEOUT="$RESIZE_TIMEOUT" python3 - <<'PYEOF'
import os, re, socket, struct, sys, time

PORT      = int(os.environ["PORT"])
BOARD     = os.environ["BOARD"].encode()
ZONE_SIZE = int(os.environ["ZONE_SIZE"])
TIMEOUT   = int(os.environ["TIMEOUT"])

REQ_COUNT, REQ_DATA, REQ_PROTO, SET_NAME, RESIZE = 0, 1, 40, 50, 1000
ARGB_ZONES  = ("D_LED1", "D_LED2")
KNOWN_ZONES = ARGB_ZONES + ("LED_C1", "LED_C2")


class Client:
    """Minimal OpenRGB SDK client.

    The server starts listening before device detection has finished, so a
    connection that succeeds says nothing about the controller list being
    ready. Every step here is therefore treated as retryable.
    """

    def __init__(self):
        self.s = socket.create_connection(("127.0.0.1", PORT), timeout=20)
        self.send(0, SET_NAME, b"openrgb-restore\x00")
        self.send(0, REQ_PROTO, struct.pack("<I", 4))
        self.proto = struct.unpack("<I", self.recv(4))[0]

    def send(self, dev, pid, data=b""):
        self.s.sendall(b"ORGB" + struct.pack("<III", dev, pid, len(data)) + data)

    def recv(self, expect=None):
        head = b""
        while len(head) < 16:
            chunk = self.s.recv(16 - len(head))
            if not chunk:
                raise ConnectionError("server closed the connection")
            head += chunk
        if head[:4] != b"ORGB":
            raise ConnectionError("bad packet magic — stream out of sync")
        _, _, size = struct.unpack("<III", head[4:16])
        body = b""
        while len(body) < size:
            chunk = self.s.recv(size - len(body))
            if not chunk:
                raise ConnectionError("server closed the connection")
            body += chunk
        if expect is not None and len(body) != expect:
            raise ConnectionError(f"expected {expect} bytes, got {len(body)}")
        return body

    def close(self):
        try:
            self.s.close()
        except OSError:
            pass


def zones(buf):
    """Yield (index, name, leds_count) for the controller's zones.

    The v5 mode block has no stable stride across builds, so rather than walking
    the whole struct we anchor on each zone name: a u16 length prefix that
    matches the string, followed by a plausible (type, min, max, count) header.
    """
    idx = 0
    for m in re.finditer(rb"[A-Z_0-9]{5,8}\x00", buf):
        i, e = m.start(), m.end()
        if i < 2:
            continue
        (prefix,) = struct.unpack_from("<H", buf, i - 2)
        if prefix != e - i:
            continue
        try:
            ztype, lmin, lmax, lcnt = struct.unpack_from("<iIII", buf, e)
        except struct.error:
            continue
        if not (0 <= ztype <= 2 and lmax <= 4096 and lcnt <= lmax and lmin <= lmax):
            continue
        name = buf[i:e - 1].decode("utf-8", "replace")
        if name in KNOWN_ZONES:
            yield idx, name, lcnt
            idx += 1


def find_board(c):
    """Return [(device_index, controller_buffer)] for the controllers to inspect.

    With BOARD set, that is the one whose name contains it — the original,
    named-board behaviour. With BOARD EMPTY it is every controller, and the fix
    narrows instead to the symptom (see needs_fix): an ARGB header reporting
    zero LEDs is wrong on any board, and a header with nothing plugged into it
    does not care what length we give it. That is what makes this script safe as
    the login path on machines that never had the bug.
    """
    c.send(0, REQ_COUNT)
    count = struct.unpack("<I", c.recv(4))[0]
    out = []
    for dev in range(count):
        c.send(dev, REQ_DATA, struct.pack("<I", c.proto))
        buf = c.recv()
        if len(buf) < 10:
            continue
        if not BOARD:
            out.append((dev, buf))
            continue
        (nlen,) = struct.unpack_from("<H", buf, 8)
        if BOARD in buf[10:10 + nlen]:
            return [(dev, buf)]
    return out


def needs_fix(lcnt):
    """Is this ARGB zone's length wrong? Named board: anything but ZONE_SIZE.
    Auto mode: only a zero, which is the enumeration bug and nothing else."""
    return lcnt != ZONE_SIZE if BOARD else lcnt == 0


def attempt():
    """One full try. Returns True once no ARGB zone is left to resize."""
    c = None
    try:
        c = Client()
        found = find_board(c)
        if not found:
            return False

        def pending(controllers):
            """Zones still wanting a resize, as [(dev, idx, name, lcnt)].

            With a named board, seeing NEITHER ARGB zone means the controller
            data was still incomplete — a retry, not a success. In auto mode
            there is no such expectation: most machines legitimately have none.
            """
            todo, seen = [], 0
            for dev, buf in controllers:
                for idx, name, lcnt in zones(buf):
                    if name not in ARGB_ZONES:
                        continue
                    seen += 1
                    if needs_fix(lcnt):
                        todo.append((dev, idx, name, lcnt))
            if BOARD and seen < len(ARGB_ZONES):
                return None                      # not ready yet
            return todo

        todo = pending(found)
        if todo is None:
            return False
        if not todo:
            print("[openrgb-restore] ARGB zones already sized correctly")
            return True

        for dev, idx, name, lcnt in todo:
            c.send(dev, RESIZE, struct.pack("<ii", idx, ZONE_SIZE))
            print(f"[openrgb-restore] {name}: {lcnt} -> {ZONE_SIZE} LEDs")

        # Read back rather than trusting the write.
        time.sleep(2)
        again = pending(find_board(c))
        return again is not None and not again
    except (OSError, ConnectionError, struct.error):
        return False
    finally:
        if c:
            c.close()


deadline = time.monotonic() + TIMEOUT
while time.monotonic() < deadline:
    if attempt():
        break
    time.sleep(2)
else:
    print(f"[openrgb-restore] could not size the ARGB zones within {TIMEOUT}s")
    sys.exit(1)
PYEOF
# Not fatal. On the board this exists for, a failed resize means the ARGB headers stay at 0 LEDs
# and those fans stay dark — but every OTHER device in the profile still lights up, and on a
# machine that never had the bug there was nothing to resize in the first place.
(( $? == 0 )) || log "zone sizing did not complete — loading the profile anyway"

# 4. The profile. On the quirky board, only now does it have zones to write into.
log "loading profile '${PROFILE}'"
openrgb -p "$PROFILE" >/dev/null 2>&1 || { log "profile load failed"; exit 1; }
printf '%s' "$PROFILE" > "$VELUMERON_USER_DIR/gui/openrgb-active" 2>/dev/null || true
log "done"
