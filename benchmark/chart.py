"""Draw benchmark/chart.svg from a results CSV. Standard library only.

    python benchmark/chart.py benchmark/results/2026-10-09.csv
"""

import csv
import math
import pathlib
import sys

W, H = 960, 560
LEFT, RIGHT, TOP, BOTTOM = 70, 250, 120, 70
Y_MAX = 20.0
BUDGET = 1000.0 / 60.0
SURFACE, INK, INK_2, GRID = "#fcfcfb", "#0b0b0b", "#52514e", "#e4e3df"
SERIES = [  # setup, label, colour, marker
    ("agent_avoid", "NavigationAgent3D + avoidance", "#2a78d6", "circle"),
    ("agent_plain", "NavigationAgent3D, no avoidance", "#eb6834", "square"),
    ("shared_path", "One path per squad of 20", "#1baf7a", "triangle"),
    ("flow_multimesh", "Flow field + MultiMesh", "#eda100", "diamond"),
]


def read(path):
    machine, rows = "", {}
    with open(path, encoding="utf-8") as f:
        lines = f.read().splitlines()
    machine = lines[0].lstrip("# ")
    for r in csv.DictReader(l for l in lines if not l.startswith("#")):
        rows.setdefault(r["setup"], []).append(r)
    return machine, rows


def x_of(units, lo, hi):
    span = math.log(hi) - math.log(lo)
    return LEFT + (math.log(units) - math.log(lo)) / span * (W - LEFT - RIGHT)


def y_of(ms):
    return TOP + (1 - min(ms, Y_MAX) / Y_MAX) * (H - TOP - BOTTOM)


def marker(kind, x, y, colour):
    ring = 'stroke="%s" stroke-width="2"' % SURFACE
    if kind == "circle":
        return '<circle cx="%.1f" cy="%.1f" r="4.5" fill="%s" %s/>' % (x, y, colour, ring)
    if kind == "square":
        return '<rect x="%.1f" y="%.1f" width="9" height="9" rx="1" fill="%s" %s/>' % (x - 4.5, y - 4.5, colour, ring)
    if kind == "triangle":
        return '<path d="M%.1f %.1f L%.1f %.1f L%.1f %.1f Z" fill="%s" %s/>' % (
            x, y - 6, x + 5.5, y + 4, x - 5.5, y + 4, colour, ring)
    return '<path d="M%.1f %.1f L%.1f %.1f L%.1f %.1f L%.1f %.1f Z" fill="%s" %s/>' % (
        x, y - 6, x + 6, y, x, y + 6, x - 6, y, colour, ring)


def text(x, y, s, size=13, fill=INK, anchor="start", weight="400"):
    s = s.replace("&", "&amp;").replace("<", "&lt;")
    return ('<text x="%.1f" y="%.1f" font-size="%d" fill="%s" text-anchor="%s" '
            'font-weight="%s">%s</text>' % (x, y, size, fill, anchor, weight, s))


def main(path):
    machine, rows = read(path)
    sizes = sorted({int(r["units"]) for rs in rows.values() for r in rs})
    lo, hi = sizes[0], sizes[-1]
    out = ['<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d" '
           'font-family="Segoe UI, Helvetica, Arial, sans-serif">' % (W, H, W, H),
           '<rect width="100%%" height="100%%" fill="%s"/>' % SURFACE,
           text(LEFT, 38, "How many moving units fit in a 60 fps frame in Godot 4?", 20, weight="600"),
           text(LEFT, 62, "Frame time of a frame that runs one simulation step, by unit count. Lower is better.", 13, INK_2),
           text(LEFT, 82, machine, 12, INK_2)]
    for ms in range(0, int(Y_MAX) + 1, 5):
        y = y_of(ms)
        out.append('<line x1="%d" x2="%d" y1="%.1f" y2="%.1f" stroke="%s"/>' % (LEFT, W - RIGHT, y, y, GRID))
        out.append(text(LEFT - 10, y + 4, "%d ms" % ms, 12, INK_2, "end"))
    for n in sizes:
        x = x_of(n, lo, hi)
        out.append(text(x, H - BOTTOM + 22, "{:,}".format(n), 12, INK_2, "middle"))
    out.append(text((LEFT + W - RIGHT) / 2, H - BOTTOM + 48, "units moving (log scale)", 12, INK_2, "middle"))
    yb = y_of(BUDGET)
    out.append('<line x1="%d" x2="%d" y1="%.1f" y2="%.1f" stroke="%s" stroke-width="1.5" '
               'stroke-dasharray="6 4"/>' % (LEFT, W - RIGHT, yb, yb, INK_2))
    out.append(text(LEFT + 6, yb - 6, "16.7 ms: the whole frame budget at 60 fps", 12, INK_2))

    ends = []
    for setup, label, colour, kind in SERIES:
        pts, fell = [], None
        for r in rows.get(setup, []):
            n = int(r["units"])
            if r["tick_frame_ms"] == "nan":
                fell = (n, float(r["catchup_ms"]), float(r["ticks_per_s"]))
                continue
            pts.append((x_of(n, lo, hi), y_of(float(r["tick_frame_ms"])), float(r["tick_frame_ms"])))
        path = " ".join(("M" if i == 0 else "L") + "%.1f %.1f" % (x, y) for i, (x, y, _) in enumerate(pts))
        if fell:
            fx = x_of(fell[0], lo, hi)
            path += " L%.1f %.1f" % (fx, TOP - 8)
            out.append(text(fx - 8, TOP - 14, "%s units: %.0f ms frames, %.0f of 60 steps a second"
                            % ("{:,}".format(fell[0]), fell[1], fell[2]), 12, INK, "end"))
        out.append('<path d="%s" fill="none" stroke="%s" stroke-width="2" stroke-linejoin="round"/>' % (path, colour))
        for x, y, _ in pts:
            out.append(marker(kind, x, y, colour))
        last = pts[-1]
        # A series that left the chart is labelled where its line leaves.
        ends.append([TOP + 10 if fell else last[1], label, colour, kind, last[2], fell])

    # Direct labels at the right, nudged apart so none overlap.
    ends.sort()
    for i in range(1, len(ends)):
        ends[i][0] = max(ends[i][0], ends[i - 1][0] + 30)
    for y, label, colour, kind, ms, fell in ends:
        lx = W - RIGHT + 16
        out.append(marker(kind, lx, y - 4, colour))
        out.append(text(lx + 12, y, label, 12))
        note = "falls behind at %s" % "{:,}".format(fell[0]) if fell else "%.1f ms at %s" % (ms, "{:,}".format(hi))
        out.append(text(lx + 12, y + 15, note, 11, INK_2))
    out.append("</svg>")
    target = pathlib.Path(__file__).with_name("chart.svg")
    target.write_text("\n".join(out) + "\n", encoding="utf-8")
    print(target)


if __name__ == "__main__":
    main(sys.argv[1])
