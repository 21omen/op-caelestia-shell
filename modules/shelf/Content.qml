pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Config
import qs.components
import qs.services

Item {
    id: root

    implicitWidth: 320
    implicitHeight: Math.min(Math.max(list.contentHeight, 48) + Tokens.padding.large * 2, 560)

    StyledText {
        anchors.centerIn: parent
        visible: ShelfStore.entries.count === 0
        text: "Dateien hierher ziehen"
        color: Colours.palette.m3onSurfaceVariant
    }

    ListView {
        id: list

        anchors.fill: parent
        anchors.margins: Tokens.padding.large
        spacing: Tokens.spacing.small
        clip: true
        interactive: contentHeight > height
        model: ShelfStore.entries

        delegate: StyledRect {
            id: chip

            required property string kind
            required property string url
            required property string name
            required property bool available
            required property int index

            width: ListView.view.width
            implicitHeight: 40
            radius: Tokens.rounding.medium
            opacity: chip.available ? 1 : 0.45
            color: chipMouse.containsMouse ? Colours.tPalette.m3surfaceContainerHigh : Colours.tPalette.m3surfaceContainer

            Drag.dragType: Drag.Automatic
            Drag.supportedActions: Qt.CopyAction | Qt.MoveAction
            Drag.mimeData: chip.kind === "link"
                ? ({ "text/uri-list": chip.url + "\r\n", "text/plain": chip.url })
                : ({ "text/uri-list": chip.url + "\r\n" })
            Drag.onDragFinished: dropAction => {
                chip.Drag.active = false;
                ShelfStore.dragging = false;
            }

            MaterialIcon {
                id: icon

                anchors.left: parent.left
                anchors.leftMargin: Tokens.padding.large
                anchors.verticalCenter: parent.verticalCenter
                text: !chip.available ? "error" : chip.kind === "link" ? "link" : "description"
                color: !chip.available ? Colours.palette.m3error
                     : chip.kind === "link" ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
            }

            StyledText {
                anchors.left: icon.right
                anchors.leftMargin: Tokens.spacing.small
                anchors.right: parent.right
                anchors.rightMargin: Tokens.padding.large
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideMiddle
                font.strikeout: !chip.available
                color: Colours.palette.m3onSurface
                text: chip.name
            }

            MouseArea {
                id: chipMouse

                property point pressPos

                anchors.fill: parent
                hoverEnabled: true
                preventStealing: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onPressed: mouse => pressPos = Qt.point(mouse.x, mouse.y)
                onClicked: mouse => {
                    if (mouse.button === Qt.RightButton) ShelfStore.removeAt(chip.index);
                    else if (chip.available) Qt.openUrlExternally(chip.url);
                }
                onPositionChanged: mouse => {
                    if (!chip.available || !(pressedButtons & Qt.LeftButton) || chip.Drag.active) return;
                    if (Math.hypot(mouse.x - pressPos.x, mouse.y - pressPos.y) < 10) return;
                    ShelfStore.dragging = true;
                    chip.Drag.active = true;
                }
            }
        }
    }
}
