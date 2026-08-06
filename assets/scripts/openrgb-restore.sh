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
#   openrgb-restore.sh [profile]     default profile: purple-blizzard

set -uo pipefail

PROFILE="${1:-purple-blizzard}"
ZONE_SIZE=15                    # LEDs per ARGB header (D_LED1 / D_LED2)
BOARD="B660M"                   # substring match on the controller name
PORT=6742
TIMEOUT=60

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
PORT="$PORT" BOARD="$BOARD" ZONE_SIZE="$ZONE_SIZE" TIMEOUT="$TIMEOUT" python3 - <<'PYEOF'
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
    """Return (device_index, controller_buffer) for the board, or None."""
    c.send(0, REQ_COUNT)
    count = struct.unpack("<I", c.recv(4))[0]
    for dev in range(count):
        c.send(dev, REQ_DATA, struct.pack("<I", c.proto))
        buf = c.recv()
        if len(buf) < 10:
            continue
        (nlen,) = struct.unpack_from("<H", buf, 8)
        if BOARD in buf[10:10 + nlen]:
            return dev, buf
    return None


def attempt():
    """One full try. Returns True once the ARGB zones are correctly sized."""
    c = None
    try:
        c = Client()
        found = find_board(c)
        if not found:
            return False
        dev, buf = found

        def sized_ok(controller_buf):
            """Both ARGB zones must be seen AND be the right length.

            Seeing neither means the controller data was still incomplete —
            that is a retry, not a success.
            """
            seen = {
                name: lcnt
                for _, name, lcnt in zones(controller_buf)
                if name in ARGB_ZONES
            }
            return len(seen) == len(ARGB_ZONES) and all(
                lcnt == ZONE_SIZE for lcnt in seen.values()
            )

        if sized_ok(buf):
            print("[openrgb-restore] ARGB zones already sized correctly")
            return True

        changed = False
        for idx, name, lcnt in zones(buf):
            if name in ARGB_ZONES and lcnt != ZONE_SIZE:
                c.send(dev, RESIZE, struct.pack("<ii", idx, ZONE_SIZE))
                print(f"[openrgb-restore] {name}: {lcnt} -> {ZONE_SIZE} LEDs")
                changed = True
        if not changed:
            return False

        # Read back rather than trusting the write.
        time.sleep(2)
        found = find_board(c)
        return bool(found) and sized_ok(found[1])
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

if (( $? != 0 )); then
    log "zone sizing failed — not loading the profile (it would silently no-op)"
    exit 1
fi

# 4. Only now does the profile have zones to write into.
log "loading profile '${PROFILE}'"
openrgb -p "$PROFILE" >/dev/null 2>&1 || { log "profile load failed"; exit 1; }
log "done"
