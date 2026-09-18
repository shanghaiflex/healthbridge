# BoW — bodywithoutorgans.cc on the phone (iOS 17+)

Private SwiftUI app, two jobs:

1. **Лекции** — keeps the three lectures the site says are next (`GET /api/lectures/preload`: what is being
   listened to, then one next lecture per channel — so Макаров and Bushwacker are both on the phone, not two
   from the same series) downloaded on the phone, plays them with the screen locked (lock-screen controls,
   ±15/30 s, speed), and pushes the position back (`PATCH /api/lecture/<id>`) every 15 s and on every pause.
   A finished lecture is marked `listened`, its file deleted, and the next one downloaded. Downloads run in a
   background `URLSession` (they survive the app being suspended or killed by iOS) and resume after a dropped
   connection; Wi-Fi only by default (Settings).
2. **Здоровье** — the old Health Bridge: HealthKit → `POST /v1/ingest/health/<workouts|sleep|metrics>` with a
   bearer token, anchored queries, on-disk retry queue, background delivery via `HKObserverQuery`
   + `BGTaskScheduler`. Every request carries `X-Trigger` (foreground / healthkit:<type> / bg-refresh / manual)
   so the server log shows what woke the app. «Ещё» → «Синк и журнал» has a journal of launches, syncs and downloads.
3. **Сайт** — bodywithoutorgans.cc сам, по вебвью на страницу. Внизу пять табов (iOS больше не показывает,
   шестой уносит в своё «More»): «Главная», «Лекции», «Миксы», «Дом», «Ещё»; в «Ещё» — «Французский», «Фильмы»,
   «Книги», «Почитать», «Well-being» и два своих экрана, «Синк и журнал» и «Настройки». «Еда» в приложении
   не показывается вовсе. Страницы перечислены в `SiteController.Page`, вебвью создаётся на первом заходе
   (`SitePage`) и дальше живёт, так что позиция в миксах переживает переключение табов. Меню сайта внутри
   приложения скрыто (`app.js` на сайте): у каждой страницы свой таб.

4. **Уведомления** — новая заметка о самочувствии и утренняя сводка советов (`GET /api/updates`).
   Пуша нет (personal team → нет APNs), уведомление ставит сам телефон, когда iOS будит приложение: синк,
   BGTask, выход на экран. Часы зеркалят его сами. `Notifier.swift`; тумблер в «Настройках».

## Build & install (no App Store, personal team)
```
xcodebuild -project BoW.xcodeproj -scheme BoW -destination 'id=<device udid>' -derivedDataPath build/device -allowProvisioningUpdates build
xcrun devicectl device install app --device <udid> build/device/Build/Products/Debug-iphoneos/BoW.app
xcrun devicectl device process launch --device <udid> cc.bodywithoutorgans.bow
```
Bundle id `cc.bodywithoutorgans.bow`, team = personal (free) → the profile lives 7 days, then the app stops
launching and must be reinstalled. The only real fix is the paid Apple Developer Program (1-year profiles,
TestFlight over the air).

Icon: `swift tools/icon.swift BoW/Assets.xcassets/AppIcon.appiconset/AppIcon.png`.

## Files
- `BoWApp.swift` — entry; the AppDelegate does everything a background launch needs (BG tasks, HealthKit observers, audio session, background-session reconnect).
- `LectureStore` / `DownloadManager` / `PlayerEngine` — the lectures side. `LecturesView` is the screen, `PreviewData` feeds the `#Preview`s.
- `SyncCoordinator` / `HealthKitManager` / `AnchorStore` / `QueueManager` / `NetworkClient` — the health side.
- `RootView` / `MoreView` / `SiteView` — табы, «Ещё» и страницы сайта в вебвью.
- `Notifier` — локальные уведомления по `GET /api/updates` (что уже показано, помнит `UserDefaults`).
- `ActivityLog` — persisted journal shown in the app.
- `Theme.swift` — журнальная тема (18.09.2026): те же hex, что в тёмной половине `theme.css` на сайте,
  прямоугольные карточки с волосяной рамкой, антиква New York в заголовках, рубрики прописными с разрядкой
  (`.sectionLabel()`). Заголовки навигации и таб-бар настраиваются раз при запуске —
  `Theme.configureAppearance()` из `AppDelegate`. Меняется палитра на сайте — менять и здесь.
- `openapi.yaml` — the ingest API.
