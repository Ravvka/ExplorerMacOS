import SwiftUI

/// "Connect to Server" sheet — protocol picker + host/port/credentials.
struct ConnectToServerView: View {
    @Bindable var connectViewModel: ConnectViewModel
    let onConnect: (RemoteConnection, String) async -> Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Picker("Протокол", selection: $connectViewModel.protocolKind) {
                ForEach(ConnectionProtocolKind.allCases) { kind in
                    Text(kind.displayName).tag(kind)
                }
            }

            TextField("Имя подключения (необязательно)", text: $connectViewModel.displayName)
            TextField("Сервер (хост или IP)", text: $connectViewModel.host)
            TextField("Порт", text: $connectViewModel.portText)

            if connectViewModel.protocolKind == .smb {
                TextField("Общая папка (share)", text: $connectViewModel.shareName)
            }

            TextField("Пользователь", text: $connectViewModel.username)
            SecureField("Пароль", text: $connectViewModel.password)

            if let errorMessage = connectViewModel.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.callout)
            }

            HStack {
                Spacer()
                Button("Отмена") { dismiss() }
                Button {
                    Task {
                        connectViewModel.isConnecting = true
                        connectViewModel.errorMessage = nil
                        let connection = connectViewModel.makeConnection()
                        let succeeded = await onConnect(connection, connectViewModel.password)
                        connectViewModel.isConnecting = false
                        if succeeded {
                            dismiss()
                        }
                    }
                } label: {
                    if connectViewModel.isConnecting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Подключиться")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!connectViewModel.isValid || connectViewModel.isConnecting)
            }
        }
        .padding()
        .frame(width: 380)
    }
}
