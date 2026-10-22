pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Config
import qs.components
import qs.services

StyledRect {
    id: chip

    required property string kind
    required property string url
    required property string name
    required property string source
    required property bool available
    required property bool isDir
    required property string thumb
    required property bool selected
    required property int index

    property string shelfKey: "main"

    readonly property string previewSource: {
        if (!available) return "";
        if (thumb !== "") return thumb;
        if (kind === "file" && !isDir && ShelfStore.isImageName(url)) return url;
        return "";
    }

    readonly property string iconName: {
        if (!available) return "error";
        if (kind === "link") return "link";
        if (isDir) return "folder";
        const n = name.toLowerCase();
        if (/\.pdf$/.test(n)) return "picture_as_pdf";
        if (/\.(mp4|mkv|webm|mov|avi)$/.test(n)) return "movie";
        if (/\.(mp3|flac|ogg|opus|wav|m4a)$/.test(n)) return "music_note";
        if (/\.(zip|tar|gz|xz|zst|7z|rar)$/.test(n)) return "folder_zip";
        if (ShelfStore.isImageName(n)) return "image";
        return "description";
    }

    readonly property string subtitle: {
        if (kind === "link") return ShelfStore.host(url);
        if (ShelfStore.isOwn(url)) return "Download · " + ShelfStore.host(source);
        const p = ShelfStore.toPath(url);
        const dir = p.substring(0, p.lastIndexOf("/"));
        return dir.startsWith(ShelfStore.home) ? "~" + dir.slice(ShelfStore.home.length) : dir;
    }

    width: ListView.view.width
    implicitHeight: 64
    radius: Tokens.rounding.medium
    opacity: chip.available ? 1 : 0.45
    color: chip.selected ? Colours.palette.m3secondaryContainer : Colours.tPalette.m3surfaceContainer

    Drag.dragType: Drag.Automatic
    Drag.supportedActions: Qt.CopyAction | Qt.MoveAction
    Drag.onDragFinished: dropAction => {
        chip.Drag.active = false;
        ShelfStore.dragging = false;
        ShelfStore.clearSelection(chip.shelfKey);
    }

    // Wird der Eintrag während eines eigenen Drags zerstört (Reiterwechsel, Entfernen),
    // kommt kein dragFinished mehr — ohne diese Zeile bliebe das Regal offen.
    Component.onDestruction: if (chip.Drag.active) ShelfStore.dragging = false

    // Hover-Hervorhebung wie Caelestias StateLayer: leichte Aufhellung in der Textfarbe
    StyledRect {
        anchors.fill: parent
        radius: chip.radius
        color: Colours.palette.m3onSurface
        opacity: chipHover.hovered && !chip.selected ? 0.1 : 0

        Behavior on opacity {
            Anim {}
        }
    }

    StyledRect {
        id: preview

        anchors.left: parent.left
        anchors.leftMargin: Tokens.padding.small
        anchors.verticalCenter: parent.verticalCenter
        width: 48
        height: 48
        radius: Tokens.rounding.small
        color: Colours.tPalette.m3surfaceContainerHigh
        clip: true

        Image {
            id: img

            anchors.fill: parent
            asynchronous: true
            fillMode: Image.PreserveAspectCrop
            sourceSize.width: 96
            sourceSize.height: 96
            source: chip.previewSource
            visible: status === Image.Ready
        }

        MaterialIcon {
            anchors.centerIn: parent
            visible: img.status !== Image.Ready
            text: chip.iconName
            fontStyle: Tokens.font.icon.large
            color: !chip.available ? Colours.palette.m3error
                 : chip.kind === "link" ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
        }
    }

    Column {
        anchors.left: preview.right
        anchors.leftMargin: Tokens.spacing.medium
        anchors.right: selectBox.left
        anchors.rightMargin: Tokens.spacing.small
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2

        StyledText {
            id: title

            width: parent.width
            elide: Text.ElideMiddle
            font.strikeout: !chip.available
            color: Colours.palette.m3onSurface
            text: chip.name
        }

        StyledText {
            width: parent.width
            elide: Text.ElideRight
            font.pointSize: title.font.pointSize * 0.85
            color: Colours.palette.m3onSurfaceVariant
            text: chip.subtitle
        }
    }

    MouseArea {
        id: chipMouse

        property point pressPos

        anchors.fill: parent
        hoverEnabled: true
        preventStealing: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onPressed: mouse => pressPos = Qt.point(mouse.x, mouse.y)
        onClicked: mouse => {
            if (mouse.button === Qt.RightButton) {
                ShelfStore.removeAt(chip.shelfKey, chip.index);
            } else if (!chip.available) {
                return;
            } else if (chip.kind === "file" && (mouse.button === Qt.MiddleButton || chip.shelfKey === "downloads")) {
                ShelfStore.reveal(chip.url);
            } else if (mouse.button === Qt.LeftButton) {
                ShelfStore.open(chip.url);
            }
        }
        onPositionChanged: mouse => {
            if (!chip.available || !(pressedButtons & Qt.LeftButton) || chip.Drag.active) return;
            if (Math.hypot(mouse.x - pressPos.x, mouse.y - pressPos.y) < 10) return;
            chip.Drag.mimeData = ShelfStore.mimeFor(chip.shelfKey, chip.index);
            ShelfStore.dragging = true;
            chip.Drag.active = true;
        }
    }

    // Auswahl-Symbol: bei Hover sichtbar, bei aktiver Auswahl an allen Einträgen
    MaterialIcon {
        id: selectBox

        anchors.right: parent.right
        anchors.rightMargin: Tokens.padding.large
        anchors.verticalCenter: parent.verticalCenter
        text: chip.selected ? "check_circle" : "radio_button_unchecked"
        color: chip.selected ? Colours.palette.m3primary : Colours.palette.m3outline
        opacity: chip.selected || chipHover.hovered || ShelfStore.selectionCount > 0 ? 1 : 0
    }

    // Klickfläche für die Auswahl: der ganze rechte Streifen des Eintrags,
    // damit ein knapp danebengehender Klick nicht die Datei öffnet
    MouseArea {
        id: selectMouse

        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: 52
        onClicked: ShelfStore.toggleSelect(chip.shelfKey, chip.index)
    }

    // MouseArea-Hover kommt im Drawer-Fenster nicht an, HoverHandler schon
    HoverHandler {
        id: chipHover
    }
}
