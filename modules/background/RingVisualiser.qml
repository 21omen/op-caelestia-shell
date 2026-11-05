pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes

Item {
    id: root

    property var values: []
    property color primaryColor: "white"
    property color secondaryColor: "white"
    property color tertiaryColor: "white"
    property int animationDuration: 200
    property real strokeWidth: 1.5

    property int layers: 6
    property int bumps: 48
    property int seed: 1
    property real radius: 0.27
    property real gain: 2
    property real contrast: 0.8

    readonly property bool settled: d.settled

    function advance(dt: real): void {
        d.advance(dt);
    }

    function mix(a: color, b: color, f: real): color {
        return Qt.rgba(a.r + (b.r - a.r) * f, a.g + (b.g - a.g) * f, a.b + (b.b - a.b) * f, a.a + (b.a - a.a) * f);
    }

    function layerColor(t: real): color {
        return t < 0.5 ? mix(primaryColor, secondaryColor, t * 2) : mix(secondaryColor, tertiaryColor, (t - 0.5) * 2);
    }

    onValuesChanged: d.settled = false
    onLayersChanged: d.maps = []
    onBumpsChanged: d.maps = []
    onSeedChanged: d.maps = []

    QtObject {
        id: d

        property var display: []
        property var maps: []
        property int mapsN: 0
        property var paths: []
        property real energy: 0
        property bool settled: true

        function rng(seed: int): var {
            let a = seed >>> 0;
            return function () {
                a = (a + 0x6D2B79F5) >>> 0;
                let t = a;
                t = Math.imul(t ^ (t >>> 15), t | 1);
                t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
                return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
            };
        }

        function buildMaps(n: int): void {
            const out = [];
            for (let k = 0; k < root.layers; k++) {
                const rand = rng(root.seed * 1000 + k + 1);
                const centres = [];
                for (let b = 0; b < root.bumps; b++)
                    centres.push(Math.floor(rand() * n));
                out.push({ centres: centres, offset: rand() * Math.PI * 2 });
            }
            mapsN = n;
            maps = out;
        }

        function advance(dt: real): void {
            const target = root.values ?? [];
            const n = target.length;
            if (n < 2 || root.bumps < 3)
                return;
            if (display.length !== n)
                display = new Array(n).fill(0);
            if (maps.length !== root.layers || mapsN !== n)
                buildMaps(n);

            const alpha = 1 - Math.exp(-(dt * 1000) / (root.animationDuration / 3));
            let moving = false;
            let sum = 0;
            for (let i = 0; i < n; i++) {
                const t = Math.max(0, Math.min(1, target[i]));
                const diff = t - display[i];
                if (Math.abs(diff) > 0.001) {
                    display[i] += diff * alpha;
                    moving = true;
                } else {
                    display[i] = t;
                }
                sum += display[i];
            }
            energy = sum / n;

            rebuild();
            settled = !moving && energy < 0.002;
        }

        function rebuild(): void {
            const n = display.length;
            const L = root.layers;
            const B = root.bumps;
            const size = Math.min(root.width, root.height);
            const cx = root.width / 2;
            const cy = root.height / 2;
            const outer = size * root.radius;
            const inner = outer * 0.3;
            const gap = L > 1 ? (outer - inner) / (L - 1) : 0;
            const amp = gap * root.gain;
            const half = 0;
            const steps = Math.max(B * 24, 180);
            const out = [];

            for (let k = 0; k < L; k++) {
                const m = maps[k];
                const p = [];
                for (let b = 0; b < B; b++) {
                    const c = m.centres[b];
                    let acc = 0;
                    let cnt = 0;
                    for (let i = c - half; i <= c + half; i++) {
                        if (i >= 0 && i < n) {
                            acc += display[i];
                            cnt++;
                        }
                    }
                    p.push(cnt > 0 ? acc / cnt : 0);
                }

                let pm = 0;
                for (let b = 0; b < B; b++)
                    pm += p[b];
                pm /= B;

                const base = outer - gap * k;
                const pts = [];
                for (let s = 0; s <= steps; s++) {
                    const u = (s % steps) / steps * B;
                    const b0 = Math.floor(u);
                    const f = u - b0;
                    const p0 = p[(b0 - 1 + B) % B];
                    const p1 = p[b0 % B];
                    const p2 = p[(b0 + 1) % B];
                    const p3 = p[(b0 + 2) % B];
                    const v = Math.max(0, 0.5 * (2 * p1 + (-p0 + p2) * f + (2 * p0 - 5 * p1 + 4 * p2 - p3) * f * f + (-p0 + 3 * p1 - 3 * p2 + p3) * f * f * f));

                    const a = (s % steps) / steps * Math.PI * 2 + m.offset;
                    const r = base + amp * ((v - pm) * root.contrast + pm * 0.3);
                    pts.push(Qt.point(cx + r * Math.cos(a), cy + r * Math.sin(a)));
                }
                out.push(pts);
            }
            paths = out;
        }
    }

    Repeater {
        model: root.layers

        Shape {
            id: layer

            required property int index
            readonly property real t: root.layers > 1 ? index / (root.layers - 1) : 0
            readonly property color col: root.layerColor(t)

            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            opacity: Math.min(1, d.energy * 6) * (1 - 0.5 * t)

            ShapePath {
                strokeColor: layer.col
                strokeWidth: root.strokeWidth
                fillColor: Qt.alpha(layer.col, 0.03)
                joinStyle: ShapePath.RoundJoin

                PathPolyline {
                    path: d.paths[layer.index] ?? []
                }
            }
        }
    }
}
