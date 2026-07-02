import SwiftUI
import WidgetKit

@main
struct FlowBridgeWidgetsBundle: WidgetBundle {
    var body: some Widget {
        DictationLiveActivity()
        DictationControlWidget()
        FlowBridgeHomeWidget()
    }
}
