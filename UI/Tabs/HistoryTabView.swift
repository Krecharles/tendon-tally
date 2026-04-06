import SwiftUI

struct HistoryTabView: View {
    @ObservedObject var viewModel: MetricsViewModel

    @AppStorage("historyOverlayEnabled") private var historyOverlayEnabled: Bool = true
    @State private var showingCustomPopover = false
    @State private var draftCustomStart = Calendar.current.startOfDay(for: Date())
    @State private var draftCustomEnd = Calendar.current.startOfDay(for: Date())

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                headerSection
                    .padding(.bottom, 20)

                HStack(spacing: 12) {
                    rangeSelector
                    dateNavigation
                    if shouldShowOverlayToggle {
                        overlayToggle
                    }
                }
                .padding(.bottom, 12)

                metricFilters
                    .padding(.bottom, 20)

                chartCard
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            syncCustomDraftsFromSelection()
        }
    }

    private var headerSection: some View {
        Text("History")
            .font(.system(size: 28, weight: .bold))
            .foregroundColor(.primary)
    }

    // MARK: - Range Selector

    private var rangeSelector: some View {
        HStack(spacing: 2) {
            ForEach(HistoryPreset.allCases, id: \.self) { preset in
                let isSelected = isPresetSelected(preset)
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        viewModel.selectHistoryPreset(preset)
                    }
                }) {
                    Text(preset.rawValue)
                        .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                        .foregroundColor(isSelected ? .white : .secondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(isSelected ? Color.accentColor : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }

            let isCustomSelected = viewModel.historySelection.mode == .custom
            Button(action: {
                syncCustomDraftsFromSelection()
                showingCustomPopover.toggle()
            }) {
                Text("Custom")
                    .font(.system(size: 12, weight: isCustomSelected ? .semibold : .regular))
                    .foregroundColor(isCustomSelected ? .white : .secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isCustomSelected ? Color.accentColor : Color.clear)
                    )
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showingCustomPopover, arrowEdge: .bottom) {
                customRangePopover
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.windowBackgroundColor).opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(NSColor.separatorColor).opacity(0.3), lineWidth: 1)
                )
        )
    }

    // MARK: - Date Navigation

    private var dateNavigation: some View {
        HStack(spacing: 8) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.15)) {
                    viewModel.shiftHistoryBackward()
                }
            }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Text(dateRangeLabelText)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.primary)

            Button(action: {
                withAnimation(.easeInOut(duration: 0.15)) {
                    viewModel.shiftHistoryForward()
                }
            }) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(viewModel.canShiftHistoryForward ? .secondary : .secondary.opacity(0.3))
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.canShiftHistoryForward)

        }
    }

    private var overlayToggle: some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.15)) {
                historyOverlayEnabled.toggle()
            }
        }) {
            HStack(spacing: 6) {
                Image(systemName: historyOverlayEnabled ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    .font(.system(size: 12, weight: .medium))
                Text("Overlay")
                    .font(.system(size: 12, weight: historyOverlayEnabled ? .semibold : .regular))
            }
            .foregroundColor(historyOverlayEnabled ? .white : .secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(historyOverlayEnabled ? Color.accentColor : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.windowBackgroundColor).opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(NSColor.separatorColor).opacity(0.3), lineWidth: 1)
                )
        )
    }

    private var customRangePopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Custom Range")
                .font(.headline)

            DatePicker(
                "Start",
                selection: $draftCustomStart,
                in: ...Calendar.current.startOfDay(for: Date()),
                displayedComponents: .date
            )

            DatePicker(
                "End",
                selection: $draftCustomEnd,
                in: draftCustomStart...Calendar.current.startOfDay(for: Date()),
                displayedComponents: .date
            )

            Text("Range is limited to 1–365 days.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button("Cancel") {
                    syncCustomDraftsFromSelection()
                    showingCustomPopover = false
                }
                .buttonStyle(.plain)

                Spacer()

                Button("Apply") {
                    viewModel.updateCustomRange(start: draftCustomStart, end: draftCustomEnd)
                    syncCustomDraftsFromSelection()
                    showingCustomPopover = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 300)
    }

    private var dateRangeLabelText: String {
        let now = Date()
        let selection = viewModel.historySelection.normalized(now: now)
        let interval = selection.dateInterval(now: now)

        if selection.mode == .preset, selection.offset == 0 {
            switch selection.preset {
            case .day:
                return "Today"
            case .week:
                return "Last 7 days"
            case .month:
                return "Last 30 days"
            case .year:
                return "Last 365 days"
            }
        }

        return formatDateRange(start: interval.start, endExclusive: interval.end)
    }

    private func formatDateRange(start: Date, endExclusive: Date) -> String {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        let inclusiveEnd = endExclusive.addingTimeInterval(-1)

        let startYear = calendar.component(.year, from: start)
        let endYear = calendar.component(.year, from: inclusiveEnd)

        if startYear == endYear {
            formatter.dateFormat = "MMM d"
            return "\(formatter.string(from: start)) \u{2013} \(formatter.string(from: inclusiveEnd))"
        }

        formatter.dateFormat = "MMM d, yyyy"
        return "\(formatter.string(from: start)) \u{2013} \(formatter.string(from: inclusiveEnd))"
    }

    private func isPresetSelected(_ preset: HistoryPreset) -> Bool {
        let selection = viewModel.historySelection
        return selection.mode == .preset && selection.preset == preset
    }

    private func syncCustomDraftsFromSelection() {
        let normalized = viewModel.historySelection.normalized()
        draftCustomStart = Calendar.current.startOfDay(for: normalized.customStartDate)
        draftCustomEnd = Calendar.current.startOfDay(for: normalized.customEndDate)
    }

    // MARK: - Chart Card (chart + summary footer)

    private var chartCard: some View {
        let selection = viewModel.historySelection
        let dataPoints = viewModel.timeSeriesData(for: selection)
        let shouldRenderOverlay = historyOverlayEnabled && shouldShowOverlayToggle
        let overlayDataPoints = shouldRenderOverlay ? viewModel.overlaySourceDataPoints(for: selection) : []

        return BarChartView(
            dataPoints: dataPoints,
            overlayDataPoints: overlayDataPoints,
            showOverlay: shouldRenderOverlay,
            selectedMetric: viewModel.selectedMetric,
            granularity: viewModel.resolvedHistoryAggregation,
            totalConfig: viewModel.effectiveTotalConfig,
            hasAnyData: hasAnyData
        )
        .frame(height: 340)
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 12, bottomLeadingRadius: 12, bottomTrailingRadius: 12, topTrailingRadius: 12))
    }

    private var hasAnyData: Bool {
        viewModel.hasAnyHistoryData()
    }

    private var shouldShowOverlayToggle: Bool {
        guard let coarser = viewModel.resolvedHistoryAggregation.nextCoarser else {
            return false
        }
        let points = viewModel.timeSeriesData(for: viewModel.historySelection)
        let groupCount = Set(points.map { coarser.alignedStart(for: $0.time) }).count
        return groupCount >= 3
    }

    // MARK: - Metric Filters

    private var metricFilters: some View {
        HStack(spacing: 6) {
            ForEach(MetricType.allCases, id: \.self) { metricType in
                MetricPill(
                    title: metricType.rawValue,
                    metricType: metricType,
                    isSelected: viewModel.selectedMetric == metricType
                ) {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        viewModel.selectedMetric = metricType
                    }
                }
            }

            Spacer()
        }
    }
}
