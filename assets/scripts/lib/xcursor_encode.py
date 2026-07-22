"""Pure-Python Xcursor binary encoder — no xcursorgen/clickgen needed.

Writes the libXcursor file format (magic "Xcur"): a file header, a table of
contents, and one IMAGE chunk per frame. Animated cursors are simply several
IMAGE chunks that share a nominal size — libXcursor cycles through same-size
images in TOC order, honouring each frame's delay.

    write_xcursor(path, images)

`images` is a list of dicts, each:
    { "size":  int,          # nominal size (the TOC subtype the loader matches)
      "width": int, "height": int,
      "xhot":  int, "yhot":  int,
      "delay": int,          # ms (0 for static)
      "pixels": bytes }      # width*height*4, premultiplied ARGB packed
                             # little-endian == byte order B, G, R, A

Reference: xcursor(3) / libXcursor file-format header.
"""
import struct

MAGIC = b"Xcur"
FILE_HEADER = 16
FILE_VERSION = 0x0001_0000
IMAGE_TYPE = 0xFFFD_0002
IMAGE_HEADER = 36            # 9 * uint32: header,type,subtype,version + w,h,xhot,yhot,delay
TOC_ENTRY = 12


def write_xcursor(path, images):
    if not images:
        raise ValueError("no images to write")

    # libXcursor animates same-size frames in TOC order; keep sizes grouped and
    # frame order stable (Python's sort is stable).
    images = sorted(images, key=lambda im: im["size"])

    n = len(images)
    toc = []
    off = FILE_HEADER + n * TOC_ENTRY
    for im in images:
        toc.append((IMAGE_TYPE, im["size"], off))
        off += IMAGE_HEADER + len(im["pixels"])

    with open(path, "wb") as f:
        # file header
        f.write(MAGIC)
        f.write(struct.pack("<III", FILE_HEADER, FILE_VERSION, n))
        # table of contents
        for typ, subtype, position in toc:
            f.write(struct.pack("<III", typ, subtype, position))
        # image chunks
        for im in images:
            w, h = im["width"], im["height"]
            expected = w * h * 4
            if len(im["pixels"]) != expected:
                raise ValueError(
                    f"pixel buffer {len(im['pixels'])} != {w}x{h}x4={expected}")
            f.write(struct.pack("<IIII", IMAGE_HEADER, IMAGE_TYPE, im["size"],
                                1))                       # chunk header + version
            f.write(struct.pack("<IIIII", w, h, im["xhot"], im["yhot"],
                                im["delay"]))
            f.write(im["pixels"])
