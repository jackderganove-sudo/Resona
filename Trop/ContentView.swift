//
//  ContentView.swift
//  Trop / Resona
//
//  Root layout: tab content, floating navigation bar (compact) or navigation
//  rail (regular width), the floating mini player and the full player sheet
//  that can be dragged open from the mini player.
//

import Combine
import SwiftUI

struct ContentView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(\.m3) private var m3
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var nowPlaying = NowPlaying.shared
    @State private var selectedTab = ResonaTab(index: SettingsStore.shared.defaultTab)
    @State private var scrollState = MiniPlayerScrollState()
    private let accountMenu = AccountMenuState.shared
    private let updates = UpdateChecker.shared

    /// 0 = collapsed (mini player), 1 = full player.
    @State private var expansion: CGFloat = 0
    @State private var isExpanded = false
    @State private var isDraggingPlayer = false

    private var usesRail: Bool { horizontalSizeClass == .regular }
    private var miniPlayerVisible: Bool { nowPlaying.isBarPresented }

    var body: some View {
        GeometryReader { geo in
            let height = geo.size.height + geo.safeAreaInsets.top + geo.safeAreaInsets.bottom
            ZStack(alignment: .bottom) {
                m3.surface.ignoresSafeArea()

                if usesRail {
                    HStack(spacing: 0) {
                        NavigationRail(selection: $selectedTab, onReselect: popToRoot)
                        ZStack(alignment: .bottom) {
                            tabContent
                            bottomChrome(height: height, bottomInset: geo.safeAreaInsets.bottom)
                                .frame(maxWidth: 640)
                                .padding(.horizontal, 16)
                        }
                    }
                } else {
                    tabContent
                    bottomChrome(height: height, bottomInset: geo.safeAreaInsets.bottom)
                        .padding(.horizontal, M3Metrics.navigationBarHorizontalPadding)
                }

                if isExpanded || expansion > 0 {
                    PlayerSheetHost(
                        expansion: expansion,
                        height: height,
                        onCollapse: { collapse() },
                        onDrag: { translation in
                            isDraggingPlayer = true
                            expansion = 1 - max(0, translation) / height
                        },
                        onDragEnded: { translation, predicted in
                            isDraggingPlayer = false
                            if predicted > height * 0.35 || translation > height * 0.25 {
                                collapse()
                            } else {
                                expand()
                            }
                        }
                    )
                    .zIndex(10)
                }

                if accountMenu.isPresented {
                    AccountMenuOverlay()
                        .zIndex(30)
                }

                if let update = updates.available, !updates.bannerDismissed, !isExpanded {
                    VStack {
                        UpdateBanner(update: update)
                            .padding(.top, 8)
                        Spacer()
                    }
                    .zIndex(25)
                }
            }
            .ignoresSafeArea(.keyboard)
        }
        .environment(scrollState)
        .onAppear {
            AppRouter.shared.selectedTabIndex = selectedTab.rawValue
            updates.checkIfDue()
        }
        .animation(M3Motion.defaultSpatial, value: updates.available)
        .animation(M3Motion.defaultSpatial, value: updates.bannerDismissed)
        .onChange(of: selectedTab) { _, newValue in
            AppRouter.shared.selectedTabIndex = newValue.rawValue
        }
        .onReceive(AppRouter.shared.$selectedTabIndex) { index in
            let tab = ResonaTab(index: index)
            if tab != selectedTab { selectedTab = tab }
        }
        .onReceive(AppRouter.shared.$activeRoute) { route in
            // A detail page was opened from an overlay: collapse the player so
            // the pushed page is visible underneath.
            if route != nil { collapse() }
        }
        .onReceive(AppRouter.shared.$playerExpandToken.dropFirst()) { _ in
            expand()
        }
        .onReceive(AppRouter.shared.$goHomeToken.dropFirst()) { _ in
            goHome()
        }
        .onChange(of: nowPlaying.isBarPresented) { _, presented in
            if !presented { collapse() }
        }
        .simultaneousGesture(backSwipeGesture)
    }

    // MARK: Tabs

    /// All tabs stay alive so every tab keeps its navigation stack and
    /// scroll position; only the selected one is visible and interactive.
    private var tabContent: some View {
        ZStack {
            ForEach(ResonaTab.ordered) { tab in
                tabView(tab)
                    .environment(\.usesNavigationRail, usesRail)
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        Color.clear.frame(height: bottomContentInset)
                    }
                    .opacity(tab == selectedTab ? 1 : 0)
                    .allowsHitTesting(tab == selectedTab)
                    .accessibilityHidden(tab != selectedTab)
            }
        }
    }

    @ViewBuilder
    private func tabView(_ tab: ResonaTab) -> some View {
        switch tab {
        case .home: HomeScreenView()
        case .search: SearchView()
        case .library: LibraryView()
        }
    }

    /// Bottom padding of the floating chrome inside the safe area.
    private var chromeBottomPadding: CGFloat { usesRail ? 12 : 4 }

    /// Exactly the height the floating chrome occupies above the safe area,
    /// plus breathing room, so no scrollable content ends up under it.
    private var bottomContentInset: CGFloat {
        var inset = chromeBottomPadding + 16
        if !usesRail { inset += M3Metrics.navigationBarHeight }
        if miniPlayerVisible {
            inset += M3Metrics.miniPlayerHeight + (usesRail ? 0 : 8)
        }
        return inset
    }

    // MARK: Bottom chrome (mini player + bar)

    private func bottomChrome(height: CGFloat, bottomInset: CGFloat) -> some View {
        VStack(spacing: 8) {
            if miniPlayerVisible {
                MiniPlayer(
                    navigationProximity: usesRail ? 0 : 1,
                    onExpand: { expand() },
                    onVerticalDrag: { translation in
                        isDraggingPlayer = true
                        expansion = min(1, max(0, -translation / height))
                    },
                    onVerticalDragEnded: { translation, predicted in
                        isDraggingPlayer = false
                        if -predicted > height * 0.3 || -translation > height * 0.2 {
                            expand()
                        } else {
                            collapse()
                        }
                    }
                )
                .opacity(1 - min(1, expansion * 2.5))
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if !usesRail {
                FloatingNavigationBar(
                    selection: $selectedTab,
                    miniPlayerProximity: miniPlayerVisible ? 1 : 0,
                    onReselect: popToRoot
                )
                .offset(y: expansion * (M3Metrics.navigationBarHeight + bottomInset + 20))
            }
        }
        .padding(.bottom, chromeBottomPadding)
        .animation(M3Motion.navigationBar, value: miniPlayerVisible)
    }

    // MARK: Player expansion

    private func expand() {
        guard nowPlaying.isBarPresented else { return }
        // Dismiss the keyboard so the reveal is visible on the first tap.
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        isExpanded = true
        withAnimation(M3Motion.bottomSheet) { expansion = 1 }
    }

    private func collapse() {
        guard isExpanded || expansion > 0 else { return }
        withAnimation(M3Motion.bottomSheet) {
            expansion = 0
        } completion: {
            if expansion == 0 { isExpanded = false }
        }
    }

    // MARK: Navigation helpers

    /// Logo tap: close sheets, menu and player, select Home, pop its stack
    /// to the root and scroll to the top.
    private func goHome() {
        Self.dismissPresentedSheets()
        if accountMenu.isPresented {
            withAnimation(M3Motion.defaultSpatial) { accountMenu.isPresented = false }
        }
        collapse()
        if selectedTab != .home {
            withAnimation(M3Motion.defaultSpatial) { selectedTab = .home }
        }
        popToRoot(.home)
        AppRouter.shared.scrollHomeToTop()
    }

    private static func dismissPresentedSheets() {
        for scene in UIApplication.shared.connectedScenes {
            guard let root = (scene as? UIWindowScene)?.keyWindow?.rootViewController,
                  root.presentedViewController != nil else { continue }
            root.dismiss(animated: true)
        }
    }

    private func popToRoot(_ tab: ResonaTab) {
        let router = AppRouter.shared
        withAnimation(M3Motion.defaultSpatial) {
            switch tab {
            case .home: router.homePath = NavigationPath()
            case .search:
                router.searchPath = NavigationPath()
                router.explorePath = NavigationPath()
            case .library: router.libraryPath = NavigationPath()
            }
        }
    }

    private var backSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .onEnded { value in
                let isHorizontal = abs(value.translation.width) > abs(value.translation.height)
                guard !isExpanded,
                      value.startLocation.x <= 28,
                      isHorizontal,
                      value.translation.width > 80 else { return }

                let router = AppRouter.shared
                let depth = router.activePathDepth
                guard depth > 0 else { return }
                guard !isExpanded, router.activePathDepth == depth else { return }
                router.popActiveRoute()
            }
    }
}

private struct UsesNavigationRailKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// True when the side navigation rail (with the brand mark) is shown.
    var usesNavigationRail: Bool {
        get { self[UsesNavigationRailKey.self] }
        set { self[UsesNavigationRailKey.self] = newValue }
    }
}

/// Positions the full player for a given expansion and forwards its
/// pull-down gesture.
private struct PlayerSheetHost: View {
    let expansion: CGFloat
    let height: CGFloat
    let onCollapse: () -> Void
    let onDrag: (CGFloat) -> Void
    let onDragEnded: (CGFloat, CGFloat) -> Void

    var body: some View {
        FullPlayerView(onCollapse: onCollapse)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .offset(y: (1 - expansion) * height)
            .environment(\.playerSheetDrag, PlayerSheetDrag(onChanged: onDrag, onEnded: onDragEnded))
    }
}

/// Lets the full player report its collapse drag to the host.
struct PlayerSheetDrag {
    var onChanged: (CGFloat) -> Void = { _ in }
    var onEnded: (CGFloat, CGFloat) -> Void = { _, _ in }
}

private struct PlayerSheetDragKey: EnvironmentKey {
    static let defaultValue = PlayerSheetDrag()
}

extension EnvironmentValues {
    var playerSheetDrag: PlayerSheetDrag {
        get { self[PlayerSheetDragKey.self] }
        set { self[PlayerSheetDragKey.self] = newValue }
    }
}

#Preview {
    ContentView()
}
