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
    @State private var showAvatarPicker = false

    var body: some View {
        ZStack {
            // Background gradient + subtle decoration
            LinearGradient(colors: [Color(.systemPink).opacity(0.2), Color(.systemPurple).opacity(0.15)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    // MARK: Header
                    VStack(spacing: 12) {
                        Text("Wedding Timeline")
                            .font(.title2).bold()
                        Text("大切な瞬間をみんなでシェア")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 24)

                    // MARK: Card
                    VStack(alignment: .leading, spacing: 16) {
                        FieldLabel(system: "wand.and.stars", title: "Room ID")
                        TextField("ルームIDを入力", text: $vm.roomId)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .modifier(InputField())

                        FieldLabel(system: "key.fill", title: "Room Key")
                        SecureField("ルームキーを入力", text: $vm.roomKey)
                            .modifier(InputField())

                        FieldLabel(system: "person.fill", title: "Username")
                        TextField("ユーザー名を入力", text: $vm.username)
                            .modifier(InputField())

                        FieldLabel(system: "photo.on.rectangle.angled", title: "プロフィールアイコン")
                        Button {
                            showAvatarPicker = true
                        } label: {
                            HStack(spacing: 12) {
                                if let icon = vm.selectedIcon {
                                    Image(icon)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 48, height: 48)
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                } else {
                                    Image(systemName: "person.crop.square.fill")
                                        .font(.system(size: 40))
                                        .frame(width: 48, height: 48)
                                        .foregroundStyle(.secondary)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(vm.selectedIcon ?? "アバター 1")
                                        .font(.subheadline).bold()
                                    Text("タップして変更")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "camera.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 14).fill(Color(.systemGray6)))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(20)
                    .background(
                        RoundedRectangle(cornerRadius: 24)
                            .fill(.white)
                            .shadow(color: .black.opacity(0.06), radius: 18, y: 8)
                    )
                    .padding(.horizontal)

                    // MARK: Join Button
                    Button {
                        Task { await vm.join(session: session) }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.right")
                            Text("入室する")
                                .fontWeight(.semibold)
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            LinearGradient(colors: [Color.pink, Color.purple], startPoint: .leading, endPoint: .trailing)
                        )
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(color: .pink.opacity(0.25), radius: 12, y: 8)
                    }
                    .padding(.horizontal)
                    .disabled(vm.roomId.isEmpty || vm.roomKey.isEmpty || vm.username.isEmpty || vm.isLogin || vm.selectedIcon == nil)
                    .overlay(alignment: .center) {
                        if vm.isLogin { ProgressView().tint(.white) }
                    }

                    if let msg = vm.errorMessage {
                        Text(msg)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .padding(.horizontal)
                    }

                    Spacer(minLength: 24)
                }
                .padding(.vertical)
            }
        }
        .sheet(isPresented: $showAvatarPicker) {
            IconPickerView(selectedIcon: $vm.selectedIcon, icons: vm.icons)
        }
        .onAppear {
            // 既に匿名ログイン済みでなければここで実行しておいてもOK
            Task { _ = try? await RoomRepository().signInAnonymouslyIfNeeded() }
        }
    }
}

// MARK: - Helpers
private struct FieldLabel: View {
    let system: String
    let title: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: system)
                .foregroundStyle(.pink)
            Text(title)
                .font(.subheadline).bold()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct InputField: ViewModifier {
    func body(content: Content) -> some View {
        content
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color(.systemPink).opacity(0.25), lineWidth: 1)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray6)))
            )
    }
}

#Preview {
    LoginView()
}
