import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.modules.common.functions

Item {
    id: root
    property real spacing: 8
    property color backgroundColor: "transparent"
    property bool showAddDialog: false
    property int dialogMargins: 20
    property int fabSize: 48
    property int fabMargins: 14

    property int startHour: 0
    property int startMinute: 0
    property int endHour: 24
    property int slotDuration: 60 // in minutes
    property int slotHeight: 60 // in pixels
    property int timeColumnWidth: 100
    property real maxContentWidth: 2000

    readonly property int totalSlots: Math.floor(((endHour * 60) - (startHour * 60 + startMinute)) / slotDuration)
    readonly property real pixelsPerMinute: slotHeight / slotDuration
    readonly property int contentHeight: totalSlots * slotHeight

    property real maxHeight: 700
    property real headerHeight: 64 // Material 3 standard header height
    property real currentTimeY: -1
    property bool initialScrollApplied: false
    readonly property real dayColumnWidth: Math.min(180, (maxContentWidth - timeColumnWidth - (days.length + 1) * spacing) / days.length)
//   readonly property int currentDayIndex: (DateTime.clock.date.getDay() - Config.options.time.firstDayOfWeek+ 6)%7
    readonly property int currentDayIndex: (DateTime.clock.date.getDay() - Config.options.time.firstDayOfWeek + 7) % 7

    implicitWidth: Math.min(maxContentWidth, timeColumnWidth + (dayColumnWidth * days.length) + ((days.length + 1) * spacing))
    implicitHeight: Math.min(headerHeight + contentHeight, maxHeight)
    property var days: CalendarService.eventsInWeek
    readonly property int allDayChipHeight: 36
    readonly property int allDayChipSpacing: 6
    readonly property int maxAllDayEventCount: {
        if (!root.days || root.days.length === 0)
            return 0;

        var maxCount = 0;
        for (var i = 0; i < root.days.length; i++) {
            var day = root.days[i];
            if (!day || !day.events)
                continue;

            var count = 0;
            for (var j = 0; j < day.events.length; j++) {
                if (root.isAllDayEvent(day.events[j]))
                    count++;
            }
            if (count > maxCount)
                maxCount = count;
        }
        return maxCount;
    }
    readonly property bool hasAllDayEvents: maxAllDayEventCount > 0
    readonly property color todayHighlightFill: withOpacity(Appearance.colors.colPrimary, 0.12)
    readonly property color todayHighlightBorder: withOpacity(Appearance.colors.colPrimary, 0.28)

    function updateCurrentTimeLine() {
        let time = DateTime.clock.date;
        let hours = time.getHours();
        let minutes = time.getMinutes();

        let baseTotalMinutes = root.startHour * 60 + root.startMinute;
        let currentTotalMinutes = hours * 60 + minutes;
        let diffMinutes = currentTotalMinutes - baseTotalMinutes;

        currentTimeY = diffMinutes * root.pixelsPerMinute;
    }

  

    function withOpacity(colorValue, alpha) {
        if (!colorValue)
            return Qt.rgba(0, 0, 0, alpha);

        let color = Qt.color(colorValue);
        return Qt.rgba(color.r, color.g, color.b, alpha);
    }

    function isAllDayEvent(event) {
        if (!event)
            return false;

        let start = event.start || "";
        let end = event.end || "";

        return (start === "00:00" && end === "23:59") ||
               (start === "00:00" && end === "00:00") ||
               (!event.start && !event.end);
    }

    function getAllDayEvents(events) {
        if (!events || !events.length)
            return [];

        return events.filter(function(evt) { return root.isAllDayEvent(evt); });
    }

    function getTimedEvents(events) {
        if (!events || !events.length)
            return [];

        return events.filter(function(evt) { return !root.isAllDayEvent(evt); });
    }

    // Groups overlapping events into clusters, then greedily assigns each
    // event a column within its cluster (classic "meeting rooms" layout,
    // same technique Google Calendar uses). Returns each event annotated
    // with .col (its column index) and .cols (total columns in its cluster).
    function layoutOverlaps(events) {
        if (!events || events.length === 0)
            return [];

        let items = events.map(function(e) {
            return { "ref": e, "startMin": root.parseTimeToMinutes(e.start), "endMin": root.parseTimeToMinutes(e.end) };
        }).filter(function(e) { return e.startMin !== null && e.endMin !== null; });

        items.sort(function(a, b) { return a.startMin - b.startMin; });

        let clusters = [];
        let current = [];
        let clusterEnd = -1;
        for (const item of items) {
            if (current.length === 0 || item.startMin < clusterEnd) {
                current.push(item);
                clusterEnd = Math.max(clusterEnd, item.endMin);
            } else {
                clusters.push(current);
                current = [item];
                clusterEnd = item.endMin;
            }
        }
        if (current.length > 0) clusters.push(current);

        let results = [];
        for (const cluster of clusters) {
            let columnEnds = []; // end time currently occupying each column
            let placements = [];
            for (const item of cluster) {
                let placedCol = -1;
                for (let c = 0; c < columnEnds.length; c++) {
                    if (columnEnds[c] <= item.startMin) {
                        placedCol = c;
                        break;
                    }
                }
                if (placedCol === -1) {
                    placedCol = columnEnds.length;
                    columnEnds.push(item.endMin);
                } else {
                    columnEnds[placedCol] = item.endMin;
                }
                placements.push({ "item": item, "col": placedCol });
            }
            const totalCols = columnEnds.length;
            for (const p of placements) {
                let merged = Object.assign({}, p.item.ref);
                merged.col = p.col;
                merged.cols = totalCols;
                results.push(merged);
            }
        }
        return results;
    }

    function formatEventTooltip(event) {
        if (!event)
            return "";

        let title = event.title || qsTr("Event");
        if (root.isAllDayEvent(event))
            return title + "\n" + qsTr("All day");

        let startTotal = root.parseTimeToMinutes(event.start);
        let endTotal = root.parseTimeToMinutes(event.end);

        let formatTime = (totalMinutes) => {
            if (totalMinutes === null)
                return "";
            let hour = Math.floor(totalMinutes / 60);
            let minute = totalMinutes % 60;
            let date = new Date();
            date.setHours(hour, minute, 0, 0);
            return Qt.formatTime(date, Config.options?.time.format ?? "hh:mm");
        };

        let startStr = formatTime(startTotal) || event.start || "";
        let endStr = formatTime(endTotal) || event.end || "";
        let range = startStr && endStr ? startStr + " - " + endStr : startStr || endStr;
        return range ? title + "\n" + range : title;
    }

    function parseTimeToMinutes(timeStr) {
        if (!timeStr)
            return null;
        let parts = timeStr.split(":");
        if (parts.length < 2)
            return null;
        let hour = parseInt(parts[0]);
        let minute = parseInt(parts[1]);
        if (isNaN(hour) || isNaN(minute))
            return null;
        return hour * 60 + minute;
    }

    function earliestEventStartMinutes() {
        if (!root.days || root.days.length === 0)
            return -1;

        var earliest = -1;
        for (var i = 0; i < root.days.length; i++) {
            var timed = root.getTimedEvents(root.days[i]?.events);
            for (var j = 0; j < timed.length; j++) {
                var start = root.parseTimeToMinutes(timed[j].start);
                if (start === null)
                    continue;
                if (earliest === -1 || start < earliest)
                    earliest = start;
            }
        }
        return earliest;
    }

    function scrollToFirstEvent() {
        if (!styledFlickable)
            return;

        let earliest = root.earliestEventStartMinutes();
        let minOfDay = earliest;

        if (minOfDay === -1 || minOfDay <= (root.startHour * 60 + root.startMinute)) {
            styledFlickable.contentY = 0;
            return;
        }

        let diff = minOfDay - (root.startHour * 60 + root.startMinute);
        if (diff < 0)
            diff = 0;

        let targetY = diff * root.pixelsPerMinute - root.slotHeight;
        targetY = Math.max(0, targetY);

        let maxScroll = Math.max(0, styledFlickable.contentHeight - styledFlickable.height);
        if (styledFlickable.height <= 0) {
            Qt.callLater(root.scrollToFirstEvent);
            return;
        }
        styledFlickable.contentY = Math.min(targetY, maxScroll);
    }

    function maybeApplyInitialScroll() {
        if (root.initialScrollApplied)
            return;

        if (!styledFlickable || styledFlickable.height <= 0 || !root.days || root.days.length === 0) {
            Qt.callLater(root.maybeApplyInitialScroll);
            return;
        }

        root.scrollToFirstEvent();
        root.initialScrollApplied = true;
    }

    Connections {
        target: DateTime.clock
        function onDateChanged() {
            root.updateCurrentTimeLine();
        }
    }

    Connections {
        target: CalendarService
        function onEventsInWeekChanged() {
            Qt.callLater(root.maybeApplyInitialScroll);
        }
    }

    Component.onCompleted: {
        root.updateCurrentTimeLine();
        Qt.callLater(root.maybeApplyInitialScroll);
    }

    // Material 3 surface container
    Rectangle {
        anchors.fill: parent
        color: Appearance.colors.colSurfaceContainer
        radius: Appearance.rounding.large
        border.width: 1
        border.color: Appearance.colors.colOutlineVariant
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        Row {
            id: headerRow
            Layout.fillWidth: true
            Layout.preferredHeight: root.headerHeight
            spacing: root.spacing

            Item {
                width: root.timeColumnWidth
                height: root.headerHeight

                // Current time indicator
                Rectangle {
                    anchors.centerIn: parent
                    width: Math.min(timeHeaderText.implicitWidth + 16, parent.width - 4)
                    height: 32
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.colSecondaryContainer

                    StyledText {
                        id: timeHeaderText
                        anchors.centerIn: parent
                        text: DateTime.time
                        font.weight: Font.Medium
                        color: Appearance.colors.colOnSecondaryContainer
                        elide: Text.ElideRight
                    }
                }
            }

            Repeater {
                model: root.days
                delegate: Item {
                    width: root.dayColumnWidth
                    height: root.headerHeight

                    property var allDayEvents: root.getAllDayEvents(modelData.events)
                    property bool isToday: index === root.currentDayIndex

                    Rectangle {
                        anchors.centerIn: parent
                        width: parent.width - 4
                        height: 40
                        radius: Appearance.rounding.large
                        border.width: allDayEvents.length > 0 ? 2 : 0
                        border.color: Appearance.colors.colPrimary
                        color: isToday ? Appearance.colors.colPrimaryContainer : Appearance.colors.colSurfaceContainerHigh
                        StyledText {
                            id: dayTitle
                            anchors.centerIn: parent
                            font.weight: Font.Medium
                            color: Appearance.colors.colOnSurfaceVariant
                            text: modelData.name
                            elide: Text.ElideRight
                          }
                            
                         HoverHandler {
                                        id: allDayHover
                          }
        

                         Column {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: parent.width - 4
                            spacing: root.allDayChipSpacing

                            Repeater {
                                model: allDayEvents
                                delegate: Rectangle {
                                    width: parent.width
                                    height: root.allDayChipHeight
                                    color: 'transparent' 

                                   

                                    ToolTip {
                                        visible: allDayHover.hovered
                                        delay: 250
                                        timeout: 0
                                        text: root.formatEventTooltip(modelData)
                                    }

                                }
                            }
                        }
                    }
                    }
            }
        }

     

        // Subtle separator
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: Appearance.colors.colOutlineVariant
            Layout.bottomMargin: 8
        }

        // TODO: replace or check for StyledScrollBar
        StyledFlickable {
            id: styledFlickable
            Layout.fillWidth: true
            Layout.fillHeight: true

            clip: true
            contentWidth: width
            contentHeight: root.contentHeight
            topMargin: 20
            bottomMargin: 20

            Row {
                id: contentRow
                spacing: root.spacing

                Column {
                    id: timeColumn
                    width: root.timeColumnWidth

                    Repeater {
                        model: root.totalSlots
                        delegate: Item {
                            width: parent.width
                            height: root.slotHeight

                            StyledText {
                                text: {
                                    let totalMinutes = root.startMinute + (index * root.slotDuration);
                                    let hour = root.startHour + Math.floor(totalMinutes / 60);
                                    let minute = totalMinutes % 60;

                                    // Format time based on DateTime format
                                    let testDate = new Date();
                                    testDate.setHours(hour, minute, 0);
                                    return Qt.formatTime(testDate, Config.options?.time.format ?? "hh:mm");
                                }
                                anchors.top: parent.top
                                anchors.topMargin: -font.pixelSize / 2
                                anchors.horizontalCenter: parent.horizontalCenter
                                font.weight: Font.Medium
                                color: Appearance.colors.colOnSurfaceVariant
                                elide: Text.ElideRight
                            }
                        }
                    }
                }

                Row {
                    id: eventsRow
                    height: root.contentHeight
                    spacing: root.spacing

                    Repeater {
                        model: root.days
                        delegate: Item {
                            width: root.dayColumnWidth
                            height: parent.height
                            clip: true
                            property bool isToday: index === root.currentDayIndex
                            property var timedEvents: root.getTimedEvents(modelData.events)

                            Rectangle {
                                anchors.fill: parent
                                radius: Appearance.rounding.large
                                color: isToday ? root.todayHighlightFill : Qt.rgba(0, 0, 0, 0)
                                border.width: isToday ? 1 : 0
                                border.color: isToday ? root.todayHighlightBorder : Qt.rgba(0, 0, 0, 0)
                                z: -1
                            }

                            Repeater {
                                model: root.layoutOverlaps(timedEvents)
                                Rectangle {
                                    property real trackWidth: parent.width - 10
                                    property real colWidth: trackWidth / modelData.cols
                                    width: colWidth - (modelData.cols > 1 ? 3 : 0)
                                    x: 5 + modelData.col * colWidth
                                    radius: Appearance.rounding.large
                                    clip: true
                                    y: {
                                        let startHr = parseInt(modelData.start.split(":")[0]);
                                        let startMin = parseInt(modelData.start.split(":")[1]);
                                        let baseTotalMinutes = root.startHour * 60 + root.startMinute;
                                        let eventTotalMinutes = startHr * 60 + startMin;
                                        let diffMinutes = eventTotalMinutes - baseTotalMinutes;
                                        return diffMinutes * root.pixelsPerMinute;
                                    }
                                    height: {
                                        let startHr = parseInt(modelData.start.split(":")[0]);
                                        let endHr = parseInt(modelData.end.split(":")[0]);
                                        let startMin = parseInt(modelData.start.split(":")[1]);
                                        let endMin = parseInt(modelData.end.split(":")[1]);
                                        let totalMins = (endHr * 60 + endMin) - (startHr * 60 + startMin);
                                        return Math.max(totalMins * root.pixelsPerMinute - 4, 48); // Minimum height for touch targets
                                    }

                                   color: modelData.color || Appearance.colors.colTertiaryContainer

                                    HoverHandler {
                                        id: eventHover
                                    }

                                    ToolTip {
                                        visible: eventHover.hovered
                                        delay: 200
                                        timeout: 0
                                        text: root.formatEventTooltip(modelData)
                                    }

                                    Column {
                                        anchors.fill: parent
                                        anchors.margins: 12
                                        spacing: 4

                                        Text {
                                            text: {
                                                let startHr = parseInt(modelData.start.split(":")[0]);
                                                let startMin = parseInt(modelData.start.split(":")[1]);
                                                let endHr = parseInt(modelData.end.split(":")[0]);
                                                let endMin = parseInt(modelData.end.split(":")[1]);

                                                let formatTime = (hour, minute) => {
                                                    let testDate = new Date();
                                                    testDate.setHours(hour, minute, 0);
                                                    return Qt.formatTime(testDate, Config.options?.time.format ?? "hh:mm");
                                                };

                                                return formatTime(startHr, startMin) + " - " + formatTime(endHr, endMin);
                                            }
                                            font.weight: Font.Medium
                                            color: ColorUtils.getContrastingTextColor(modelData.color)
                                            width: parent.width
                                            wrapMode: Text.NoWrap
                                            elide: Text.ElideRight
                                            lineHeight: 1.2
                                        }

                                        Text {
                                            id: eventTitle
                                            text: modelData.title
                                            font.weight: Font.Medium
                                            wrapMode: Text.WordWrap
                                            elide: Text.ElideRight
                                            maximumLineCount: 2
                                            width: parent.width
                                            color: ColorUtils.getContrastingTextColor(modelData.color)
                                            lineHeight: 1.1
                                            visible: !truncated
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Rectangle {
                id: currentTimeLine
                width: contentRow.width
                height: 3
                color: Appearance.colors.colPrimary
                y: root.currentTimeY
                visible: root.currentTimeY >= 0 && root.currentTimeY <= contentRow.height
                z: 10
                radius: Appearance.rounding.unsharpen

                // Material 3 time chip
                Rectangle {
                    x: (timeColumn.width / 2) - (width / 2)
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(timeText.implicitWidth + 20, timeColumn.width - 4)
                    height: 32
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.colPrimary

                    Text {
                        id: timeText
                        anchors.centerIn: parent
                        text: DateTime.time
                        color: Appearance.colors.colOnPrimary
                        font.weight: Font.Medium
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }
    // + FAB to add an event
    StyledRectangularShadow {
        target: addEventFab
        radius: addEventFab.buttonRadius
        blur: 0.6 * Appearance.sizes.elevationMargin
    }
    FloatingActionButton {
        id: addEventFab
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: root.fabMargins
        anchors.bottomMargin: root.fabMargins
        onClicked: root.showAddDialog = true
        iconText: "add"
    }

    Item {
        anchors.fill: parent
        z: 9999
        visible: opacity > 0
        opacity: root.showAddDialog ? 1 : 0
        Behavior on opacity {
            NumberAnimation {
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Appearance.animation.elementMoveFast.type
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
        }

        onVisibleChanged: {
            if (!visible) {
                eventTitleInput.text = ""
                eventDescInput.text = ""
                customColorInput.text = ""
                addEventDialog.customMode = false
                addEventDialog.selectedColor = addEventDialog.colorOptions[0].hex
                addEventFab.focus = true
            }
        }

        Rectangle { // Scrim
            anchors.fill: parent
            radius: Appearance.rounding.small
            color: Appearance.colors.colScrim
            MouseArea {
                hoverEnabled: true
                anchors.fill: parent
                preventStealing: true
                propagateComposedEvents: false
                onClicked: root.showAddDialog = false
            }
        }

        Rectangle { // The dialog
            id: addEventDialog
            anchors.centerIn: parent
            width: Math.min(420, parent.width - root.dialogMargins * 2)
            implicitHeight: addEventColumnLayout.implicitHeight
            color: Appearance.m3colors.m3surfaceContainerHigh
            radius: Appearance.rounding.normal

            MouseArea { // Absorb clicks so they don't fall through to the scrim below
                anchors.fill: parent
                preventStealing: true
            }

            property string errorText: ""
            property var colorOptions: [
                { "name": Translation.tr("Blue"), "hex": "#039be5" },
                { "name": Translation.tr("Green"), "hex": "#33b679" },
                { "name": Translation.tr("Yellow"), "hex": "#f6bf26" },
                { "name": Translation.tr("Red"), "hex": "#d50000" }
            ]
            property string selectedColor: colorOptions[0].hex
            property bool customMode: false
            readonly property var hexPattern: /^#[0-9a-fA-F]{6}$/

            function isPreset(hex) {
                return addEventDialog.colorOptions.some(function(o) { return o.hex === hex; });
            }

            function parseDateTime(dateStr, timeStr) {
                const dp = dateStr.split("-");
                const tp = timeStr.split(":");
                if (dp.length !== 3 || tp.length !== 2) return null;
                const d = new Date(Number(dp[0]), Number(dp[1]) - 1, Number(dp[2]), Number(tp[0]), Number(tp[1]));
                return isNaN(d.getTime()) ? null : d;
            }

            function addEvent() {
                addEventDialog.errorText = "";
                if (eventTitleInput.text.length === 0) return;

                const start = addEventDialog.parseDateTime(startDateInput.text, startTimeInput.text);
                const end = addEventDialog.parseDateTime(endDateInput.text, endTimeInput.text);
                if (!start || !end) {
                    addEventDialog.errorText = Translation.tr("Enter valid dates as yyyy-MM-dd and times as hh:mm");
                    return;
                }
                if (end <= start) {
                    addEventDialog.errorText = Translation.tr("End must be after start");
                    return;
                }

                CalendarService.addLocalEvent(eventTitleInput.text, eventDescInput.text, start, end, addEventDialog.selectedColor);
                eventTitleInput.text = ""
                eventDescInput.text = ""
                customColorInput.text = ""
                addEventDialog.customMode = false
                addEventDialog.selectedColor = addEventDialog.colorOptions[0].hex
                root.showAddDialog = false
            }

            ColumnLayout {
                id: addEventColumnLayout
                anchors.fill: parent
                spacing: 24

                StyledText {
                    Layout.topMargin: 24
                    Layout.leftMargin: 20
                    Layout.rightMargin: 20
                    Layout.alignment: Qt.AlignLeft
                    color: Appearance.m3colors.m3onSurface
                    font.pixelSize: Appearance.font.pixelSize.larger
                    text: Translation.tr("Add event")
                }

                TextField {
                    id: eventTitleInput
                    Layout.fillWidth: true
                    Layout.leftMargin: 16
                    Layout.rightMargin: 16
                    implicitHeight: 44
                    padding: 9
                    placeholderText: Translation.tr("Title")
                    placeholderTextColor: Appearance.m3colors.m3outline
                    color: activeFocus ? Appearance.m3colors.m3onSurface : Appearance.m3colors.m3onSurfaceVariant
                    focus: root.showAddDialog
                    background: Rectangle {
                        anchors.fill: parent
                        radius: Appearance.rounding.verysmall
                        border.width: 2
                        border.color: eventTitleInput.activeFocus ? Appearance.colors.colPrimary : Appearance.m3colors.m3outline
                        color: "transparent"
                    }
                }

                TextField {
                    id: eventDescInput
                    Layout.fillWidth: true
                    Layout.leftMargin: 16
                    Layout.rightMargin: 16
                    implicitHeight: 44
                    padding: 10
                    placeholderText: Translation.tr("Description (optional)")
                    placeholderTextColor: Appearance.m3colors.m3outline
                    color: activeFocus ? Appearance.m3colors.m3onSurface : Appearance.m3colors.m3onSurfaceVariant
                    background: Rectangle {
                        anchors.fill: parent
                        radius: Appearance.rounding.verysmall
                        border.width: 2
                        border.color: eventDescInput.activeFocus ? Appearance.colors.colPrimary : Appearance.m3colors.m3outline
                        color: "transparent"
                    }
                }

                ColumnLayout {
                    Layout.leftMargin: 16
                    Layout.rightMargin: 16
                    Layout.fillWidth: true
                    spacing: 4
                    property date defaultStart: new Date()

                    StyledText { text: Translation.tr("Start"); color: Appearance.m3colors.m3onSurfaceVariant }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        TextField {
                            id: startDateInput
                            Layout.fillWidth: true
                            padding: 10
                            text: Qt.formatDate(parent.parent.defaultStart, "yyyy-MM-dd")
                            placeholderText: "yyyy-MM-dd"
                            placeholderTextColor: Appearance.m3colors.m3outline
                            color: activeFocus ? Appearance.m3colors.m3onSurface : Appearance.m3colors.m3onSurfaceVariant
                            background: Rectangle {
                                anchors.fill: parent
                                radius: Appearance.rounding.verysmall
                                border.width: 2
                                border.color: startDateInput.activeFocus ? Appearance.colors.colPrimary : Appearance.m3colors.m3outline
                                color: "transparent"
                            }
                        }
                        TextField {
                            id: startTimeInput
                            Layout.preferredWidth: 90
                            padding: 10
                            text: Qt.formatTime(parent.parent.defaultStart, "hh:mm")
                            placeholderText: "hh:mm"
                            placeholderTextColor: Appearance.m3colors.m3outline
                            color: activeFocus ? Appearance.m3colors.m3onSurface : Appearance.m3colors.m3onSurfaceVariant
                            background: Rectangle {
                                anchors.fill: parent
                                radius: Appearance.rounding.verysmall
                                border.width: 2
                                border.color: startTimeInput.activeFocus ? Appearance.colors.colPrimary : Appearance.m3colors.m3outline
                                color: "transparent"
                            }
                        }
                    }
                }

                ColumnLayout {
                    Layout.leftMargin: 16
                    Layout.rightMargin: 16
                    Layout.fillWidth: true
                    spacing: 4
                    property date defaultEnd: new Date(Date.now() + 3600000)

                    StyledText { text: Translation.tr("End"); color: Appearance.m3colors.m3onSurfaceVariant }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        TextField {
                            id: endDateInput
                            Layout.fillWidth: true
                            padding: 10
                            text: Qt.formatDate(parent.parent.defaultEnd, "yyyy-MM-dd")
                            placeholderText: "yyyy-MM-dd"
                            placeholderTextColor: Appearance.m3colors.m3outline
                            color: activeFocus ? Appearance.m3colors.m3onSurface : Appearance.m3colors.m3onSurfaceVariant
                            background: Rectangle {
                                anchors.fill: parent
                                radius: Appearance.rounding.verysmall
                                border.width: 2
                                border.color: endDateInput.activeFocus ? Appearance.colors.colPrimary : Appearance.m3colors.m3outline
                                color: "transparent"
                            }
                        }
                        TextField {
                            id: endTimeInput
                            Layout.preferredWidth: 90
                            padding: 10
                            text: Qt.formatTime(parent.parent.defaultEnd, "hh:mm")
                            placeholderText: "hh:mm"
                            placeholderTextColor: Appearance.m3colors.m3outline
                            color: activeFocus ? Appearance.m3colors.m3onSurface : Appearance.m3colors.m3onSurfaceVariant
                            background: Rectangle {
                                anchors.fill: parent
                                radius: Appearance.rounding.verysmall
                                border.width: 2
                                border.color: endTimeInput.activeFocus ? Appearance.colors.colPrimary : Appearance.m3colors.m3outline
                                color: "transparent"
                            }
                        }
                    }
                }

                ColumnLayout {
                    Layout.leftMargin: 16
                    Layout.rightMargin: 16
                    Layout.fillWidth: true
                    spacing: 4

                    StyledText { text: Translation.tr("Color"); color: Appearance.m3colors.m3onSurfaceVariant }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12

                        Repeater {
                            model: addEventDialog.colorOptions
                            delegate: Rectangle {
                                Layout.preferredWidth: 36
                                Layout.preferredHeight: 36
                                radius: Appearance.rounding.full
                                color: modelData.hex
                                border.width: addEventDialog.selectedColor === modelData.hex ? 3 : 0
                                border.color: Appearance.m3colors.m3onSurface

                                StyledText {
                                    anchors.centerIn: parent
                                    visible: addEventDialog.selectedColor === modelData.hex
                                    text: "check"
                                    font.family: Appearance.font.family.iconMaterial
                                    color: ColorUtils.getContrastingTextColor(modelData.hex)
                                }

                                ToolTip {
                                    visible: swatchHover.hovered
                                    delay: 250
                                    timeout: 0
                                    text: modelData.name
                                }
                                HoverHandler {
                                    id: swatchHover
                                }
                                TapHandler {
                                    onTapped: {
                                        addEventDialog.customMode = false;
                                        addEventDialog.selectedColor = modelData.hex;
                                    }
                                }
                            }
                        }

                        Repeater {
                            model: CalendarService.customColorOptions
                            delegate: Rectangle {
                                Layout.preferredWidth: 36
                                Layout.preferredHeight: 36
                                radius: Appearance.rounding.full
                                color: modelData.hex
                                border.width: (!addEventDialog.customMode && addEventDialog.selectedColor === modelData.hex) ? 3 : 0
                                border.color: Appearance.m3colors.m3onSurface

                                StyledText {
                                    anchors.centerIn: parent
                                    visible: !addEventDialog.customMode && addEventDialog.selectedColor === modelData.hex
                                    text: "check"
                                    font.family: Appearance.font.family.iconMaterial
                                    color: ColorUtils.getContrastingTextColor(modelData.hex)
                                }

                                ToolTip {
                                    visible: savedSwatchHover.hovered
                                    delay: 250
                                    timeout: 0
                                    text: modelData.name
                                }
                                HoverHandler {
                                    id: savedSwatchHover
                                }
                                TapHandler {
                                    onTapped: {
                                        addEventDialog.customMode = false;
                                        addEventDialog.selectedColor = modelData.hex;
                                    }
                                }
                            }
                        }

                        Rectangle {
                            id: customSwatch
                            Layout.preferredWidth: 36
                            Layout.preferredHeight: 36
                            radius: Appearance.rounding.full
                            property bool hasValidHex: addEventDialog.hexPattern.test(customColorInput.text)
                            color: hasValidHex ? customColorInput.text : Appearance.m3colors.m3surfaceContainerHighest
                            border.width: addEventDialog.customMode ? 3 : 1
                            border.color: addEventDialog.customMode ? Appearance.m3colors.m3onSurface : Appearance.m3colors.m3outline

                            StyledText {
                                anchors.centerIn: parent
                                visible: !customSwatch.hasValidHex
                                text: "palette"
                                font.family: Appearance.font.family.iconMaterial
                                color: Appearance.m3colors.m3onSurfaceVariant
                            }
                            StyledText {
                                anchors.centerIn: parent
                                visible: customSwatch.hasValidHex && addEventDialog.customMode
                                text: "check"
                                font.family: Appearance.font.family.iconMaterial
                                color: ColorUtils.getContrastingTextColor(customColorInput.text)
                            }

                            ToolTip {
                                visible: customSwatchHover.hovered
                                delay: 250
                                timeout: 0
                                text: Translation.tr("Custom color")
                            }
                            HoverHandler {
                                id: customSwatchHover
                            }
                            TapHandler {
                                onTapped: {
                                    addEventDialog.customMode = true;
                                    customColorInput.forceActiveFocus();
                                    if (customSwatch.hasValidHex) addEventDialog.selectedColor = customColorInput.text;
                                }
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: 4
                        spacing: 8
                        visible: addEventDialog.customMode

                        TextField {
                            id: customColorInput
                            Layout.fillWidth: true
                            padding: 8
                            placeholderText: Translation.tr("Custom hex, e.g. #8ab4f8")
                            placeholderTextColor: Appearance.m3colors.m3outline
                            color: activeFocus ? Appearance.m3colors.m3onSurface : Appearance.m3colors.m3onSurfaceVariant
                            onTextChanged: {
                                if (addEventDialog.hexPattern.test(text)) addEventDialog.selectedColor = text;
                            }
                            background: Rectangle {
                                anchors.fill: parent
                                radius: Appearance.rounding.verysmall
                                border.width: 2
                                border.color: customColorInput.activeFocus ? Appearance.colors.colPrimary : Appearance.m3colors.m3outline
                                color: "transparent"
                            }
                        }

                        RippleButton {
                            id: saveCustomColorButton
                            implicitWidth: 40
                            implicitHeight: 40
                            buttonRadius: Appearance.rounding.verysmall
                            enabled: addEventDialog.hexPattern.test(customColorInput.text) && !CalendarService.customColorOptions.some(function(o) { return o.hex === customColorInput.text; })
                            onClicked: CalendarService.addCustomColorOption(customColorInput.text)

                            ToolTip {
                                visible: saveCustomColorButton.hovered
                                delay: 250
                                timeout: 0
                                text: Translation.tr("Save to options")
                            }

                            StyledText {
                                anchors.centerIn: parent
                                text: "bookmark_add"
                                font.family: Appearance.font.family.iconMaterial
                                color: saveCustomColorButton.enabled ? Appearance.m3colors.m3onSurface : Appearance.m3colors.m3outline
                            }
                        }
                    }
                }

                StyledText {
                    Layout.leftMargin: 16
                    Layout.rightMargin: 16
                    visible: addEventDialog.errorText.length > 0
                    color: Appearance.colors.colError
                    text: addEventDialog.errorText
                }

                RowLayout {
                    Layout.bottomMargin: 16
                    Layout.leftMargin: 16
                    Layout.rightMargin: 16
                    Layout.alignment: Qt.AlignRight
                    spacing: 5

                    DialogButton {
                        buttonText: Translation.tr("Cancel")
                        onClicked: root.showAddDialog = false
                    }
                    DialogButton {
                        buttonText: Translation.tr("Add")
                        enabled: eventTitleInput.text.length > 0
                        onClicked: addEventDialog.addEvent()
                    }
                }
            }
        }
    }
}

