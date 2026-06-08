import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.UI

Item {
    id: root

    property var pluginApi: null

    property var cfg: pluginApi?.pluginSettings || ({})
    property var defaults: pluginApi?.manifest?.metadata?.defaultSettings || ({})

    readonly property bool fortuneEnabled: cfg.fortuneEnabled ?? defaults.fortuneEnabled ?? false
    readonly property bool fortuneOffensive: cfg.fortuneOffensive ?? defaults.fortuneOffensive ?? false
    readonly property bool fortuneEqual: cfg.fortuneEqual ?? defaults.fortuneEqual ?? false
    readonly property string fortuneCategory: cfg.fortuneCategory ?? defaults.fortuneCategory ?? ""
    readonly property int fortuneMaxLength: cfg.fortuneMaxLength ?? defaults.fortuneMaxLength ?? 60

    readonly property bool listEnabled: cfg.listEnabled ?? defaults.listEnabled ?? false
    readonly property string textFile: cfg.textFile ?? defaults.textFile ?? ""
    readonly property bool refreshOnWallpaper: cfg.refreshOnWallpaper ?? defaults.refreshOnWallpaper ?? true

    property string fortuneText: ""
    property int _retries: 0
    readonly property int _maxRetries: 10

    property string listText: ""

    readonly property string _examplesPath: Qt.resolvedUrl("examples.txt").toString().replace(/^file:\/\//, "")
    readonly property string _activePath: textFile.trim().length > 0 ? textFile.trim() : _examplesPath

    // =========================
    // SOCKET PATH
    // =========================
    property string socketPath: "/tmp/quickshell-refresh.sock"

    Component.onCompleted: {
        if (fortuneEnabled) triggerFortune()
        if (listEnabled) pickFromFile()
    }

    // =========================
    // debounce
    // =========================
    Timer {
        id: debounce
        interval: 300
        repeat: false

        onTriggered: {
            if (root.fortuneEnabled) triggerFortune()
            if (root.listEnabled) pickFromFile()
        }
    }

    // =========================
    // wallpaper trigger
    // =========================
    Connections {
        target: WallpaperService
        function onWallpaperChanged(screenName, path) {
            if (!root.refreshOnWallpaper) return
            if (root.fortuneEnabled || root.listEnabled) debounce.restart()
        }
    }

    // =========================
    // SOCKET LISTENER (FIXED FOR NIX)
    // =========================
    Process {
        id: socketListener

        command: [
            "socat",
            "-u",
            "UNIX-LISTEN:" + root.socketPath + ",fork",
            "STDOUT"
        ]

        running: true

        stdout: StdioCollector {
            onStreamFinished: {
                var msg = text.trim()

                if (msg.length > 0) {
                    if (root.fortuneEnabled || root.listEnabled) {
                        debounce.restart()
                    }
                }
            }
        }

        onExited: (code) => {
            Logger.w("NotJustText", "socket listener exited:", code)

            Qt.callLater(() => {
                socketListener.running = true
            })
        }
    }

    // =========================
    // fortune process
    // =========================
    Process {
        id: fortuneProcess

        command: {
            var cmd = ["fortune", "-s"]
            if (root.fortuneOffensive) cmd.push("-o")
            if (root.fortuneEqual) cmd.push("-e")
            if (root.fortuneCategory.trim().length > 0)
                cmd.push(root.fortuneCategory.trim())
            return cmd
        }

        running: false

        stdout: StdioCollector {
            onStreamFinished: {
                var lines = text.trim().split('\n').filter(l => l.trim().length > 0)
                var valid = lines.length === 1 && lines[0].length <= root.fortuneMaxLength

                if (valid) {
                    root.fortuneText = lines[0].trim()
                    root._retries = 0
                } else if (root._retries < root._maxRetries) {
                    root._retries++
                    root.triggerFortune()
                } else {
                    root.fortuneText = root.pluginApi?.tr("fortune.gaveUp")
                    root._retries = 0
                }
            }
        }
    }

    function triggerFortune() {
        fortuneProcess.running = false
        fortuneProcess.running = true
    }

    // =========================
    // list file reader
    // =========================
    Process {
        id: textFileProcess
        command: ["cat", root._activePath]
        running: false

        stdout: StdioCollector {
            onStreamFinished: {
                var lines = text
                    .split('\n')
                    .filter(l => l.trim().length > 0 && !l.trim().startsWith('# '))

                if (lines.length > 0) {
                    root.listText = lines[Math.floor(Math.random() * lines.length)].trim()
                } else {
                    root.listText = ""
                }
            }
        }
    }

    function pickFromFile() {
        textFileProcess.running = false
        textFileProcess.running = true
    }
}
