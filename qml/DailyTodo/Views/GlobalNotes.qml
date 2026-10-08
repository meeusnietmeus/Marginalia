import QtQuick
import QtQuick.Layouts
import DailyTodo.Style
import DailyTodo.Controls

// The notes and Q&A of a whole resource (not of one page or moment), for every document tab: a
// "Global" heading with a switch between the two, and the list. Give it the tab's notes session
// and the delegate its entries are drawn with (an EntryCard).
ColumnLayout {
    id: global

    property var session: null
    property Component delegate
    property bool qa: false                  // showing the Q&A instead of the notes
    property string emptyNotes: "No global notes yet"
    property string emptyQuestions: "No global questions yet"

    spacing: 10

    Flow {
        Layout.fillWidth: true
        Layout.leftMargin: 14
        spacing: 12
        SectionTitle {
            text: "Global"
            size: 22
            height: 30
        }
        SegmentedSwitch {
            leftText: "Notes (" + (global.session ? global.session.globalNoteCount : 0) + ")"
            rightText: "Q&A (" + (global.session ? global.session.globalQuestionCount : 0) + ")"
            rightActive: global.qa
            onToggledTo: (right) => global.qa = right
        }
    }
    SectionList {
        title: ""
        model: global.session ? (global.qa ? global.session.globalQuestions
                                           : global.session.globalNotes) : null
        delegate: global.delegate
        emptyText: global.qa ? global.emptyQuestions : global.emptyNotes
        Layout.fillWidth: true
        Layout.fillHeight: true
    }
}
