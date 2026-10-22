pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Config
import qs.components
import qs.services

Item {
    id: root

    property bool hovered
    property bool dragOver

    readonly property bool shouldBeActive: hovered || dragOver || ShelfStore.dragging
    property real offsetScale: shouldBeActive ? 0 : 1

    onShouldBeActiveChanged: if (shouldBeActive) ShelfStore.checkFiles()

    visible: offsetScale < 1
    anchors.rightMargin: (-implicitWidth - 5) * offsetScale
    implicitWidth: content.implicitWidth
    implicitHeight: content.implicitHeight
    opacity: 1 - offsetScale

    Behavior on offsetScale {
        Anim {}
    }

    Content {
        id: content

        dragOver: root.dragOver
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
    }
}
