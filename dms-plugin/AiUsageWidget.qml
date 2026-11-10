import QtQuick
import Quickshell
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    layerNamespacePlugin: "ai-usage"

    property var accounts: []
    property string generatedAt: ""
    property int refreshSeconds: 600
    property bool loadFailed: false
    // Why the last refresh failed ("proxy unavailable", "no config"), or "".
    property string lastError: ""
    property bool refreshInProgress: false
    property real refreshStartedMs: 0
    // The clock behind the countdowns; it only ticks while the popout is open.
    property real nowMs: Date.now()
    property string collectorPath: Quickshell.env("HOME") + "/.local/bin/dux-ai-usage"

    // Active subscriptions first; accounts disabled in the proxy sink to the end.
    readonly property var sortedAccounts: {
        const all = root.providerAccounts("claude").concat(root.providerAccounts("codex"))
        return all.filter(account => !root.isDisabled(account))
            .concat(all.filter(account => root.isDisabled(account)))
    }

    function refreshUsage() {
        // One run at a time. If a run never reports back (the collector could not
        // even start), stop waiting for it after 8 minutes; a real run is done
        // well before that.
        if (root.refreshInProgress && Date.now() - root.refreshStartedMs < 480000)
            return
        root.refreshInProgress = true
        root.refreshStartedMs = Date.now()
        Proc.runCommand(
            null,
            [root.collectorPath, "--cached"],
            (stdout, exitCode) => {
                root.refreshInProgress = false
                root.nowMs = Date.now()
                if (exitCode !== 0 && !stdout.trim()) {
                    root.loadFailed = true
                    root.lastError = "collector failed"
                    return
                }
                try {
                    const payload = JSON.parse(stdout.trim())
                    root.loadFailed = exitCode !== 0 || Boolean(payload.error)
                    root.lastError = String(payload.error || (exitCode !== 0 ? "collector failed" : "")).replace(/_/g, " ")
                    // A run that could not even read its config has no accounts to
                    // offer: keep showing the ones we have.
                    if (Array.isArray(payload.accounts) && (payload.accounts.length > 0 || !root.loadFailed))
                        root.accounts = payload.accounts
                    if (payload.generated_at)
                        root.generatedAt = payload.generated_at
                    if (payload.refresh_seconds >= 30)
                        root.refreshSeconds = payload.refresh_seconds
                } catch (error) {
                    root.loadFailed = true
                    root.lastError = "collector failed"
                }
            },
            100,
            -1, // The collector bounds provider requests and SSH itself.
            root
        )
    }

    function isDisabled(account) {
        return Boolean(account) && account.status === "disabled"
    }

    function isReachable(account) {
        return account.status === "ok" || account.status === "stale"
    }

    function isConnected(account) {
        return root.isReachable(account) && root.windowsOf(account).length > 0
    }

    // Full email when the collector knows it, else its neutral label.
    function displayName(account) {
        const email = String(account && account.email || "").trim()
        if (email.length > 0)
            return email
        const label = String(account && account.label || "").trim()
        return label.length > 0 ? label : "Unnamed account"
    }

    function providerAccounts(provider) {
        return accounts
            .filter(account => account.provider === provider)
            .sort((left, right) => root.displayName(left).localeCompare(root.displayName(right)))
    }

    // Accounts crossing a Repeater arrive as QVariantMaps: windows becomes a
    // QVariantList, which fails Array.isArray. Iterate by length instead, and
    // drop hidden quotas defensively, including from an older cache.
    function windowsOf(account) {
        const raw = account ? account.windows : undefined
        if (!raw || typeof raw.length !== "number")
            return []
        const result = []
        for (let i = 0; i < raw.length; i++) {
            const item = raw[i]
            if (!item)
                continue
            const text = (String(item.id || "") + " " + String(item.label || "")).toLowerCase()
            if (text.indexOf("spark") !== -1)
                continue
            if (account.provider === "codex"
                    && (text.indexOf("gpt-reserve") !== -1 || text.indexOf("base_model_inference") !== -1))
                continue
            if (account.provider === "codex" && item.label !== "7d")
                continue
            if (account.provider === "claude" && item.id !== "five_hour" && item.id !== "seven_day")
                continue
            result.push(item)
        }
        return result
    }

    function labeledWindow(account, label) {
        for (const item of root.windowsOf(account)) {
            if (item.label === label)
                return item
        }
        return null
    }

    // remaining_percent may be a QVariant-wrapped number; Number() + isFinite
    // is the only conversion that survives every wrapping.
    function remainingOf(item) {
        if (!item)
            return -1
        const raw = item.remaining_percent
        if (raw === undefined || raw === null || raw === "")
            return -1
        const value = Number(raw)
        return isFinite(value) ? value : -1
    }

    function percentText(item) {
        const remaining = root.remainingOf(item)
        return remaining < 0 ? "–" : Math.round(remaining) + "%"
    }

    function statusColor(remaining) {
        if (remaining < 0)
            return Theme.surfaceVariantText
        if (remaining <= 15)
            return Theme.error
        if (remaining <= 35)
            return Theme.warning
        return Theme.primary
    }

    function statusText(account) {
        if (account.status === "ok")
            return root.windowsOf(account).length > 0 ? "" : "no usage data"
        if (account.status === "stale") {
            // Say why it is old, and how old.
            const why = String(account.error || "").replace(/_/g, " ")
            const age = root.agoText(account.updated_at)
            return ["stale", why, age].filter(part => part.length > 0).join(" · ")
        }
        const status = String(account.status || "unavailable").replace(/_/g, " ")
        const error = String(account.error || "").replace(/_/g, " ")
        return error.length > 0 && error !== status ? status + " · " + error : status
    }

    // Shortest window first, named the way Claude's own /usage names them.
    function limitsOf(account) {
        const result = []
        const session = root.labeledWindow(account, "5h")
        const week = root.labeledWindow(account, "7d")
        if (session)
            result.push({ name: "Session", data: session })
        if (week)
            result.push({ name: "Week", data: week })
        return result
    }

    // "12m ago", "3h ago", "9d ago" for an ISO time; "" when unknown.
    function agoText(iso) {
        const then = iso ? new Date(iso).getTime() : NaN
        if (isNaN(then))
            return ""
        const minutes = Math.max(0, Math.floor((root.nowMs - then) / 60000))
        if (minutes < 60)
            return minutes + "m ago"
        const hours = Math.floor(minutes / 60)
        return hours < 24 ? hours + "h ago" : Math.floor(hours / 24) + "d ago"
    }

    // Language-neutral countdown ("57m", "5d 17h"), counted from root.nowMs so it
    // stays right while the popout is open.
    function resetIn(item) {
        const value = item ? item.resets_at : undefined
        if (value === undefined || value === null || value === "")
            return ""
        const numeric = Number(value)
        const date = isFinite(numeric) && typeof value !== "string"
            ? new Date(numeric * 1000)
            : new Date(value)
        if (isNaN(date.getTime()))
            return ""
        const minutes = Math.floor((date.getTime() - root.nowMs) / 60000)
        if (minutes <= 0)
            return "now"
        if (minutes < 60)
            return minutes + "m"
        const hours = Math.floor(minutes / 60)
        if (hours < 24)
            return hours + "h " + (minutes % 60) + "m"
        return Math.floor(hours / 24) + "d " + (hours % 24) + "h"
    }

    component CapacityMeter: Rectangle {
        id: meterRoot

        property real value: -1
        property color meterColor: Theme.primary
        property color trackColor: Theme.withAlpha(meterColor, 0.18)

        height: 6
        radius: height / 2
        color: trackColor

        Rectangle {
            width: meterRoot.value >= 0
                ? meterRoot.width * Math.max(0, Math.min(100, meterRoot.value)) / 100
                : 0
            height: parent.height
            radius: parent.radius
            color: meterRoot.meterColor
        }
    }

    component ProviderIcon: Item {
        id: providerIconRoot

        property string provider
        property real size: Theme.iconSizeSmall

        width: size
        height: size

        // The apps' own icons when they are installed...
        readonly property string iconSource: Quickshell.iconPath(provider === "claude" ? "claude-desktop" : "chatgpt", true)

        Image {
            anchors.fill: parent
            visible: providerIconRoot.iconSource !== ""
            source: providerIconRoot.iconSource
            sourceSize.width: 32
            sourceSize.height: 32
            fillMode: Image.PreserveAspectFit
            smooth: true
            mipmap: true
        }

        // ...else a letter, so Claude and Codex rows can still be told apart.
        Rectangle {
            anchors.fill: parent
            visible: providerIconRoot.iconSource === ""
            radius: 4
            color: Theme.withAlpha(Theme.primary, 0.18)

            StyledText {
                anchors.centerIn: parent
                text: providerIconRoot.provider === "claude" ? "C" : "X"
                font.pixelSize: Math.round(providerIconRoot.size * 0.6)
                font.weight: Font.Medium
                color: Theme.primary
            }
        }
    }

    // The bar shows a single agent icon; every account lives in the popout.
    // A bot after Lucide's (ISC), redrawn on a 20 px grid and rendered 1:1:
    // 2 px strokes on whole-pixel centers keep every edge sharp. Painted
    // directly in the theme color, since a tint effect greys thin strokes.
    component AgentIcon: Item {
        id: agentIconRoot

        readonly property color iconColor: root.loadFailed ? Theme.error : Theme.widgetIconColor
        readonly property string svg: '<svg xmlns="http://www.w3.org/2000/svg" width="20" height="20"'
            + ' viewBox="0 0 20 20" fill="none" stroke="' + agentIconRoot.iconColor.toString() + '"'
            + ' stroke-width="2" stroke-linecap="round" stroke-linejoin="round">'
            + '<path d="M10 7V3H7"/><rect x="3" y="7" width="14" height="10" rx="2"/>'
            + '<path d="M1 12h2"/><path d="M17 12h2"/><path d="M7 11v2"/><path d="M13 11v2"/></svg>'

        implicitWidth: 20
        implicitHeight: 20

        Image {
            width: 20
            height: 20
            source: "data:image/svg+xml;utf8," + encodeURIComponent(agentIconRoot.svg)
            sourceSize.width: 20
            sourceSize.height: 20
            smooth: false
        }
    }

    // One quota per line, laid out as a table: name, meter, percent, reset.
    component LimitRow: Row {
        id: limitRoot

        property string name
        property var windowData
        readonly property real remaining: root.remainingOf(windowData)
        // The columns are sized for a 12 px font; they grow with the font setting.
        readonly property real fontScale: Math.max(1, Theme.fontSizeSmall / 12)
        readonly property real nameWidth: Math.ceil(48 * fontScale)
        readonly property real percentWidth: Math.ceil(36 * fontScale)
        readonly property real resetWidth: Math.ceil(56 * fontScale)

        spacing: Theme.spacingM

        StyledText {
            width: limitRoot.nameWidth
            text: limitRoot.name
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            anchors.verticalCenter: parent.verticalCenter
        }

        CapacityMeter {
            width: Math.max(0, limitRoot.width - limitRoot.nameWidth - limitRoot.percentWidth - limitRoot.resetWidth - limitRoot.spacing * 3)
            height: 4
            value: limitRoot.remaining
            meterColor: root.statusColor(limitRoot.remaining)
            trackColor: Theme.withAlpha(Theme.surfaceText, 0.08)
            anchors.verticalCenter: parent.verticalCenter
        }

        StyledText {
            width: limitRoot.percentWidth
            text: root.percentText(limitRoot.windowData)
            font.pixelSize: Theme.fontSizeSmall
            font.features: { "tnum": 1 }
            color: Theme.surfaceText
            horizontalAlignment: Text.AlignRight
            anchors.verticalCenter: parent.verticalCenter
        }

        StyledText {
            width: limitRoot.resetWidth
            text: root.resetIn(limitRoot.windowData)
            font.pixelSize: Theme.fontSizeSmall
            font.features: { "tnum": 1 }
            color: Theme.surfaceVariantText
            horizontalAlignment: Text.AlignRight
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    // Disabled accounts take one dim line: no quota, just the name.
    component DisabledRow: Row {
        id: disabledRoot

        property var account

        spacing: Theme.spacingS
        opacity: 0.5

        ProviderIcon {
            id: disabledIcon

            provider: disabledRoot.account.provider
            anchors.verticalCenter: parent.verticalCenter
        }

        StyledText {
            width: disabledRoot.width - disabledIcon.width - disabledTag.implicitWidth - disabledRoot.spacing * 2
            text: root.displayName(disabledRoot.account)
            textFormat: Text.PlainText
            font.pixelSize: Theme.fontSizeMedium
            font.weight: Font.Medium
            color: Theme.surfaceText
            elide: Text.ElideRight
            anchors.verticalCenter: parent.verticalCenter
        }

        StyledText {
            id: disabledTag

            text: "disabled"
            font.pixelSize: Theme.fontSizeMedium
            color: Theme.surfaceVariantText
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    component AccountSection: Column {
        id: sectionRoot

        property var account
        readonly property bool connected: root.isConnected(account)
        readonly property string status: root.statusText(account)

        spacing: Theme.spacingXS + 2

        // Emails wrap anywhere so the full address is always readable.
        Row {
            width: parent.width
            spacing: Theme.spacingS
            opacity: root.isReachable(sectionRoot.account) ? 1 : 0.6

            ProviderIcon {
                id: sectionIcon

                provider: sectionRoot.account.provider
                y: Math.max(0, (nameText.lineHeightPx - height) / 2)
            }

            Column {
                width: parent.width - sectionIcon.width - parent.spacing
                spacing: 1

                StyledText {
                    id: nameText

                    readonly property real lineHeightPx: font.pixelSize * 1.3

                    width: parent.width
                    text: root.displayName(sectionRoot.account)
                    textFormat: Text.PlainText
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight: Font.Medium
                    color: Theme.surfaceText
                    wrapMode: Text.WrapAnywhere
                }

                StyledText {
                    visible: sectionRoot.status.length > 0
                    width: parent.width
                    text: sectionRoot.status
                    textFormat: Text.PlainText
                    font.pixelSize: Theme.fontSizeSmall
                    color: sectionRoot.account.status === "stale" ? Theme.warning
                        : root.isReachable(sectionRoot.account) ? Theme.surfaceVariantText : Theme.error
                    wrapMode: Text.Wrap
                }
            }
        }

        // Indented so quota names line up under the email.
        Column {
            visible: sectionRoot.connected
            x: Theme.iconSizeSmall + Theme.spacingS
            width: parent.width - x
            spacing: Theme.spacingXS + 2

            Repeater {
                model: sectionRoot.connected ? root.limitsOf(sectionRoot.account) : []

                delegate: LimitRow {
                    required property var modelData

                    width: parent.width
                    name: modelData.name
                    windowData: modelData.data
                }
            }
        }
    }

    Timer {
        interval: root.refreshSeconds * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refreshUsage()
    }

    // Opening the popout shows current numbers: refresh, and keep the countdowns
    // moving while it is open.
    onInteractionActiveChanged: {
        if (root.interactionActive) {
            root.nowMs = Date.now()
            root.refreshUsage()
        }
    }

    Timer {
        interval: 30000
        repeat: true
        running: root.interactionActive
        onTriggered: root.nowMs = Date.now()
    }

    horizontalBarPill: Component {
        AgentIcon {}
    }

    verticalBarPill: Component {
        AgentIcon {}
    }

    popoutContent: Component {
        PopoutComponent {
            id: popout

            // Grow with the account list, then scroll instead of leaving the screen.
            readonly property real maxListHeight: Math.max(240,
                (popout.parentPopout && popout.parentPopout.screen ? popout.parentPopout.screen.height : 1080) * 0.7)

            Flickable {
                id: listFlick

                width: parent.width
                implicitHeight: Math.min(contentColumn.implicitHeight + Theme.spacingS * 2, popout.maxListHeight)
                contentWidth: width
                contentHeight: contentColumn.implicitHeight + Theme.spacingS * 2
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                interactive: contentHeight > height

                // Clicking anywhere outside a scroll gesture closes the popout.
                MouseArea {
                    width: listFlick.contentWidth
                    height: listFlick.contentHeight
                    acceptedButtons: Qt.AllButtons
                    onClicked: root.closePopout()
                }

                Column {
                    id: contentColumn

                    readonly property var sections: root.sortedAccounts

                    x: Theme.spacingS
                    y: Theme.spacingS
                    width: listFlick.width - Theme.spacingS * 2 - (scrollBar.visible ? scrollBar.width : 0)

                    // The whole refresh failed: say so above the (old) numbers.
                    StyledText {
                        visible: root.loadFailed && root.accounts.length > 0
                        width: parent.width
                        bottomPadding: Theme.spacingS
                        text: "Can't refresh" + (root.lastError.length > 0 ? " · " + root.lastError : "")
                            + (root.agoText(root.generatedAt).length > 0 ? " · last try " + root.agoText(root.generatedAt) : "")
                        textFormat: Text.PlainText
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.error
                        wrapMode: Text.Wrap
                    }

                    Repeater {
                        model: contentColumn.sections

                        delegate: Column {
                            id: sectionDelegate

                            required property var modelData
                            required property int index

                            readonly property bool disabled: root.isDisabled(modelData)
                            readonly property bool afterDisabled: index > 0
                                && root.isDisabled(contentColumn.sections[index - 1])

                            width: parent.width

                            // Disabled rows share one divider above the group.
                            Rectangle {
                                visible: sectionDelegate.index > 0 && !sectionDelegate.afterDisabled
                                width: parent.width
                                height: 1
                                color: Theme.withAlpha(Theme.outline, 0.2)
                            }

                            AccountSection {
                                visible: !sectionDelegate.disabled
                                width: parent.width
                                account: sectionDelegate.modelData
                                topPadding: sectionDelegate.index > 0 ? Theme.spacingS + 2 : 0
                                bottomPadding: sectionDelegate.index < contentColumn.sections.length - 1 ? Theme.spacingS + 2 : 0
                            }

                            Item {
                                visible: sectionDelegate.disabled
                                width: parent.width
                                height: disabledRow.implicitHeight
                                    + (sectionDelegate.afterDisabled ? Theme.spacingXS : Theme.spacingS)

                                DisabledRow {
                                    id: disabledRow

                                    width: parent.width
                                    y: parent.height - implicitHeight
                                    account: sectionDelegate.modelData
                                }
                            }
                        }
                    }

                    StyledText {
                        visible: root.accounts.length === 0
                        width: parent.width
                        text: root.loadFailed ? "Can't load usage" + (root.lastError.length > 0 ? " · " + root.lastError : "")
                            : root.generatedAt === "" ? "Loading…"
                            : "No subscriptions found"
                        font.pixelSize: Theme.fontSizeMedium
                        color: root.loadFailed ? Theme.error : Theme.surfaceVariantText
                        wrapMode: Text.Wrap
                    }
                }

                Rectangle {
                    id: scrollBar

                    visible: listFlick.interactive
                    x: listFlick.width - width
                    y: listFlick.contentY + listFlick.visibleArea.yPosition * listFlick.height
                    width: 3
                    height: listFlick.visibleArea.heightRatio * listFlick.height
                    radius: width / 2
                    color: Theme.withAlpha(Theme.surfaceText, 0.3)
                }
            }
        }
    }

    popoutWidth: 380
}
