//
//  DetailSkeletonView.swift
//  Resona
//
//  Full-width loading placeholder shaped like a detail page: hero area with
//  title, subtitle and the action row, followed by song rows — replaces the
//  centred spinner that only filled a narrow strip on wide screens.
//

import SwiftUI

struct DetailSkeletonView: View {
    @Environment(\.m3) private var m3
    var rows = 10

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottom) {
                ShimmerFill(radius: 0)
                    .frame(height: 420)
                LinearGradient(colors: [.clear, m3.surface], startPoint: .center, endPoint: .bottom)
                VStack(spacing: 12) {
                    ShimmerBlock(width: 240, height: 30, radius: 10)
                    ShimmerBlock(width: 150, height: 18, radius: 8)
                    HStack(spacing: 12) {
                        ShimmerBlock(width: 52, height: 52, radius: 26)
                        ShimmerBlock(width: 130, height: 56, radius: 28)
                        ShimmerBlock(width: 52, height: 52, radius: 26)
                        ShimmerBlock(width: 52, height: 52, radius: 26)
                    }
                    .padding(.top, 10)
                }
                .padding(.bottom, 24)
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 0) {
                ForEach(0..<rows, id: \.self) { i in
                    HStack(spacing: 16) {
                        ShimmerBlock(width: M3Metrics.listThumbnail, height: M3Metrics.listThumbnail, radius: M3Metrics.thumbnailRadius)
                        VStack(alignment: .leading, spacing: 8) {
                            ShimmerBlock(width: [200, 160, 230, 180][i % 4], height: 16, radius: 6)
                            ShimmerBlock(width: [120, 140, 100, 130][i % 4], height: 13, radius: 6)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
            }
            .frame(maxWidth: M3Metrics.contentMaxWidth)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .accessibilityLabel(Text("Loading"))
    }
}
