pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    readonly property int daysShown: 7
    readonly property int fetchIntervalMs: 15 * 60 * 1000

    property bool authenticated: true
    property string lastError: ""
    property var rawEvents: []
    property var localEvents: []   // events added locally, persisted to disk, merged in regardless of mode
    property var eventsInWeek: []
    property var customColorOptions: []   // user-saved custom colors, offered as swatches in the Add Event dialog

    function persistLocalData() {
        localDataFileView.setText(JSON.stringify({
            "localEvents": root.localEvents,
            "customColorOptions": root.customColorOptions
        }));
    }

    function addCustomColorOption(hex) {
        if (root.customColorOptions.some(function(o) { return o.hex === hex; })) return;
        let updated = root.customColorOptions.slice(0);
        updated.push({ "name": hex, "hex": hex });
        root.customColorOptions = updated;
        root.persistLocalData();
    }

    function addLocalEvent(title, desc, startDate, endDate, color) {
        let updated = root.localEvents.slice(0);
        updated.push({
            "title": title,
            "description": desc,
            "start": root.isoLocal(startDate),
            "end": root.isoLocal(endDate),
            "allDay": false,
            "color": color
        });
        root.localEvents = updated;
        root.persistLocalData();
    }

    function placeEventInDays(days, ev) {
        if (!ev.start) return;
        let evDate = new Date(ev.start);
        for (let day of days) {
            if (evDate.getFullYear() === day.date.getFullYear() &&
                evDate.getMonth() === day.date.getMonth() &&
                evDate.getDate() === day.date.getDate()) {
                if (ev.allDay) {
                    day.events.push({ "title": ev.title, "start": "00:00", "end": "23:59", "color": ev.color });
                } else {
                    let endDate = ev.end ? new Date(ev.end) : evDate;
                    day.events.push({
                        "title": ev.title,
                        "start": `${root.pad(evDate.getHours())}:${root.pad(evDate.getMinutes())}`,
                        "end": `${root.pad(endDate.getHours())}:${root.pad(endDate.getMinutes())}`,
                        "color": ev.color
                    });
                }
                break;
            }
        }
    }

    // TEMP: while building the Timetable UI, skip the Python process entirely
    // and render sample data instead. Flip to false once gcal.py is wired up.

    function pad(n) {
        return String(n).padStart(2, "0");
    }

    function isoLocal(date) {
        let tzOffsetMin = -date.getTimezoneOffset();
        let sign = tzOffsetMin >= 0 ? "+" : "-";
        tzOffsetMin = Math.abs(tzOffsetMin);
        let tzStr = `${sign}${pad(Math.floor(tzOffsetMin / 60))}:${pad(tzOffsetMin % 60)}`;
        return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}` +
               `T${pad(date.getHours())}:${pad(date.getMinutes())}:${pad(date.getSeconds())}${tzStr}`;
    }

    function startOfWeek() {
        const firstDay = Config.options?.time?.firstDayOfWeek ?? 1; // 1=Mon..7=Sun
        const now = new Date();
        const jsDay = now.getDay() === 0 ? 7 : now.getDay();
        const diff = (jsDay - firstDay + 7) % 7;
        const start = new Date(now.getFullYear(), now.getMonth(), now.getDate());
        start.setDate(start.getDate() - diff);
        return start;
    }

    function dayName(date) {
        const jsDay = date.getDay() === 0 ? 7 : date.getDay();
        return Qt.locale().dayName(jsDay, Locale.ShortFormat);
    }

    function refresh() {
        const start = root.startOfWeek();
        fetcher.command = [
            `${Directories.scriptPath}/calendar/gcal-venv.sh`,
            "list", "--days", String(root.daysShown),
            "--start", root.isoLocal(start)
        ];
        fetcher.running = true;
    }

    function rebuildWeek() {
        const start = root.startOfWeek();
        let days = [];
        for (let i = 0; i < root.daysShown; i++) {
            let d = new Date(start);
            d.setDate(d.getDate() + i);
            days.push({ "name": root.dayName(d), "date": d, "events": [] });
        }

        for (const ev of root.rawEvents) root.placeEventInDays(days, ev);
        for (const ev of root.localEvents) root.placeEventInDays(days, ev);
        root.eventsInWeek = days;
    }

    onRawEventsChanged: root.rebuildWeek()
    onLocalEventsChanged: root.rebuildWeek()

    FileView {
        id: localDataFileView
        path: Qt.resolvedUrl(Directories.calendarLocalDataPath)
        onLoaded: {
            try {
                const parsed = JSON.parse(localDataFileView.text());
                root.localEvents = parsed.localEvents ?? [];
                root.customColorOptions = parsed.customColorOptions ?? [];
                console.log("[CalendarService] Local data loaded");
            } catch (e) {
                console.warn(`[CalendarService] Failed to parse local data: ${e.message}`);
            }
        }
        onLoadFailed: (error) => {
            if (error == FileViewError.FileNotFound) {
                console.log("[CalendarService] Local data file not found, creating new one.");
                root.localEvents = [];
                root.customColorOptions = [];
                localDataFileView.setText(JSON.stringify({ "localEvents": [], "customColorOptions": [] }));
            } else {
                console.warn(`[CalendarService] Error loading local data: ${error}`);
            }
        }
    }

    Component.onCompleted: {
        localDataFileView.reload();
        if (root.useMockData) {
            root.generateMockWeek();
        } else {
            root.refresh();
        }
    }

    Process {
        id: fetcher
        stdout: StdioCollector {
            onStreamFinished: {
                const out = text.trim();
                if (out.length === 0) return;
                if (out.startsWith("ERROR:")) {
                    root.authenticated = !out.includes("not authenticated");
                    root.lastError = out.replace("ERROR:", "").trim();
                    console.warn(`[CalendarService] ${root.lastError}`);
                    return;
                }
                try {
                    const parsed = JSON.parse(out);
                    root.lastError = "";
                    root.authenticated = true;
                    root.rawEvents = parsed.events ?? [];
                } catch (e) {
                    root.lastError = `Failed to parse gcal.py output: ${e.message}`;
                    console.error(`[CalendarService] ${root.lastError}`);
                }
            }
        }
    }

    Timer {
        running: false
        repeat: true
        interval: root.fetchIntervalMs
        triggeredOnStart: false
        onTriggered: root.refresh()
    }
}