#!/usr/bin/env bash
# hypridle-set.sh <lock_secs> <suspend_secs>
# Rewrite the two listener `timeout =` values in hypr.lua/hypridle.conf (1st = idle→lock,
# 2nd = idle→suspend) and restart hypridle so the new timers take effect. Called by the
# Lockscreen & suspend settings page.
source "$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)/lib/env.sh"

# The LIVE file hypridle reads is ~/.config/hypr/hypridle.conf → symlink → the user-data copy.
conf="$VELUMERON_USER_DIR/hypr.lua/hypridle.conf"
[[ -f "$conf" ]] || conf="$VELUMERON_DIR/hypr.lua/hypridle.conf"
[[ -f "$conf" ]] || exit 0
[[ "$1" =~ ^[0-9]+$ && "$2" =~ ^[0-9]+$ ]] || { echo "usage: hypridle-set.sh <lock_secs> <suspend_secs>" >&2; exit 1; }

python3 - "$conf" "$1" "$2" <<'PY'
import sys, re
conf, lock, susp = sys.argv[1], sys.argv[2], sys.argv[3]
c = open(conf).read()
vals = [lock, susp]; i = [0]
def repl(m):
    j = i[0]; i[0] += 1
    return m.group(1) + vals[j] if j < 2 else m.group(0)
open(conf, 'w').write(re.sub(r'(timeout\s*=\s*)\d+', repl, c))
PY

pkill -x hypridle 2>/dev/null
sleep 0.3
setsid -f hypridle >/dev/null 2>&1
