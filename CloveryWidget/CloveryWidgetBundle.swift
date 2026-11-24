import WidgetKit
import SwiftUI

@main
struct CloveryWidgetBundle: WidgetBundle {
    var body: some Widget {
        CloveryQuickWriteWidget()
        CloveryLeafWidget()
        CloveryDiaryWidget()
        CloveryFieldWidget()
        CloveryLockScreenWidget()
    }
}
