import SwiftUI

struct HealthView: View {
    @ObservedObject private var coordinator = SyncCoordinator.shared
    @ObservedObject private var log = ActivityLog.shared
    @State private var syncing = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    statusCard
                    backgroundCard
                    journalCard
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Здоровье")
            .toolbarBackground(.hidden, for: .navigationBar)
        }
    }

    private var statusCard: some View {
        VStack(spacing: 0) {
            row("Сервер", value: coordinator.serverReachable ? "на связи" : "недоступен", color: coordinator.serverReachable ? Theme.ok : Theme.warn)
            divider
            row("Последняя отправка", value: coordinator.lastSync.map { Fmt.time.string(from: $0) + (coordinator.lastSyncTrigger.map { " · \($0)" } ?? "") } ?? "ещё не было")
            divider
            row("В очереди", value: coordinator.queueCount == 0 ? "пусто" : "\(coordinator.queueCount)")
            if let e = coordinator.lastError {
                divider
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ошибка").font(.subheadline).foregroundStyle(Theme.text2)
                    Text(e).font(.footnote).foregroundStyle(Theme.warn)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
            }
            divider
            Button {
                syncing = true
                Task { await coordinator.syncNowCompletely(trigger: "manual"); syncing = false }
            } label: {
                HStack {
                    if syncing { ProgressView().tint(.white) } else { Image(systemName: "arrow.triangle.2.circlepath") }
                    Text("Отправить сейчас").fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .disabled(syncing)
        }
        .card()
    }

    private var backgroundCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("В фоне").font(.footnote.weight(.semibold)).foregroundStyle(Theme.text2).textCase(.uppercase)
            let status = BackgroundScheduler.refreshStatusText
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: status == "включено" ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(status == "включено" ? Theme.ok : Theme.warn)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Обновление контента: \(status)").font(.subheadline)
                    Text("iOS будит BoW при новых данных в Здоровье и раз в несколько часов сама. Не смахивай приложение из переключателя — после этого iOS не будит его до следующего запуска.")
                        .font(.caption).foregroundStyle(Theme.text2)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .card()
    }

    private var journalCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Журнал").font(.footnote.weight(.semibold)).foregroundStyle(Theme.text2).textCase(.uppercase)
            if log.entries.isEmpty {
                Text("Пока пусто").font(.footnote).foregroundStyle(Theme.text3)
            }
            ForEach(log.entries.prefix(60)) { e in
                HStack(alignment: .top, spacing: 10) {
                    Text(Fmt.time.string(from: e.at)).font(.caption.monospacedDigit()).foregroundStyle(Theme.text3).frame(width: 92, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(e.event).font(.caption.weight(.medium))
                        if let d = e.detail { Text(d).font(.caption2).foregroundStyle(Theme.text2) }
                    }
                }
                .padding(.vertical, 3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .card()
    }

    private var divider: some View { Divider().overlay(Theme.line) }

    private func row(_ title: String, value: String, color: Color = .white) -> some View {
        HStack {
            Text(title).font(.subheadline).foregroundStyle(Theme.text2)
            Spacer()
            Text(value).font(.subheadline.weight(.medium)).foregroundStyle(color)
        }
        .padding(14)
    }
}

#Preview {
    HealthView().preferredColorScheme(.dark)
}
