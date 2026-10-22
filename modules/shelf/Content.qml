pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Config
import qs.components
import qs.services

Item {
    id: root

    property bool dragOver
    property string currentTab: "main"
    readonly property var currentModel: ShelfStore.modelFor(currentTab)
    readonly property var currentTabInfo: ShelfStore.tabs.find(t => t.key === currentTab) ?? ShelfStore.tabs[0]

    // Nur bei Drags von außen auf „Regal“ springen. Ein eigener Drag aus einem
    // anderen Reiter würde sonst durch den Listenwechsel seine Quelle zerstören.
    onDragOverChanged: if (dragOver && !ShelfStore.dragging) currentTab = "main"
    onCurrentTabChanged: ShelfStore.clearAllSelections()
    onDropHoverChanged: if (dropHover && !ShelfStore.dragging) currentTab = "main"

    readonly property bool hovered: panelHover.hovered
    readonly property bool dropHover: panelDrop.containsDrag

    HoverHandler {
        id: panelHover
    }

    DropArea {
        id: panelDrop

        anchors.fill: parent
        onDropped: drop => ShelfStore.handleDrop(drop)
    }

    implicitWidth: 360
    implicitHeight: Math.min(Math.max(tabBar.height + selBar.height + Tokens.spacing.small * 2 + list.contentHeight + Tokens.padding.large * 2, 320), 680)
    // Nur als Referenz für die Standard-Schriftgröße
    StyledText {
        id: fontRef

        visible: false
    }

    Row {
        id: tabBar

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Tokens.padding.large
        spacing: Tokens.spacing.small
        height: 52

        Repeater {
            model: ShelfStore.tabs

            StyledRect {
                id: tab

                required property var modelData
                readonly property bool active: root.currentTab === modelData.key
                readonly property int count: ShelfStore.modelFor(modelData.key).count
                readonly property color fg: active ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant

                width: (tabBar.width - tabBar.spacing * 2) / 3
                height: tabBar.height
                radius: Tokens.rounding.medium
                color: active ? Colours.tPalette.m3surfaceContainerHigh
                     : tabHover.hovered ? Colours.tPalette.m3surfaceContainer : "transparent"

                Column {
                    anchors.centerIn: parent
                    width: parent.width - Tokens.padding.small * 2
                    spacing: 2

                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 4

                        MaterialIcon {
                            text: tab.modelData.icon
                            color: tab.fg
                        }

                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: tab.count > 0
                            text: tab.count
                            color: tab.fg
                            font.pointSize: fontRef.font.pointSize * 0.8
                        }
                    }

                    StyledText {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        text: tab.modelData.label
                        color: tab.fg
                        font.pointSize: fontRef.font.pointSize * 0.85
                    }
                }

                HoverHandler {
                    id: tabHover
                }

                MouseArea {
                    id: tabMouse

                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: root.currentTab = tab.modelData.key
                }
            }
        }
    }
    component BarButton: StyledRect {
        id: btn

        property string icon
        property string label
        property color fg: Colours.palette.m3onSurfaceVariant

        signal clicked

        implicitWidth: btnRow.implicitWidth + Tokens.padding.large * 2
        implicitHeight: 32
        radius: Tokens.rounding.medium
        color: btnHover.hovered ? Colours.tPalette.m3surfaceContainer : "transparent"

        Row {
            id: btnRow

            anchors.centerIn: parent
            spacing: 4

            MaterialIcon {
                anchors.verticalCenter: parent.verticalCenter
                text: btn.icon
                color: btn.fg
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: btn.label
                color: btn.fg
                font.pointSize: fontRef.font.pointSize * 0.85
            }
        }

        HoverHandler {
            id: btnHover
        }

        MouseArea {
            anchors.fill: parent
            onClicked: btn.clicked()
        }
    }

    // Auswahlleiste: nur für den aktuellen Reiter (Auswahl wird beim Reiterwechsel geleert)
    Item {
        id: selBar

        readonly property int count: root.currentModel.count
        readonly property int selected: ShelfStore.selectionCount
        readonly property bool allSelected: count > 0 && selected === count

        anchors.top: tabBar.bottom
        anchors.topMargin: Tokens.spacing.small
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: Tokens.padding.large
        anchors.rightMargin: Tokens.padding.large
        height: count > 0 ? 32 : 0
        visible: count > 0

        StyledText {
            anchors.left: parent.left
            anchors.leftMargin: Tokens.padding.small
            anchors.verticalCenter: parent.verticalCenter
            text: selBar.selected > 0 ? selBar.selected + " markiert"
                : selBar.count + (selBar.count === 1 ? " Eintrag" : " Einträge")
            color: Colours.palette.m3onSurfaceVariant
            font.pointSize: fontRef.font.pointSize * 0.85
        }

        Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Tokens.spacing.small

            BarButton {
                visible: selBar.selected > 0
                icon: "delete"
                label: "Entfernen"
                fg: Colours.palette.m3error
                onClicked: ShelfStore.removeSelected(root.currentTab)
            }

            BarButton {
                icon: selBar.allSelected ? "deselect" : "select_all"
                label: selBar.allSelected ? "Keine" : "Alle"
                onClicked: selBar.allSelected ? ShelfStore.clearSelection(root.currentTab)
                                              : ShelfStore.selectAll(root.currentTab)
            }
        }
    }

    Column {
        anchors.centerIn: list
        visible: root.currentModel.count === 0
        spacing: Tokens.spacing.small

        MaterialIcon {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.currentTabInfo.icon
            color: Colours.palette.m3onSurfaceVariant
            fontStyle: Tokens.font.icon.large
        }

        StyledText {
            width: 260
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: root.currentTabInfo.empty
            color: Colours.palette.m3onSurfaceVariant
        }
    }

    ListView {
        id: list

        anchors.top: selBar.bottom
        anchors.topMargin: Tokens.spacing.small
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: Tokens.padding.large
        anchors.rightMargin: Tokens.padding.large
        anchors.bottomMargin: Tokens.padding.large
        spacing: Tokens.spacing.small
        clip: true
        interactive: contentHeight > height
        model: root.currentModel

        delegate: ShelfItem {
            shelfKey: root.currentTab
        }
    }
}
