import QtQuick 2.4

// One slow drifting coloured glow (a pre-rendered soft radial image, so it costs almost nothing to move).
Image {
    id: g
    property real cx: 960              // centre of its path
    property real cy: 540
    property real ax: 600              // how far it drifts either way
    property real ay: 300
    property int dx: 24000             // ms for one leg across
    property int dy: 21000
    property real strength: .5
    property bool running: true
    property int size: 900
    width: size; height: size
    smooth: true; opacity: strength
    x: cx - size / 2 - ax; y: cy - size / 2 + ay * .4

    SequentialAnimation on x { loops: Animation.Infinite; running: g.running
        NumberAnimation { to: g.cx - g.size / 2 + g.ax; duration: g.dx; easing.type: Easing.InOutSine }
        NumberAnimation { to: g.cx - g.size / 2 - g.ax; duration: g.dx; easing.type: Easing.InOutSine } }
    SequentialAnimation on y { loops: Animation.Infinite; running: g.running
        NumberAnimation { to: g.cy - g.size / 2 + g.ay; duration: g.dy; easing.type: Easing.InOutSine }
        NumberAnimation { to: g.cy - g.size / 2 - g.ay; duration: g.dy; easing.type: Easing.InOutSine } }
}
