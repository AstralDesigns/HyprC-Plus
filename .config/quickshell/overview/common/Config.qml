pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

Singleton {
    id: root
    
    property QtObject options: QtObject {
        property QtObject appearance: QtObject {
            property bool useMatugenColors: true
        }

        property QtObject overview: QtObject {
            property bool enable: true
            property int numWorkspaces: 10        // Number of workspace rows shown
            property real workspaceLabelWidth: 52 // px width of the workspace number cell
            property real windowStripSpacing: 6   // px spacing between window preview cells
            property bool hideEmptyWorkspaces: false // Hide workspace rows with no windows (except active)
        }
        
        property QtObject hacks: QtObject {
            property int arbitraryRaceConditionDelay: 150
        }
    }
}
