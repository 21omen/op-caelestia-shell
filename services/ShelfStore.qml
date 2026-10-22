pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property bool dragging: false
    property bool loaded: false
    property bool recheck: false
    property var dismissed: ({})

    readonly property string home: Quickshell.env("HOME")
    readonly property string store: home + "/.local/share/caelestia-shelf"
    readonly property string thumbDir: home + "/.cache/thumbnails"
    readonly property string ownThumbDir: home + "/.cache/caelestia-shelf"
    readonly property string screenshotDir: home + "/Bilder/Screenshots"
    readonly property string downloadDir: home + "/Downloads"
    readonly property int autoLimit: 50
    readonly property real startTime: Date.now()

    readonly property var tabs: [
        { key: "main", label: "Regal", icon: "inventory_2", empty: "Dateien, Bilder oder Links hierher ziehen" },
        { key: "screenshots", label: "Screenshots", icon: "screenshot_monitor", empty: "Neue Screenshots erscheinen hier automatisch" },
        { key: "downloads", label: "Downloads", icon: "download", empty: "Neue Downloads erscheinen hier automatisch" }
    ]

    // Prüft je Datei: existiert sie, ist sie ein Ordner, gibt es ein Vorschaubild.
    // Aufruf: sh -c SCRIPT sh THUMBDIR OWNTHUMBDIR pfad hash1 hash2 ...
    readonly property string checkScript: `TD=$1; OD=$2; shift 2
mkdir -p "$OD"
while [ $# -ge 3 ]; do
  f=$1; h1=$2; h2=$3; shift 3
  [ -e "$f" ] || continue
  t=f; [ -d "$f" ] && t=d
  th=-
  for s in xx-large x-large large normal; do
    for h in "$h1" "$h2"; do
      if [ "$th" = - ] && [ -f "$TD/$s/$h.png" ]; then th="$TD/$s/$h.png"; fi
    done
  done
  if [ "$th" = - ] && [ "$t" = f ]; then
    b="$OD/$h1"
    if [ ! -f "$b.png" ] || [ "$f" -nt "$b.png" ]; then
      case "$f" in
        *.pdf|*.PDF)
          command -v pdftoppm >/dev/null && pdftoppm -png -singlefile -scale-to 256 -f 1 -l 1 "$f" "$b" 2>/dev/null ;;
        *.mp4|*.MP4|*.mkv|*.MKV|*.webm|*.mov|*.MOV|*.avi)
          command -v ffmpegthumbnailer >/dev/null && ffmpegthumbnailer -i "$f" -o "$b.png" -s 256 2>/dev/null ;;
      esac
    fi
    [ -f "$b.png" ] && th="$b.png"
  fi
  printf '%s\\t%s\\t%s\\n' "$t" "$th" "$f"
done`

    function modelFor(key) {
        return key === "screenshots" ? shotsModel : key === "downloads" ? dlModel : mainModel;
    }

    function decode(s) {
        try { return decodeURIComponent(s); } catch (e) { return s; }
    }

    function toPath(url) {
        return decode(url.slice(7));
    }

    function isOwn(url) {
        return url.startsWith("file://") && toPath(url).startsWith(store + "/");
    }

    function host(url) {
        return url.replace(/^https?:\/\//, "").split("/")[0];
    }

    function isImageName(s) {
        return /\.(jpe?g|png|gif|webp|avif|bmp|svg)$/i.test(s.split("?")[0]);
    }

    function newEntry(kind, url, name, source) {
        const shown = kind === "file" && isOwn(url) ? name.replace(/^\d{13}-/, "") : name;
        return { kind: kind, url: url, name: shown, source: source ?? "", available: true, isDir: false, thumb: "", selected: false };
    }

    // --- Speichern / Laden -------------------------------------------------

    function serialize(m) {
        const items = [];
        for (let i = 0; i < m.count; i++) {
            const e = m.get(i);
            items.push({ kind: e.kind, url: e.url, name: e.name, source: e.source });
        }
        return items;
    }

    function save() {
        stateFile.setText(JSON.stringify({
            main: serialize(mainModel),
            screenshots: serialize(shotsModel),
            downloads: serialize(dlModel)
        }, null, 2));
    }

    function load(text) {
        if (loaded) return;
        loaded = true;
        Quickshell.execDetached(["find", store, "-mindepth", "1", "-type", "d", "-empty", "-delete"]);
        try {
            const data = JSON.parse(text);
            const parts = Array.isArray(data) ? { main: data } : data;
            for (const t of tabs)
                for (const e of (parts[t.key] ?? []))
                    modelFor(t.key).append(newEntry(e.kind, e.url, e.name, e.source));
            console.log("shelf: loaded", mainModel.count, shotsModel.count, dlModel.count, "entries");
        } catch (err) {
            console.log("shelf: could not parse state:", err);
        }
        checkFiles();
    }

    FileView {
        id: stateFile
        path: root.home + "/.local/state/caelestia/shelf.json"
        onLoaded: root.load(text())
        onLoadFailed: err => {
            root.loaded = true;
            console.log("shelf: no saved state yet");
        }
    }

    // --- Einträge ----------------------------------------------------------

    function addEntry(kind, url, name, source, key, atTop) {
        const m = modelFor(key ?? "main");
        for (let i = 0; i < m.count; i++) {
            const e = m.get(i);
            if (e.url === url || (source !== "" && e.source === source)) return;
        }
        const entry = newEntry(kind, url, name, source);
        if (atTop) m.insert(0, entry);
        else m.append(entry);
        if (atTop && m.count > autoLimit) m.remove(autoLimit, m.count - autoLimit);
        console.log("shelf: added", key ?? "main", kind, url);
        save();
        checkFiles();
    }

    // --- Entfernen ---------------------------------------------------------

    function removeOne(m, key, i) {
        const e = m.get(i);
        if (e.kind === "file" && isOwn(e.url)) {
            const p = toPath(e.url);
            const dir = p.substring(0, p.lastIndexOf("/"));
            Quickshell.execDetached(dir !== store ? ["rm", "-rf", "--", dir] : ["rm", "--", p]);
            console.log("shelf: deleted own download", dir !== store ? dir : p);
        }
        if (key !== "main") {
            const d = dismissed;
            d[e.url] = true;
            dismissed = d;
        }
        m.remove(i);
    }

    // Rechtsklick auf einen markierten Eintrag entfernt die ganze Auswahl
    function removeAt(key, i) {
        const m = modelFor(key);
        const targets = m.get(i).selected ? selectedIndices(key) : [i];
        for (let k = targets.length - 1; k >= 0; k--)
            removeOne(m, key, targets[k]);
        recount();
        save();
    }

    // --- Auswahl -----------------------------------------------------------

    property int selectionCount: 0

    function recount() {
        let n = 0;
        for (const m of [mainModel, shotsModel, dlModel])
            for (let i = 0; i < m.count; i++)
                if (m.get(i).selected) n++;
        selectionCount = n;
    }

    function selectedIndices(key) {
        const m = modelFor(key);
        const out = [];
        for (let i = 0; i < m.count; i++)
            if (m.get(i).selected) out.push(i);
        return out;
    }

    function toggleSelect(key, i) {
        const m = modelFor(key);
        m.setProperty(i, "selected", !m.get(i).selected);
        recount();
    }

    function clearSelection(key) {
        const m = modelFor(key);
        for (let i = 0; i < m.count; i++)
            if (m.get(i).selected) m.setProperty(i, "selected", false);
        recount();
    }

    function clearAllSelections() {
        for (const t of tabs)
            clearSelection(t.key);
    }

    // Markierter Eintrag: alle markierten (mit Datei) — sonst nur er selbst
    function dragUrls(key, i) {
        const m = modelFor(key);
        const e = m.get(i);
        const urls = [];
        if (e.selected)
            for (let j = 0; j < m.count; j++) {
                const x = m.get(j);
                if (x.selected && x.available) urls.push(x.url);
            }
        if (urls.length === 0) urls.push(e.url);
        return urls;
    }

    function mimeFor(key, i) {
        const urls = dragUrls(key, i);
        const mime = { "text/uri-list": urls.join("\r\n") + "\r\n" };
        if (urls.every(u => /^https?:/.test(u)))
            mime["text/plain"] = urls.join("\n");
        return mime;
    }

    function open(url) {
        Quickshell.execDetached(["xdg-open", url.startsWith("file://") ? toPath(url) : url]);
    }

    function reveal(url) {
        Quickshell.execDetached(["dolphin", "--select", toPath(url)]);
    }

    function linkTitle(drop, url) {
        if (drop.formats.includes("_NETSCAPE_URL")) {
            const lines = drop.getDataAsString("_NETSCAPE_URL").split("\n");
            if (lines.length > 1 && lines[1].trim() !== "") return lines[1].trim();
        }
        return host(url);
    }

    function download(url) {
        for (let i = 0; i < mainModel.count; i++)
            if (mainModel.get(i).source === url) {
                console.log("shelf: already on shelf", url);
                return;
            }
        const base = decode(url.split("?")[0].split("#")[0].split("/").pop()) || "bild";
        const dest = store + "/" + Date.now() + "/" + base;
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
                if (isImage || isImageName(s))
                    download(s);
                else
                    addEntry("link", s, linkTitle(drop, s), "");
            } else {
                console.log("shelf: ignored", s);
            }
        }
        drop.accept(Qt.CopyAction);
    }

    // --- Automatische Reiter -----------------------------------------------
    // FolderListModel meldet eine Umbenennung bei gleicher Dateianzahl nur als
    // dataChanged, nicht als rowsInserted (FluxDown: .fdownloading -> fertige Datei).
    // Deshalb wird bei jeder Änderung die ganze Liste gegen die bekannten Namen
    // abgeglichen. Beim ersten Einlesen werden nur die vorhandenen Namen gemerkt.

    function prime(watcher) {
        const k = {};
        for (let i = 0; i < watcher.count; i++)
            k[watcher.get(i, "fileName")] = true;
        watcher.known = k;
        watcher.primed = true;
    }

    function scan(watcher, key) {
        if (!watcher.primed) return;
        const present = {};
        for (let i = 0; i < watcher.count; i++) {
            const name = watcher.get(i, "fileName");
            present[name] = true;
            if (watcher.known[name]) continue;
            if (name.startsWith(".") || /\.(part|crdownload|tmp|download|fdownloading)$/i.test(name)) {
                console.log("shelf: skipped temp file", name);
                continue;
            }
            const url = watcher.get(i, "fileUrl").toString();
            if (dismissed[url]) continue;
            addEntry("file", url, name, "", key, true);
        }
        watcher.known = present;
    }

    component Watcher: FolderListModel {
        property var known: ({})
        property bool primed: false

        showDirs: false
    }

    Watcher {
        id: shotWatcher
        folder: "file://" + root.screenshotDir
        onStatusChanged: if (shotWatcher.status === FolderListModel.Ready && !shotWatcher.primed) root.prime(shotWatcher)
        onCountChanged: root.scan(shotWatcher, "screenshots")
        onDataChanged: root.scan(shotWatcher, "screenshots")
        onModelReset: root.scan(shotWatcher, "screenshots")
    }

    Watcher {
        id: dlWatcher
        folder: "file://" + root.downloadDir
        onStatusChanged: if (dlWatcher.status === FolderListModel.Ready && !dlWatcher.primed) root.prime(dlWatcher)
        onCountChanged: root.scan(dlWatcher, "downloads")
        onDataChanged: root.scan(dlWatcher, "downloads")
        onModelReset: root.scan(dlWatcher, "downloads")
    }

    // --- Existenz- und Vorschauprüfung -------------------------------------

    function checkFiles() {
        if (checker.running) {
            recheck = true;
            return;
        }
        const args = [];
        for (const m of [mainModel, shotsModel, dlModel])
            for (let i = 0; i < m.count; i++) {
                const e = m.get(i);
                if (e.kind !== "file") continue;
                const p = toPath(e.url);
                args.push(p, Qt.md5("file://" + encodeURI(p)), Qt.md5("file://" + p));
            }
        if (args.length === 0) return;
        checker.command = ["sh", "-c", checkScript, "sh", thumbDir, ownThumbDir].concat(args);
        checker.running = true;
    }

    function applyResults(text) {
        const info = {};
        for (const line of text.split("\n")) {
            const parts = line.split("\t");
            if (parts.length < 3) continue;
            info[parts.slice(2).join("\t")] = { dir: parts[0] === "d", thumb: parts[1] === "-" ? "" : "file://" + parts[1] };
        }
        for (const m of [mainModel, shotsModel, dlModel])
            for (let i = 0; i < m.count; i++) {
                const e = m.get(i);
                if (e.kind !== "file") continue;
                const x = info[toPath(e.url)];
                m.setProperty(i, "available", x !== undefined);
                if (x) {
                    m.setProperty(i, "isDir", x.dir);
                    m.setProperty(i, "thumb", x.thumb);
                }
            }
    }

    // Auto-Reiter spiegeln Ordner: Einträge ohne Datei fliegen raus statt ausgegraut zu bleiben.
    function pruneAuto() {
        let removed = false;
        for (const m of [shotsModel, dlModel])
            for (let i = m.count - 1; i >= 0; i--)
                if (!m.get(i).available) {
                    m.remove(i);
                    removed = true;
                }
        if (removed) save();
    }

    Process {
        id: checker
        stdout: StdioCollector {
            onStreamFinished: {
                root.applyResults(text);
                root.pruneAuto();
            }
        }
        onExited: {
            if (root.recheck) {
                root.recheck = false;
                root.checkFiles();
            }
        }
    }

    ListModel { id: mainModel }
    ListModel { id: shotsModel }
    ListModel { id: dlModel }

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
