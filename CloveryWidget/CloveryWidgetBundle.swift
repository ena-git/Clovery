//
//  CloveryWidgetBundle.swift
//  CloveryWidget
//
//  Created by Irene Liang on 6/22/26.
//

import WidgetKit
import SwiftUI

@main
struct CloveryWidgetBundle: WidgetBundle {
    var body: some Widget {
        CloveryQuickWriteWidget()
        CloveryLeafWidget()
        CloveryDiaryWidget()
        CloveryFieldWidget()
        if #available(iOS 18.0, *) {
            CloveryWidgetControl()
        }
    }
}
