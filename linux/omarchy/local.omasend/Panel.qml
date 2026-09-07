import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "local.omasend"
  ipcTarget: "local.omasend"
  manageIpc: false

  property var status: ({ autoCopy: false, peers: [], historySize: 0 })
  property var history: []
  property string lastError: ""
  property int cursorIndex: -1
  property bool devicesExpanded: false
  readonly property int historyStartIndex: 3
  readonly property int pairingIndex: history.length + historyStartIndex
  readonly property int lastCursorIndex: status.trustedLAN ? pairingIndex - 1 : pairingIndex

  readonly property int peerCount: (status.peers || []).length
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color muted: Qt.darker(foreground, 1.4)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color hoverFill: Style.hoverFillFor(foreground, Color.accent)

  function commandFor(args) { return [String(settings.command || "omasend")].concat(args) }
  function refresh() {
    if (!statusProc.running) { statusProc.command = commandFor(["status", "--json"]); statusProc.running = true }
    if (!historyProc.running) { historyProc.command = commandFor(["history", "--json"]); historyProc.running = true }
  }
  function setAuto(value) {
    if (actionProc.running) return
    actionProc.command = commandFor(["auto", value ? "on" : "off", "--json"])
    actionProc.running = true
  }
  function copyItem(index) {
    if (index < 0 || index >= history.length || actionProc.running) return
    actionProc.command = commandFor(["copy", String(history[index].id)])
    actionProc.running = true
    root.close()
  }
  function setLAN(value) {
    if (actionProc.running) return
    actionProc.command = commandFor(["lan", value ? "on" : "off", "--json"]); actionProc.running = true
  }
  function copyPairingCode() {
    if (actionProc.running) return
    actionProc.command = commandFor(["pair", "copy"])
    actionProc.running = true
  }
  function clearHistory() {
    if (actionProc.running) return
    actionProc.command = commandFor(["clear", "--json"])
    actionProc.running = true
  }
  function preview(value) {
    var text = String(value || "").replace(/\s+/g, " ").trim()
    return text.length > 72 ? text.slice(0, 69) + "..." : text
  }
  function stateText() {
    if (lastError !== "") return "Service unavailable"
    if (peerCount === 0) return "Looking for paired devices"
    return peerCount + (peerCount === 1 ? " device connected" : " devices connected")
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight
  Component.onCompleted: refresh()
  onOpenedChanged: if (opened) {
    cursorIndex = -1
    devicesExpanded = false
    refresh()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }
  onLastCursorIndexChanged: cursorIndex = Math.min(cursorIndex, lastCursorIndex)

  function moveCursor(delta) {
    cursorIndex = Math.max(0, Math.min(lastCursorIndex, cursorIndex + delta))
    if (cursorIndex < historyStartIndex) panelFlick.contentY = 0
    else if (cursorIndex === pairingIndex) panelFlick.contentY = Math.max(0, panelFlick.contentHeight - panelFlick.height)
    else {
      historyList.positionViewAtIndex(cursorIndex - historyStartIndex, ListView.Contain)
      panelFlick.contentY = Math.max(0, Math.min(historyList.mapToItem(content, 0, 0).y, panelFlick.contentHeight - panelFlick.height))
    }
  }
  function activateCursor() {
    if (cursorIndex === 0) setAuto(!status.autoCopy)
    else if (cursorIndex === 1) setLAN(!status.trustedLAN)
    else if (cursorIndex === 2) devicesExpanded = !devicesExpanded
    else if (cursorIndex === pairingIndex && !status.trustedLAN) copyPairingCode()
    else if (cursorIndex >= historyStartIndex) copyItem(cursorIndex - historyStartIndex)
  }

  Timer { interval: Math.max(750, Number(settings.refreshIntervalMs || 1500)); running: true; repeat: true; onTriggered: root.refresh() }

  Process {
    id: statusProc
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: {
      try { root.status = JSON.parse(String(text || "{}")); root.lastError = "" }
      catch (error) { root.lastError = "Invalid status" }
    } }
    stderr: StdioCollector { waitForEnd: true; onStreamFinished: if (String(text || "").trim() !== "") root.lastError = String(text).trim() }
  }
  Process {
    id: historyProc
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: {
      try { root.history = JSON.parse(String(text || "[]")) }
      catch (error) { root.history = [] }
    } }
  }
  Process {
    id: actionProc
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true; onStreamFinished: if (String(text || "").trim() !== "") root.lastError = String(text).trim() }
    onRunningChanged: if (!running) root.refresh()
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { root.refresh(); return "ok" }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰅇"
    fontFamily: "JetBrainsMono Nerd Font"
    foreground: root.foreground
    activeColor: root.foreground
    active: root.peerCount > 0
    tooltipText: root.stateText()
    onPressed: function(mouseButton) { if (mouseButton === Qt.MiddleButton) root.setAuto(!root.status.autoCopy); else if (mouseButton === Qt.RightButton) root.clearHistory(); else root.toggle() }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(content.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) { if (dy !== 0) root.moveCursor(dy) }
      onActivateRequested: root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) {
        if (text === "a" || text === "A") root.setAuto(!root.status.autoCopy)
        else if (text === "r" || text === "R") root.refresh()
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: content.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        Controls.ScrollBar.vertical: Controls.ScrollBar { policy: Controls.ScrollBar.AsNeeded }

        Column {
          id: content
          width: panelFlick.width
          spacing: Style.space(10)

          Item {
            id: header
            width: parent.width
            implicitHeight: hero.implicitHeight
            readonly property bool autoCopy: root.status.autoCopy === true
            readonly property bool busy: actionProc.running
            readonly property bool hasCursor: root.cursorIndex === 0
            function toggleAuto() { root.setAuto(!root.status.autoCopy) }
            function focusAuto() { root.cursorIndex = 0 }

            PanelHero {
              id: hero
              width: parent.width
              title: "OmaSend"
              meta: root.lastError !== "" ? "Service unavailable" : (root.status.trustedLAN ? "Local network" : "Encrypted clipboard")
              foreground: root.foreground
              fontFamily: root.fontFamily
              iconOpacity: root.peerCount > 0 ? 1 : 0.5
              iconComponent: Component {
                Text {
                  text: "󰅇"
                  color: hero.foreground
                  font.family: hero.fontFamily
                  font.pixelSize: Style.font.display
                }
              }
              trailingControl: Component {
                ToggleSwitch {
                  id: autoSwitch
                  checked: header.autoCopy
                  busy: header.busy
                  hasCursor: header.hasCursor
                  foreground: hero.foreground
                  onHovered: function(on) { if (on) header.focusAuto() }
                  onToggled: header.toggleAuto()
                  PanelToolTip {
                    visible: autoSwitch.containsMouse
                    text: header.autoCopy ? "Auto copy on: incoming items replace your clipboard" : "Auto copy off: save incoming items to history"
                    fontFamily: hero.fontFamily
                  }
                }
              }
            }
          }

          Text {
            visible: root.lastError !== ""
            width: parent.width
            text: root.lastError
            textFormat: Text.PlainText
            color: Color.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          PanelSeparator { foreground: root.foreground }

          Column {
            width: parent.width
            spacing: Style.space(6)
            RowLayout {
              width: parent.width
              PanelSectionHeader {
                text: "TRUSTED LAN"
                foreground: root.foreground
                fontFamily: root.fontFamily
                Layout.fillWidth: true
              }
              ToggleSwitch {
                id: lanSwitch
                checked: root.status.trustedLAN === true
                busy: actionProc.running
                hasCursor: root.cursorIndex === 1
                foreground: root.foreground
                trackHeight: Style.space(18)
                onHovered: function(on) { if (on) root.cursorIndex = 1 }
                onToggled: root.setLAN(!root.status.trustedLAN)
                PanelToolTip {
                  visible: lanSwitch.containsMouse
                  text: root.status.trustedLAN ? "Switch to encrypted pairing" : "Share without pairing on a trusted local network"
                  fontFamily: root.fontFamily
                }
              }
            }
          }

          PanelSeparator { foreground: root.foreground }

          Column {
            width: parent.width
            spacing: Style.space(6)
            CursorSurface {
              id: devicesRow
              width: parent.width
              height: Style.space(36)
              foreground: root.foreground
              hasCursor: root.cursorIndex === 2
              Accessible.role: Accessible.Button
              Accessible.name: root.peerCount + (root.peerCount === 1 ? " device connected" : " devices connected")
              Accessible.description: root.devicesExpanded ? "Collapse devices" : "Expand devices"
              Accessible.onPressAction: root.devicesExpanded = !root.devicesExpanded

              RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Style.space(6)
                anchors.rightMargin: Style.space(6)
                spacing: Style.space(8)
                Text {
                  text: "󰌢"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.title
                  Layout.preferredWidth: Style.space(28)
                  horizontalAlignment: Text.AlignHCenter
                }
                Text {
                  Layout.fillWidth: true
                  text: root.peerCount + (root.peerCount === 1 ? " device connected" : " devices connected")
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  elide: Text.ElideRight
                }
                Text {
                  text: "󰅀"
                  rotation: root.devicesExpanded ? 0 : -90
                  color: root.muted
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.title
                  Layout.preferredWidth: Style.space(16)
                  horizontalAlignment: Text.AlignHCenter
                }
              }
              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: root.cursorIndex = 2
                onClicked: root.devicesExpanded = !root.devicesExpanded
              }
            }
            Repeater {
              model: root.devicesExpanded ? (root.status.peers || []) : []
              RowLayout {
                required property var modelData
                width: parent.width
                height: Style.space(42)
                spacing: Style.space(8)
                Text {
                  text: "󰌢"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.title
                  Layout.preferredWidth: Style.space(28)
                  horizontalAlignment: Text.AlignHCenter
                }
                Column {
                  Layout.fillWidth: true
                  spacing: Style.space(2)
                  Text {
                    width: parent.width
                    text: String(modelData.name || "Device")
                    textFormat: Text.PlainText
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    elide: Text.ElideRight
                  }
                  Text {
                    width: parent.width
                    text: "Connected · " + String(modelData.via || "Local network")
                    textFormat: Text.PlainText
                    color: root.muted
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                  }
                }
              }
            }
            Text {
              visible: root.devicesExpanded && root.peerCount === 0
              width: parent.width
              text: "Looking for devices…"
              color: root.muted
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }
          }

          PanelSeparator { foreground: root.foreground }

          Column {
            width: parent.width
            spacing: Style.space(8)
            RowLayout {
              width: parent.width
              PanelSectionHeader {
                text: "CLIPBOARD"
                foreground: root.foreground
                fontFamily: root.fontFamily
                Layout.fillWidth: true
              }
              Text {
                text: root.history.length
                color: root.muted
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
            ListView {
              id: historyList
              width: parent.width
              height: root.history.length === 0 ? emptyLabel.implicitHeight : Math.min(contentHeight, Style.space(240))
              spacing: Style.space(2)
              clip: true
              boundsBehavior: Flickable.StopAtBounds
              model: root.history.length
              Controls.ScrollBar.vertical: Controls.ScrollBar { policy: Controls.ScrollBar.AsNeeded }
              delegate: CursorSurface {
                id: historyRow
                required property int index
                readonly property var entry: root.history[index] || ({})
                readonly property string thumbnail: String(entry.thumbnail || "")
                width: historyList.width
                height: Style.space(58)
                foreground: root.foreground
                fill: root.hoverFill
                hasCursor: root.cursorIndex === index + root.historyStartIndex

                RowLayout {
                  anchors.fill: parent
                  anchors.leftMargin: Style.space(6)
                  anchors.rightMargin: Style.space(6)
                  spacing: Style.space(8)
                  Item {
                    Layout.preferredWidth: Style.space(28)
                    Layout.preferredHeight: Style.space(28)
                    Image {
                      anchors.fill: parent
                      visible: historyRow.thumbnail !== ""
                      source: visible ? "data:image/png;base64," + historyRow.thumbnail : ""
                      fillMode: Image.PreserveAspectFit
                      sourceSize.width: 112
                      sourceSize.height: 112
                    }
                    Text {
                      anchors.centerIn: parent
                      visible: historyRow.thumbnail === ""
                      text: String(historyRow.entry.fileName || "") !== "" ? "󰈔" : "󰅇"
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.title
                    }
                  }
                  Column {
                    Layout.fillWidth: true
                    spacing: Style.space(2)
                    Text {
                      width: parent.width
                      text: String(historyRow.entry.fileName || "") || (historyRow.thumbnail !== "" ? "Image" : root.preview(historyRow.entry.text))
                      textFormat: Text.PlainText
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      elide: Text.ElideRight
                    }
                    Text {
                      width: parent.width
                      text: historyRow.entry.isLocal ? "This device" : String(historyRow.entry.originName || "Paired device")
                      textFormat: Text.PlainText
                      color: root.muted
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      elide: Text.ElideRight
                    }
                  }
                  Text {
                    text: "󰆏"
                    color: root.muted
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.icon
                  }
                }
                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onEntered: root.cursorIndex = historyRow.index + root.historyStartIndex
                  onClicked: root.copyItem(historyRow.index)
                }
              }
              Text {
                id: emptyLabel
                visible: root.history.length === 0
                text: "Copy something on either device to begin."
                color: root.muted
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                wrapMode: Text.WordWrap
                width: parent.width
              }
            }
          }

          PanelSeparator { visible: !root.status.trustedLAN; foreground: root.foreground }
          Button {
            visible: !root.status.trustedLAN
            width: parent.width
            text: "Copy pairing code"
            foreground: root.foreground
            fontFamily: root.fontFamily
            hasCursor: root.cursorIndex === root.pairingIndex
            enabled: !actionProc.running
            onHovered: function(on) { if (on) root.cursorIndex = root.pairingIndex }
            onClicked: root.copyPairingCode()
          }
        }
      }
    }
  }
}
