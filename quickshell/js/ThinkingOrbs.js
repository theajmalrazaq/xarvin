// Port of Jakubantalik/thinking-orbs (MIT) for QtQuick / Quickshell 2D Canvas.
// Supports all 9 3D halftone dot-orb states:
//   working (orbits), searching (globe), solving (rubik), listening (wave),
//   connecting (web), weaving (braid), composing (ribbon), breathing (ring), shaping (morph).

function lerp(a, b, f) {
    return a + (b - a) * f;
}

function frac(x) {
    return x - Math.floor(x);
}

function hashD(a, b) {
    var h = Math.sin(a * 12.9898 + b * 78.233) * 43758.5453;
    return h - Math.floor(h);
}

function vnoise(x, y) {
    var xi = Math.floor(x);
    var yi = Math.floor(y);
    var fx = x - xi;
    var fy = y - yi;
    fx = fx * fx * (3 - 2 * fx);
    fy = fy * fy * (3 - 2 * fy);
    var a = hashD(xi, yi);
    var b = hashD(xi + 1, yi);
    var c = hashD(xi, yi + 1);
    var d = hashD(xi + 1, yi + 1);
    return a + (b - a) * fx + (c - a) * fy + (a - b - c + d) * fx * fy;
}

function fibDir(i, n) {
    var golden = Math.PI * (3 - Math.sqrt(5));
    var y = 1 - (2 * (i + 0.5)) / n;
    var rad = Math.sqrt(Math.max(0, 1 - y * y));
    var a = i * golden;
    return [rad * Math.cos(a), y, rad * Math.sin(a)];
}

function angleDelta(a, b) {
    return Math.atan2(Math.sin(a - b), Math.cos(a - b));
}

function makeProj(yaw, tilt, cx, cy, scale) {
    var st = Math.sin(tilt);
    var ct = Math.cos(tilt);
    var sy = Math.sin(yaw);
    var cyw = Math.cos(yaw);
    return function (x, y, z) {
        var x1 = x * cyw + z * sy;
        var z1 = -x * sy + z * cyw;
        var y1 = y * ct - z1 * st;
        var z2 = y * st + z1 * ct;
        return [cx + x1 * scale, cy - y1 * scale, z2];
    };
}

function radiusScale(size, pow) {
    var effSize = size < 64 ? (26 + size * 0.58) : size;
    return Math.pow(effSize / 260, pow);
}

function finalizeFrame(dots, lines, rMin) {
    var floor = rMin !== undefined ? rMin : 0.3;
    var visible = [];
    for (var i = 0; i < dots.length; i++) {
        var d = dots[i];
        var a = d.a !== undefined ? d.a : 1;
        if (a < 0.02)
            continue;
        d.r = Math.max(floor, d.r);
        visible.push(d);
    }
    var visLines = [];
    for (var j = 0; j < lines.length; j++) {
        var l = lines[j];
        if ((l.a !== undefined ? l.a : 1) >= 0.02)
            visLines.push(l);
    }
    return { dots: visible, lines: visLines };
}

// ---- Profiles & Presets ----

var BASE_PROFILES = {
    globe:  { latRings: 17, lonDensity: 44, rBase: 0.6, rDepth: 1.7, rBoost: 1.0, inkFar: 0.62, inkSpan: 0.54, rsPow: 0.6, rMin: 0.3 },
    orbits: { orbitN: 12, ghostN: 40, ghostR: 0.9, ghostA: 0.5, particles: 3, partR: 1.2, partRDepth: 1.6, rsPow: 0.6, rMin: 0.3 },
    rubik:  { latRings: 15, lonDensity: 40, moveCount: 14, rBase: 0.6, rDepth: 1.7, rActive: 0.3, inkFar: 0.62, inkSpan: 0.54, rsPow: 0.6, rMin: 0.3 },
    wave:   { rings: 15, lonDensity: 40, rBase: 0.6, rDepth: 1.7, rsPow: 0.6, rMin: 0.3 },
    web:    { nodeN: 30, thr: 0.72, signals: 5, nodeR: 1.4, nodeRDepth: 1.8, lineW: 0.8, rsPow: 0.6, rMin: 0.3 },
    braid:  { strandN: 52, turns: 3.0, ghostN: 150, rBase: 1.2, rDepth: 1.8, rsPow: 0.6, rMin: 0.3 },
    ribbon: { lanes: 5, segs: 88, ghostN: 150, rBase: 1.1, rDepth: 1.7, rsPow: 0.6, rMin: 0.3 },
    ring:   { lanes: 5, segs: 88, ghostN: 0, faceOn: 1, rBase: 1.1, rDepth: 1.7, rsPow: 0.6, rMin: 0.3 },
    morph:  { rDot: 0.021, iconD: 1, rMin: 0.25 }
};

var STATE_TO_MODE = {
    working:    "orbits",
    searching:  "globe",
    solving:    "rubik",
    listening:  "wave",
    connecting: "web",
    weaving:    "braid",
    composing:  "ribbon",
    breathing:  "ring",
    shaping:    "morph"
};

var PRESETS_64 = {
    orbits: { speed: 1.885, count: 1,     size: 1 },
    globe:  { speed: 2.015, count: 0.42,  size: 1.15, extra: { scanMul: 4.08, dimBase: 0.45 } },
    rubik:  { speed: 1.82,  count: 0.35,  size: 1.05 },
    wave:   { speed: 4.388, count: 0.341, size: 1 },
    web:    { speed: 3.315, count: 1.35,  size: 0.95 },
    braid:  { speed: 1.625, count: 0.5,   size: 1 },
    ribbon: { speed: 2.34,  count: 0.45,  size: 0.9,  extra: { spin: 0.9, bandMul: 1.4, wobMul: 0.85 } },
    ring:   { speed: 3.24,  count: 0.28,  size: 0.956, extra: { spin: 0, bandMul: 2.2, wobMul: 0.368 } },
    morph:  { speed: 2.405, count: 0.702, size: 0.395, extra: { spread: 1.45 } }
};

var COUNT_PAIRS = [["latRings", "lonDensity"], ["rings", "lonDensity"], ["lanes", "segs"]];
var COUNT_KEYS = ["orbitN", "ghostN", "nodeN", "strandN", "signals"];
var RADIUS_KEYS = ["rBase", "rDepth", "rActive", "rDot", "ghostR", "partR", "partRDepth", "nodeR", "nodeRDepth"];

function scaleCounts(opts, scale) {
    var out = Object.assign({}, opts);
    var done = {};
    var rt = Math.sqrt(scale);
    for (var i = 0; i < COUNT_PAIRS.length; i++) {
        var a = COUNT_PAIRS[i][0];
        var b = COUNT_PAIRS[i][1];
        if (out[a] !== undefined && out[b] !== undefined && !done[a] && !done[b]) {
            out[a] = Math.max(2, Math.round(out[a] * rt));
            out[b] = Math.max(2, Math.round(out[b] * rt));
            done[a] = true;
            done[b] = true;
        }
    }
    for (var j = 0; j < COUNT_KEYS.length; j++) {
        var k = COUNT_KEYS[j];
        if (out[k] !== undefined && out[k] !== 0 && !done[k])
            out[k] = Math.max(1, Math.round(out[k] * scale));
    }
    if (out.iconD !== undefined)
        out.iconD = Math.max(0.02, out.iconD * scale);
    return out;
}

function scaleRadii(opts, scale) {
    var out = Object.assign({}, opts);
    for (var i = 0; i < RADIUS_KEYS.length; i++) {
        var k = RADIUS_KEYS[i];
        if (out[k] !== undefined)
            out[k] = out[k] * scale;
    }
    out.rSizeMul = (out.rSizeMul !== undefined ? out.rSizeMul : 1) * scale;
    return out;
}

var presetCache = {};

function resolvePreset(state, size) {
    var sz = size || 120;
    var bucket = Math.max(16, Math.round(sz / 8) * 8);
    var cacheKey = state + ":" + bucket;
    if (presetCache[cacheKey])
        return presetCache[cacheKey];
    var mode = STATE_TO_MODE[state] || "orbits";
    var preset = PRESETS_64[mode] || PRESETS_64.orbits;
    var opts = Object.assign({}, BASE_PROFILES[mode]);

    var countMul = preset.count;
    if (bucket < 64) {
        countMul = preset.count * Math.max(0.28, Math.pow(bucket / 64, 1.1));
    } else if (bucket > 64) {
        var f = Math.min(1, (bucket - 64) / 160);
        countMul = preset.count + (1.0 - preset.count) * f;
    }

    if (countMul !== 1)
        opts = scaleCounts(opts, countMul);
    if (preset.size !== 1)
        opts = scaleRadii(opts, preset.size);
    if (preset.extra)
        opts = Object.assign(opts, preset.extra);
    if (bucket < 40 && opts.bandMul !== undefined)
        opts.bandMul = opts.bandMul * 0.52;
    else if (bucket > 96 && opts.bandMul !== undefined) {
        var fb = Math.min(1, (bucket - 96) / 140);
        opts.bandMul = opts.bandMul * (1 - 0.35 * fb);
    }
    if (bucket < 40)
        opts.rMin = 0.42;

    var res = { mode: mode, speed: preset.speed, opts: opts };
    presetCache[cacheKey] = res;
    return res;
}

// ---- Geometry Builders ----

function frameOrbits(size, t, o) {
    var cx = size / 2;
    var cy = size / 2;
    var R = (size / 2) * 0.88;
    var pt = makeProj(t * 0.12, 0.3, cx, cy, 1);
    var rs = radiusScale(size, o.rsPow !== undefined ? o.rsPow : 0.6);

    var dots = [];
    var orbitN = o.orbitN !== undefined ? o.orbitN : 12;
    var ghostN = o.ghostN !== undefined ? o.ghostN : 40;
    var particles = o.particles !== undefined ? o.particles : 3;

    for (var orb = 0; orb < orbitN; orb++) {
        var h1 = hashD(orb, 1.7);
        var h2 = hashD(orb, 5.2);
        var h3 = hashD(orb, 8.9);
        var ro = R * (0.45 + 0.52 * h1);
        var th = h1 * 2 * Math.PI;
        var phi = Math.acos(2 * h2 - 1);
        var nx = Math.sin(phi) * Math.cos(th);
        var ny = Math.cos(phi);
        var nz = Math.sin(phi) * Math.sin(th);
        var ux = -ny;
        var uy = nx;
        var uz = 0;
        var ul = Math.max(1e-6, Math.sqrt(ux * ux + uy * uy));
        ux /= ul;
        uy /= ul;
        var vx = ny * uz - nz * uy;
        var vy = nz * ux - nx * uz;
        var vz = nx * uy - ny * ux;
        var speed = (0.25 + 0.55 * h3) * (h3 > 0.5 ? 1 : -1);

        for (var k = 0; k < ghostN; k++) {
            var a = (k / ghostN) * 2 * Math.PI;
            var p = pt(
                (ux * Math.cos(a) + vx * Math.sin(a)) * ro,
                (uy * Math.cos(a) + vy * Math.sin(a)) * ro,
                (uz * Math.cos(a) + vz * Math.sin(a)) * ro
            );
            var depth = (p[2] / ro + 1) / 2;
            dots.push({
                x: p[0], y: p[1], z: p[2],
                r: (o.ghostR !== undefined ? o.ghostR : 0.9) * rs,
                white: 0.72,
                a: (o.ghostA !== undefined ? o.ghostA : 0.5) * (0.4 + 0.6 * depth)
            });
        }
        for (var m = 0; m < particles; m++) {
            var a2 = t * speed + (m / particles) * 2 * Math.PI + h2 * 6;
            var p2 = pt(
                (ux * Math.cos(a2) + vx * Math.sin(a2)) * ro,
                (uy * Math.cos(a2) + vy * Math.sin(a2)) * ro,
                (uz * Math.cos(a2) + vz * Math.sin(a2)) * ro
            );
            var depth2 = (p2[2] / ro + 1) / 2;
            dots.push({
                x: p2[0], y: p2[1], z: p2[2],
                r: ((o.partR !== undefined ? o.partR : 1.2) + (o.partRDepth !== undefined ? o.partRDepth : 1.6) * depth2) * rs,
                white: 0.3 - 0.22 * depth2
            });
        }
    }
    return finalizeFrame(dots, [], o.rMin);
}

function frameGlobe(size, t, o) {
    var spin = 0.5;
    var cx = size / 2;
    var cy = size / 2;
    var radius = (size / 2) * 0.88;
    var tilt = 0.4 + 0.06 * Math.sin(t * 0.35);
    var pt = makeProj(t * spin, tilt, cx, cy, radius);
    var scan = t * (spin + (1.7 - spin) * (o.scanMul !== undefined ? o.scanMul : 1));
    var rs = radiusScale(size, o.rsPow !== undefined ? o.rsPow : 0.6);
    var dimBase = o.dimBase !== undefined ? o.dimBase : 1;

    var dots = [];
    var latRings = o.latRings !== undefined ? o.latRings : 17;
    var lonDensity = o.lonDensity !== undefined ? o.lonDensity : 44;
    for (var li = 0; li <= latRings; li++) {
        var lat = -Math.PI / 2 + (li / latRings) * Math.PI;
        var cosLat = Math.cos(lat);
        var sinLat = Math.sin(lat);
        var lonCount = Math.max(1, Math.round(Math.abs(cosLat) * lonDensity));
        for (var lj = 0; lj < lonCount; lj++) {
            var lon = (lj / lonCount) * 2 * Math.PI;
            var p = pt(cosLat * Math.cos(lon), sinLat, cosLat * Math.sin(lon));
            var depth = (p[2] + 1) / 2;
            var d = angleDelta(lon + t * spin, scan);
            var boost = Math.exp(-(d * d) / 0.18) * Math.max(0, p[2]);
            dots.push({
                x: p[0], y: p[1], z: p[2],
                r: ((o.rBase !== undefined ? o.rBase : 0.6) + (o.rDepth !== undefined ? o.rDepth : 1.7) * depth + (o.rBoost !== undefined ? o.rBoost : 1) * boost) * rs,
                white: (o.inkFar !== undefined ? o.inkFar : 0.62) - (o.inkSpan !== undefined ? o.inkSpan : 0.54) * depth,
                a: dimBase + (1 - dimBase) * Math.min(1, boost)
            });
        }
    }
    return finalizeFrame(dots, [], o.rMin);
}

function solveCycle(time, count, slotDur, rest) {
    var cyc = 2 * count * slotDur + rest;
    var tc = time % cyc;
    var amount = [];
    for (var k = 0; k < count; k++)
        amount.push(0);
    var active = -1;
    if (tc < 2 * count * slotDur) {
        var slot = Math.floor(tc / slotDur);
        var p = (tc - slot * slotDur) / slotDur;
        var cl = Math.min(1, p / 0.7);
        var ep = 1 - Math.pow(1 - cl, 3);
        if (slot < count) {
            for (var i = 0; i < slot; i++)
                amount[i] = 1;
            amount[slot] = ep;
            active = slot;
        } else {
            var u = 2 * count - 1 - slot;
            for (var j = 0; j < u; j++)
                amount[j] = 1;
            amount[u] = 1 - ep;
            active = u;
        }
    }
    return { amount: amount, active: active };
}

function makeMoves(count) {
    var moves = [];
    for (var i = 0; i < count; i++) {
        var axis = Math.min(2, Math.floor(hashD(i, 2.3) * 3));
        var lo = -1.0 + 0.5 * Math.min(3, Math.floor(hashD(i, 5.9) * 4));
        var dir = hashD(i, 7.7) < 0.5 ? 1 : -1;
        moves.push({ axis: axis, lo: lo, hi: lo + 0.5, ang: (dir * Math.PI) / 2 });
    }
    return moves;
}

function applyMoves(pt3, moves, sc) {
    var x = pt3[0], y = pt3[1], z = pt3[2];
    var inActive = false;
    for (var i = 0; i < moves.length; i++) {
        if (sc.amount[i] <= 0)
            continue;
        var mv = moves[i];
        var coord = mv.axis === 0 ? x : (mv.axis === 1 ? y : z);
        if (coord < mv.lo || coord >= mv.hi)
            continue;
        if (i === sc.active)
            inActive = true;
        var a = mv.ang * sc.amount[i];
        var ca = Math.cos(a);
        var sa = Math.sin(a);
        if (mv.axis === 0) {
            var y2 = y * ca - z * sa;
            z = y * sa + z * ca;
            y = y2;
        } else if (mv.axis === 1) {
            var x2 = x * ca + z * sa;
            z = -x * sa + z * ca;
            x = x2;
        } else {
            var x3 = x * ca - y * sa;
            y = x * sa + y * ca;
            x = x3;
        }
    }
    return [x, y, z, inActive];
}

function frameRubik(size, t, o) {
    var cx = size / 2;
    var cy = size / 2;
    var R = (size / 2) * 0.88;
    var pt = makeProj(t * 0.55, 0.35 + 0.1 * Math.sin(t * 0.9), cx, cy, R);
    var rs = radiusScale(size, o.rsPow !== undefined ? o.rsPow : 0.6);
    var moveCount = o.moveCount !== undefined ? o.moveCount : 14;
    var moves = makeMoves(moveCount);
    var sc = solveCycle(t, moveCount, 0.42, 1.2);

    var dots = [];
    var latRings = o.latRings !== undefined ? o.latRings : 15;
    var lonDensity = o.lonDensity !== undefined ? o.lonDensity : 40;
    for (var li = 0; li <= latRings; li++) {
        var lat = -Math.PI / 2 + (li / latRings) * Math.PI;
        var cosLat = Math.cos(lat);
        var sinLat = Math.sin(lat);
        var lonCount = Math.max(1, Math.round(Math.abs(cosLat) * lonDensity));
        for (var lj = 0; lj < lonCount; lj++) {
            var lon = (lj / lonCount) * 2 * Math.PI;
            var m = applyMoves([cosLat * Math.cos(lon), sinLat, cosLat * Math.sin(lon)], moves, sc);
            var p = pt(m[0], m[1], m[2]);
            var depth = (p[2] + 1) / 2;
            dots.push({
                x: p[0], y: p[1], z: p[2],
                r: ((o.rBase !== undefined ? o.rBase : 0.6) + (o.rDepth !== undefined ? o.rDepth : 1.7) * depth + (m[3] ? (o.rActive !== undefined ? o.rActive : 0.3) : 0)) * rs,
                white: (o.inkFar !== undefined ? o.inkFar : 0.62) - (o.inkSpan !== undefined ? o.inkSpan : 0.54) * depth - (m[3] ? 0.14 : 0)
            });
        }
    }
    return finalizeFrame(dots, [], o.rMin);
}

function frameWave(size, t, o, audioLevel) {
    var cx = size / 2;
    var cy = size / 2;
    var boostAmp = 1 + (audioLevel || 0) * 1.4;
    var R = (size / 2) * 0.874;
    var pt = makeProj(t * 0.18, 0.38, cx, cy, 1);
    var rs = radiusScale(size, o.rsPow !== undefined ? o.rsPow : 0.6);

    var dots = [];
    var rings = o.rings !== undefined ? o.rings : 15;
    var lonDensity = o.lonDensity !== undefined ? o.lonDensity : 40;
    for (var ri = 0; ri <= rings; ri++) {
        var lat = -Math.PI / 2 + (ri / rings) * Math.PI;
        var cosLat = Math.cos(lat);
        var sinLat = Math.sin(lat);
        var w = (0.62 * Math.sin(t * 2.1 - ri * 0.52) + 0.38 * Math.sin(t * 1.27 + ri * 0.83)) * boostAmp;
        var rr = R * (0.88 + 0.105 * w);
        var lonCount = Math.max(1, Math.round(Math.abs(cosLat) * lonDensity));
        for (var lj = 0; lj < lonCount; lj++) {
            var lon = (lj / lonCount) * 2 * Math.PI;
            var p = pt(cosLat * Math.cos(lon) * rr, sinLat * rr, cosLat * Math.sin(lon) * rr);
            var depth = (p[2] / R + 1) / 2;
            var crest = Math.max(0, w);
            dots.push({
                x: p[0], y: p[1], z: p[2],
                r: ((o.rBase !== undefined ? o.rBase : 0.6) + (o.rDepth !== undefined ? o.rDepth : 1.7) * depth) * (1 + 0.4 * crest) * rs,
                white: 0.66 - 0.56 * depth - 0.1 * crest
            });
        }
    }
    return finalizeFrame(dots, [], o.rMin);
}

function frameWeb(size, t, o) {
    var cx = size / 2;
    var cy = size / 2;
    var R = (size / 2) * 0.8 * (o.spread !== undefined ? o.spread : 1);
    var pt = makeProj(t * 0.12, 0.32, cx, cy, R);
    var rs = radiusScale(size, o.rsPow !== undefined ? o.rsPow : 0.6);

    var nodeN = o.nodeN !== undefined ? o.nodeN : 30;
    var thr = o.thr !== undefined ? o.thr : 0.72;
    var nodeR = o.nodeR !== undefined ? o.nodeR : 1.4;
    var nodeRDepth = o.nodeRDepth !== undefined ? o.nodeRDepth : 1.8;

    var nodes = [];
    for (var i = 0; i < nodeN; i++) {
        var d = fibDir(i, nodeN);
        var x = d[0] + 0.3 * (vnoise(i * 0.31 + 9, t * 0.24) - 0.5) * 2;
        var y = d[1] + 0.3 * (vnoise(i * 0.53 + 27, t * 0.21) - 0.5) * 2;
        var z = d[2] + 0.3 * (vnoise(i * 0.77 + 55, t * 0.27) - 0.5) * 2;
        var l = Math.sqrt(x * x + y * y + z * z);
        nodes.push([x / l, y / l, z / l]);
    }

    var lines = [];
    var dots = [];

    for (var i2 = 0; i2 < nodeN; i2++) {
        for (var j = i2 + 1; j < nodeN; j++) {
            var dx = nodes[i2][0] - nodes[j][0];
            var dy = nodes[i2][1] - nodes[j][1];
            var dz = nodes[i2][2] - nodes[j][2];
            var dist = Math.sqrt(dx * dx + dy * dy + dz * dz);
            if (dist >= thr)
                continue;
            var p1 = pt(nodes[i2][0], nodes[i2][1], nodes[i2][2]);
            var p2 = pt(nodes[j][0], nodes[j][1], nodes[j][2]);
            var depth = ((p1[2] + p2[2]) / 2 + 1) / 2;
            lines.push({
                x1: p1[0], y1: p1[1], x2: p2[0], y2: p2[1],
                white: 0.42,
                a: (1 - dist / thr) * (0.3 + 0.55 * depth),
                w: Math.max(0.6, (o.lineW !== undefined ? o.lineW : 0.8) * rs)
            });
        }
    }

    for (var k = 0; k < nodeN; k++) {
        var pk = pt(nodes[k][0], nodes[k][1], nodes[k][2]);
        var depthK = (pk[2] + 1) / 2;
        var pulse = 1 + 0.25 * Math.sin(t * 1.4 + k * 2.7);
        dots.push({
            x: pk[0], y: pk[1], z: pk[2],
            r: (nodeR + nodeRDepth * depthK) * pulse * rs,
            white: 0.55 - 0.45 * depthK
        });
    }

    var signals = o.signals !== undefined ? o.signals : 5;
    for (var s = 0; s < signals; s++) {
        var seg = Math.floor(t * 0.55 + s * 7.31);
        var aIdx = Math.floor(hashD(seg, s * 3.1 + 1.7) * nodeN);
        var bIdx = Math.floor(hashD(seg, s * 5.7 + 4.2) * nodeN);
        if (aIdx === bIdx)
            continue;
        var f = frac(t * 0.55 + s * 7.31);
        var sx = lerp(nodes[aIdx][0], nodes[bIdx][0], f);
        var sy = lerp(nodes[aIdx][1], nodes[bIdx][1], f);
        var sz = lerp(nodes[aIdx][2], nodes[bIdx][2], f);
        var sl = Math.max(1e-6, Math.sqrt(sx * sx + sy * sy + sz * sz));
        var ps = pt(sx / sl, sy / sl, sz / sl);
        var depthS = (ps[2] + 1) / 2;
        dots.push({
            x: ps[0], y: ps[1], z: ps[2],
            r: (nodeR * 1.5 + nodeRDepth * depthS) * rs,
            white: 0.05,
            a: 0.5 + 0.5 * depthS
        });
    }

    return finalizeFrame(dots, lines, o.rMin);
}

function frameBraid(size, t, o) {
    var cx = size / 2;
    var cy = size / 2;
    var R = (size / 2) * 0.86;
    var pt = makeProj(t * 0.4, 0.3, cx, cy, 1);
    var rs = radiusScale(size, o.rsPow !== undefined ? o.rsPow : 0.6);

    var dots = [];
    var ghostN = o.ghostN !== undefined ? o.ghostN : 150;
    for (var i = 0; i < ghostN; i++) {
        var d = fibDir(i, ghostN);
        var p = pt(d[0] * R, d[1] * R, d[2] * R);
        var depth = (p[2] / R + 1) / 2;
        dots.push({ x: p[0], y: p[1], z: p[2], r: 0.8 * rs, white: 0.78, a: 0.1 + 0.22 * depth });
    }

    var strandN = o.strandN !== undefined ? o.strandN : 52;
    var turns = o.turns !== undefined ? o.turns : 3;
    for (var s = 0; s < 3; s++) {
        var phase = (s / 3) * 2 * Math.PI;
        for (var j = 0; j < strandN; j++) {
            var u = (frac(j / strandN + t * 0.045) * 2 - 1) * 0.96;
            var surf = Math.sqrt(Math.max(0, 1 - u * u));
            var endFade = Math.min(1, (1 - Math.abs(u)) / 0.1);
            var a = u * Math.PI * turns + phase;
            var weave = 1 + 0.075 * Math.sin(u * Math.PI * turns * 2 + phase * 2 + t * 0.8);
            var rr = surf * R * weave;
            var p2 = pt(Math.cos(a) * rr, u * R * weave, Math.sin(a) * rr);
            var depth2 = (p2[2] / R + 1) / 2;
            dots.push({
                x: p2[0], y: p2[1], z: p2[2],
                r: ((o.rBase !== undefined ? o.rBase : 1.2) + (o.rDepth !== undefined ? o.rDepth : 1.8) * depth2) * rs,
                white: 0.55 - 0.45 * depth2,
                a: endFade * (0.45 + 0.55 * depth2)
            });
        }
    }
    return finalizeFrame(dots, [], o.rMin);
}

function frameRibbon(size, t, o, audioLevel) {
    var cx = size / 2;
    var cy = size / 2;
    var R = (size / 2) * 0.86;
    var spin = o.spin !== undefined ? o.spin : 1;
    var camTilt = 0.3;
    var pt = makeProj(t * 0.1 * spin, camTilt, cx, cy, 1);
    var rs = radiusScale(size, o.rsPow !== undefined ? o.rsPow : 0.6);

    var dots = [];
    var ghostN = o.ghostN !== undefined ? o.ghostN : 150;
    for (var i = 0; i < ghostN; i++) {
        var d = fibDir(i, ghostN);
        var p = pt(d[0] * R, d[1] * R, d[2] * R);
        var depth = (p[2] / R + 1) / 2;
        dots.push({ x: p[0], y: p[1], z: p[2], r: (0.75 + 0.65 * depth) * rs, white: 0.65 - 0.35 * depth, a: 0.32 + 0.48 * depth });
    }

    var ya = t * 0.24 * spin;
    var ta = o.faceOn ? -camTilt : -0.25 + 0.25 * Math.sin(t * 0.22) * spin;
    var ux = Math.cos(ya);
    var uy = 0;
    var uz = Math.sin(ya);
    var vx = -uz * Math.sin(ta);
    var vy = Math.cos(ta);
    var vz = ux * Math.sin(ta);
    var nx = uy * vz - uz * vy;
    var ny = uz * vx - ux * vz;
    var nz = ux * vy - uy * vx;

    var wobScale = (o.wobMul !== undefined ? o.wobMul : 1) * (1 + (audioLevel || 0) * 1.2);
    var wobAmp = 0.23 * wobScale;
    var baseR = o.faceOn ? R / (1 + 0.85 * wobAmp) : R;

    var baseLanes = o.lanes !== undefined ? o.lanes : 5;
    var segs = o.segs !== undefined ? o.segs : 88;
    var lanes = Math.max(1, Math.round(baseLanes * (o.bandMul !== undefined ? o.bandMul : 1)));
    for (var w = 0; w < lanes; w++) {
        var laneOff = (w - (lanes - 1) / 2) * 0.075;
        var edge = Math.abs(w - (lanes - 1) / 2) / Math.max(1, (lanes - 1) / 2);
        for (var k = 0; k < segs; k++) {
            var a = (k / segs) * 2 * Math.PI;
            var wob = (0.16 * Math.sin(a * 3 - t * 1.7 + w * 0.22) + 0.07 * Math.sin(a * 5 + t * 1.1)) * wobScale;
            var radial = o.faceOn ? 1 + wob : 1;
            var off = o.faceOn ? laneOff : laneOff + wob;
            var x = ux * Math.cos(a) + vx * Math.sin(a) + nx * off;
            var y = uy * Math.cos(a) + vy * Math.sin(a) + ny * off;
            var z = uz * Math.cos(a) + vz * Math.sin(a) + nz * off;
            var l = Math.sqrt(x * x + y * y + z * z);
            var rr = baseR * radial;
            var p2 = pt((x / l) * rr, (y / l) * rr, (z / l) * rr);
            var depth2 = (p2[2] / R + 1) / 2;
            dots.push({
                x: p2[0], y: p2[1], z: p2[2],
                r: ((o.rBase !== undefined ? o.rBase : 1.1) + (o.rDepth !== undefined ? o.rDepth : 1.7) * depth2) * (1 - 0.25 * edge) * rs,
                white: 0.52 - 0.44 * depth2 + 0.18 * edge,
                a: 0.4 + 0.6 * depth2
            });
        }
    }
    return finalizeFrame(dots, [], o.rMin);
}

var MODE_FRAMES = {
    orbits: frameOrbits,
    globe:  frameGlobe,
    rubik:  frameRubik,
    wave:   frameWave,
    web:    frameWeb,
    braid:  frameBraid,
    ribbon: frameRibbon,
    ring:   frameRibbon
};

// Paint frame onto QtQuick Canvas 2D Context with batched depth buckets (8 draw calls instead of 400)
function drawOrb(ctx, size, state, tSec, dark, tintColor, audioLevel) {
    var resolved = resolvePreset(state, size);
    var fn = MODE_FRAMES[resolved.mode] || frameOrbits;
    var frame = fn(size, tSec * resolved.speed, resolved.opts, audioLevel);

    var tr = tintColor ? Math.round(tintColor.r * 255) : 255;
    var tg = tintColor ? Math.round(tintColor.g * 255) : 255;
    var tb = tintColor ? Math.round(tintColor.b * 255) : 255;
    var useTint = tintColor !== undefined && tintColor !== null;

    if (frame.lines.length > 0) {
        ctx.beginPath();
        var rL = useTint ? Math.round(tr * 0.6) : 150;
        var gL = useTint ? Math.round(tg * 0.6) : 150;
        var bL = useTint ? Math.round(tb * 0.6) : 150;
        ctx.strokeStyle = "rgba(" + rL + "," + gL + "," + bL + ",0.45)";
        ctx.lineWidth = frame.lines[0].w;
        for (var i = 0; i < frame.lines.length; i++) {
            var l = frame.lines[i];
            ctx.moveTo(l.x1, l.y1);
            ctx.lineTo(l.x2, l.y2);
        }
        ctx.stroke();
    }

    var BUCKETS = 8;
    var buckets = [[], [], [], [], [], [], [], []];
    var dots = frame.dots;
    for (var j = 0; j < dots.length; j++) {
        var d = dots[j];
        var da = d.a !== undefined ? d.a : 1;
        var dw = Math.min(1, Math.max(0, d.white));
        var shade = dark ? (1 - dw) : dw;
        var intensity = Math.min(1, Math.max(0, shade * (0.35 + 0.65 * da)));
        var bIdx = Math.min(BUCKETS - 1, Math.max(0, Math.floor(intensity * BUCKETS)));
        buckets[bIdx].push(d);
    }

    var TWO_PI = Math.PI * 2;
    for (var b = 0; b < BUCKETS; b++) {
        var list = buckets[b];
        if (list.length === 0)
            continue;
        var f = (b + 0.5) / BUCKETS;
        var alpha = (0.28 + 0.72 * f).toFixed(2);
        var shadeVal = 0.35 + 0.65 * f;
        if (useTint) {
            var rD = Math.round(tr * shadeVal);
            var gD = Math.round(tg * shadeVal);
            var bD = Math.round(tb * shadeVal);
            ctx.fillStyle = "rgba(" + rD + "," + gD + "," + bD + "," + alpha + ")";
        } else {
            var g1 = Math.round(shadeVal * 255);
            ctx.fillStyle = "rgba(" + g1 + "," + g1 + "," + g1 + "," + alpha + ")";
        }
        ctx.beginPath();
        for (var k = 0; k < list.length; k++) {
            var pt = list[k];
            ctx.moveTo(pt.x + pt.r, pt.y);
            ctx.arc(pt.x, pt.y, pt.r, 0, TWO_PI);
        }
        ctx.fill();
    }
}
