import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets
import Caelestia
import Caelestia.Config
import qs.components
import qs.services

Item {
    id: root

    required property Props props
    required property ScreenState screenState

    property string activeTab: "notifications"

    readonly property bool aiAvailable: AiSettings.cfg.enableOllama || AiSettings.cfg.enableOpenRouter || AiSettings.cfg.enableOpenClaw
    readonly property var tabs: {
        const t = [{ id: "notifications", label: qsTr("Notifications"), icon: "notifications" }];
        if (aiAvailable)
            t.push({ id: "ai", label: qsTr("AI Assistant"), icon: "smart_toy" });
        return t;
    }
    readonly property int activeIndex: Math.max(0, tabs.findIndex(t => t.id === activeTab))

    onAiAvailableChanged: {
        if (!aiAvailable && activeTab === "ai")
            activeTab = "notifications";
    }

    ColumnLayout {
        id: layout

        anchors.fill: parent
        spacing: Tokens.spacing.medium

        StyledRect {
            Layout.fillWidth: true
            Layout.fillHeight: true

            radius: Tokens.rounding.large
            color: Colours.tPalette.m3surfaceContainerLow

            ColumnLayout {
                anchors.fill: parent
                spacing: 0

                Item {
                    id: header

                    Layout.fillWidth: true
                    implicitHeight: 64
                    visible: root.tabs.length > 1

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Tokens.padding.medium
                        anchors.rightMargin: Tokens.padding.medium
                        spacing: 0

                        Repeater {
                            model: root.tabs

                            delegate: Item {
                                id: tabBtn

                                required property var modelData
                                readonly property bool active: root.activeTab === modelData.id

                                Layout.fillWidth: true
                                Layout.fillHeight: true

                                StateLayer {
                                    id: tabState

                                    anchors.fill: parent
                                    anchors.margins: 4
                                    radius: Tokens.rounding.medium
                                    color: Colours.palette.m3onSurface
                                    onClicked: root.activeTab = tabBtn.modelData.id
                                }

                                ColumnLayout {
                                    anchors.centerIn: parent
                                    spacing: 0

                                    MaterialIcon {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: tabBtn.modelData.icon
                                        fill: tabBtn.active ? 1 : 0
                                        color: tabBtn.active ? Colours.palette.m3primary : tabState.containsMouse ? Colours.palette.m3onSurface : Colours.palette.m3onSurfaceVariant

                                        Behavior on fill {
                                            Anim {
                                                type: Anim.DefaultEffects
                                            }
                                        }
                                    }

                                    StyledText {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: tabBtn.modelData.label
                                        color: tabBtn.active ? Colours.palette.m3primary : tabState.containsMouse ? Colours.palette.m3onSurface : Colours.palette.m3onSurfaceVariant
                                        font: Tokens.font.label.medium
                                    }
                                }
                            }
                        }
                    }

                    StyledRect {
                        readonly property real tabWidth: (header.width - Tokens.padding.medium * 2) / root.tabs.length

                        anchors.bottom: parent.bottom
                        implicitHeight: 3
                        width: tabWidth - Tokens.padding.medium * 2
                        x: Tokens.padding.medium + root.activeIndex * tabWidth + (tabWidth - width) / 2
                        radius: Tokens.rounding.full
                        color: Colours.palette.m3primary

                        Behavior on x {
                            Anim {}
                        }
                    }
                }

                StyledRect {
                    Layout.fillWidth: true
                    implicitHeight: 1
                    visible: header.visible
                    color: Colours.tPalette.m3outlineVariant
                }

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true

                    Item {
                        width: parent.width
                        height: parent.height
                        x: root.activeTab === "notifications" ? 0 : -width
                        opacity: root.activeTab === "notifications" ? 1 : 0
                        visible: opacity > 0

                        NotifDock {
                            objectName: "sidebarNotifications"

                            props: root.props
                            screenState: root.screenState
                        }

                        Behavior on x {
                            Anim {}
                        }
                        Behavior on opacity {
                            Anim {
                                type: Anim.DefaultEffects
                            }
                        }
                    }

                    Loader {
                        width: parent.width
                        height: parent.height
                        x: root.activeTab === "ai" ? 0 : width
                        opacity: root.activeTab === "ai" ? 1 : 0
                        visible: opacity > 0
                        active: root.aiAvailable
                        asynchronous: true

                        sourceComponent: AiAssistant {}

                        Behavior on x {
                            Anim {}
                        }
                        Behavior on opacity {
                            Anim {
                                type: Anim.DefaultEffects
                            }
                        }
                    }
                }
            }
        }

        StyledRect {
            Layout.topMargin: Tokens.padding.large - layout.spacing
            Layout.fillWidth: true
            implicitHeight: 1

            color: Colours.tPalette.m3outlineVariant
        }
    }
}
