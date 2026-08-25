import QtQuick
import QtQuick.Controls
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
  property bool cursorActive: false
  property int selectedItem: 0

  readonly property int peerCount: (status.peers || []).length
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color muted: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.58)
  readonly property color faint: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.08)
  readonly property color accent: peerCount > 0 ? "#60a5fa" : muted

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
  onOpenedChanged: if (opened) { selectedItem = 0; cursorActive = false; refresh(); Qt.callLater(function() { keyCatcher.forceActiveFocus() }) }

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
    foreground: root.accent
    activeColor: "#ffffff"
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
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(content.implicitHeight, Style.space(520))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) { if (dy !== 0 && history.length > 0) { cursorActive = true; selectedItem = Math.max(0, Math.min(history.length - 1, selectedItem + dy)) } }
      onActivateRequested: root.copyItem(selectedItem)
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) { if (text === "a" || text === "A") root.setAuto(!root.status.autoCopy); else if (text === "r" || text === "R") root.refresh() }

      Column {
        id: content
        width: parent.width
        spacing: Style.space(12)

        PanelHero {
          width: parent.width
          title: "OmaSend"
          meta: root.stateText()
          foreground: root.foreground
          fontFamily: bar ? bar.fontFamily : Style.font.family
          iconOpacity: 1
          iconComponent: Component {
            Text { text: "󰅇"; color: root.accent; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: Style.font.display }
          }
        }

        Rectangle {
          width: parent.width
          implicitHeight: autoRow.implicitHeight + Style.space(20)
          radius: Style.space(12)
          color: root.faint
          RowLayout {
            id: autoRow
            anchors.fill: parent
            anchors.margins: Style.space(10)
            ColumnLayout {
              spacing: Style.space(2)
              Text { text: "Auto copy"; color: root.foreground; font.family: bar ? bar.fontFamily : Style.font.family; font.pixelSize: Style.font.body; font.bold: true }
              Text { text: status.autoCopy ? "Incoming items replace your clipboard" : "History only. Click an item to copy."; color: root.muted; font.family: bar ? bar.fontFamily : Style.font.family; font.pixelSize: Style.font.caption }
            }
            Item { Layout.fillWidth: true }
            Switch { checked: status.autoCopy === true; onToggled: root.setAuto(checked) }
          }
        }

        Text { text: "SHARED CLIPBOARD"; color: root.muted; font.family: bar ? bar.fontFamily : Style.font.family; font.pixelSize: Style.font.caption; font.bold: true }

        ListView {
          id: historyList
          width: parent.width
          height: history.length === 0 ? emptyLabel.implicitHeight : Math.min(contentHeight, Style.space(280))
          spacing: Style.space(4)
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          model: history.length
          delegate: Rectangle {
            required property int index
            width: historyList.width
            height: Math.max(Style.space(46), itemRow.implicitHeight + Style.space(12))
            radius: Style.space(8)
            color: root.cursorActive && root.selectedItem === index ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.18) : itemMouse.containsMouse ? root.faint : "transparent"
            RowLayout {
              id: itemRow
              anchors.fill: parent
              anchors.margins: Style.space(6)
              spacing: Style.space(8)
              Image {
                visible: String(history[index].thumbnail || "") !== ""
                source: visible ? "data:image/png;base64," + history[index].thumbnail : ""
                Layout.preferredWidth: Style.space(40)
                Layout.preferredHeight: Style.space(34)
                fillMode: Image.PreserveAspectCrop
                sourceSize.width: 160
                sourceSize.height: 160
              }
              Text {
                visible: String(history[index].thumbnail || "") === ""
                text: String(history[index].filePath || "") !== "" ? "󰈔" : (history[index].isLocal ? "󰌢" : "󰅇")
                color: history[index].isLocal ? root.muted : root.accent
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: Style.font.title
                Layout.preferredWidth: Style.space(40)
                horizontalAlignment: Text.AlignHCenter
              }
              Text {
                text: String(history[index].fileName || "") !== "" ? String(history[index].fileName) : (String(history[index].thumbnail || "") !== "" ? "Image" : root.preview(history[index].text))
                color: root.foreground
                font.family: bar ? bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.body
                elide: Text.ElideRight
                maximumLineCount: 2
                wrapMode: Text.Wrap
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
              }
              Text { text: "󰆏"; color: root.muted; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: Style.font.body; Layout.alignment: Qt.AlignVCenter }
            }
            MouseArea { id: itemMouse; anchors.fill: parent; hoverEnabled: true; onClicked: root.copyItem(index); onEntered: { root.cursorActive = true; root.selectedItem = index } }
          }
          Text { id: emptyLabel; visible: history.length === 0; text: "Copy something on either computer to begin."; color: root.muted; font.family: bar ? bar.fontFamily : Style.font.family; font.pixelSize: Style.font.body; wrapMode: Text.WordWrap; width: parent.width }
        }

        Rectangle { width: parent.width; height: 1; color: root.faint }
        RowLayout {
          width: parent.width
          Text { text: peerCount > 0 ? (status.peers || []).map(function(peer) { return peer.name }).join(", ") : "No paired devices online"; color: root.muted; font.family: bar ? bar.fontFamily : Style.font.family; font.pixelSize: Style.font.caption; elide: Text.ElideRight; Layout.fillWidth: true }
          Button { text: "Copy pairing code"; onClicked: root.copyPairingCode() }
        }
      }
    }
  }
}
