import SwiftUI
import PhotosUI
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif
#if canImport(FoundationModels)
import FoundationModels
#endif

enum FocusTimerMode: String, Codable, CaseIterable {
    case countDown
    case countUp

    var title: String {
        self == .countDown ? "Countdown" : "Count Up"
    }
}

struct FocusRecord: Identifiable, Codable, Equatable {
    enum Outcome: String, Codable {
        case completed
        case failed
    }

    let id: UUID
    let name: String
    let duration: TimeInterval
    let finishedAt: Date
    let outcome: Outcome
    let timerMode: FocusTimerMode

    init(
        id: UUID,
        name: String,
        duration: TimeInterval,
        finishedAt: Date,
        outcome: Outcome,
        timerMode: FocusTimerMode
    ) {
        self.id = id
        self.name = name
        self.duration = duration
        self.finishedAt = finishedAt
        self.outcome = outcome
        self.timerMode = timerMode
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, duration, finishedAt, outcome, timerMode
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        duration = try values.decode(TimeInterval.self, forKey: .duration)
        finishedAt = try values.decode(Date.self, forKey: .finishedAt)
        outcome = try values.decode(Outcome.self, forKey: .outcome)
        timerMode = try values.decodeIfPresent(FocusTimerMode.self, forKey: .timerMode) ?? .countDown
    }
}

struct FocusSession: Equatable {
    let id: UUID
    let name: String
    let mode: FocusTimerMode
    let totalDuration: TimeInterval
    var remainingWhenPaused: TimeInterval
    var endDate: Date
    var elapsedWhenPaused: TimeInterval
    var startedAt: Date
    var isPaused: Bool
    var taskID: UUID

    var remaining: TimeInterval {
        isPaused ? remainingWhenPaused : max(0, endDate.timeIntervalSinceNow)
    }

    var elapsed: TimeInterval {
        isPaused ? elapsedWhenPaused : elapsedWhenPaused + max(0, Date().timeIntervalSince(startedAt))
    }
}

struct PlanBlock: Identifiable, Codable, Equatable {
    let id: UUID
    let day: String
    let title: String
    let details: String
    let minutes: Int

    init(id: UUID = UUID(), day: String, title: String, details: String, minutes: Int) {
        self.id = id
        self.day = day
        self.title = title
        self.details = details
        self.minutes = minutes
    }
}

struct BookBookmark: Identifiable, Codable, Equatable {
    let id: UUID
    let name: String
    let imageData: Data?
    var currentPage: Int

    init(id: UUID, name: String, imageData: Data?, currentPage: Int = 0) {
        self.id = id
        self.name = name
        self.imageData = imageData
        self.currentPage = currentPage
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, imageData, currentPage
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        imageData = try values.decodeIfPresent(Data.self, forKey: .imageData)
        currentPage = try values.decodeIfPresent(Int.self, forKey: .currentPage) ?? 0
    }
}

enum AppPage {
    case focus
    case planner
    case books
}

struct ContentView: View {
    @State private var selectedPage: AppPage = .focus
    @State private var questName = ""
    @State private var durationMinutes = 25.0
    @State private var timerMode: FocusTimerMode = .countDown
    @State private var session: FocusSession?
    @State private var records = FocusStorage.load()
    @State private var planBlocks = PlanStorage.load()
    @State private var bookmarks = BookmarkStorage.load()
    @State private var monthlyGoalMinutes = GoalStorage.loadGoal()
    @State private var awardedGoalMonths = GoalStorage.loadAwardedMonths()
    @State private var pendingPlanBlock: PlanBlock?
    @State private var pendingRepeatRecord: FocusRecord?
    @State private var showsEndConfirmation = false
    @State private var showsProfile = false

    var body: some View {
        ZStack {
            CozyBackground()

            Group {
                switch selectedPage {
                case .focus:
                    FocusPage(
                        questName: $questName,
                        durationMinutes: $durationMinutes,
                        timerMode: $timerMode,
                        session: session,
                        records: records,
                        planBlocks: planBlocks,
                        monthlyMinutes: completedMinutesThisMonth,
                        monthlyGoalMinutes: monthlyGoalMinutes,
                        onStart: startQuest,
                        onPauseOrResume: togglePause,
                        onEnd: { showsEndConfirmation = true },
                        onRepeatFocus: { pendingRepeatRecord = $0 }
                    )
                case .planner:
                    WeekPlannerPage(
                        planBlocks: $planBlocks,
                        onStartRequest: { pendingPlanBlock = $0 }
                    )
                case .books:
                    BooksPage(bookmarks: $bookmarks)
                }
            }
            .safeAreaPadding(.bottom, session == nil ? 86 : 0)
        }
        .overlay(alignment: .topLeading) {
            if session == nil {
                Button {
                    showsProfile = true
                } label: {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(CozyColors.espresso, CozyColors.cream)
                        .padding(10)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open profile and medals")
                .padding()
            }
        }
        .safeAreaInset(edge: .bottom) {
            if session == nil {
                CozyTabBar(selectedPage: $selectedPage)
            }
        }
        .alert(session?.mode == .countUp ? "Finish this focus?" : "End this quest?", isPresented: $showsEndConfirmation) {
            Button("Keep Focusing", role: .cancel) {}
            Button(session?.mode == .countUp ? "Finish & Save" : "End & Fail", role: session?.mode == .countUp ? nil : .destructive) {
                endCurrentFocus()
            }
        } message: {
            Text(session?.mode == .countUp
                 ? "Your elapsed focus time will be saved as completed."
                 : "Ending before the timer reaches zero marks this focus quest as failed.")
        }
        .alert("Start this plan block?", isPresented: planBlockAlertBinding, presenting: pendingPlanBlock) { block in
            Button(session == nil ? "Start \(block.minutes) min" : "Switch Focus & Start") {
                startPlanBlock(block)
            }
            Button("Not Now", role: .cancel) {
                pendingPlanBlock = nil
            }
        } message: { block in
            if session == nil {
                Text("\(block.title) will be loaded into a \(block.minutes)-minute focus.")
            } else {
                Text("Your current focus will be marked failed, then \(block.title) will start for \(block.minutes) minutes.")
            }
        }
        .alert("Do this focus again?", isPresented: repeatAlertBinding, presenting: pendingRepeatRecord) { record in
            Button("Continue") {
                repeatFocus(record)
            }
            Button("Cancel", role: .cancel) {
                pendingRepeatRecord = nil
            }
        } message: { record in
            Text(record.timerMode == .countUp
                 ? "Start a new count-up focus named \(record.name)?"
                 : "Start \(record.name) again for \(Int(record.duration / 60)) minutes?")
        }
        .task(id: session?.taskID) {
            guard session?.isPaused == false else { return }

            while !Task.isCancelled {
                guard let session else { return }
                guard session.mode == .countDown else {
                    try? await Task.sleep(for: .seconds(1))
                    continue
                }

                if session.remaining <= 0 {
                    completeQuest()
                    return
                }

                try? await Task.sleep(for: .seconds(0.25))
            }
        }
        .sheet(isPresented: $showsProfile) {
            ProfileView(
                records: records,
                monthlyMinutes: completedMinutesThisMonth,
                monthlyGoalMinutes: $monthlyGoalMinutes,
                awardedGoalMonths: awardedGoalMonths
            )
            .onChange(of: monthlyGoalMinutes) { _, newValue in
                GoalStorage.saveGoal(newValue)
                awardMonthlyMedalIfNeeded()
            }
        }
        .preferredColorScheme(.light)
    }

    private var completedMinutesThisMonth: Int {
        records
            .filter {
                $0.outcome == .completed
                    && Calendar.current.isDate($0.finishedAt, equalTo: Date(), toGranularity: .month)
                    && Calendar.current.isDate($0.finishedAt, equalTo: Date(), toGranularity: .year)
            }
            .reduce(0) { $0 + Int($1.duration / 60) }
    }

    private var planBlockAlertBinding: Binding<Bool> {
        Binding(
            get: { pendingPlanBlock != nil },
            set: { if !$0 { pendingPlanBlock = nil } }
        )
    }

    private var repeatAlertBinding: Binding<Bool> {
        Binding(
            get: { pendingRepeatRecord != nil },
            set: { if !$0 { pendingRepeatRecord = nil } }
        )
    }

    private func startPlanBlock(_ block: PlanBlock) {
        if let current = session {
            save(current, outcome: .failed)
        }

        let duration = TimeInterval(block.minutes * 60)
        questName = block.title
        durationMinutes = Double(block.minutes)
        session = FocusSession(
            id: UUID(),
            name: block.title,
            mode: .countDown,
            totalDuration: duration,
            remainingWhenPaused: duration,
            endDate: Date().addingTimeInterval(duration),
            elapsedWhenPaused: 0,
            startedAt: Date(),
            isPaused: false,
            taskID: UUID()
        )
        pendingPlanBlock = nil
        selectedPage = .focus
    }

    private func startQuest() {
        let trimmedName = questName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmedName.isEmpty ? "Cozy focus" : trimmedName
        let safeMinutes = min(max(durationMinutes.rounded(), 1), 1_440)
        durationMinutes = safeMinutes
        let duration = safeMinutes * 60

        session = FocusSession(
            id: UUID(),
            name: name,
            mode: timerMode,
            totalDuration: timerMode == .countDown ? duration : 0,
            remainingWhenPaused: duration,
            endDate: Date().addingTimeInterval(duration),
            elapsedWhenPaused: 0,
            startedAt: Date(),
            isPaused: false,
            taskID: UUID()
        )
    }

    private func togglePause() {
        guard var current = session else { return }

        if current.isPaused {
            if current.mode == .countDown {
                current.endDate = Date().addingTimeInterval(current.remainingWhenPaused)
            } else {
                current.startedAt = Date()
            }
            current.isPaused = false
        } else {
            if current.mode == .countDown {
                current.remainingWhenPaused = current.remaining
            } else {
                current.elapsedWhenPaused = current.elapsed
            }
            current.isPaused = true
        }

        current.taskID = UUID()
        session = current
    }

    private func completeQuest() {
        guard let current = session else { return }
        save(current, outcome: .completed)
        session = nil
        questName = ""
    }

    private func endCurrentFocus() {
        guard let current = session else { return }
        save(current, outcome: current.mode == .countUp ? .completed : .failed)
        session = nil
        questName = ""
    }

    private func repeatFocus(_ record: FocusRecord) {
        questName = record.name
        timerMode = record.timerMode
        durationMinutes = max(1, record.duration / 60)

        let duration = record.timerMode == .countDown ? record.duration : 0
        session = FocusSession(
            id: UUID(),
            name: record.name,
            mode: record.timerMode,
            totalDuration: duration,
            remainingWhenPaused: duration,
            endDate: Date().addingTimeInterval(duration),
            elapsedWhenPaused: 0,
            startedAt: Date(),
            isPaused: false,
            taskID: UUID()
        )
        pendingRepeatRecord = nil
        selectedPage = .focus
    }

    private func save(_ session: FocusSession, outcome: FocusRecord.Outcome) {
        records.insert(
            FocusRecord(
                id: UUID(),
                name: session.name,
                duration: session.mode == .countUp ? session.elapsed : session.totalDuration,
                finishedAt: Date(),
                outcome: outcome,
                timerMode: session.mode
            ),
            at: 0
        )
        FocusStorage.save(records)

        if outcome == .completed {
            awardMonthlyMedalIfNeeded()
        }
    }

    private func awardMonthlyMedalIfNeeded() {
        guard completedMinutesThisMonth >= monthlyGoalMinutes else { return }
        let monthKey = GoalStorage.currentMonthKey

        if !awardedGoalMonths.contains(monthKey) {
            awardedGoalMonths.insert(monthKey)
            GoalStorage.saveAwardedMonths(awardedGoalMonths)
        }
    }
}

struct CozyBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(red: 0.98, green: 0.93, blue: 0.84),
                Color(red: 0.93, green: 0.89, blue: 0.79),
                Color(red: 0.88, green: 0.91, blue: 0.82)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(.white.opacity(0.28))
                .frame(width: 280)
                .blur(radius: 8)
                .offset(x: 100, y: -100)
        }
    }
}

struct FocusPage: View {
    @Binding var questName: String
    @Binding var durationMinutes: Double
    @Binding var timerMode: FocusTimerMode
    let session: FocusSession?
    let records: [FocusRecord]
    let planBlocks: [PlanBlock]
    let monthlyMinutes: Int
    let monthlyGoalMinutes: Int
    let onStart: () -> Void
    let onPauseOrResume: () -> Void
    let onEnd: () -> Void
    let onRepeatFocus: (FocusRecord) -> Void

    @State private var showsPlanner = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                if let session {
                    ActiveFocusCard(
                        session: session,
                        hasPlan: !planBlocks.isEmpty,
                        onPauseOrResume: onPauseOrResume,
                        onEnd: onEnd,
                        onSeePlanner: { showsPlanner = true }
                    )
                } else {
                    CozyHeader(
                        eyebrow: "FOCUSQUEST",
                        title: "Settle in & begin",
                        subtitle: "A little pocket of calm for what matters."
                    )

                    StartFocusCard(
                        questName: $questName,
                        durationMinutes: $durationMinutes,
                        timerMode: $timerMode,
                        onStart: onStart
                    )

                    MonthlyGoalCard(
                        completedMinutes: monthlyMinutes,
                        goalMinutes: monthlyGoalMinutes
                    )

                    RecentFocuses(
                        records: records,
                        onRepeat: onRepeatFocus
                    )
                }
            }
            .frame(maxWidth: 620)
            .padding(.horizontal, 22)
            .padding(.top, 28)
            .padding(.bottom, 30)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .sheet(isPresented: $showsPlanner) {
            FocusPlanSheet(blocks: planBlocks)
        }
    }
}

struct CozyHeader: View {
    let eyebrow: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 8) {
            Label(eyebrow, systemImage: "leaf.fill")
                .font(.caption.weight(.bold))
                .tracking(2)
                .foregroundStyle(CozyColors.sage)

            Text(title)
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .foregroundStyle(CozyColors.espresso)
                .multilineTextAlignment(.center)

            Text(subtitle)
                .font(.callout)
                .foregroundStyle(CozyColors.muted)
                .multilineTextAlignment(.center)
        }
        .accessibilityElement(children: .combine)
    }
}

struct StartFocusCard: View {
    @Binding var questName: String
    @Binding var durationMinutes: Double
    @Binding var timerMode: FocusTimerMode
    let onStart: () -> Void

    var body: some View {
        VStack(spacing: 28) {
            TextField("What are you focusing on?", text: $questName)
                .textFieldStyle(.plain)
                .font(.headline)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .background(CozyColors.cream, in: Capsule())

            Picker("Timer style", selection: $timerMode) {
                ForEach(FocusTimerMode.allCases, id: \.self) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Button(action: onStart) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [CozyColors.terracotta, CozyColors.warmRose],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: CozyColors.terracotta.opacity(0.28), radius: 18, y: 10)

                    VStack(spacing: 8) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 34))
                        Text("START")
                            .font(.headline.weight(.heavy))
                            .tracking(2)
                    }
                    .foregroundStyle(.white)
                }
                .frame(width: 176, height: 176)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Starts a focus timer")

            if timerMode == .countDown {
                VStack(spacing: 14) {
                    HStack {
                    Label("Timer", systemImage: "clock.fill")
                        .font(.headline)
                    Spacer()
                    TextField(
                        "Minutes",
                        value: $durationMinutes,
                        format: .number.precision(.fractionLength(0))
                    )
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                    .font(.title3.monospacedDigit().bold())
                    .foregroundStyle(CozyColors.terracotta)
                    .frame(width: 72)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(CozyColors.cream, in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityLabel("Custom focus minutes")

                    Text("min")
                        .foregroundStyle(CozyColors.muted)
                }

                Slider(value: $durationMinutes, in: 5...240, step: 5)
                    .tint(CozyColors.terracotta)
                    .accessibilityLabel("Focus duration")

                HStack {
                    Text("5 min")
                    Spacer()
                    Text("4 hours")
                }
                    .font(.caption)
                    .foregroundStyle(CozyColors.muted)
                }
            } else {
                Label("The timer starts at zero and runs until you finish.", systemImage: "stopwatch.fill")
                    .font(.callout)
                    .foregroundStyle(CozyColors.muted)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(CozyColors.cream.opacity(0.72), in: RoundedRectangle(cornerRadius: 16))
            }
        }
        .padding(26)
        .background(.white.opacity(0.58), in: RoundedRectangle(cornerRadius: 32))
        .overlay {
            RoundedRectangle(cornerRadius: 32)
                .stroke(.white.opacity(0.72), lineWidth: 1)
        }
        .shadow(color: CozyColors.espresso.opacity(0.08), radius: 22, y: 12)
    }
}

struct ActiveFocusCard: View {
    let session: FocusSession
    let hasPlan: Bool
    let onPauseOrResume: () -> Void
    let onEnd: () -> Void
    let onSeePlanner: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text(session.name)
                .font(.title2.bold())
                .foregroundStyle(CozyColors.espresso)
                .multilineTextAlignment(.center)

            TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                CozyTimerRing(
                    value: session.mode == .countUp ? session.elapsed : session.remaining,
                    total: session.totalDuration,
                    mode: session.mode,
                    isPaused: session.isPaused
                )
            }

            HStack(spacing: 12) {
                Button(action: onPauseOrResume) {
                    Label(
                        session.isPaused ? "Resume" : "Pause",
                        systemImage: session.isPaused ? "play.fill" : "pause.fill"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(CozyPrimaryButtonStyle())

                Button(role: session.mode == .countDown ? .destructive : nil, action: onEnd) {
                    Label(
                        session.mode == .countUp ? "Finish" : "End",
                        systemImage: session.mode == .countUp ? "checkmark" : "xmark"
                    )
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(CozySecondaryButtonStyle())
            }

            if hasPlan {
                Button(action: onSeePlanner) {
                    Label("See Planner", systemImage: "calendar")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(CozySecondaryButtonStyle())
            }
        }
        .padding(26)
        .background(.white.opacity(0.6), in: RoundedRectangle(cornerRadius: 32))
        .shadow(color: CozyColors.espresso.opacity(0.08), radius: 22, y: 12)
    }
}

struct CozyTimerRing: View {
    let value: TimeInterval
    let total: TimeInterval
    let mode: FocusTimerMode
    let isPaused: Bool

    var body: some View {
        ZStack {
            Circle()
                .stroke(CozyColors.sage.opacity(0.16), lineWidth: 15)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    LinearGradient(
                        colors: [CozyColors.sage, CozyColors.terracotta],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    style: StrokeStyle(lineWidth: 15, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            VStack(spacing: 6) {
                Image(systemName: isPaused ? "cup.and.saucer.fill" : "leaf.fill")
                    .foregroundStyle(CozyColors.sage)

                Text(formattedTime)
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(CozyColors.espresso)
                    .contentTransition(.numericText())

                Text(isPaused ? "PAUSED" : (mode == .countUp ? "COUNTING UP" : "STAY COZY"))
                    .font(.caption2.bold())
                    .tracking(1.5)
                    .foregroundStyle(CozyColors.muted)
            }
        }
        .frame(width: 230, height: 230)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            isPaused ? "Timer paused" : (mode == .countUp ? "Elapsed focus time" : "Time remaining")
        )
        .accessibilityValue(formattedTime)
    }

    private var progress: Double {
        if mode == .countUp {
            return value.truncatingRemainder(dividingBy: 60) / 60
        }
        guard total > 0 else { return 0 }
        return min(max(value / total, 0), 1)
    }

    private var formattedTime: String {
        let roundedValue = mode == .countUp ? value.rounded(.down) : value.rounded(.up)
        let seconds = max(0, Int(roundedValue))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

struct RecentFocuses: View {
    let records: [FocusRecord]
    let onRepeat: (FocusRecord) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent focuses")
                .font(.headline)
                .foregroundStyle(CozyColors.espresso)

            if records.isEmpty {
                Label("Your finished quests will rest here.", systemImage: "moon.stars.fill")
                    .font(.callout)
                    .foregroundStyle(CozyColors.muted)
                    .frame(maxWidth: .infinity)
                    .padding(22)
                    .background(.white.opacity(0.38), in: RoundedRectangle(cornerRadius: 20))
            } else {
                ForEach(records.prefix(3)) { record in
                    FocusRecordRow(record: record) {
                        onRepeat(record)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct FocusRecordRow: View {
    let record: FocusRecord
    let onRepeat: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: record.outcome == .completed ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.title2)
                .foregroundStyle(record.outcome == .completed ? CozyColors.sage : CozyColors.warmRose)

            VStack(alignment: .leading, spacing: 3) {
                Text(record.name)
                    .font(.headline)
                    .foregroundStyle(CozyColors.espresso)
                    .lineLimit(1)
                Text(record.finishedAt, format: .dateTime.month(.abbreviated).day())
                    .font(.caption)
                    .foregroundStyle(CozyColors.muted)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(record.timerMode.title)
                    .font(.caption2.bold())
                    .foregroundStyle(CozyColors.sage)
                Text(formattedDuration)
                    .font(.caption.bold())
                    .foregroundStyle(CozyColors.muted)
            }

            Button(action: onRepeat) {
                Image(systemName: "arrow.clockwise")
                    .font(.caption.bold())
                    .foregroundStyle(CozyColors.warmRose)
                    .frame(width: 28, height: 28)
                    .background(.white.opacity(0.72), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Do This Layout Again")
        }
        .padding(14)
        .background(.white.opacity(0.48), in: RoundedRectangle(cornerRadius: 18))
    }

    private var formattedDuration: String {
        let totalSeconds = max(0, Int(record.duration.rounded()))
        if totalSeconds < 60 {
            return "\(totalSeconds) sec"
        }
        return "\(totalSeconds / 60) min"
    }
}

struct WeekPlannerPage: View {
    @Binding var planBlocks: [PlanBlock]
    let onStartRequest: (PlanBlock) -> Void

    @State private var goal = ""
    @State private var isGenerating = false
    @State private var planSource = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                CozyHeader(
                    eyebrow: "COZY PLANNER",
                    title: "A fair week, made for you",
                    subtitle: "Every plan becomes a set of focus-ready blocks with room for rest."
                )

                VStack(alignment: .leading, spacing: 16) {
                    Label("What are you planning?", systemImage: "wand.and.stars")
                        .font(.headline)
                        .foregroundStyle(CozyColors.espresso)

                    TextEditor(text: $goal)
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 110)
                        .padding(12)
                        .background(CozyColors.cream, in: RoundedRectangle(cornerRadius: 18))
                        .overlay(alignment: .topLeading) {
                            if goal.isEmpty {
                                Text("Example: Study for my biology exam and finish my presentation...")
                                    .foregroundStyle(CozyColors.muted.opacity(0.75))
                                    .padding(.horizontal, 17)
                                    .padding(.vertical, 20)
                                    .allowsHitTesting(false)
                            }
                        }

                    Button(action: makePlan) {
                        HStack {
                            if isGenerating {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "sparkles")
                            }
                            Text(isGenerating ? "Building focus blocks..." : "Make My Week Plan")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(CozyPrimaryButtonStyle())
                    .disabled(goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isGenerating)
                }
                .padding(22)
                .background(.white.opacity(0.58), in: RoundedRectangle(cornerRadius: 28))
                .shadow(color: CozyColors.espresso.opacity(0.07), radius: 18, y: 10)

                if !planBlocks.isEmpty {
                    HStack {
                        Label("Your balanced week", systemImage: "calendar.badge.checkmark")
                            .font(.title3.bold())
                        Spacer()
                        if !planSource.isEmpty {
                            Text(planSource)
                                .font(.caption.bold())
                                .foregroundStyle(CozyColors.sage)
                        }
                    }
                    .foregroundStyle(CozyColors.espresso)

                    PlanBlocksSection(
                        title: "Tap any block to focus",
                        blocks: planBlocks,
                        onSelect: onStartRequest
                    )
                }
            }
            .frame(maxWidth: 680)
            .padding(.horizontal, 22)
            .padding(.top, 28)
            .padding(.bottom, 30)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
    }

    private func makePlan() {
        let trimmedGoal = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedGoal.isEmpty else { return }

        isGenerating = true

        Task {
            let result = await WeekPlanGenerator.generate(for: trimmedGoal)
            planBlocks = result.blocks
            planSource = result.source
            PlanStorage.save(result.blocks)
            isGenerating = false
        }
    }
}

struct FocusPlanSheet: View {
    let blocks: [PlanBlock]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Your Week Plan")
                            .font(.largeTitle.bold())
                        Text("A quick look without leaving your focus.")
                            .foregroundStyle(CozyColors.muted)
                    }
                    Spacer()
                    Button("Done") { dismiss() }
                        .buttonStyle(CozyPrimaryButtonStyle())
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                    ForEach(blocks) { block in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(block.day.uppercased())
                                    .font(.caption2.bold())
                                    .foregroundStyle(CozyColors.sage)
                                Spacer()
                                Text("\(block.minutes) min")
                                    .font(.caption.bold())
                                    .foregroundStyle(CozyColors.terracotta)
                            }
                            Text(block.title)
                                .font(.headline)
                                .foregroundStyle(CozyColors.espresso)
                            Text(block.details)
                                .font(.caption)
                                .foregroundStyle(CozyColors.muted)
                        }
                        .frame(maxWidth: .infinity, minHeight: 105, alignment: .topLeading)
                        .padding(16)
                        .background(.white.opacity(0.62), in: RoundedRectangle(cornerRadius: 20))
                    }
                }
            }
            .frame(maxWidth: 680)
            .padding(28)
            .frame(maxWidth: .infinity)
        }
        .background(CozyBackground())
    }
}

struct PlanBlocksSection: View {
    let title: String
    let blocks: [PlanBlock]
    let onSelect: (PlanBlock) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: "square.grid.2x2.fill")
                .font(.headline)
                .foregroundStyle(CozyColors.espresso)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                ForEach(blocks) { block in
                    PlanBlockButton(block: block) {
                        onSelect(block)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PlanBlockButton: View {
    let block: PlanBlock
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text(block.day.uppercased())
                        .font(.caption2.bold())
                        .tracking(1.2)
                        .foregroundStyle(CozyColors.sage)
                    Spacer()
                    Label("\(block.minutes) min", systemImage: "timer")
                        .font(.caption.bold())
                        .foregroundStyle(CozyColors.terracotta)
                }

                Text(block.title)
                    .font(.headline)
                    .foregroundStyle(CozyColors.espresso)
                    .multilineTextAlignment(.leading)

                Text(block.details)
                    .font(.caption)
                    .foregroundStyle(CozyColors.muted)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)

                Label("Tap to start", systemImage: "play.circle.fill")
                    .font(.caption.bold())
                    .foregroundStyle(CozyColors.sage)
            }
            .frame(maxWidth: .infinity, minHeight: 126, alignment: .topLeading)
            .padding(16)
            .background(.white.opacity(0.6), in: RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
    }
}

struct BooksPage: View {
    @Binding var bookmarks: [BookBookmark]
    @State private var selectedBookmark: BookBookmark?

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                CozyHeader(
                    eyebrow: "READING NOOK",
                    title: "Your cozy bookshelf",
                    subtitle: "Save covers and keep your place in every story."
                )

                BookmarksSection(
                    bookmarks: bookmarks,
                    onAdd: addBookmark,
                    onSelect: { selectedBookmark = $0 }
                )
            }
            .frame(maxWidth: 680)
            .padding(.horizontal, 22)
            .padding(.top, 28)
            .padding(.bottom, 30)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .sheet(item: $selectedBookmark) { bookmark in
            BookmarkDetailView(
                bookmark: bookmark,
                onSavePage: { page in updatePage(for: bookmark.id, page: page) },
                onDelete: { deleteBookmark(id: bookmark.id) }
            )
        }
    }

    private func addBookmark(_ bookmark: BookBookmark) {
        bookmarks.insert(bookmark, at: 0)
        BookmarkStorage.save(bookmarks)
    }

    private func updatePage(for id: UUID, page: Int) {
        guard let index = bookmarks.firstIndex(where: { $0.id == id }) else { return }
        bookmarks[index].currentPage = max(0, page)
        BookmarkStorage.save(bookmarks)
        selectedBookmark = nil
    }

    private func deleteBookmark(id: UUID) {
        bookmarks.removeAll { $0.id == id }
        BookmarkStorage.save(bookmarks)
        selectedBookmark = nil
    }
}

struct BookmarksSection: View {
    let bookmarks: [BookBookmark]
    let onAdd: (BookBookmark) -> Void
    let onSelect: (BookBookmark) -> Void

    @State private var bookName = ""
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var selectedImageData: Data?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("My book bookmarks", systemImage: "books.vertical.fill")
                .font(.headline)
                .foregroundStyle(CozyColors.espresso)

            if !bookmarks.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 12) {
                        ForEach(bookmarks) { bookmark in
                            Button {
                                onSelect(bookmark)
                            } label: {
                                BookBookmarkCard(bookmark: bookmark)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }

            HStack(spacing: 10) {
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    BookmarkImage(data: selectedImageData)
                        .frame(width: 54, height: 70)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(CozyColors.sage.opacity(0.25))
                        }
                }
                .buttonStyle(.plain)
                .onChange(of: selectedPhoto) { _, newPhoto in
                    guard let newPhoto else { return }
                    Task {
                        selectedImageData = try? await newPhoto.loadTransferable(type: Data.self)
                    }
                }

                TextField("Name this book", text: $bookName)
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(CozyColors.cream, in: RoundedRectangle(cornerRadius: 14))

                Button("Add") {
                    addBookmark()
                }
                .buttonStyle(CozyPrimaryButtonStyle())
                .disabled(bookName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            Text("Tap the cover to choose a picture, name your book, then add it to the shelf.")
                .font(.caption)
                .foregroundStyle(CozyColors.muted)
        }
        .padding(20)
        .background(.white.opacity(0.42), in: RoundedRectangle(cornerRadius: 24))
    }

    private func addBookmark() {
        let trimmedName = bookName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        onAdd(BookBookmark(id: UUID(), name: trimmedName, imageData: selectedImageData))
        bookName = ""
        selectedImageData = nil
        selectedPhoto = nil
    }
}

struct BookBookmarkCard: View {
    let bookmark: BookBookmark

    var body: some View {
        VStack(spacing: 7) {
            BookmarkImage(data: bookmark.imageData)
                .frame(width: 82, height: 108)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            Text(bookmark.name)
                .font(.caption.bold())
                .foregroundStyle(CozyColors.espresso)
                .lineLimit(2)
                .frame(width: 92)

            Text(bookmark.currentPage > 0 ? "Page \(bookmark.currentPage)" : "Not started")
                .font(.caption2)
                .foregroundStyle(CozyColors.muted)
        }
        .accessibilityElement(children: .combine)
    }
}

struct BookmarkImage: View {
    let data: Data?

    var body: some View {
        Group {
            #if canImport(AppKit)
            if let data, let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder
            }
            #elseif canImport(UIKit)
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder
            }
            #else
            placeholder
            #endif
        }
        .clipped()
    }

    private var placeholder: some View {
        ZStack {
            CozyColors.sage.opacity(0.14)
            Image(systemName: "photo.badge.plus")
                .font(.title2)
                .foregroundStyle(CozyColors.sage)
        }
    }
}

struct MonthlyGoalCard: View {
    let completedMinutes: Int
    let goalMinutes: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Monthly focus goal", systemImage: "medal.fill")
                    .font(.headline)
                    .foregroundStyle(CozyColors.espresso)
                Spacer()
                Text("\(completedMinutes) / \(goalMinutes) min")
                    .font(.caption.bold())
                    .foregroundStyle(CozyColors.sage)
            }

            ProgressView(value: Double(min(completedMinutes, goalMinutes)), total: Double(max(goalMinutes, 1)))
                .tint(CozyColors.terracotta)

            Text(completedMinutes >= goalMinutes
                 ? "Goal complete — your monthly medal is waiting in your profile!"
                 : "\(max(0, goalMinutes - completedMinutes)) focused minutes until your medal.")
                .font(.caption)
                .foregroundStyle(CozyColors.muted)
        }
        .padding(18)
        .background(.white.opacity(0.48), in: RoundedRectangle(cornerRadius: 20))
    }
}

struct BookmarkDetailView: View {
    let bookmark: BookBookmark
    let onSavePage: (Int) -> Void
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var currentPage: Int
    @State private var showsDeleteConfirmation = false

    init(bookmark: BookBookmark, onSavePage: @escaping (Int) -> Void, onDelete: @escaping () -> Void) {
        self.bookmark = bookmark
        self.onSavePage = onSavePage
        self.onDelete = onDelete
        _currentPage = State(initialValue: bookmark.currentPage)
    }

    var body: some View {
        VStack(spacing: 22) {
            BookmarkImage(data: bookmark.imageData)
                .frame(width: 150, height: 205)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .shadow(color: CozyColors.espresso.opacity(0.18), radius: 16, y: 8)

            Text(bookmark.name)
                .font(.largeTitle.bold())
                .foregroundStyle(CozyColors.espresso)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 10) {
                Text("Reading progress")
                    .font(.headline)

                HStack {
                    TextField("Page number", value: $currentPage, format: .number)
                        .textFieldStyle(.plain)
                        .font(.title2.monospacedDigit().bold())
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
                        .accessibilityLabel("Current page number")

                    Text("page")
                        .foregroundStyle(CozyColors.muted)

                    Stepper("Page", value: $currentPage, in: 0...20_000)
                        .labelsHidden()
                }

                Text(currentPage == 0 ? "Not started" : "Currently on page \(currentPage)")
                    .font(.callout)
                    .foregroundStyle(CozyColors.muted)
            }
            .padding()
            .background(CozyColors.cream, in: RoundedRectangle(cornerRadius: 16))

            Button("Save Page") {
                onSavePage(currentPage)
                dismiss()
            }
            .buttonStyle(CozyPrimaryButtonStyle())
            .frame(maxWidth: .infinity)

            Button("Delete Bookmark", role: .destructive) {
                showsDeleteConfirmation = true
            }
            .foregroundStyle(CozyColors.warmRose)

            Spacer()
        }
        .padding(28)
        .frame(minWidth: 340, minHeight: 540)
        .background(CozyBackground())
        .alert("Delete this bookmark?", isPresented: $showsDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                onDelete()
                dismiss()
            }
        } message: {
            Text("This removes \(bookmark.name) and its saved reading progress.")
        }
    }
}

struct ProfileView: View {
    let records: [FocusRecord]
    let monthlyMinutes: Int
    @Binding var monthlyGoalMinutes: Int
    let awardedGoalMonths: Set<String>

    @Environment(\.dismiss) private var dismiss

    private var completedCount: Int {
        records.filter { $0.outcome == .completed }.count
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Your Profile")
                            .font(.largeTitle.bold())
                        Text("Cozy progress, one quest at a time.")
                            .foregroundStyle(CozyColors.muted)
                    }
                    Spacer()
                    Button("Done") { dismiss() }
                        .buttonStyle(CozyPrimaryButtonStyle())
                }

                VStack(alignment: .leading, spacing: 14) {
                    Label("Monthly goal", systemImage: "target")
                        .font(.title3.bold())

                    Stepper(value: $monthlyGoalMinutes, in: 30...3000, step: 30) {
                        Text("\(monthlyGoalMinutes) focused minutes")
                            .font(.headline)
                    }

                    ProgressView(
                        value: Double(min(monthlyMinutes, monthlyGoalMinutes)),
                        total: Double(max(monthlyGoalMinutes, 1))
                    )
                    .tint(CozyColors.terracotta)

                    Text("\(monthlyMinutes) minutes completed this month")
                        .font(.caption)
                        .foregroundStyle(CozyColors.muted)
                }
                .padding(20)
                .background(.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 24))

                VStack(alignment: .leading, spacing: 14) {
                    Text("Medal Cabinet")
                        .font(.title2.bold())

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                        MedalCard(title: "First Quest", detail: "Complete 1 focus", symbol: "sparkles", isUnlocked: completedCount >= 1)
                        MedalCard(title: "Steady Quester", detail: "Complete 5 focuses", symbol: "flame.fill", isUnlocked: completedCount >= 5)
                        MedalCard(title: "Quest Veteran", detail: "Complete 25 focuses", symbol: "shield.fill", isUnlocked: completedCount >= 25)
                        MedalCard(title: "Goal Medal", detail: "Reach a monthly goal", symbol: "medal.fill", isUnlocked: !awardedGoalMonths.isEmpty)
                        MedalCard(title: "Advanced Quester", detail: "Win 10 goal medals", symbol: "crown.fill", isUnlocked: awardedGoalMonths.count >= 10)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: 680)
            .padding(28)
            .frame(maxWidth: .infinity)
        }
        .background(CozyBackground())
    }
}

struct MedalCard: View {
    let title: String
    let detail: String
    let symbol: String
    let isUnlocked: Bool

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: isUnlocked ? symbol : "lock.fill")
                .font(.system(size: 34))
                .foregroundStyle(isUnlocked ? CozyColors.terracotta : CozyColors.muted.opacity(0.5))

            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)
            Text(isUnlocked ? "Unlocked" : detail)
                .font(.caption)
                .foregroundStyle(CozyColors.muted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
        .padding(12)
        .background(.white.opacity(isUnlocked ? 0.68 : 0.34), in: RoundedRectangle(cornerRadius: 20))
        .foregroundStyle(CozyColors.espresso)
        .accessibilityElement(children: .combine)
    }
}

struct CozyTabBar: View {
    @Binding var selectedPage: AppPage

    var body: some View {
        HStack(spacing: 12) {
            TabButton(
                title: "Focus",
                systemImage: "timer",
                isSelected: selectedPage == .focus
            ) {
                selectedPage = .focus
            }

            TabButton(
                title: "Planner",
                systemImage: "sparkles",
                isSelected: selectedPage == .planner
            ) {
                selectedPage = .planner
            }

            TabButton(
                title: "Books",
                systemImage: "books.vertical.fill",
                isSelected: selectedPage == .books
            ) {
                selectedPage = .books
            }
        }
        .padding(10)
        .frame(maxWidth: 520)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay {
            Capsule().stroke(.white.opacity(0.7))
        }
        .shadow(color: CozyColors.espresso.opacity(0.14), radius: 18, y: 8)
        .padding(.horizontal, 20)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity)
    }
}

struct TabButton: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.bold())
                .foregroundStyle(isSelected ? .white : CozyColors.espresso)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    isSelected ? CozyColors.sage : Color.clear,
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
    }
}

struct CozyPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .padding(.vertical, 13)
            .padding(.horizontal, 18)
            .background(
                CozyColors.sage.opacity(configuration.isPressed ? 0.72 : 1),
                in: RoundedRectangle(cornerRadius: 15)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct CozySecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(CozyColors.warmRose)
            .padding(.vertical, 13)
            .padding(.horizontal, 18)
            .background(.white.opacity(configuration.isPressed ? 0.45 : 0.72), in: RoundedRectangle(cornerRadius: 15))
    }
}

enum CozyColors {
    static let espresso = Color(red: 0.27, green: 0.20, blue: 0.16)
    static let muted = Color(red: 0.45, green: 0.39, blue: 0.33)
    static let sage = Color(red: 0.34, green: 0.48, blue: 0.36)
    static let terracotta = Color(red: 0.73, green: 0.40, blue: 0.29)
    static let warmRose = Color(red: 0.69, green: 0.33, blue: 0.32)
    static let cream = Color(red: 1.0, green: 0.98, blue: 0.91)
}

struct GeneratedPlanResult {
    let blocks: [PlanBlock]
    let source: String
}

#if canImport(FoundationModels)
@available(macOS 26.0, iOS 26.0, *)
@Generable(description: "A fair seven-day plan")
struct GeneratedWeekPlan {
    @Guide(description: "One focus block for each day, Monday through Sunday", .minimumCount(7), .maximumCount(7))
    var days: [GeneratedPlanDay]
}

@available(macOS 26.0, iOS 26.0, *)
@Generable(description: "One practical focus block")
struct GeneratedPlanDay {
    @Guide(description: "Day of the week")
    var day: String

    @Guide(description: "Short action-focused task name")
    var title: String

    @Guide(description: "One concise sentence explaining a realistic stopping point")
    var details: String

    @Guide(description: "Focus duration in minutes", .range(10...90))
    var minutes: Int
}
#endif

enum WeekPlanGenerator {
    static func generate(for goal: String) async -> GeneratedPlanResult {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, iOS 26.0, *) {
            let model = SystemLanguageModel.default

            if case .available = model.availability {
                do {
                    let instructions = """
                        You are a kind weekly planning coach. Create exactly seven practical
                        focus blocks from Monday through Sunday. Keep the workload fair.
                        Thursday and Sunday should be lighter recovery days. Each block needs
                        one clear action, a realistic stopping point, and 10 to 90 minutes.
                        """
                    let session = LanguageModelSession(instructions: instructions)
                    let response = try await session.respond(
                        to: "Create a balanced week plan for this goal: <user_goal>\(goal)</user_goal>",
                        generating: GeneratedWeekPlan.self
                    )
                    let blocks = response.content.days.map {
                        PlanBlock(
                            day: $0.day,
                            title: $0.title,
                            details: $0.details,
                            minutes: $0.minutes
                        )
                    }
                    if blocks.count == 7 {
                        return GeneratedPlanResult(blocks: blocks, source: "Apple Intelligence")
                    }
                } catch {
                    // A dependable local plan keeps the feature useful if generation fails.
                }
            }
        }
        #endif

        return GeneratedPlanResult(blocks: fallbackPlan(for: goal), source: "Cozy Plan")
    }

    private static func fallbackPlan(for goal: String) -> [PlanBlock] {
        [
            PlanBlock(day: "Monday", title: "Define the finish line", details: "Clarify what done means for \(goal) and list three small next steps.", minutes: 25),
            PlanBlock(day: "Tuesday", title: "Take the first step", details: "Complete the easiest useful piece and leave a note for tomorrow.", minutes: 30),
            PlanBlock(day: "Wednesday", title: "Build momentum", details: "Move the most important part forward without polishing it yet.", minutes: 45),
            PlanBlock(day: "Thursday", title: "Light review", details: "Tidy loose ends, check progress, and stop early for recovery.", minutes: 20),
            PlanBlock(day: "Friday", title: "Make meaningful progress", details: "Create a solid draft of the biggest remaining piece.", minutes: 45),
            PlanBlock(day: "Saturday", title: "Polish and check", details: "Review, test, or practice until the work feels complete enough.", minutes: 40),
            PlanBlock(day: "Sunday", title: "Rest and reset", details: "Notice your progress and choose one gentle step for next week.", minutes: 10)
        ]
    }
}

enum FocusStorage {
    private static let key = "focusQuest.records"

    static func load() -> [FocusRecord] {
        guard
            let data = UserDefaults.standard.data(forKey: key),
            let records = try? JSONDecoder().decode([FocusRecord].self, from: data)
        else {
            return []
        }

        return records
    }

    static func save(_ records: [FocusRecord]) {
        guard let data = try? JSONEncoder().encode(records) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

enum PlanStorage {
    private static let key = "focusQuest.planBlocks"

    static func load() -> [PlanBlock] {
        guard
            let data = UserDefaults.standard.data(forKey: key),
            let blocks = try? JSONDecoder().decode([PlanBlock].self, from: data)
        else {
            return []
        }
        return blocks
    }

    static func save(_ blocks: [PlanBlock]) {
        guard let data = try? JSONEncoder().encode(blocks) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

enum GoalStorage {
    private static let goalKey = "focusQuest.monthlyGoalMinutes"
    private static let awardedMonthsKey = "focusQuest.awardedGoalMonths"

    static var currentMonthKey: String {
        let components = Calendar.current.dateComponents([.year, .month], from: Date())
        return "\(components.year ?? 0)-\(components.month ?? 0)"
    }

    static func loadGoal() -> Int {
        let saved = UserDefaults.standard.integer(forKey: goalKey)
        return saved > 0 ? saved : 300
    }

    static func saveGoal(_ minutes: Int) {
        UserDefaults.standard.set(minutes, forKey: goalKey)
    }

    static func loadAwardedMonths() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: awardedMonthsKey) ?? [])
    }

    static func saveAwardedMonths(_ months: Set<String>) {
        UserDefaults.standard.set(Array(months), forKey: awardedMonthsKey)
    }
}

enum BookmarkStorage {
    private static let key = "focusQuest.bookmarks"

    static func load() -> [BookBookmark] {
        guard
            let data = UserDefaults.standard.data(forKey: key),
            let bookmarks = try? JSONDecoder().decode([BookBookmark].self, from: data)
        else {
            return []
        }
        return bookmarks
    }

    static func save(_ bookmarks: [BookBookmark]) {
        guard let data = try? JSONEncoder().encode(bookmarks) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

#Preview {
    ContentView()
}
