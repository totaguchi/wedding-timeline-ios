//
//  LoginView.swift
//  WeddingTimeline
//
//  Created by 田口友暉 on 2025/07/24.
//

import SwiftUI

struct LoginView: View {
    @Environment(Session.self) private var session
    @State private var vm = LoginViewModel()

        var body: some View {
            ScrollView {
                VStack(spacing: 16) {
                    TextField("Room ID", text: $vm.roomId)
                        .textFieldStyle(.roundedBorder)
                    SecureField("Room Key", text: $vm.roomKey)
                        .textFieldStyle(.roundedBorder)
                    TextField("Username", text: $vm.username)
                        .textFieldStyle(.roundedBorder)
                    Grid {
                        ForEach(0..<2, id: \.self) { row in
                            GridRow {
                                ForEach(0..<3, id: \.self) { col in
                                    let index = row * 3 + col
                                    if index < vm.icons.count {
                                        let icon = vm.icons[index]
                                        Button {
                                            vm.selectedIcon = icon
                                        } label: {
                                            Image(icon)
                                                .resizable()
                                                .frame(width: 50, height: 50)
                                                .clipShape(RoundedRectangle(cornerRadius: 25))
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 25)
                                                        .stroke(vm.selectedIcon == icon ? Color.blue : Color.clear, lineWidth: 3)
                                                )
                                        }
                                    } else {
                                        Spacer()
                                    }
                                }
                            }
                        }
                    }
                    
                    Button {
                        Task {
                            await vm.join(session: session)
                        }
                    } label: {
                        if vm.isLogin { ProgressView() }
                        else { Text("入室する") }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(vm.roomId.isEmpty || vm.roomKey.isEmpty || vm.username.isEmpty || vm.isLogin || vm.selectedIcon == nil)
                    
                    if let msg = vm.errorMessage {
                        Text(msg).foregroundColor(.red)
                    }
                }
                .padding()
                .onAppear {
                    // 既に匿名ログイン済みでなければここで実行しておいてもOK
                    Task { _ = try? await RoomRepository().signInAnonymouslyIfNeeded() }
                }
            }
        }
}

#Preview {
    LoginView()
}
