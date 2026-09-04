import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "QuickAskModel.js" as Model

// Quick Ask popup: a small chat box bound to the system's default agent.
// History lives only in memory; "+ Nova conversa" clears it.
Panel {
  id: root
  moduleName: "wolften.quickask"
  ipcTarget: "wolften.quickask"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property color contentDim: bar ? Qt.darker(bar.foreground, 1.5) : Qt.darker(Color.foreground, 1.5)
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family

  property string agentName: ""
  property string agentModel: ""
  property string liveModel: ""
  readonly property string headerText: {
    var name = root.agentName !== "" ? root.agentName : "…"
    var model = root.liveModel !== "" ? root.liveModel : root.agentModel
    return model !== "" ? name + " · " + model : name
  }
  property bool busy: askProc.running

  readonly property string scriptPath: String(Qt.resolvedUrl("ask.sh")).replace(/^file:\/\//, "")
  readonly property string modelScriptPath: String(Qt.resolvedUrl("model.sh")).replace(/^file:\/\//, "")

  function open() {
    root.controller.show()
    refreshAgent()
    Qt.callLater(function() { input.forceActiveFocus() })
  }

  function close() {
    root.controller.hide()
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
    input.clear()
    input.forceActiveFocus()
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
    historyModel.append({ question: question, answer: "", pending: true, qtime: stampNow(), atime: "" })
    historyList.positionViewAtEnd()
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
    var stick = historyList.atYEnd
    historyModel.set(last, { question: current.question, answer: cleaned, pending: true, qtime: current.qtime, atime: current.atime })
    if (stick) historyList.positionViewAtEnd()
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
    Qt.callLater(function() { historyList.positionViewAtEnd() })
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

  // Debounces chunk → UI updates during streaming.
  Timer {
    id: flushTimer
    interval: 80
    onTriggered: root.pushStream(root.stagedStream)
  }

  // Spawn watchdog: if the process never started (bad path, missing
  // binary), surface it instead of hanging on "pensando…" forever.
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

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(440))
    contentHeight: panel.fittedContentHeight(bodyColumn.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: input.activeFocus
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: bodyColumn
        width: parent.width
        spacing: Style.space(10)

        Row {
          width: parent.width
          height: Math.max(agentLabel.implicitHeight, newButton.height, termButton.height)
          spacing: Style.space(8)

          Text {
            id: agentLabel
            textFormat: Text.PlainText
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - newButton.width - termButton.width - parent.spacing * 2
            elide: Text.ElideRight
            text: "󰚩  " + root.headerText
            color: root.contentDim
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.caption
            font.letterSpacing: 1
          }

          PanelActionButton {
            id: newButton
            anchors.verticalCenter: parent.verticalCenter
            iconText: "+"
            tooltipText: "Nova conversa (limpa o histórico)"
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily
            onClicked: root.newConversation()
          }

          PanelActionButton {
            id: termButton
            anchors.verticalCenter: parent.verticalCenter
            iconText: "󰆍"
            tooltipText: "Abrir agente no terminal"
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily
            onClicked: root.openInTerminal()
          }
        }

        Item {
          width: parent.width
          height: Style.space(280)

          ListView {
            id: historyList
            anchors.fill: parent
            clip: true
            model: historyModel
            spacing: Style.space(14)
            onCountChanged: Qt.callLater(function() { historyList.positionViewAtEnd() })

            delegate: Column {
              required property string question
              required property string answer
              required property bool pending
              required property string qtime
              required property string atime

              readonly property color userFill: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.16)
              readonly property string agentCaption: (root.agentName !== "" ? root.agentName : "agente").toUpperCase() + (atime !== "" ? " · " + atime : "")
              readonly property string userCaption: "VOCÊ" + (qtime !== "" ? " · " + qtime : "")

              width: historyList.width
              spacing: Style.space(4)

              // ---- user message: caption + right-aligned bubble
              Text {
                textFormat: Text.PlainText
                anchors.right: parent.right
                text: userCaption
                color: root.contentDim
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.caption
                font.letterSpacing: 1
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
                  color: root.contentForeground
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.body
                }
              }

              // ---- agent answer: caption + left accent bar + body
              Text {
                textFormat: Text.PlainText
                visible: !pending || answer !== ""
                text: agentCaption
                color: root.contentDim
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.caption
                font.letterSpacing: 1
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
                  color: root.contentForeground
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.body
                }
              }

              Text {
                visible: pending && answer === ""
                textFormat: Text.PlainText
                text: "pensando…"
                color: root.contentDim
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.body
                opacity: 0.7
              }
            }
          }

          Text {
            anchors.centerIn: parent
            visible: historyModel.count === 0
            textFormat: Text.PlainText
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            width: parent.width - Style.space(40)
            text: "Pergunte algo rápido ao agente.\nEnter envia · Esc fecha."
            color: root.contentDim
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.body
          }
        }

        Row {
          width: parent.width
          spacing: Style.space(8)

          TextField {
            id: input
            width: parent.width - sendButton.width - parent.spacing
            placeholderText: root.busy ? "Aguarde a resposta…" : "Pergunte ao agente…"
            enabled: !root.busy
            font.family: root.contentFontFamily
            foreground: root.contentForeground
            onAccepted: root.send()
            Keys.onEscapePressed: root.close()
          }

          Button {
            id: sendButton
            text: root.busy ? "…" : "Enviar"
            enabled: !root.busy && input.text.trim() !== ""
            foreground: root.contentForeground
            onClicked: root.send()
          }
        }
      }
    }
  }
}
