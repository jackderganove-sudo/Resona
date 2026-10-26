//
//  NavigationTitleView.swift
//  Trop
//
//  Created by 686udjie on 01/07/2026.
//

import SwiftUI

struct NavigationTitleView: View {
    @Environment(\.m3) private var m3
    var title: String
    var label: String?
    var thumbnailUrl: String?
    var onClick: (() -> Void)?

    var body: some View {
        Button(
            action: { onClick?() },
            label: {
                HStack(spacing: 12) {
                    if let thumbnailUrl {
                        AsyncImageView(url: thumbnailUrl)
                            .frame(width: 40, height: 40)
                            .clipShape(Circle())
                    }

                    VStack(alignment: .leading, spacing: 0) {
                        if let label {
                            Text(LocalizedStringKey(label))
                                .font(.m3(.bodyMedium))
                                .foregroundStyle(m3.onSurfaceVariant)
                        }
                        Text(LocalizedStringKey(title))
                            .font(.m3(.headlineSmall))
                            .foregroundStyle(m3.onSurface)
                            .lineLimit(1)
                    }

                    Spacer()

                    if onClick != nil {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(m3.onSurfaceVariant)
                            .frame(width: 40, height: 40)
                            .background(m3.surfaceContainerHigh, in: Circle())
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 20)
                .padding(.bottom, 10)
            }
        )
        .buttonStyle(.plain)
    }
}
