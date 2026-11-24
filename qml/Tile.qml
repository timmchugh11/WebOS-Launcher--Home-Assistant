import QtQuick 2.4

// One app tile (home screen and All apps page).
Item {
    id: t
    property string title: ""
    property string icon: ""
    property bool focused: false
    property bool moving: false
    property bool pinned: false
    signal hovered()
    signal activated()
    signal held()

    width: 190; height: 200
    z: (focused || moving) ? 5 : 0
    scale: moving ? 1.12 : (focused ? 1.1 : 1.0)
    Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutQuad } }

    Rectangle {
        anchors.fill: parent; radius: 22
        color: t.focused ? "#26ffffff" : "#0bffffff"
        Behavior on color { ColorAnimation { duration: 140 } }
    }
    Rectangle {                                   // focus / move ring
        anchors.fill: parent; anchors.margins: -4; radius: 26
        color: "transparent"; border.width: 4
        border.color: t.moving ? "#ffd166" : "#e8e8e8"
        opacity: (t.focused || t.moving) ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 140 } }
    }
    Rectangle {                                   // placeholder while the icon is missing
        width: 112; height: 112; radius: 14; color: "#14ffffff"
        anchors.horizontalCenter: parent.horizontalCenter; y: 22
        visible: img.status !== Image.Ready
    }
    Image {
        id: img
        width: 112; height: 112; y: 22
        anchors.horizontalCenter: parent.horizontalCenter
        source: t.icon; fillMode: Image.PreserveAspectFit
        asynchronous: true; smooth: true
        sourceSize.width: 224; sourceSize.height: 224
    }
    Text {
        y: 22 + 112 + 16; width: 170; height: 34
        anchors.horizontalCenter: parent.horizontalCenter
        horizontalAlignment: Text.AlignHCenter
        text: t.title; elide: Text.ElideRight; font.pixelSize: 24; font.family: "LG Smart UI"
        color: t.focused ? "#ffffff" : "#8a8a8a"
        Behavior on color { ColorAnimation { duration: 140 } }
    }
    Rectangle {                                   // "already on the home screen" dot (All apps page)
        x: parent.width - 26; y: 12; width: 14; height: 14; radius: 7
        color: "#7fe3d6"; opacity: .85; visible: t.pinned
    }
    MouseArea {
        anchors.fill: parent; hoverEnabled: true
        onPositionChanged: t.hovered()
        onClicked: t.activated()
        onPressAndHold: t.held()
    }
}
