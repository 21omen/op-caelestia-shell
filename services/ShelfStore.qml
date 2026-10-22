pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property bool dragging: false
    property bool loaded: false
    property bool recheck: false
    readonly property string home: Quickshell.env("HOME")
    readonly property string store: home + "/.local/share/caelestia-shelf"
    readonly property string thumbDir: home + "/.cache/thumbnails"
    readonly property string ownThumbDir: home + "/.cache/caelestia-shelf"
    readonly property alias entries: shelf

    // Prüft je Datei: existiert sie, ist sie ein Ordner, gibt es ein Vorschaubild im Cache.
    // Aufruf: sh -c SCRIPT sh THUMBDIR pfad hash1 hash2 pfad hash1 hash2 ...
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
        return { kind: kind, url: url, name: shown, source: source ?? "", available: true, isDir: false, thumb: "" };
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
        Quickshell.execDetached(["find", store, "-mindepth", "1", "-type", "d", "-empty", "-delete"]);
        try {
            for (const e of JSON.parse(text))
                shelf.append(newEntry(e.kind, e.url, e.name, e.source));
            console.log("shelf: loaded", shelf.count, "entries");
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

    function addEntry(kind, url, name, source) {
        for (let i = 0; i < shelf.count; i++) {
            const e = shelf.get(i);
            if (e.url === url || (source !== "" && e.source === source)) return;
        }
        shelf.append(newEntry(kind, url, name, source));
        console.log("shelf: added", kind, url);
        save();
        checkFiles();
    }

    function removeAt(i) {
        const e = shelf.get(i);
        if (e.kind === "file" && isOwn(e.url)) {
            const p = toPath(e.url);
            const dir = p.substring(0, p.lastIndexOf("/"));
            Quickshell.execDetached(dir !== store ? ["rm", "-rf", "--", dir] : ["rm", "--", p]);
            console.log("shelf: deleted own download", dir !== store ? dir : p);
        }
        shelf.remove(i);
        save();
    }

    function linkTitle(drop, url) {
        if (drop.formats.includes("_NETSCAPE_URL")) {
            const lines = drop.getDataAsString("_NETSCAPE_URL").split("\n");
            if (lines.length > 1 && lines[1].trim() !== "") return lines[1].trim();
        }
        return host(url);
    }

    function download(url) {
        for (let i = 0; i < shelf.count; i++)
            if (shelf.get(i).source === url) {
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

    // --- Existenz- und Vorschauprüfung -------------------------------------

    function checkFiles() {
        if (checker.running) {
            recheck = true;
            return;
        }
        const args = [];
        for (let i = 0; i < shelf.count; i++) {
            const e = shelf.get(i);
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
        for (let i = 0; i < shelf.count; i++) {
            const e = shelf.get(i);
            if (e.kind !== "file") continue;
            const x = info[toPath(e.url)];
            shelf.setProperty(i, "available", x !== undefined);
            if (x) {
                shelf.setProperty(i, "isDir", x.dir);
                shelf.setProperty(i, "thumb", x.thumb);
            }
        }
    }

    Process {
        id: checker
        stdout: StdioCollector {
            onStreamFinished: root.applyResults(text)
        }
        onExited: {
            if (root.recheck) {
                root.recheck = false;
                root.checkFiles();
            }
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
