import SwiftUI

struct CaptureItemRow: View {
    let item: CaptureItem

    var body: some View {
        switch item {
        case .text:
            EmptyView()

        case .image(let filename, _):
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(.darkGray))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Image(systemName: "photo")
                            .foregroundColor(.gray)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(filename)
                        .font(.system(size: 12))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(8)
            .background(Color(.darkGray).opacity(0.3))
            .cornerRadius(8)

        case .video(let filename, _):
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(.darkGray))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Image(systemName: "video")
                            .foregroundColor(.gray)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(filename)
                        .font(.system(size: 12))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(8)
            .background(Color(.darkGray).opacity(0.3))
            .cornerRadius(8)

        case .link(let url):
            HStack(spacing: 8) {
                Image(systemName: "link")
                    .foregroundColor(.blue)
                    .frame(width: 24, height: 24)
                Text(url.absoluteString)
                    .font(.system(size: 12))
                    .foregroundColor(.blue)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
            }
            .padding(8)
            .background(Color(.darkGray).opacity(0.3))
            .cornerRadius(8)
        }
    }
}
