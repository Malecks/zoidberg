import SwiftUI

struct ToastView: View {
    let message: String
    let isError: Bool

    var body: some View {
        Text(message)
            .font(.system(size: 11))
            .foregroundColor(isError ? .white : Color(.systemGreen))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(isError ? Color.red.opacity(0.9) : Color.green.opacity(0.15))
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
