#!/usr/bin/env python3
"""Velumeron integrations — surgical config editor.

Small, format-aware helpers used by integrations.sh to flip a single selection
key (or manage one marker-delimited block) inside a user's existing config
WITHOUT reformatting or dropping the rest of the file. The caller always backs
the file up first, so a disable can restore the byte-exact original regardless.

    integrations-edit.py kv-get   <file> <key>
    integrations-edit.py kv-set   <file> <key> <value>      # key = "value"
    integrations-edit.py json-get <file> <key>
    integrations-edit.py json-set <file> <key> <value>      # "key": "value"
    integrations-edit.py block-set <file>  < content-on-stdin
"""
import re
import sys

BEGIN = "# >>> velumeron integration >>>"
END = "# <<< velumeron integration <<<"


def read(path):
    try:
        with open(path) as fh:
            return fh.read()
    except OSError:
        return None


def write(path, s):
    with open(path, "w") as fh:
        fh.write(s)


def kv_get(path, key):
    s = read(path)
    if s is None:
        return ""
    m = re.search(r'(?m)^[ \t]*' + re.escape(key) + r'[ \t]*=[ \t]*"([^"]*)"', s)
    return m.group(1) if m else ""


def kv_set(path, key, value):
    s = read(path) or ""
    pat = re.compile(r'(?m)^([ \t]*' + re.escape(key) + r'[ \t]*=[ \t]*)"[^"]*"')
    if pat.search(s):
        s = pat.sub(lambda m: m.group(1) + '"%s"' % value, s, count=1)
    else:                                    # insert before first [section], else append
        sm = re.search(r'(?m)^\[', s)
        line = '%s = "%s"\n' % (key, value)
        s = (s[:sm.start()] + line + s[sm.start():]) if sm else (s.rstrip("\n") + "\n" + line)
    write(path, s)


def json_get(path, key):
    s = read(path)
    if s is None:
        return ""
    m = re.search(r'"' + re.escape(key) + r'"[ \t]*:[ \t]*"([^"]*)"', s)
    return m.group(1) if m else ""


def json_set(path, key, value):
    s = read(path) or "{\n}\n"
    pat = re.compile(r'("' + re.escape(key) + r'"[ \t]*:[ \t]*)"[^"]*"')
    if pat.search(s):
        s = pat.sub(lambda m: m.group(1) + '"%s"' % value, s, count=1)
    else:                                    # insert as the first entry after the opening brace
        i = s.index("{")
        s = s[:i + 1] + '\n    "%s": "%s",' % (key, value) + s[i + 1:]
    write(path, s)


def block_strip(s):
    return re.sub(re.escape(BEGIN) + r".*?" + re.escape(END) + r"\n?", "", s, flags=re.S)


def block_set(path):
    content = sys.stdin.read().rstrip("\n")
    s = read(path) or ""
    s = block_strip(s).rstrip("\n")
    s = (s + "\n\n" if s else "") + BEGIN + "\n" + content + "\n" + END + "\n"
    write(path, s)


def main():
    a = sys.argv[1:]
    if not a:
        sys.exit(2)
    op = a[0]
    try:
        if op == "kv-get":
            print(kv_get(a[1], a[2]))
        elif op == "kv-set":
            kv_set(a[1], a[2], a[3])
        elif op == "json-get":
            print(json_get(a[1], a[2]))
        elif op == "json-set":
            json_set(a[1], a[2], a[3])
        elif op == "block-set":
            block_set(a[1])
        else:
            sys.exit(2)
    except IndexError:
        sys.exit(2)


if __name__ == "__main__":
    main()
