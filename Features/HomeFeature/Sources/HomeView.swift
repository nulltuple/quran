//
//  HomeView.swift
//
//
//  Created by Mohamed Afifi on 2023-07-16.
//

import FeaturesSupport
import HifzReviewFeature
import Localization
import MemorizationPersistence
import MemorizationService
import NoorUI
import QuranAnnotations
import QuranKit
import QuranLocalization
import QuranText
import SwiftUI
import UIx

struct HomeView: View {
    @StateObject var viewModel: HomeViewModel

    var body: some View {
        #if QURAN_SYNC
        HomeViewUI(
            type: viewModel.type,
            readingBookmarks: viewModel.readingBookmarks,
            lastPages: viewModel.lastPages,
            suras: viewModel.suras,
            quarters: viewModel.quarters,
            quranFont: viewModel.reading.quranFont,
            hifzDueCount: viewModel.hifzDueCount,
            hifzRepairCount: viewModel.hifzRepairCount,
            hifzHasHistory: viewModel.hifzHasHistory,
            topDuePassage: viewModel.topDuePassage,
            todayPlan: viewModel.todayPlan,
            start: { await viewModel.start() },
            selectReadingBookmark: { viewModel.navigateTo($0) },
            selectLastPage: { viewModel.navigateTo($0) },
            selectSura: { viewModel.navigateTo($0) },
            selectQuarter: { viewModel.navigateTo($0) },
            openGoals: { viewModel.openGoals() },
            openGoal: { viewModel.openGoal($0) },
            openMemorization: { viewModel.openMemorization() },
            openRepairQueue: { viewModel.openRepairQueue() },
            openSpotTest: { viewModel.openSpotTest() },
            practiceTopDue: { viewModel.practiceTopDuePassage() },
            surahSortOrder: viewModel.surahSortOrder,
            isJuzExpanded: { viewModel.isJuzExpanded($0) },
            setJuzExpanded: { viewModel.setJuz($0, expanded: $1) }
        )
        #else
        HomeViewUI(
            type: viewModel.type,
            lastPages: viewModel.lastPages,
            suras: viewModel.suras,
            quarters: viewModel.quarters,
            quranFont: viewModel.reading.quranFont,
            hifzDueCount: viewModel.hifzDueCount,
            hifzRepairCount: viewModel.hifzRepairCount,
            hifzHasHistory: viewModel.hifzHasHistory,
            topDuePassage: viewModel.topDuePassage,
            todayPlan: viewModel.todayPlan,
            start: { await viewModel.start() },
            selectLastPage: { viewModel.navigateTo($0) },
            selectSura: { viewModel.navigateTo($0) },
            selectQuarter: { viewModel.navigateTo($0) },
            openGoals: { viewModel.openGoals() },
            openGoal: { viewModel.openGoal($0) },
            openMemorization: { viewModel.openMemorization() },
            openRepairQueue: { viewModel.openRepairQueue() },
            openSpotTest: { viewModel.openSpotTest() },
            practiceTopDue: { viewModel.practiceTopDuePassage() },
            surahSortOrder: viewModel.surahSortOrder,
            isJuzExpanded: { viewModel.isJuzExpanded($0) },
            setJuzExpanded: { viewModel.setJuz($0, expanded: $1) }
        )
        #endif
    }
}

private struct HomeViewUI: View {
    let type: HomeViewType
    #if QURAN_SYNC
    let readingBookmarks: [PlacedReadingBookmark]
    #endif
    let lastPages: [LastPage]
    let suras: [Sura]
    let quarters: [QuarterItem]
    let quranFont: QuranFont
    let hifzDueCount: Int
    let hifzRepairCount: Int
    let hifzHasHistory: Bool
    let topDuePassage: Passage?
    let todayPlan: TodayPlanSummary

    let start: AsyncAction

    #if QURAN_SYNC
    let selectReadingBookmark: ItemAction<PlacedReadingBookmark>
    #endif
    let selectLastPage: ItemAction<LastPage>
    let selectSura: ItemAction<Sura>
    let selectQuarter: ItemAction<QuarterItem>
    let openGoals: Action
    let openGoal: ItemAction<GoalProgressSnapshot>
    let openMemorization: Action
    let openRepairQueue: Action
    let openSpotTest: Action
    let practiceTopDue: Action
    let surahSortOrder: SurahSortOrder
    let isJuzExpanded: (Juz) -> Bool
    let setJuzExpanded: (Juz, Bool) -> Void

    var body: some View {
        ZStack {
            NoorList {
                #if QURAN_SYNC
                ContinueReadingSection(
                    title: l("home.continue-reading.title"),
                    readingBookmarks: readingBookmarks,
                    lastPages: lastPages,
                    selectReadingBookmark: selectReadingBookmark,
                    selectLastPage: selectLastPage
                )
                #else
                ContinueReadingSection(title: l("home.continue-reading.title"), lastPages: lastPages, selectLastPage: selectLastPage)
                #endif

                todaySection

                memorizationSection

                switch type {
                case .suras:
                    sectionsView(items: suras, groupBy: \.page.startJuz) { sura in
                        suraView(sura)
                    }
                case .juzs:
                    sectionsView(items: quarters, groupBy: \.quarter.juz) { quarter in
                        quarterView(quarter)
                    }
                }
            }
            // iOS 15's SwiftUI List produces invalid UITableView batch updates when
            // every section and row moves at once. Replace the list snapshot instead.
            .id(surahSortOrder.rawValue)
        }
        .task { await start() }
    }

    var todaySection: some View {
        let scheduled = todayPlan.scheduledTodayGoals
        let streakDays = todayPlan.streak.currentStreakDays
        var parts: [String] = []
        if !scheduled.isEmpty {
            parts.append(lFormat(
                "goals.home.goals_progress",
                NumberFormatter.shared.format(todayPlan.completedTodayGoalCount),
                NumberFormatter.shared.format(scheduled.count)
            ))
        }
        if todayPlan.todayTotalSeconds > 0 {
            parts.append(GoalsViewModel.formatMinutes(fromSeconds: todayPlan.todayTotalSeconds))
        }
        if streakDays > 0 {
            parts.append(lFormat("goals.streak.days", NumberFormatter.shared.format(streakDays)))
        }
        let summarySubtitle = parts.isEmpty ? l("goals.home.setup") : parts.joined(separator: " · ")

        return NoorBasicSection(title: l("goals.section.today")) {
            NoorListItem(
                image: .init(.studyGoal),
                title: .text(l("goals.title")),
                subtitle: .init(text: .text(summarySubtitle), location: .bottom),
                accessory: .disclosureIndicator,
                action: .sync { openGoals() }
            )

            ForEach(Array(scheduled.prefix(3))) { snapshot in
                let progressText: String = if snapshot.isTodayMet {
                    l("goals.status.done_today")
                } else {
                    GoalsViewModel.formatProgressRatio(
                        completed: snapshot.todayCompleted,
                        target: snapshot.todayTarget,
                        unit: snapshot.goal.unit
                    )
                }
                let subtitleText: String = if let nextPage = snapshot.nextKhatmahPage, !snapshot.isTodayMet {
                    "\(progressText) · \(lFormat("goals.action.open_page", NumberFormatter.shared.format(nextPage)))"
                } else {
                    progressText
                }
                NoorListItem(
                    image: .init(
                        snapshot.isTodayMet ? .goalComplete : GoalsViewModel.activityImage(snapshot.goal.activity),
                        color: snapshot.isTodayMet ? .green : nil
                    ),
                    title: .text(GoalsViewModel.displayTitle(for: snapshot.goal)),
                    subtitle: .init(text: .text(subtitleText), location: .bottom),
                    accessory: .disclosureIndicator,
                    action: .sync { openGoal(snapshot) }
                )
            }
        }
    }

    var memorizationSection: some View {
        let subtitle: String = if hifzDueCount > 0 {
            lFormat("hifz_review.home.due_count", NumberFormatter.shared.format(hifzDueCount))
        } else if hifzHasHistory {
            l("hifz_review.home.caught_up")
        } else {
            l("hifz_review.home.setup")
        }

        return NoorBasicSection(title: l("hifz_review.title")) {
            NoorListItem(
                image: .init(.reviewQueue),
                title: .text(l("hifz_review.home.entry")),
                subtitle: .init(text: .text(subtitle), location: .bottom),
                accessory: .disclosureIndicator,
                action: .sync { openMemorization() }
            )

            if let topDuePassage {
                let range: MultipartText = "\(ayahRange: topDuePassage.first ... topDuePassage.last)"
                NoorListItem(
                    image: .init(.hifzPractice),
                    title: .text(l("hifz_review.home.start_next")),
                    subtitle: .init(text: range, location: .bottom),
                    accessory: .disclosureIndicator,
                    action: .sync { practiceTopDue() }
                )
            }

            if hifzRepairCount > 0 {
                NoorListItem(
                    image: .init(.repairQueue),
                    title: .text(l("repair_queue.home.title")),
                    subtitle: .init(
                        text: .text(lFormat("repair_queue.home.count", NumberFormatter.shared.format(hifzRepairCount))),
                        location: .bottom
                    ),
                    accessory: .disclosureIndicator,
                    action: .sync { openRepairQueue() }
                )
            }

            NoorListItem(
                image: .init(.spotTest),
                title: .text(l("hifz_test.title")),
                subtitle: .init(text: .text(l("hifz_test.home.subtitle")), location: .bottom),
                accessory: .disclosureIndicator,
                action: .sync { openSpotTest() }
            )
        }
    }

    func suraView(_ sura: Sura) -> some View {
        let ayahsString = lFormat("verses", table: .android, sura.verses.count)
        let suraType = sura.isMakki ? lAndroid("makki") : lAndroid("madani")
        var subtitleComponents = [suraType, ayahsString]
        if !Locale.preferredLanguageLocale.isArabicLanguage {
            subtitleComponents.insert(sura.localizedTranslatedName(), at: 0)
        }
        let subtitle = subtitleComponents.joined(separator: " · ")

        return NoorListItem(
            title: "\(sura.localizedSuraNumber). \(sura: sura, nameStyle: .decorated)",
            subtitle: .init(text: .text(subtitle), location: .bottom),
            accessory: .text(sura.page.localizedNumber, accessibilityLabel: sura.page.localizedName),
            action: .sync { selectSura(sura) }
        )
    }

    func quarterView(_ item: QuarterItem) -> some View {
        let quarter = item.quarter
        let ayah = quarter.firstVerse
        let page = ayah.page

        return NoorListItem(
            subheading: .text(quarter.localizedName),
            title: "\(ayah: ayah, nameStyle: .decorated)",
            rightSubtitle: "\(quran: item.ayahText, font: quranFont, lineLimit: 1)",
            accessory: .text(page.localizedNumber, accessibilityLabel: page.localizedName),
            action: .sync { selectQuarter(item) }
        )
    }

    @ViewBuilder
    func sectionsView<Item: Identifiable>(
        items: [Item],
        groupBy: (Item) -> Juz,
        @ViewBuilder listItem: @escaping (Item) -> some View
    ) -> some View {
        let itemsByJuz = Dictionary(grouping: items, by: groupBy)
        let juzs = itemsByJuz.keys.sorted {
            surahSortOrder.rawValue * ($0.juzNumber - $1.juzNumber) < 0
        }

        ForEach(juzs) { juz in
            let items = (itemsByJuz[juz] ?? []).sorted {
                switch ($0, $1) {
                case let (thisSura as Sura, thatSura as Sura):
                    surahSortOrder.rawValue * (thisSura.suraNumber - thatSura.suraNumber) < 0
                case let (thisQuarter as QuarterItem, thatQuarter as QuarterItem):
                    surahSortOrder.rawValue * (thisQuarter.quarter.quarterNumber - thatQuarter.quarter.quarterNumber) < 0
                default:
                    false
                }
            }
            let isExpanded = Binding(
                get: { isJuzExpanded(juz) },
                set: { setJuzExpanded(juz, $0) }
            )
            NoorSection(title: juz.localizedName, isExpanded: isExpanded, items) { item in
                listItem(item)
            }
        }
    }
}

@MainActor
private struct HomePreview: View {
    static let ayahText: QuranText = "وَإِذۡ قَالَ مُوسَىٰ لِقَوۡمِهِۦ يَٰقَوۡمِ إِنَّكُمۡ ظَلَمۡتُمۡ أَنفُسَكُم بِٱتِّخَاذِكُمُ ٱلۡعِجۡلَ فَتُوبُوٓاْ إِلَىٰ بَارِئِكُمۡ فَٱقۡتُلُوٓاْ أَنفُسَكُمۡ ذَٰلِكُمۡ خَيۡرٞ لَّكُمۡ عِندَ بَارِئِكُمۡ فَتَابَ عَلَيۡكُمۡۚ إِنَّهُۥ هُوَ ٱلتَّوَّابُ ٱلرَّحِيمُ"

    static var staticLastPages: [LastPage] {
        let pages = [0, 4, 49, 76, 105, 127, 150, 176, 200, 221].map { Quran.hafsMadani1405.pages[$0] }
        return (0 ..< pages.count).map { i -> LastPage in
            let timestamp = Date(timeIntervalSinceNow: -Double(i * 31 + 1) * 60)
            #if QURAN_SYNC
            return LastPage(
                id: "preview-\(i)",
                page: pages[i],
                modifiedOn: timestamp
            )
            #else
            return LastPage(
                page: pages[i],
                createdOn: timestamp,
                modifiedOn: timestamp
            )
            #endif
        }
    }

    let quran = Quran.hafsMadani1405

    @State var lastPages: [LastPage] = staticLastPages
    #if QURAN_SYNC
    @State var readingBookmarks: [PlacedReadingBookmark] = [
        PlacedReadingBookmark(
            id: "preview-orange", slot: .orange,
            placement: .ayah(Quran.hafsMadani1405.suras[0].verses[5]),
            modifiedOn: Date(timeIntervalSinceNow: -36000)
        ),
        PlacedReadingBookmark(
            id: "preview-teal", slot: .teal,
            placement: .page(Quran.hafsMadani1405.pages[22]),
            modifiedOn: Date(timeIntervalSinceNow: -86400)
        ),
        PlacedReadingBookmark(
            id: "preview-red", slot: .red,
            placement: .ayah(Quran.hafsMadani1405.suras[35].verses[57]),
            modifiedOn: Date(timeIntervalSinceNow: -259_200)
        ),
    ]
    #endif
    @State var type: HomeViewType = .suras
    @State var collapsedJuzs: Set<Juz> = []

    var body: some View {
        NavigationView {
            Group {
                #if QURAN_SYNC
                HomeViewUI(
                    type: type,
                    readingBookmarks: readingBookmarks,
                    lastPages: lastPages,
                    suras: quran.suras,
                    quarters: quran.quarters.map { QuarterItem(quarter: $0, ayahText: Self.ayahText) },
                    quranFont: .uthmanicHafs,
                    hifzDueCount: 3,
                    hifzRepairCount: 1,
                    hifzHasHistory: true,
                    topDuePassage: Passage(quran.suras[111].firstVerse, quran.suras[111].lastVerse),
                    todayPlan: .empty(on: Date()),
                    start: {},
                    selectReadingBookmark: { _ in },
                    selectLastPage: { _ in },
                    selectSura: { _ in },
                    selectQuarter: { _ in },
                    openGoals: {},
                    openGoal: { _ in },
                    openMemorization: {},
                    openRepairQueue: {},
                    openSpotTest: {},
                    practiceTopDue: {},
                    surahSortOrder: .ascending,
                    isJuzExpanded: { !collapsedJuzs.contains($0) },
                    setJuzExpanded: { juz, expanded in
                        if expanded { collapsedJuzs.remove(juz) } else { collapsedJuzs.insert(juz) }
                    }
                )
                #else
                HomeViewUI(
                    type: type,
                    lastPages: lastPages,
                    suras: quran.suras,
                    quarters: quran.quarters.map { QuarterItem(quarter: $0, ayahText: Self.ayahText) },
                    quranFont: .uthmanicHafs,
                    hifzDueCount: 3,
                    hifzRepairCount: 1,
                    hifzHasHistory: true,
                    topDuePassage: Passage(quran.suras[111].firstVerse, quran.suras[111].lastVerse),
                    todayPlan: .empty(on: Date()),
                    start: {},
                    selectLastPage: { _ in },
                    selectSura: { _ in },
                    selectQuarter: { _ in },
                    openGoals: {},
                    openGoal: { _ in },
                    openMemorization: {},
                    openRepairQueue: {},
                    openSpotTest: {},
                    practiceTopDue: {},
                    surahSortOrder: .ascending,
                    isJuzExpanded: { !collapsedJuzs.contains($0) },
                    setJuzExpanded: { juz, expanded in
                        if expanded { collapsedJuzs.remove(juz) } else { collapsedJuzs.insert(juz) }
                    }
                )
                #endif
            }
            .navigationTitle("Home")
            .toolbar {
                if type == .suras {
                    Button("Juzs") { type = .juzs }
                } else {
                    Button("Suras") { type = .suras }
                }

                if lastPages.isEmpty {
                    Button("Populate Last Pages") { lastPages = Self.staticLastPages }
                } else {
                    Button("Empty") { lastPages = [] }
                }
            }
        }
    }
}

#Preview {
    HomePreview()
}
