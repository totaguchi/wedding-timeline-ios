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

    @FocusState private var focus: FocusField?
    private enum FocusField { case roomId, roomKey, username }

    private var joinEnabled: Bool {
        let idOK  = !vm.roomId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let keyOK = !vm.roomKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let nameOK = !vm.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return idOK && keyOK && nameOK && vm.selectedIcon != nil && !vm.isLogin
    }

    @ViewBuilder
    private var joinButtonBackground: some View {
        if joinEnabled {
            LinearGradient(
                colors: [TLColor.btnCategorySelFrom, TLColor.icoCategoryPurple],
                startPoint: .leading, endPoint: .trailing
            )
        } else {
            TLColor.borderCard // 無効時は薄いグレー系
        }
    }

    var body: some View {
        ZStack {
            // Background gradient + subtle decoration
            LinearGradient(colors: [TLColor.btnCategorySelFrom.opacity(0.2), TLColor.icoCategoryPurple.opacity(0.15)],
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
                            .foregroundStyle(TLColor.textMeta)
                    }
                    .padding(.top, 24)

                    if let msg = vm.errorMessage {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.subheadline)
                                .foregroundStyle(TLColor.textDeleteTitle)
                                .padding(.top, 2)
                            Text(msg)
                                .font(.footnote)
                                .foregroundStyle(TLColor.textDeleteTitle)
                                .multilineTextAlignment(.leading)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.red.opacity(0.08))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(TLColor.textDeleteTitle.opacity(0.25), lineWidth: 1)
                        )
                        .padding(.horizontal)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .animation(.easeInOut(duration: 0.2), value: vm.errorMessage)
                    }

                    // MARK: Card
                    VStack(alignment: .leading, spacing: 16) {
                        FieldLabel(system: "wand.and.stars", title: "Room ID")
                        TextField("ルームIDを入力", text: $vm.roomId)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .modifier(InputField())
                            .focused($focus, equals: .roomId)
                            .submitLabel(.next)

                        FieldLabel(system: "key.fill", title: "Room Key")
                        SecureField("ルームキーを入力", text: $vm.roomKey)
                            .modifier(InputField())
                            .focused($focus, equals: .roomKey)
                            .submitLabel(.next)

                        FieldLabel(system: "person.fill", title: "Username")
                        TextField("ユーザー名を入力", text: $vm.username)
                            .modifier(InputField())
                            .focused($focus, equals: .username)
                            .submitLabel(.join)

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
                                        .foregroundStyle(TLColor.textMeta)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(vm.selectedIcon ?? "アバター")
                                        .font(.subheadline).bold()
                                    Text("タップして変更")
                                        .font(.caption)
                                        .foregroundStyle(TLColor.textMeta)
                                }
                                Spacer()
                                Image(systemName: "camera.fill")
                                    .foregroundStyle(TLColor.textMeta)
                            }
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 14).fill(TLColor.bgCard))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(20)
                    .background(
                        RoundedRectangle(cornerRadius: 24)
                            .fill(AppColor.white)
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
                        .background(joinButtonBackground)
                        .foregroundStyle(joinEnabled ? TLColor.btnCategorySelText : TLColor.textMeta)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .strokeBorder(joinEnabled ? .clear : TLColor.borderCard.opacity(0.8), lineWidth: 1)
                        )
                        .shadow(color: TLColor.hoverTextPink500.opacity(joinEnabled ? 0.25 : 0.0), radius: 12, y: 8)
                    }
                    .padding(.horizontal)
                    .disabled(!joinEnabled)
                    .opacity(joinEnabled ? 1 : 0.6)
                    .animation(.easeInOut(duration: 0.2), value: joinEnabled)
                    .overlay(alignment: .center) {
                        if vm.isLogin { ProgressView().tint(TLColor.btnCategorySelText) }
                    }

                    Spacer(minLength: 24)
                }
                .padding(.vertical)
            }
        }
        .onSubmit {
            switch focus {
            case .roomId:
                focus = .roomKey
            case .roomKey:
                focus = .username
            case .username:
                if joinEnabled {
                    Task { await vm.join(session: session) }
                }
            case .none:
                break
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
                .foregroundStyle(TLColor.icoCategoryPink)
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
                    .strokeBorder(TLColor.borderCard.opacity(0.25), lineWidth: 1)
                    .background(RoundedRectangle(cornerRadius: 12).fill(TLColor.bgCard))
            )
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

#Preview {
    LoginView()
}
