//
//  PetView.swift
//  看板娘
//

import SwiftUI

/// 保留原入口名称，实际桌宠界面由组件化的 PetRootView 提供。
struct PetView: View {
    @ObservedObject var petViewBackend: PetViewBackend

    var body: some View {
        ZStack(alignment: .bottom) {
            PetRootView(petViewBackend: petViewBackend)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }
}
