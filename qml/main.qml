import QtQuick 2.4
import QtQuick.LocalStorage 2.0
import Eos.Window 0.1
import WebOSServices 1.0
import "cfg.js" as Cfg
import "Defaults.js" as Defaults

// Lifes Good launcher - QML version.
// Home screen of app tiles (editable), clock, Home Assistant read-out + light presets, "All apps" page read live from the
// TV, Back = open apps (close them). Arrow keys + OK, Yellow (or hold OK) = edit, Magic Remote pointer.
WebOSWindow {
    id: win
    windowType: "_WEBOS_WINDOW_TYPE_CARD"
    width: 1920
    height: 1080
    visible: true
    color: "black"
    appId: "com.ha-launcher.home"
    title: "Lifes Good"
    // Keys we want delivered to us instead of the TV's default handling. Without Back here the TV shows its own
    // "Do you want to exit the app?" prompt; Yellow is how the edit menu opens. Home is left alone on purpose.
    keyMask: WebOSWindow.KeyMaskDefault | WebOSWindow.KeyMaskBack | WebOSWindow.KeyMaskRemoteColorYellow

    // ---------------------------------------------------------------- state
    readonly property int cols: 8
    // the tile grid sits under the light-preset chips; with no presets configured it moves up to close the gap
    readonly property int gridTop: Cfg.preset ? 318 : 214
    readonly property int maxHome: 23
    readonly property bool appActive: Qt.application.state !== Qt.ApplicationSuspended && Qt.application.state !== Qt.ApplicationHidden

    property string page: "home"          // home | all
    property int sel: 0
    property string row: "grid"           // grid | chips
    property int chipSel: 0
    property bool moving: false
    property bool menuOpen: false
    property var menuItems: []
    property int menuSel: 0
    property string menuTitle: ""
    property int allSel: 0
    property string allRow: "grid"        // grid | back
    property string allLabel: "All apps"
    property var allList: []
    property var homeIds: []
    property var savedInfo: ({})
    property var opened: []
    property var lpMap: ({})
    property var presetOpts: []
    property string presetLabel: ""    // text before the preset chips: Cfg.presetLabel, else the entity's friendly name from Home Assistant
    property string preset: ""
    // the read-out top right: any Home Assistant entity (sensor, binary_sensor, input_number, ...). Value + unit come from the state.
    property string sensorText: "--"
    property string sensorLabel: ""
    property real sensorPct: -1        // 0-100 when the unit is "%" (draws the bar), otherwise -1
    property int sensorWarn: 0         // battery entities only: 1 = low (amber), 2 = very low (red)
    property bool idle: false
    property string toastText: ""
    property string hintText: ""
    property bool okDown: false
    property bool okHeld: false

    readonly property var hideIds: ({ "com.ha-launcher.home": 1, "org.webosbrew.inputhook": 1, "org.webosbrew.custom-screensaver": 1 })
    readonly property var notApps: ({ "com.ha-launcher.home": 1, "com.webos.app.home": 1, "com.webos.app.screensaver": 1, "com.webos.app.voice": 1,
                                      "com.webos.app.livemenu": 1, "com.webos.app.inputcommon": 1, "com.webos.app.tvhotkey": 1, "com.webos.app.toast": 1 })
    readonly property var allTile: ({ id: "__all", title: "All apps", icon: Qt.resolvedUrl("assets/allicon.png") })
    property var baseMap: ({})

    // the tiles shown on the home screen (the saved ids, then the All apps tile)
    property var homeApps: []

    // ---------------------------------------------------------------- storage (survives restarts)
    property var db: LocalStorage.openDatabaseSync("lifesgood", "1.0", "Launcher", 200000)
    function kvGet(k) {
        var v = null
        try { db.transaction(function(tx) {
            tx.executeSql("CREATE TABLE IF NOT EXISTS kv(k TEXT PRIMARY KEY, v TEXT)")
            var r = tx.executeSql("SELECT v FROM kv WHERE k=?", [k])
            if (r.rows.length) v = JSON.parse(r.rows.item(0).v)
        }) } catch (e) { v = null }
        return v
    }
    function kvSet(k, v) {
        try { db.transaction(function(tx) {
            tx.executeSql("CREATE TABLE IF NOT EXISTS kv(k TEXT PRIMARY KEY, v TEXT)")
            tx.executeSql("INSERT OR REPLACE INTO kv VALUES(?,?)", [k, JSON.stringify(v)])
        }) } catch (e) {}
    }

    // ---------------------------------------------------------------- apps
    function iconUrl(p) {
        if (!p) return ""
        p = String(p)
        if (p.indexOf("file://") === 0 || p.indexOf("http") === 0) return p
        if (p.charAt(0) === "/") return "file://" + p
        return ""
    }
    function infoOf(id) {
        var b = baseMap[id]
        if (b) return { id: b.id, title: b.title, icon: Qt.resolvedUrl(b.icon) }
        if (lpMap[id]) return lpMap[id]
        if (savedInfo[id]) return savedInfo[id]
        return null
    }
    function rebuildHome() {
        var a = []
        for (var i = 0; i < homeIds.length; i++) { var o = infoOf(homeIds[i]); if (o) a.push(o) }
        a.push(allTile)
        homeApps = a
        if (sel > a.length - 1) sel = a.length - 1
        if (sel < 0) sel = 0
    }
    function saveHome() { kvSet("home", homeIds); kvSet("info", savedInfo) }
    function pinned(id) { return homeIds.indexOf(id) >= 0 }
    function loadSaved() {
        var m = {}
        for (var i = 0; i < Defaults.APPS.length; i++) m[Defaults.APPS[i].id] = Defaults.APPS[i]
        baseMap = m
        var h = kvGet("home")
        if (!h || !h.length) { h = []; for (var j = 0; j < Defaults.APPS.length; j++) h.push(Defaults.APPS[j].id) }
        homeIds = h.slice(0, maxHome)
        savedInfo = kvGet("info") || {}
        opened = kvGet("opened") || []
        sel = kvGet("sel") || 0
        rebuildHome()
        homeIds = homeIds.filter(function(id) { return infoOf(id) })
        rebuildHome()
    }

    // ---------------------------------------------------------------- messages
    Timer { id: toastT; interval: 4000; onTriggered: win.toastText = "" }
    Timer { id: hintT; interval: 9000; onTriggered: win.hintText = "" }
    function toast(m) { hintText = ""; toastText = m; toastT.restart() }
    function hint(m) { hintText = m; hintT.restart() }

    // ---------------------------------------------------------------- TV services (live from the app manager)
    Service { id: svcLaunch; appId: win.appId; service: "com.webos.service.applicationmanager"; method: "launch"
        onResponse: { var o = parse(payload); if (o.returnValue === false) win.toast("Could not open the app: " + (o.errorText || "error")) } }
    Service { id: svcClose; appId: win.appId; service: "com.webos.service.applicationmanager"; method: "closeByAppId"
        onResponse: { var o = parse(payload); if (o.returnValue === false) win.toast("Could not close it: " + (o.errorText || "error")) } }
    Service { id: svcRunning; appId: win.appId; service: "com.webos.service.applicationmanager"; method: "running"
        onResponse: win.gotRunning(parse(payload)) }
    Service { id: svcPoints; appId: win.appId; service: "com.webos.service.applicationmanager"; method: "listLaunchPoints"
        onResponse: win.gotPoints(parse(payload)) }
    Service { id: svcFg; appId: win.appId; service: "com.webos.service.applicationmanager"; method: "getForegroundAppInfo"
        onResponse: { var o = parse(payload); if (o.appId) { win.noteFg(o.appId); win.fgChanged(o.appId) } } }
    // Cold-boot gap: until the Home stand-in is mounted (about 40 s after power-on) Home opens LG's own Home.
    // This app is already running by then, so when the foreground becomes LG's Home we take the screen back.
    property var stealTimes: []
    function fgChanged(id) {
        if (id !== "com.webos.app.home") return
        var now = Date.now(), t = stealTimes.filter(function(x) { return now - x < 60000 })
        if (t.length >= 30 || (t.length && now - t[t.length - 1] < 500)) return   // loop guard: 0.5 s apart, 30 a minute
        t.push(now); stealTimes = t
        svcLaunch.callService({ id: win.appId })
    }
    function parse(p) { try { return JSON.parse(p) } catch (e) { return {} } }

    function launch(a) {
        if (!a) return
        if (a.id === "__all") { openAll(); return }
        noteFg(a.id)
        svcLaunch.callService({ id: a.id })
    }

    // launch points -> titles/icons for any app (also fills the All apps page)
    property bool wantAll: false
    function gotPoints(o) {
        var lp = o.launchPoints || []
        var m = {}
        for (var i = 0; i < lp.length; i++) {
            var p = lp[i]
            if (p && p.id) m[p.id] = { id: p.id, title: p.title || p.id, icon: iconUrl(p.largeIcon || p.icon) }
        }
        if (lp.length) { lpMap = m; rebuildHome() }
        if (wantAll && page === "all") {
            if (!lp.length) { allLabel = "Couldn't read the app list from the TV" + (o.errorText ? ": " + o.errorText : ""); return }
            allList = mergeAll(m)
            allSel = 0
            allLabel = "All apps (" + allList.length + ")"
        }
    }
    function mergeAll(m) {
        var seen = {}, list = []
        for (var i = 0; i < Defaults.APPS.length; i++) {
            var b = Defaults.APPS[i]; seen[b.id] = 1
            list.push({ id: b.id, title: b.title, icon: Qt.resolvedUrl(b.icon) })
        }
        for (var id in m) { if (!seen[id] && !hideIds[id]) { seen[id] = 1; list.push(m[id]) } }
        list.sort(function(x, y) { var a = String(x.title || x.id).toLowerCase(), b = String(y.title || y.id).toLowerCase(); return a < b ? -1 : (a > b ? 1 : 0) })
        return list
    }

    // ---------------------------------------------------------------- open apps (Back on the home screen)
    // The TV's running list also holds apps LG preloaded, so only apps that have actually been in front are offered.
    function noteFg(id) {
        if (!id || notApps[id] || opened.indexOf(id) >= 0) return
        var o = opened.slice(); o.push(id); opened = o; kvSet("opened", opened)
    }
    function titleOf(id) { var a = infoOf(id); return a ? a.title : id }
    function openAppsPanel() { svcRunning.callService({}) }
    function gotRunning(o) {
        if (!o.running) { if (page === "home" && !menuOpen) toast("Couldn't read the running apps"); return }
        if (page !== "home" || menuOpen || moving) return
        var run = {}
        for (var i = 0; i < o.running.length; i++) run[o.running[i].id] = 1
        opened = opened.filter(function(id) { return run[id] })
        kvSet("opened", opened)
        if (!opened.length) { toast("No apps are open"); return }
        var items = opened.map(function(id) { return { label: "Close " + titleOf(id), fn: function() { closeApp(id); openLater.start() } } })
        if (opened.length > 1) items.push({ label: "Close all", fn: function() { opened.slice().forEach(closeApp); openLater.interval = 700; openLater.start() } })
        items.push({ label: "Back" })
        openMenu("Open apps", items)
    }
    Timer { id: openLater; interval: 500; onTriggered: { interval = 500; win.openAppsPanel() } }
    function closeApp(id) {
        svcClose.callService({ id: id })
        opened = opened.filter(function(x) { return x !== id }); kvSet("opened", opened)
    }

    // ---------------------------------------------------------------- All apps page
    function openAll() {
        page = "all"; allRow = "grid"; allSel = 0; allList = []; wantAll = true
        allLabel = "Loading apps..."
        hint("Yellow button or hold OK on an app: add it to / remove it from the home screen")
        svcPoints.callService({})
    }
    function closeAll() { if (page !== "all") return; page = "home"; wantAll = false }

    // ---------------------------------------------------------------- menus + editing
    function openMenu(title, items) { menuTitle = title; menuItems = items; menuSel = 0; menuOpen = true }
    function closeMenu() { menuOpen = false }
    function chooseMenu() { var it = menuItems[menuSel]; closeMenu(); if (it && it.fn) it.fn() }
    function pin(a) {
        if (pinned(a.id)) return
        if (homeIds.length >= maxHome) { toast("The home screen is full (" + maxHome + " apps) - remove one first"); return }
        if (!baseMap[a.id]) { var s = savedInfo; s[a.id] = { id: a.id, title: a.title, icon: String(a.icon) }; savedInfo = s }
        var h = homeIds.slice(); h.push(a.id); homeIds = h
        saveHome(); rebuildHome(); toast(a.title + " added to the home screen")
    }
    function unpin(a) {
        homeIds = homeIds.filter(function(x) { return x !== a.id })
        saveHome(); rebuildHome(); toast(a.title + " removed from the home screen")
    }
    function allMenu(i) {
        var a = allList[i]; if (!a) return
        openMenu(a.title, pinned(a.id)
            ? [{ label: "Remove from home screen", fn: function() { unpin(a) } }, { label: "Cancel" }]
            : [{ label: "Add to home screen", fn: function() { pin(a) } }, { label: "Cancel" }])
    }
    function homeMenu(i) {
        var a = homeApps[i]; if (!a) return
        if (a.id === "__all") { openMenu("All apps", [{ label: "Reset home screen to the default apps", fn: resetHome }, { label: "Cancel" }]); return }
        openMenu(a.title, [
            { label: "Move", fn: function() { moving = true; toast("Arrow keys move it, OK drops it") } },
            { label: "Remove from home screen", fn: function() { unpin(a) } },
            { label: "Reset home screen to the default apps", fn: resetHome },
            { label: "Cancel" }])
    }
    function resetHome() {
        var h = []; for (var j = 0; j < Defaults.APPS.length; j++) h.push(Defaults.APPS[j].id)
        homeIds = h; savedInfo = {}; sel = 0; saveHome(); rebuildHome(); toast("Home screen reset to the default apps")
    }
    function resetUI() { closeMenu(); moving = false; closeAll() }

    // ---------------------------------------------------------------- Home Assistant (plain HTTP, polled)
    function ha(method, path, body, cb) {
        if (!Cfg.token || !Cfg.url) return
        var x = new XMLHttpRequest()
        x.onreadystatechange = function() { if (x.readyState === 4 && cb) cb(x.status, x.responseText) }
        x.open(method, Cfg.url + path)
        x.setRequestHeader("Authorization", "Bearer " + Cfg.token)
        if (body) x.setRequestHeader("Content-Type", "application/json")
        x.send(body ? JSON.stringify(body) : undefined)
    }
    function showSensor(o) {
        var at = o.attributes || {}, unit = at.unit_of_measurement || "", v = o.state
        sensorLabel = Cfg.label || at.friendly_name || ""
        sensorPct = -1; sensorWarn = 0
        if (v === undefined || v === "unavailable" || v === "unknown" || v === "") { sensorText = "--"; return }
        var n = Number(v)
        if (v !== "" && !isNaN(n)) {
            var t = (Math.abs(n) >= 100 || Math.round(n) === n) ? String(Math.round(n)) : String(Math.round(n * 10) / 10)
            sensorText = t + (unit === "" ? "" : (unit.charAt(0) === "%" || unit.charAt(0) === "°" ? unit : " " + unit))
            if (unit === "%") sensorPct = Math.max(0, Math.min(100, n))
            if (at.device_class === "battery") sensorWarn = n <= 10 ? 2 : (n <= 25 ? 1 : 0)
        } else {
            sensorText = String(v).charAt(0).toUpperCase() + String(v).slice(1)      // "on" -> "On", "home" -> "Home"
        }
    }
    function haPoll() {
        if (!Cfg.token) return
        if (Cfg.sensor) ha("GET", "/api/states/" + Cfg.sensor, null, function(st, txt) {
            if (st === 200) showSensor(parse(txt))
            else { sensorText = "--"; sensorPct = -1; sensorWarn = 0 } })
        if (Cfg.preset) ha("GET", "/api/states/" + Cfg.preset, null, function(st, txt) {
            if (st !== 200) return
            var o = parse(txt), opts = (o.attributes && o.attributes.options) || presetOpts
            presetLabel = Cfg.presetLabel || (o.attributes && o.attributes.friendly_name) || ""
            if (opts.join("|") !== presetOpts.join("|")) presetOpts = opts
            if (o.state && o.state !== "unknown" && o.state !== "unavailable") preset = o.state
            if (chipSel >= presetOpts.length) chipSel = 0 })
    }
    function setPreset(opt) {
        if (!Cfg.token) { toast("Home Assistant isn't set up"); return }
        preset = opt
        ha("POST", "/api/services/select/select_option", { entity_id: Cfg.preset, option: opt }, function(st) {
            if (st !== 200) toast("Home Assistant: couldn't set the preset (" + st + ")")
            pollSoon.start() })
    }
    Timer { id: pollSoon; interval: 1500; onTriggered: win.haPoll() }
    Timer { interval: 25000; running: win.appActive; repeat: true; triggeredOnStart: false; onTriggered: win.haPoll() }

    // ---------------------------------------------------------------- clock, idle dim, OLED drift
    property string clockText: ""
    property string dateText: ""
    function tick() { var d = new Date(); clockText = Qt.formatTime(d, "hh:mm"); dateText = Qt.formatDate(d, "dddd d MMMM") }
    Timer { interval: 5000; running: win.appActive; repeat: true; triggeredOnStart: true; onTriggered: win.tick() }
    Timer { id: idleT; interval: 300000; running: true; onTriggered: win.idle = true }
    function awake() { idle = false; idleT.restart() }
    property real driftX: 0
    property real driftY: 0
    Timer { interval: 180000; running: win.appActive; repeat: true
        onTriggered: { win.driftX = Math.round(Math.random() * 20 - 10); win.driftY = Math.round(Math.random() * 20 - 10) } }

    property string claimNote: ""
    // Back policy: the TV only passes Back to the app (instead of its "exit the app?" prompt) when the window carries
    // _WEBOS_ACCESS_POLICY_KEYS_BACK = "true". Only an in-place write to win.windowProperties works from QML
    // (setWindowProperty/updateWindowProperties are not callable and assigning the map is read-only).
    property bool claimOk: false
    property string lastKey: "no key yet"
    property int keyCount: 0
    function claimKeys() {
        try {
            win.windowProperties["_WEBOS_ACCESS_POLICY_KEYS_BACK"] = "true"
            win.windowProperties["_WEBOS_ACCESS_POLICY_KEYS_EXIT"] = "true"
            claimOk = true
        } catch (e) { claimOk = false }
    }
    // the property is set again once the window is really on screen (setting it only at start may be too early)
    property int policyTries: 0
    Timer { id: policyT; interval: 1000; repeat: true
        onTriggered: { win.claimKeys(); if (++win.policyTries >= 5) stop() } }
    onVisibleChanged: if (visible) { claimKeys(); policyTries = 0; policyT.restart() }
    onActiveChanged: if (active) claimKeys()

    onAppActiveChanged: { if (!appActive) resetUI(); else { claimKeys(); tick(); haPoll() } }
    Connections { target: Qt.application
        onStateChanged: { if (Qt.application.state === Qt.ApplicationActive) { win.tick(); win.haPoll() } else win.resetUI() } }

    Component.onCompleted: {
        // Tell the TV this window handles Back itself. Without this property the TV's key filter shows its own
        // "Do you want to exit the app?" prompt instead of passing Back to us (the key mask above is not enough).
        loadSaved()
        tick()
        svcFg.callService({ subscribe: true })
        svcPoints.callService({})
        haPoll()
        win.claimKeys()
        policyT.start()
        hint("Yellow button or hold OK on a tile: edit the home screen  -  Back: open apps")
    }

    // ---------------------------------------------------------------- keys
    function keyName(e) {
        switch (e.key) {
        case Qt.Key_Left: return "left"
        case Qt.Key_Right: return "right"
        case Qt.Key_Up: return "up"
        case Qt.Key_Down: return "down"
        case Qt.Key_Return: case Qt.Key_Enter: case Qt.Key_Select: return "ok"
        case Qt.Key_Back: case Qt.Key_Escape: case Qt.Key_Backspace: return "back"
        case Qt.Key_Yellow: case Qt.Key_Y: case 0x1200013: return "yellow"   // 0x1200013 (scan 408) is what the Magic Remote's Yellow button sends
        }
        if (e.nativeScanCode === 408) return "yellow"
        if (e.key === 0x1200003 || e.nativeScanCode === 420 || e.nativeScanCode === 412) return "back"      // the remote's Back button (KEY_PREVIOUS) arrives as scan code 412
        return ""
    }
    function handleKey(k) {
        if (menuOpen) {
            if (k === "up") menuSel = (menuSel + menuItems.length - 1) % menuItems.length
            else if (k === "down") menuSel = (menuSel + 1) % menuItems.length
            else if (k === "ok") chooseMenu()
            else if (k === "back" || k === "yellow") closeMenu()
            return
        }
        if (moving) {
            var last = homeIds.length - 1, n = sel
            if (k === "ok" || k === "back" || k === "yellow") { moving = false; return }
            if (k === "left") n = sel - 1; else if (k === "right") n = sel + 1; else if (k === "up") n = sel - cols; else if (k === "down") n = sel + cols; else return
            if (n < 0 || n > last || n === sel) return
            var h = homeIds.slice(), t = h[sel]; h[sel] = h[n]; h[n] = t; homeIds = h; sel = n
            kvSet("sel", sel); saveHome(); rebuildHome()
            return
        }
        if (page === "all") { allKey(k); return }
        if (k === "back") { openAppsPanel(); return }
        if (k === "yellow" && row === "grid") { homeMenu(sel); return }
        if (row === "chips") {
            if (k === "left") chipSel = Math.max(0, chipSel - 1)
            else if (k === "right") chipSel = Math.min(presetOpts.length - 1, chipSel + 1)
            else if (k === "down") row = "grid"
            else if (k === "ok") { if (presetOpts[chipSel]) setPreset(presetOpts[chipSel]) }
            return
        }
        var m = sel, count = homeApps.length
        if (k === "left") m = sel - 1
        else if (k === "right") m = sel + 1
        else if (k === "up") { if (sel < cols && presetOpts.length) { row = "chips"; return } m = sel - cols }
        else if (k === "down") m = sel + cols
        else if (k === "ok") { launch(homeApps[sel]); return }
        else return
        if (m < 0) m = 0
        if (m >= count) m = (k === "down") ? count - 1 : sel
        sel = m; kvSet("sel", sel)
    }
    function allKey(k) {
        if (k === "yellow") { if (allRow === "grid") allMenu(allSel); return }
        if (k === "back") { closeAll(); return }
        if (allRow === "back") {
            if (k === "ok") closeAll()
            else if (k === "down" || k === "right") allRow = "grid"
            return
        }
        var n = allSel
        if (k === "left") n = allSel - 1; else if (k === "right") n = allSel + 1
        else if (k === "up") { if (allSel < cols) { allRow = "back"; return } n = allSel - cols }
        else if (k === "down") n = allSel + cols
        else if (k === "ok") { launch(allList[allSel]); return }
        else return
        if (n < 0) n = 0
        if (n >= allList.length) n = (k === "down") ? allList.length - 1 : allSel
        if (n >= 0) allSel = n
    }
    // OK: a short press acts on release, holding it (0.65 s) opens the edit menu - same as the Yellow button
    Timer { id: holdT; interval: 650
        onTriggered: { win.okHeld = true
            if (win.menuOpen || win.moving) return
            if (win.page === "all") { if (win.allRow === "grid") win.allMenu(win.allSel) }
            else if (win.row === "grid") win.homeMenu(win.sel) } }

    Item {
        id: keys
        anchors.fill: parent
        focus: true
        Keys.onPressed: {
            win.awake()
            var k = win.keyName(event)
            if (k === "ok") {
                event.accepted = true
                if (event.isAutoRepeat || win.okDown) return
                win.okDown = true; win.okHeld = false
                if (win.menuOpen || win.moving) { win.okDown = false; win.handleKey("ok"); return }   // menus: act at once
                holdT.restart()
                return
            }
            if (k !== "") { win.handleKey(k); event.accepted = true; return }
            if (event.key === Qt.Key_Shift || event.key === Qt.Key_Control || event.key === Qt.Key_Alt || event.key === Qt.Key_Meta) return
            win.toast("Unrecognised key 0x" + event.key.toString(16) + " (scan " + event.nativeScanCode + ")")
        }
        Keys.onReleased: {
            if (win.keyName(event) !== "ok" || event.isAutoRepeat) return
            event.accepted = true
            if (!win.okDown) return
            win.okDown = false; holdT.stop()
            if (!win.okHeld) win.handleKey("ok")
        }
    }

    // ================================================================ screen
    // animated background: slow purple + teal glows on black (OLED friendly: dims after 5 min idle)
    Item {
        id: bgLayer
        anchors.fill: parent
        opacity: win.idle ? .28 : .6
        Behavior on opacity { NumberAnimation { duration: 6000 } }
        Glow { source: Qt.resolvedUrl("assets/glow_purple.png"); size: 1050; cx: 960; cy: 540; ax: 760; ay: 260; dx: 26000; dy: 31000; strength: .55; running: win.appActive }
        Glow { source: Qt.resolvedUrl("assets/glow_teal.png");   size: 950;  cx: 960; cy: 540; ax: 800; ay: 300; dx: 32000; dy: 23000; strength: .50; running: win.appActive }
        Glow { source: Qt.resolvedUrl("assets/glow_purple.png"); size: 800;  cx: 960; cy: 540; ax: 600; ay: 340; dx: 21000; dy: 36000; strength: .40; running: win.appActive }
        Glow { source: Qt.resolvedUrl("assets/glow_teal.png");   size: 700;  cx: 960; cy: 540; ax: 670; ay: 220; dx: 29000; dy: 19000; strength: .36; running: win.appActive }
        Glow { source: Qt.resolvedUrl("assets/glow_lilac.png");  size: 600;  cx: 960; cy: 540; ax: 470; ay: 220; dx: 17000; dy: 25000; strength: .22; running: win.appActive }
    }

    Item {
        id: shift
        width: 1920; height: 1080
        x: win.driftX; y: win.driftY
        Behavior on x { NumberAnimation { duration: 4000; easing.type: Easing.InOutQuad } }
        Behavior on y { NumberAnimation { duration: 4000; easing.type: Easing.InOutQuad } }

        // header
        Text { id: clockTxt; x: 120; y: 56; text: win.clockText; font.pixelSize: 96; font.weight: Font.Light; font.letterSpacing: 2; color: "#bdbdbd"; font.family: "LG Smart UI" }
        Text { x: 120 + clockTxt.width + 36; y: 56 + 62; text: win.dateText; font.pixelSize: 34; color: "#6f6f6f"; font.family: "LG Smart UI" }

        // read-out (home page only): any Home Assistant entity; hidden when none is configured
        Item {
            id: batBox
            x: 1920 - 130 - 300; y: 84; width: 300; height: 150
            opacity: (win.page === "home" && Cfg.sensor) ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: 200 } }
            Text { anchors.right: parent.right; y: 0; width: 300; horizontalAlignment: Text.AlignRight
                   font.pixelSize: 84; minimumPixelSize: 36; fontSizeMode: Text.HorizontalFit; elide: Text.ElideRight
                   font.weight: Font.Light; font.family: "LG Smart UI"
                   text: win.sensorText
                   color: win.sensorWarn === 2 ? "#d9534f" : (win.sensorWarn === 1 ? "#d9a441" : "#bdbdbd") }
            Text { anchors.right: parent.right; y: 92; width: 300; horizontalAlignment: Text.AlignRight; elide: Text.ElideRight
                   text: win.sensorLabel; font.pixelSize: 26; color: "#6f6f6f"; font.family: "LG Smart UI" }
            Rectangle { anchors.right: parent.right; y: 132; width: 260; height: 8; radius: 4; color: "#161616"
                visible: win.sensorPct >= 0
                Rectangle { height: parent.height; radius: 4
                    width: win.sensorPct < 0 ? 0 : parent.width * win.sensorPct / 100
                    color: win.sensorWarn === 2 ? "#d9534f" : (win.sensorWarn === 1 ? "#d9a441" : "#8f8f8f")
                    Behavior on width { NumberAnimation { duration: 600 } } } }
        }

        // light preset chips
        Row {
            id: chipRow
            x: 120; y: 214; spacing: 16
            opacity: win.page === "home" ? 1 : 0
            visible: opacity > 0 && win.presetOpts.length > 0
            Behavior on opacity { NumberAnimation { duration: 200 } }
            Text { text: win.presetLabel; font.pixelSize: 26; color: "#6f6f6f"; anchors.verticalCenter: parent.verticalCenter; width: Math.min(implicitWidth, 280) + 14; elide: Text.ElideRight; font.family: "LG Smart UI" }
            Repeater {
                model: win.presetOpts
                Rectangle {
                    property bool foc: win.row === "chips" && win.chipSel === index
                    property bool act: modelData === win.preset
                    height: 64; width: lbl.implicitWidth + 60; radius: 32
                    color: foc ? (act ? "#38ffffff" : "#24ffffff") : (act ? "#2bffffff" : "#0dffffff")
                    scale: foc ? 1.08 : 1
                    Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutQuad } }
                    Behavior on color { ColorAnimation { duration: 140 } }
                    Rectangle { anchors.fill: parent; anchors.margins: -4; radius: 36; color: "transparent"; border.width: 4; border.color: "#e8e8e8"; opacity: parent.foc ? 1 : 0
                                Behavior on opacity { NumberAnimation { duration: 140 } } }
                    Text { id: lbl; anchors.centerIn: parent; text: modelData; font.pixelSize: 28; color: (parent.foc || parent.act) ? "#ffffff" : "#8a8a8a"; font.family: "LG Smart UI" }
                    MouseArea { anchors.fill: parent; hoverEnabled: true
                        onPositionChanged: { if (win.row !== "chips" || win.chipSel !== index) { win.row = "chips"; win.chipSel = index } }
                        onClicked: { win.row = "chips"; win.chipSel = index; win.setPreset(modelData) } }
                }
            }
        }

        // home tiles
        Item {
            id: homeGrid
            x: 0; y: 0; width: 1920; height: 1080
            opacity: win.page === "home" ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: 200 } }
            Repeater {
                model: win.homeApps
                Tile {
                    x: 120 + (index % win.cols) * 214
                    y: win.gridTop + Math.floor(index / win.cols) * 224
                    title: modelData.title; icon: String(modelData.icon)
                    focused: win.page === "home" && win.row === "grid" && win.sel === index
                    moving: win.moving && win.sel === index
                    Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutQuad } }
                    Behavior on y { NumberAnimation { duration: 180; easing.type: Easing.OutQuad } }
                    onHovered: { if (win.menuOpen) return; win.awake(); if (win.row !== "grid" || win.sel !== index) { win.row = "grid"; win.sel = index; kvSet("sel", index) } }
                    onActivated: { if (win.menuOpen) return; win.row = "grid"; win.sel = index; if (win.moving) { win.moving = false; return } win.launch(modelData) }
                    onHeld: { if (win.menuOpen) return; win.row = "grid"; win.sel = index; win.homeMenu(index) }
                }
            }
        }

        // All apps page
        Item {
            id: allPage
            x: 0; y: 0; width: 1920; height: 1080
            opacity: win.page === "all" ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: 200 } }
            Row {
                x: 120; y: 214; spacing: 26
                Rectangle {
                    property bool foc: win.allRow === "back"
                    height: 64; width: backText.implicitWidth + 60; radius: 32
                    color: foc ? "#24ffffff" : "#0dffffff"; scale: foc ? 1.08 : 1
                    Behavior on scale { NumberAnimation { duration: 140 } }
                    Rectangle { anchors.fill: parent; anchors.margins: -4; radius: 36; color: "transparent"; border.width: 4; border.color: "#e8e8e8"; opacity: parent.foc ? 1 : 0 }
                    Text { id: backText; anchors.centerIn: parent; text: "‹ Back"; font.pixelSize: 28; color: parent.foc ? "#fff" : "#8a8a8a"; font.family: "LG Smart UI" }
                    MouseArea { anchors.fill: parent; hoverEnabled: true
                        onPositionChanged: win.allRow = "back"
                        onClicked: win.closeAll() }
                }
                Text { text: win.allLabel; font.pixelSize: 26; color: "#6f6f6f"; anchors.verticalCenter: parent.verticalCenter; font.family: "LG Smart UI" }
            }
            GridView {
                id: allGrid
                x: 100; y: 300; width: 1760; height: 740
                cellWidth: 214; cellHeight: 224
                leftMargin: 20; topMargin: 20
                clip: true
                model: win.allList
                interactive: false
                highlightFollowsCurrentItem: false
                currentIndex: win.allSel
                onCurrentIndexChanged: positionViewAtIndex(currentIndex, GridView.Contain)
                Behavior on contentY { NumberAnimation { duration: 180; easing.type: Easing.OutQuad } }
                delegate: Tile {
                    title: modelData.title; icon: String(modelData.icon)
                    focused: win.page === "all" && win.allRow === "grid" && win.allSel === index
                    pinned: win.pinned(modelData.id)
                    onHovered: { if (win.menuOpen) return; win.awake(); if (win.allRow !== "grid" || win.allSel !== index) { win.allRow = "grid"; win.allSel = index } }
                    onActivated: { if (win.menuOpen) return; win.allRow = "grid"; win.allSel = index; win.launch(modelData) }
                    onHeld: { if (win.menuOpen) return; win.allRow = "grid"; win.allSel = index; win.allMenu(index) }
                }
            }
        }

        // status line (hint / toast) - bottom left
        Text { x: 120; y: 1080 - 60 - 34; font.pixelSize: 26; color: "#8a8a8a"; text: win.toastText; font.family: "LG Smart UI" }
        Text { x: 120; y: 1080 - 60 - 34; font.pixelSize: 24; color: "#5f5f5f"; text: win.hintText; font.family: "LG Smart UI"
               opacity: win.toastText === "" ? 1 : 0; Behavior on opacity { NumberAnimation { duration: 1500 } } }
    }

    // menu (edit menu and open-apps list)
    Rectangle {
        id: menuBox
        width: 640; height: 52 + 48 + menuItems.length * 76
        x: (1920 - width) / 2; y: 540 - 190
        radius: 26; color: "#f70e0e12"
        border.width: 2; border.color: "#1fffffff"
        opacity: win.menuOpen ? 1 : 0
        visible: opacity > 0
        scale: win.menuOpen ? 1 : .96
        z: 30
        Behavior on opacity { NumberAnimation { duration: 150 } }
        Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
        Text { x: 34; y: 22; width: 572; text: win.menuTitle; elide: Text.ElideRight; font.pixelSize: 32; color: "#cfcfcf"; font.family: "LG Smart UI" }
        Column {
            x: 26; y: 82; spacing: 8; width: 588
            Repeater {
                model: win.menuItems
                Rectangle {
                    width: 588; height: 68; radius: 16
                    property bool foc: win.menuSel === index
                    color: foc ? "#29ffffff" : "#0affffff"
                    Behavior on color { ColorAnimation { duration: 120 } }
                    Rectangle { anchors.fill: parent; anchors.margins: -3; radius: 19; color: "transparent"; border.width: 3; border.color: "#e8e8e8"; opacity: parent.foc ? 1 : 0 }
                    Text { x: 24; anchors.verticalCenter: parent.verticalCenter; text: modelData.label; font.pixelSize: 30; color: parent.foc ? "#ffffff" : "#9a9a9a"; font.family: "LG Smart UI" }
                    MouseArea { anchors.fill: parent; hoverEnabled: true
                        onPositionChanged: win.menuSel = index
                        onClicked: { win.menuSel = index; win.chooseMenu() } }
                }
            }
        }
        MouseArea { anchors.fill: parent; z: -1 }     // swallow clicks on the panel itself
    }
    MouseArea {                                        // click outside the menu closes it
        anchors.fill: parent; z: 20; enabled: win.menuOpen; visible: win.menuOpen
        onClicked: win.closeMenu()
    }
}
