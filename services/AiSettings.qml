pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property alias cfg: adapter
    readonly property string configDir: `${Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config"}/caelestia`
    property string siftdogKey: ""

    FileView {
        path: `${root.configDir}/ai.json`
        watchChanges: true
        onFileChanged: reload()
        onAdapterUpdated: writeAdapter()
        onLoadFailed: err => {
            if (err === FileViewError.FileNotFound)
                writeAdapter();
        }

        JsonAdapter {
            id: adapter

            property bool enableOllama: true
            property string ollamaUrl: "http://localhost:11434"
            property string defaultOllamaModel: "llama3"
            property string activeProvider: "ollama"

            property bool enableOpenRouter: false
            property string openRouterUrl: "https://openrouter.ai/api/v1"
            property string openRouterApiKey: ""
            property string openRouterModel: "openrouter/auto"

            property bool enableOpenClaw: false
            property string openClawUrl: "http://127.0.0.1:18789"
            property string openClawToken: ""
            property string openClawModel: "openclaw/default"

            property bool enableWebTools: true
            property string siftdogUrl: "http://192.168.1.113:8101"

            property var recentModels: []
            property string ollamaHistoryJson: "[]"
        }
    }

    FileView {
        path: `${root.configDir}/siftdog.key`
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.siftdogKey = text().trim()
        onLoadFailed: root.siftdogKey = ""
    }
}
