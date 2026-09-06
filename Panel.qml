import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "QuickAskModel.js" as Model

// Centered Spotlight-style overlay for Quick Ask. Summoned from the bar
// icon or SUPER+SHIFT+A: a compact card in the middle of the screen with
// the composer already focused. Conversation grows downward under the
// input so the field stays put, like Spotlight results.
Panel {
  id: root
  moduleName: "wolften.quickask"
  ipcTarget: "wolften.quickask"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root
  readonly property var anchorWindow: {
    if (anchorItem && anchorItem.QsWindow) return anchorItem.QsWindow.window
    if (root.QsWindow) return root.QsWindow.window
    return null
  }

  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property color scrim: Color.menu.scrim
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color selectedBackground: Color.menu.selectedBackground
  readonly property color dim: Qt.darker(foreground, 1.5)
  readonly property string fontFamily: Style.font.menuFamily
  readonly property int cornerRadius: Style.cornerRadius
  readonly property int contentMargin: Style.spacing.panelPadding
  readonly property int contentSpacing: Style.spacing.md

  property string agentName: ""
  property string agentModel: ""
  property string liveModel: ""
  readonly property string resolvedModel: liveModel !== "" ? liveModel : agentModel
  readonly property string identityText: {
    var name = agentName !== "" ? agentName : "agente"
    return resolvedModel !== "" ? name + " · " + resolvedModel : name
  }
  property bool busy: askProc.running

  readonly property string scriptPath: String(Qt.resolvedUrl("ask.sh")).replace(/^file:\/\//, "")
  readonly property string modelScriptPath: String(Qt.resolvedUrl("model.sh")).replace(/^file:\/\//, "")

  // Pin the card's top edge the first time conversation appears so growth
  // happens downward (Spotlight) instead of re-centering and jumping the
  // input. Cleared on close and on nova conversa.
  property int frozenTop: -1

  function open() {
    root.controller.show()
    if (root.bar && typeof root.bar.requestPopout === "function")
      root.bar.requestPopout(root.barIdentity)
    refreshAgent()
    Qt.callLater(root.focusInput)
    focusRetry.restart()
  }

  function close() {
    focusRetry.stop()
    if (root.bar && typeof root.bar.releasePopout === "function"
        && root.bar.activePopout === root.barIdentity)
      root.bar.releasePopout(root.barIdentity)
    root.controller.hide()
    frozenTop = -1
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function focusInput() {
    if (!root.opened) return
    input.forceActiveFocus()
  }

  function freezeTopIfNeeded() {
    if (frozenTop >= 0 || !overlay.visible) return
    frozenTop = Math.max(Style.gapsOut, Math.round((overlay.height - card.height) / 2))
  }

  function historyPinnedToEnd() {
    return historyFlick.contentY + historyFlick.height >= historyFlick.contentHeight - 8
  }

  function scrollHistoryToEnd() {
    Qt.callLater(function() {
      historyFlick.contentY = Math.max(0, historyFlick.contentHeight - historyFlick.height)
    })
  }

  function refreshAgent() {
    if (!agentProc.running) {
      agentName = ""
      agentProc.running = true
    }
    if (!modelProc.running) {
      agentModel = ""
      modelProc.command = [root.modelScriptPath]
      modelProc.running = true
    }
  }

  function newConversation() {
    if (askProc.running) askProc.running = false
    askTimeout.stop()
    spawnWatch.stop()
    flushTimer.stop()
    stagedStream = ""
    askError = ""
    askFinalized = true
    historyModel.clear()
    frozenTop = -1
    input.clear()
    root.focusInput()
  }

  function openInTerminal() {
    if (root.bar) root.bar.run("omarchy-agent --pick")
    root.close()
  }

  function stampNow() {
    return Qt.formatTime(new Date(), "HH:mm")
  }

  function send() {
    var question = input.text.trim()
    if (question === "" || askProc.running) return
    freezeTopIfNeeded()
    historyModel.append({ question: question, answer: "", pending: true, qtime: stampNow(), atime: "" })
    root.scrollHistoryToEnd()
    input.clear()
    input.forceActiveFocus()
    askError = ""
    stagedStream = ""
    askFinalText = ""
    askExitCode = 0
    askStdoutDone = false
    askExited = false
    askFinalized = false
    askProc.exec([root.scriptPath, question])
    askTimeout.restart()
    spawnWatch.restart()
  }

  property string askError: ""
  property string stagedStream: ""
  property string askFinalText: ""
  property int askExitCode: 0
  property bool askStdoutDone: false
  property bool askExited: false
  property bool askFinalized: false

  // Incremental chunk from the running agent: debounce UI updates so a
  // fast token stream doesn't relayout the list on every byte.
  function stageStream(text) {
    stagedStream = String(text || "")
    flushTimer.restart()
  }

  function pushStream(text) {
    var last = historyModel.count - 1
    if (last < 0 || !askProc.running) return
    var cleaned = Model.cleanStream(text, false)
    var current = historyModel.get(last)
    if (current.answer === cleaned) return
    var stick = root.historyPinnedToEnd()
    historyModel.set(last, { question: current.question, answer: cleaned, pending: true, qtime: current.qtime, atime: current.atime })
    if (stick) root.scrollHistoryToEnd()
  }

  // Finalize only once stdout has closed AND the process has exited:
  // either one alone can arrive first, and stderr (errors, banners)
  // may land in between.
  function onAskStdoutFinished(text) {
    askFinalText = String(text || "")
    askStdoutDone = true
    tryFinish()
  }

  function onAskExited(code) {
    askExitCode = code
    askExited = true
    tryFinish()
  }

  function tryFinish() {
    if (askFinalized || !askStdoutDone || !askExited) return
    askFinalized = true
    finishAnswer(askFinalText)
  }

  function finishAnswer(text) {
    flushTimer.stop()
    stagedStream = ""
    askTimeout.stop()
    spawnWatch.stop()
    var cleaned = Model.cleanStream(text, true)
    var last = historyModel.count - 1
    if (last < 0) return
    var finalAnswer = cleaned
    var problem = askError
    if (problem === "" && askExitCode !== 0 && cleaned === "") {
      problem = "Agente falhou (exit " + askExitCode + ")."
    }
    if (problem !== "") {
      finalAnswer = cleaned !== "" ? cleaned + "\n\n[" + problem + "]" : problem
    } else if (cleaned === "") {
      finalAnswer = "Sem resposta do agente."
    }
    finalAnswer = Model.withPermissionHint(finalAnswer)
    historyModel.set(last, {
      question: historyModel.get(last).question,
      answer: finalAnswer,
      pending: false,
      qtime: historyModel.get(last).qtime,
      atime: stampNow()
    })
    root.scrollHistoryToEnd()
  }

  ListModel {
    id: historyModel
  }

  Process {
    id: agentProc
    command: ["omarchy-default-agent"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var name = String(text || "").trim()
        root.agentName = name !== "" ? name : "agente"
      }
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (root.agentName === "") root.agentName = "agente"
      }
    }
  }

  Process {
    id: modelProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.agentModel = String(text || "").trim()
      }
    }
  }

  Process {
    id: askProc
    stdout: StdioCollector {
      // waitForEnd:false → text grows as the agent prints, so answers
      // stream token by token whenever the CLI flushes progressively.
      waitForEnd: false
      onTextChanged: root.stageStream(text)
      onStreamFinished: root.onAskStdoutFinished(text)
    }
    onExited: function(code, status) { root.onAskExited(code) }
    stderr: StdioCollector {
      id: askStderr
      waitForEnd: true
      onStreamFinished: {
        var live = Model.findBannerModel(text)
        if (live !== "") root.liveModel = live
        var err = Model.cleanError(text, 3)
        if (err !== "") root.askError = err
      }
    }
  }

  Timer {
    id: flushTimer
    interval: 80
    onTriggered: root.pushStream(root.stagedStream)
  }

  Timer {
    id: spawnWatch
    interval: 3000
    onTriggered: {
      if (!root.askFinalized && !root.askStdoutDone && !askProc.running) {
        root.askError = "Falha ao iniciar o agente (" + root.scriptPath + ")."
        root.askStdoutDone = true
        root.askExited = true
        root.tryFinish()
      }
    }
  }

  Timer {
    id: askTimeout
    interval: 180000
    onTriggered: {
      // Don't finalize here: killing the process fires onStreamFinished,
      // which finalizes with the partial output plus this error.
      if (askProc.running) askProc.running = false
      flushTimer.stop()
      root.askError = "Tempo esgotado (180s)."
    }
  }

  // Layer-shell grants the surface focus on map, but the TextField still
  // needs activeFocus inside it. Retry a few frames in case Exclusive
  // lands after the first callLater.
  Timer {
    id: focusRetry
    interval: 40
    repeat: true
    property int attempts: 0
    onTriggered: {
      attempts++
      if (input.activeFocus || !root.opened || attempts > 10) {
        stop()
        attempts = 0
      } else {
        root.focusInput()
      }
    }
    onRunningChanged: if (!running) attempts = 0
  }

  PanelWindow {
    id: overlay
    visible: root.opened || card.opacity > 0.01
    screen: root.anchorWindow ? root.anchorWindow.screen : null
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "wolften-quickask"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    anchors {
      top: true
      bottom: true
      left: true
      right: true
    }

    onVisibleChanged: if (visible && root.opened) Qt.callLater(root.focusInput)

    Rectangle {
      anchors.fill: parent
      color: root.scrim
      opacity: root.opened ? 1 : 0
      Behavior on opacity {
        NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
      }
    }

    MouseArea {
      anchors.fill: parent
      enabled: root.opened
      acceptedButtons: Qt.AllButtons
      onClicked: root.close()
    }

    BorderSurface {
      id: card
      width: Math.min(Style.space(560), Math.max(Style.space(320), overlay.width - Style.gapsOut * 2))
      height: Math.min(
        bodyColumn.implicitHeight + contentTopInset + contentBottomInset,
        overlay.height - Style.gapsOut * 2
      )
      radius: root.cornerRadius
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin
      opacity: root.opened ? 1 : 0
      scale: root.opened ? 1 : 0.98

      x: Math.max(Style.gapsOut, Math.round((overlay.width - width) / 2))
      y: {
        var centered = Math.max(Style.gapsOut, Math.round((overlay.height - height) / 2))
        var top = root.frozenTop >= 0 ? root.frozenTop : centered
        var maxY = overlay.height - height - Style.gapsOut
        return Math.max(Style.gapsOut, Math.min(top, maxY))
      }

      Behavior on opacity {
        NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
      }
      Behavior on scale {
        NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
      }
      Behavior on height {
        NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
      }

      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onClicked: root.focusInput()
      }

      Column {
        id: bodyColumn
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: card.contentLeftInset
        anchors.rightMargin: card.contentRightInset
        anchors.topMargin: card.contentTopInset
        spacing: root.contentSpacing

        // ---- 1. Composer: the primary action, already focused ----
        Row {
          width: parent.width
          spacing: Style.space(10)
          height: Math.max(askIcon.implicitHeight, input.implicitHeight, sendButton.implicitHeight)

          Text {
            id: askIcon
            textFormat: Text.PlainText
            anchors.verticalCenter: parent.verticalCenter
            text: "󰚩"
            color: root.busy ? Color.accent : root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
            opacity: root.busy ? 1 : 0.85
          }

          TextField {
            id: input
            width: parent.width - askIcon.width - sendButton.width - parent.spacing * 2
            anchors.verticalCenter: parent.verticalCenter
            placeholderText: root.busy ? "Aguarde a resposta…" : "Pergunte ao agente…"
            enabled: !root.busy
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
            foreground: root.foreground
            accent: Color.accent
            onAccepted: root.send()
            Keys.onEscapePressed: root.close()
          }

          Button {
            id: sendButton
            anchors.verticalCenter: parent.verticalCenter
            text: "Enviar"
            tooltipText: "Enviar (Enter)"
            enabled: !root.busy && input.text.trim() !== ""
            foreground: root.foreground
            fontFamily: root.fontFamily
            fontSize: Style.font.body
            onClicked: root.send()
          }
        }

        // ---- 2. Identity + secondary actions ----
        Row {
          width: parent.width
          spacing: Style.space(8)
          height: Math.max(identityLabel.implicitHeight, newButton.height, termButton.height)

          Text {
            id: identityLabel
            textFormat: Text.PlainText
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, parent.width - newButton.width - termButton.width - parent.spacing * 2)
            elide: Text.ElideRight
            text: root.busy ? root.identityText + "  ·  pensando" : root.identityText
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.letterSpacing: 1
            font.bold: true
          }

          PanelActionButton {
            id: newButton
            anchors.verticalCenter: parent.verticalCenter
            iconText: "+"
            tooltipText: "Nova conversa (limpa o histórico)"
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: root.newConversation()
          }

          PanelActionButton {
            id: termButton
            anchors.verticalCenter: parent.verticalCenter
            iconText: "󰆍"
            tooltipText: "Abrir agente no terminal"
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: root.openInTerminal()
          }
        }

        // ---- 3. Conversation (grows under the composer) ----
        PanelSeparator {
          visible: historyModel.count > 0
          foreground: root.foreground
        }

        Flickable {
          id: historyFlick
          width: parent.width
          visible: historyModel.count > 0
          height: {
            if (historyModel.count === 0) return 0
            var maxH = Math.min(Style.space(320), Math.round(overlay.height * 0.48))
            return Math.min(maxH, Math.max(Style.space(64), historyColumn.implicitHeight))
          }
          contentWidth: width
          contentHeight: historyColumn.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          flickableDirection: Flickable.VerticalFlick
          onContentHeightChanged: if (root.historyPinnedToEnd()) root.scrollHistoryToEnd()

          Column {
            id: historyColumn
            width: historyFlick.width
            spacing: Style.space(14)

            Repeater {
              model: historyModel

              delegate: Column {
              required property string question
              required property string answer
              required property bool pending
              required property string qtime
              required property string atime

              readonly property color userFill: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.16)
              readonly property string agentCaption: (root.agentName !== "" ? root.agentName : "agente").toUpperCase() + (atime !== "" ? " · " + atime : "")
              readonly property string userCaption: "VOCÊ" + (qtime !== "" ? " · " + qtime : "")

              width: historyColumn.width
              spacing: Style.space(4)

              Text {
                textFormat: Text.PlainText
                anchors.right: parent.right
                text: userCaption
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.letterSpacing: 1
                font.bold: true
              }

              Item {
                anchors.right: parent.right
                width: Math.min(userText.implicitWidth + Style.space(20), parent.width * 0.88)
                height: userText.implicitHeight + Style.space(14)

                BorderSurface {
                  anchors.fill: parent
                  color: userFill
                  radius: Style.cornerRadius
                }

                Text {
                  id: userText
                  anchors.fill: parent
                  anchors.leftMargin: Style.space(10)
                  anchors.rightMargin: Style.space(10)
                  anchors.topMargin: Style.space(7)
                  anchors.bottomMargin: Style.space(7)
                  verticalAlignment: Text.AlignVCenter
                  textFormat: Text.PlainText
                  wrapMode: Text.Wrap
                  text: question
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }
              }

              Text {
                textFormat: Text.PlainText
                visible: !pending || answer !== ""
                text: agentCaption
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.letterSpacing: 1
                font.bold: true
              }

              Row {
                width: parent.width
                spacing: Style.space(8)
                visible: !pending || answer !== ""

                Rectangle {
                  width: Style.space(3)
                  height: agentText.height
                  radius: width / 2
                  color: Color.accent
                }

                Text {
                  id: agentText
                  width: parent.width - Style.space(11)
                  textFormat: Text.PlainText
                  wrapMode: Text.Wrap
                  text: {
                    if (!pending) return answer
                    if (answer === "") return ""
                    return answer + " ▍"
                  }
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }
              }

              Text {
                visible: pending && answer === ""
                textFormat: Text.PlainText
                text: "pensando…"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                opacity: 0.7
              }
              } // message delegate
            } // Repeater
          } // historyColumn
        } // historyFlick

        // ---- 4. Empty-state hint (tertiary) ----
        Text {
          visible: historyModel.count === 0
          width: parent.width
          textFormat: Text.PlainText
          text: "Enter envia  ·  Esc fecha"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          opacity: 0.8
        }
      }
    }
  }
}
