#!/usr/bin/env python3
"""Audio routing for the mixer popout (stdlib + pactl only).

Quickshell's Pipewire service can read and set volumes, but it cannot MOVE a stream to another
device — and the obvious `pactl move-sink-input <id>` doesn't work either, because the id it wants
is not the id Quickshell hands out. Three numbers name the same stream:

    PipeWire node id   64     what Quickshell's PwNode.id gives, and what QML knows
    object.serial      6978   what pactl calls the sink-input "index"
    pactl index        6978   the handle move-sink-input actually takes

pactl reports `object.id` in each sink-input's properties, and that IS the PipeWire node id — so it
is the hinge between the two worlds. This script does that lookup and the move in one step, so QML
only ever deals in node ids.

Commands (all quiet; exit 0 on success, 1 on failure):
  move <nodeId> <sinkName>          route a playback stream to an output
  move-source <nodeId> <srcName>    route a recording stream to an input
  default-sink <name>               set the default output
  default-source <name>             set the default input
  streams                           print the streams as JSON: [{nodeId, index, sink, app, media}]
"""

import json
import subprocess
import sys


def _pactl_json(what):
    try:
        out = subprocess.run(["pactl", "-f", "json", "list", what],
                             capture_output=True, text=True, timeout=5)
        return json.loads(out.stdout) if out.returncode == 0 else []
    except (OSError, ValueError, subprocess.SubprocessError):
        return []


def _index_for(node_id, what):
    """pactl's index for the sink-input / source-output whose PipeWire node id is `node_id`."""
    want = str(node_id)
    for item in _pactl_json(what):
        props = item.get("properties") or {}
        if str(props.get("object.id")) == want:
            return item.get("index")
    return None


def _run(args):
    try:
        return subprocess.run(args, capture_output=True, text=True, timeout=5).returncode == 0
    except (OSError, subprocess.SubprocessError):
        return False


def move(node_id, target, kind):
    what = "sink-inputs" if kind == "sink" else "source-outputs"
    verb = "move-sink-input" if kind == "sink" else "move-source-output"
    idx = _index_for(node_id, what)
    if idx is None:
        sys.stderr.write("no %s for node %s\n" % (what[:-1], node_id))
        return False
    return _run(["pactl", verb, str(idx), target])


def _device_names(what):
    """pactl device index → its PipeWire node name, so a stream can report WHERE it plays in the
    same vocabulary the device list uses (Quickshell knows devices by node name).

    Per kind, NOT merged: pactl numbers sinks and sources in separate namespaces, so index 6577 is
    a sink AND a different source. One shared dict let the sources overwrite the sinks and every
    playback stream claimed to be on some `.monitor` device.
    """
    return {d.get("index"): (d.get("name") or "") for d in _pactl_json(what)}


def streams():
    names = {"sink": _device_names("sinks"), "source": _device_names("sources")}
    out = []
    for kind, what in (("sink", "sink-inputs"), ("source", "source-outputs")):
        for item in _pactl_json(what):
            props = item.get("properties") or {}
            oid = props.get("object.id")
            if oid is None:
                continue
            dev = item.get("sink") if kind == "sink" else item.get("source")
            out.append({
                "nodeId": int(oid),
                "index":  item.get("index"),
                "kind":   kind,
                # Where it currently plays / records — pactl's numeric id and the node name.
                "device":     dev,
                "deviceName": names[kind].get(dev, ""),
                "app":        props.get("application.name") or props.get("node.name") or "",
                "media":      props.get("media.name") or "",
            })
    return out


def main():
    argv = sys.argv[1:]
    if not argv:
        sys.stderr.write(__doc__)
        return 2
    cmd, args = argv[0], argv[1:]

    if cmd == "streams":
        json.dump(streams(), sys.stdout)
        sys.stdout.write("\n")
        return 0
    if cmd == "move" and len(args) == 2:
        return 0 if move(args[0], args[1], "sink") else 1
    if cmd == "move-source" and len(args) == 2:
        return 0 if move(args[0], args[1], "source") else 1
    if cmd == "default-sink" and len(args) == 1:
        return 0 if _run(["pactl", "set-default-sink", args[0]]) else 1
    if cmd == "default-source" and len(args) == 1:
        return 0 if _run(["pactl", "set-default-source", args[0]]) else 1

    sys.stderr.write("bad command: %s\n" % " ".join(argv))
    return 2


if __name__ == "__main__":
    sys.exit(main())
