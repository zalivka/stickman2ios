"""Hand model: turns shape key points into BonePaper session ops the way a finger on the editor would.

Units are sheet pixels (y down). Numbers are fitted to the first real recording (iPhone SE, 60 Hz):
brush 14, 500–900 px/s mean, sample spacing ~13 px (max ~25), loops overshooting or missing their start by 10–35 px.
"""
import math
import random

HZ = 60
SLOP = 12.0
# Share of minimum-jerk in the speed profile; the rest is constant speed. Real strokes peak ~1.4x their mean.
EASE = 0.4


class Hand:
    def __init__(self, seed: int, origin=(0, 0)):
        self.rng = random.Random(seed)
        self.origin = origin
        self.t = 0.5
        self.ops = []
        self.size = 14
        self.opacity = 1.0

    # --- shapes -> dense paths -------------------------------------------------

    def curve(self, keys, closed=False):
        """Catmull-Rom through keys, ~2 px steps."""
        pts = list(keys)
        if closed:
            ext = [pts[-1]] + pts + [pts[0], pts[1]]
        else:
            ext = [pts[0]] + pts + [pts[-1]]
        out = []
        for i in range(1, len(ext) - 2):
            p0, p1, p2, p3 = ext[i - 1], ext[i], ext[i + 1], ext[i + 2]
            n = max(2, int(math.dist(p1, p2) / 2))
            for k in range(n):
                u = k / n
                out.append(tuple(
                    0.5 * ((2 * p1[j]) + (-p0[j] + p2[j]) * u
                           + (2 * p0[j] - 5 * p1[j] + 4 * p2[j] - p3[j]) * u * u
                           + (-p0[j] + 3 * p1[j] - 3 * p2[j] + p3[j]) * u ** 3)
                    for j in range(2)))
        out.append(pts[0] if closed else pts[-1])
        return [out]

    def poly(self, keys, closed=False):
        """Straight segments; each corner is a separate motion (the finger slows and turns)."""
        pts = list(keys) + ([keys[0]] if closed else [])
        pieces = []
        for a, b in zip(pts, pts[1:]):
            n = max(2, int(math.dist(a, b) / 2))
            pieces.append([(a[0] + (b[0] - a[0]) * k / n, a[1] + (b[1] - a[1]) * k / n) for k in range(n + 1)])
        return pieces

    # --- motion ---------------------------------------------------------------

    def _close(self, pieces, closed):
        """Loops: run on past the start (so a fill holds) by 4–14% of the perimeter."""
        if not closed:
            return pieces
        flat = [p for piece in pieces for p in piece]
        per = self._length(flat)
        want = per * self.rng.uniform(0.04, 0.14)
        extra, acc = [], 0.0
        for a, b in zip(flat, flat[1:]):
            if acc > want:
                break
            extra.append(b)
            acc += math.dist(a, b)
        return pieces + [[pieces[-1][-1]] + extra]

    def _wobble(self, pieces, scale):
        """Low-frequency sideways drift along arc length."""
        waves = [(self.rng.uniform(0.3, 0.7) * scale, self.rng.uniform(60, 240), self.rng.uniform(0, 6.3))
                 for _ in range(3)]
        out, s = [], 0.0
        prev = pieces[0][0]
        for piece in pieces:
            q = []
            for i, p in enumerate(piece):
                s += math.dist(prev, p)
                prev = p
                a = piece[max(i - 1, 0)]
                b = piece[min(i + 1, len(piece) - 1)]
                tx, ty = b[0] - a[0], b[1] - a[1]
                n = math.hypot(tx, ty) or 1.0
                off = sum(amp * math.sin(2 * math.pi * s / lam + ph) for amp, lam, ph in waves)
                q.append((p[0] - ty / n * off, p[1] + tx / n * off))
            out.append(q)
        return out

    @staticmethod
    def _length(pts):
        return sum(math.dist(a, b) for a, b in zip(pts, pts[1:]))

    def _sample(self, pieces):
        """Minimum-jerk speed per piece, sampled at 60 Hz. Returns [(x, y, t)]."""
        speed = self.rng.uniform(500, 900)
        samples = []
        t = self.t
        for piece in pieces:
            length = self._length(piece)
            if length < 0.5:
                continue
            dur = max(length / speed, 0.08)
            cum = [0.0]
            for a, b in zip(piece, piece[1:]):
                cum.append(cum[-1] + math.dist(a, b))
            frames = max(1, round(dur * HZ))
            for f in range(1 if samples else 0, frames + 1):
                tau = f / frames
                target = length * ((1 - EASE) * tau + EASE * (10 * tau ** 3 - 15 * tau ** 4 + 6 * tau ** 5))
                j = next((k for k in range(1, len(cum)) if cum[k] >= target), len(cum) - 1)
                a, b = piece[j - 1], piece[j]
                seg = cum[j] - cum[j - 1] or 1.0
                u = (target - cum[j - 1]) / seg
                x = a[0] + (b[0] - a[0]) * u + self.rng.gauss(0, 0.25)
                y = a[1] + (b[1] - a[1]) * u + self.rng.gauss(0, 0.25)
                samples.append((x, y, t + f / HZ))
            t += frames / HZ
        return samples

    # --- ops ------------------------------------------------------------------

    def _world(self, x, y):
        return [round(x + self.origin[0], 2), round(y + self.origin[1], 2)]

    def stroke(self, pieces, color, closed=False, jitter=1.0, size=None):
        size = size or self.size
        flat = [p for piece in pieces for p in piece]
        xs, ys = [p[0] for p in flat], [p[1] for p in flat]
        extent = max(max(xs) - min(xs), max(ys) - min(ys), 1)
        pieces = self._close(pieces, closed)
        pieces = self._wobble(pieces, jitter * min(4.0, 1.2 + extent / 90))
        samples = self._sample(pieces)
        start = samples[0]
        taken = next((i for i, p in enumerate(samples) if math.dist(p[:2], start[:2]) >= SLOP), None)
        if taken is None:
            raise SystemExit(f"hand: stroke shorter than slop at {start[:2]}")
        points = [start] + samples[taken:]
        self.ops.append({
            "op": "stroke", "input": "finger", "erase": False, "color": color,
            "size": size, "opacity": self.opacity, "zoom": 0.715,
            "t": round(samples[taken][2], 4), "t1": round(samples[-1][2], 4), "end": "commit",
            "points": [self._world(x, y) + [round(t, 4)] for x, y, t in points],
            "raw": [self._world(x, y) + [round(t, 4)] for x, y, t in samples],
        })
        self.t = samples[-1][2] + self.rng.uniform(0.35, 1.8)

    def fill(self, at, color):
        x = at[0] + self.rng.uniform(-3, 3)
        y = at[1] + self.rng.uniform(-3, 3)
        self.ops.append({
            "op": "fill", "input": "finger", "color": color, "opacity": self.opacity, "zoom": 0.715,
            "at": self._world(x, y), "t": round(self.t, 4),
            "raw": [self._world(x, y) + [round(self.t, 4)], self._world(x, y) + [round(self.t + 0.07, 4)]],
        })
        self.t += self.rng.uniform(0.4, 1.2)
