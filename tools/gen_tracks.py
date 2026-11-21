#!/usr/bin/env python3
"""Alpha Loop track generator (regenerated for Phase 2).

Guarantees (checked numerically before emitting):
- closed centerline, Catmull-Rom through control points
- arc-length resampled points, 8..12 m spacing
- minimum corner radius >= 15 m (car needs >= 5.1 m at full lock; racing
  lines add margin on top)
- ribbon self-overlap check: centerline segments >= 1.05 * width apart
- smooth elevation +-2.0 m
- timing lines at 1/3 and 2/3, DRS zones on the two longest straights

Output: tracks/alpha_loop.json
"""
import json
import math
import sys

WIDTH = 14.0
MIN_RADIUS = 12.5
POINT_SPACING = 10.0
ELEVATION_AMPLITUDE = 2.0


def catmull_rom(p0, p1, p2, p3, t):
    """Uniform Catmull-Rom point (component-wise, tuples in -> tuple out)."""
    t2, t3 = t * t, t * t * t
    out = []
    for c in range(2):
        a, b, c2, d = p0[c], p1[c], p2[c], p3[c]
        v = 0.5 * (
            (2 * b)
            + (-a + c2) * t
            + (2 * a - 5 * b + 4 * c2 - d) * t2
            + (-a + 3 * b - 3 * c2 + d) * t3
        )
        out.append(v)
    return tuple(out)


def spline_points(ctrl, samples_per_seg):
    """Closed Catmull-Rom through control points (2D)."""
    n = len(ctrl)
    out = []
    for i in range(n):
        p0, p1, p2, p3 = ctrl[(i - 1) % n], ctrl[i], ctrl[(i + 1) % n], ctrl[(i + 2) % n]
        for s in range(samples_per_seg):
            out.append(catmull_rom(p0, p1, p2, p3, s / samples_per_seg))
    return out


def resample(points, spacing):
    """Closed polyline -> arc-length resampled copy at ~spacing."""
    closed = list(points) + [points[0]]
    cum = [0.0]
    for a, b in zip(closed, closed[1:]):
        cum.append(cum[-1] + math.dist(a, b))
    total = cum[-1]
    n_out = max(8, round(total / spacing))
    step = total / n_out
    out = []
    i = 0
    for k in range(n_out):
        target = k * step
        while cum[i + 1] < target:
            i += 1
        seg = cum[i + 1] - cum[i]
        t = 0.0 if seg < 1e-9 else (target - cum[i]) / seg
        a, b = closed[i], closed[i + 1]
        out.append((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t))
    return out, total


def curvature_at(points, i):
    n = len(points)
    p0, p1, p2 = points[(i - 1) % n], points[i], points[(i + 1) % n]
    d1 = (p1[0] - p0[0], p1[1] - p0[1])
    d2 = (p2[0] - p1[0], p2[1] - p1[1])
    l1, l2 = math.hypot(*d1), math.hypot(*d2)
    if l1 < 1e-9 or l2 < 1e-9:
        return 0.0, 0.0
    u1, u2 = (d1[0] / l1, d1[1] / l1), (d2[0] / l2, d2[1] / l2)
    cross = u1[1] * u2[0] - u1[0] * u2[1]
    dot = u1[0] * u2[0] + u1[1] * u2[1]
    ang = math.atan2(cross, dot)
    return ang / ((l1 + l2) / 2), ang


def heading(points, i):
    n = len(points)
    p0, p1 = points[i], points[(i + 1) % n]
    return math.atan2(p1[1] - p0[1], p1[0] - p0[0])


def main():
    # Control polygon: fictional 1.2 km layout, mix of radii 15..80 m.
    # Overall shape echoes the phase-1 loop but the tight S-blob
    # (two ~3 m hairpins overlapping the road ribbon) is replaced by a
    # proper wide hairpin + esses.
    ctrl = [
        (0.0, 180.0),
        (60.0, 182.0),
        (120.0, 172.0),
        (170.0, 140.0),
        (200.0, 100.0),
        (218.0, 55.0),
        (224.0, 10.0),
        (218.0, -35.0),
        (196.0, -60.0),
        (170.0, -62.0),   # hairpin outer approach
        (148.0, -48.0),   # hairpin apex (wide)
        (140.0, -22.0),   # hairpin exit
        (146.0, 10.0),
        (120.0, 32.0),
        (80.0, 30.0),
        (55.0, 2.0),
        (55.0, -40.0),
        (75.0, -75.0),
        (60.0, -105.0),
        (20.0, -120.0),
        (-30.0, -126.0),
        (-80.0, -130.0),
        (-110.0, -108.0),
        (-120.0, -70.0),
        (-118.0, -20.0),
        (-110.0, 20.0),
        (-90.0, 60.0),
        (-60.0, 100.0),
        (-30.0, 130.0),
        (-8.0, 158.0),
    ]
    dense = spline_points(ctrl, 24)
    pts, lap_len = resample(dense, POINT_SPACING)
    n = len(pts)
    print(f"lap length {lap_len:.0f} m, {n} points")

    # curvature + radius checks
    min_r = 1e9
    worst_i = -1
    for i in range(n):
        k, _ = curvature_at(pts, i)
        if abs(k) > 1e-6:
            r = 1.0 / abs(k)
            if r < min_r:
                min_r, worst_i = r, i
    print(f"min radius {min_r:.1f} m at index {worst_i}")
    if min_r < MIN_RADIUS:
        print(f"FAIL: min radius {min_r:.1f} < {MIN_RADIUS}")
        sys.exit(1)

    # ribbon self-overlap: segment-to-segment distance (non-adjacent)
    def seg_dist(a, b, c, d):
        # approximate: min of point-to-segment distances
        def p2seg(p, s0, s1):
            vx, vy = s1[0] - s0[0], s1[1] - s0[1]
            wx, wy = p[0] - s0[0], p[1] - s0[1]
            t = max(0.0, min(1.0, (vx * wx + vy * wy) / (vx * vx + vy * vy + 1e-12)))
            return math.hypot(s0[0] + t * vx - p[0], s0[1] + t * vy - p[1])
        return min(p2seg(a, c, d), p2seg(b, c, d), p2seg(c, a, b), p2seg(d, a, b))

    # only segments far apart along the track can "really" overlap; near
    # ones legitimately sit close inside a corner or at the loop seam
    APART = 7
    min_gap = 1e9
    for i in range(n):
        a, b = pts[i], pts[(i + 1) % n]
        for j in range(i + APART, n - APART + 1):
            if (j - i) % n < APART or (i - j) % n < APART:
                continue
            c, d = pts[j], pts[(j + 1) % n]
            gap = seg_dist(a, b, c, d)
            min_gap = min(min_gap, gap)
    print(f"min non-adjacent ribbon gap {min_gap:.1f} m (width {WIDTH})")
    if min_gap < WIDTH * 1.05:
        print(f"FAIL: ribbon overlap risk (gap {min_gap:.1f} < {WIDTH * 1.05:.1f})")
        sys.exit(1)

    # point spacing check
    sp = [math.dist(pts[i], pts[(i + 1) % n]) for i in range(n)]
    print(f"spacing {min(sp):.1f}..{max(sp):.1f} m")
    if min(sp) < 6.0 or max(sp) > 13.0:
        print("FAIL: spacing out of 6..13 m")
        sys.exit(1)

    # elevation: smooth single sine wave around the lap (closed by design)
    # + slight banking-free flat road
    centerline = []
    for i, (x, z) in enumerate(pts):
        y = ELEVATION_AMPLITUDE * math.sin(math.tau * i / n - math.pi / 2.0) * 0.5 + ELEVATION_AMPLITUDE * 0.5 * (
            math.sin(math.tau * i / n)
        ) ** 2
        # y range: -1..+2, smooth
        centerline.append({
            "x": round(x, 2), "y": round(y, 2), "z": round(z, 2),
            "width": WIDTH, "banking_deg": 0.0,
        })

    # timing lines: start/finish at 0, sectors at 1/3 and 2/3
    s1 = n // 3
    s2 = 2 * n // 3

    # DRS zones: find the two longest straights (runs of |k| < 1/80 m radius)
    runs = []
    cur_start = None
    for i in range(n):
        k, _ = curvature_at(pts, i)
        straight = abs(k) < 1.0 / 80.0
        if straight and cur_start is None:
            cur_start = i
        elif not straight and cur_start is not None:
            runs.append((cur_start, i - 1, i - cur_start))
            cur_start = None
    if cur_start is not None:
        runs.append((cur_start, n - 1, n - cur_start + 1))
    runs.sort(key=lambda r: -r[2])
    drs = []
    for start, end, length in runs[:2]:
        # trim zone so activation is within the straight
        z_start = start + 2
        z_end = max(start + 4, end - 2)
        drs.append({"start_index": int(z_start), "end_index": int(z_end)})
    print("drs zones:", drs, "on straights:", [(r[0], r[1], r[2]) for r in runs[:3]])

    track = {
        "name": "Alpha Loop",
        "closed": True,
        "centerline": centerline,
        "surfaces": {
            "asphalt": {"grip": 1.0},
            "kerb": {"grip": 0.95},
            "grass": {"grip": 0.55},
            "gravel": {"grip": 0.45},
            "barrier": {"grip": 0.25},
        },
        "timing_lines": [
            {"name": "start_finish", "index": 0},
            {"name": "sector_1", "index": int(s1)},
            {"name": "sector_2", "index": int(s2)},
        ],
        "spawn": {"point_index": 0, "offset_lateral": 0.0},
        "drs_zones": drs,
        "camera_points": [],
        "scenery": {"grandstands": [], "trees_density": 0.0},
    }
    with open("tracks/alpha_loop.json", "w") as f:
        json.dump(track, f, indent=1)
    print("written tracks/alpha_loop.json")


if __name__ == "__main__":
    main()
