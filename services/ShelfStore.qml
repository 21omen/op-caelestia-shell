pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property bool dragging: false
    property bool loaded: false
    readonly property string store: Quickshell.env("HOME") + "/.local/share/caelestia-shelf"
    readonly property alias entries: shelf

    function decode(s) {
        try { return decodeURIComponent(s); } catch (e) { return s; }
    }

    function toPath(url) {
        return decode(url.slice(7));
    }

    // --- Speichern / Laden -------------------------------------------------

    function save() {
        const items = [];
        for (let i = 0; i < shelf.count; i++) {
            const e = shelf.get(i);
            items.push({ kind: e.kind, url: e.url, name: e.name, source: e.source });
        }
        stateFile.setText(JSON.stringify(items, null, 2));
    }

    function load(text) {
        if (loaded) return;
        loaded = true;
        try {
            for (const e of JSON.parse(text))
                shelf.append({ kind: e.kind, url: e.url, name: e.name, source: e.source ?? "", available: true });
            console.log("shelf: loaded", shelf.count, "entries");
        } catch (err) {
            console.log("shelf: could not parse state:", err);
        }
        checkFiles();
    }

    FileView {
        id: stateFile
        path: Quickshell.env("HOME") + "/.local/state/caelestia/shelf.json"
        onLoaded: root.load(text())
        onLoadFailed: err => {
            root.loaded = true;
            console.log("shelf: no saved state yet");
        }
    }

    // --- Einträge ----------------------------------------------------------

    function addEntry(kind, url, name, source) {
        for (let i = 0; i < shelf.count; i++) {
            const e = shelf.get(i);
            if (e.url === url || (source !== "" && e.source === source)) return;
        }
        shelf.append({ kind: kind, url: url, name: name, source: source, available: true });
        console.log("shelf: added", kind, url);
        save();
    }

    function removeAt(i) {
        const e = shelf.get(i);
        const p = toPath(e.url);
        if (e.kind === "file" && p.startsWith(store + "/")) {
            Quickshell.execDetached(["rm", "--", p]);
            console.log("shelf: deleted own download", p);
        }
        shelf.remove(i);
        save();
    }

    function linkTitle(drop, url) {
        if (drop.formats.includes("_NETSCAPE_URL")) {
            const lines = drop.getDataAsString("_NETSCAPE_URL").split("\n");
            if (lines.length > 1 && lines[1].trim() !== "") return lines[1].trim();
        }
        return url.replace(/^https?:\/\//, "").split("/")[0];
    }

    function download(url) {
        for (let i = 0; i < shelf.count; i++)
            if (shelf.get(i).source === url) {
                console.log("shelf: already on shelf", url);
                return;
            }
        const base = decode(url.split("?")[0].split("#")[0].split("/").pop()) || "bild";
        const dest = store + "/" + Date.now() + "-" + base;
        const p = downloader.createObject(root, { dest: dest, base: base, source: url });
        p.command = ["curl", "-fsSL", "--create-dirs", "-o", dest, url];
        p.running = true;
        console.log("shelf: downloading", url);
    }

    function handleDrop(drop) {
        const isImage = drop.formats.includes("application/x-moz-nativeimage")
                     || drop.formats.includes("application/x-qt-image");
        for (const u of drop.urls) {
            const s = u.toString();
            if (s.startsWith("file://")) {
                addEntry("file", s, decode(s.split("/").pop()), "");
            } else if (/^https?:\/\//.test(s)) {
                if (isImage || /\.(jpe?g|png|gif|webp|avif|bmp|svg)$/i.test(s.split("?")[0]))
                    download(s);
                else
                    addEntry("link", s, linkTitle(drop, s), "");
            } else {
                console.log("shelf: ignored", s);
            }
        }
        drop.accept(Qt.CopyAction);
    }

    // --- Existenzprüfung ---------------------------------------------------

    function checkFiles() {
        if (checker.running) return;
        const paths = [];
        for (let i = 0; i < shelf.count; i++) {
            const e = shelf.get(i);
            if (e.kind === "file") paths.push(toPath(e.url));
        }
        if (paths.length === 0) return;
        checker.command = ["sh", "-c", 'for f do [ -e "$f" ] && printf "%s\\n" "$f"; done', "sh"].concat(paths);
        checker.running = true;
    }

    function applyExisting(text) {
        const ok = new Set(text.split("\n"));
        for (let i = 0; i < shelf.count; i++) {
            const e = shelf.get(i);
            if (e.kind === "file") shelf.setProperty(i, "available", ok.has(toPath(e.url)));
        }
    }

    Process {
        id: checker
        stdout: StdioCollector {
            onStreamFinished: root.applyExisting(text)
        }
    }

    ListModel { id: shelf }

    Component {
        id: downloader
        Process {
            property string dest
            property string base
            property string source
            onExited: (code, status) => {
                if (code === 0) root.addEntry("file", "file://" + dest, base, source);
                else console.log("shelf: download failed, curl exit", code);
                destroy();
            }
        }
    }
}
