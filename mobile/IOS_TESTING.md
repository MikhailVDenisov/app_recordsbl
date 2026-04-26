# Тестирование на iOS Simulator (macOS, без iPhone)

Инструкция для проверки приложения **recordsbl** на Mac через **iOS Simulator** (без реального iPhone).

Важно: в вашем приложении есть **запись с микрофона** и **фоновый режим audio**. Эти вещи корректнее всего проверяются на **реальном iPhone**, но базовые сценарии (UI, БД, загрузка) можно прогнать на симуляторе.

## 1. Подготовка окружения

Нужно:
- macOS
- Xcode (установлен из App Store)
- Flutter SDK

Один раз:

```bash
xcode-select --install
sudo xcodebuild -license accept
```

Проверка:

```bash
flutter --version
flutter doctor
```

## 2. Запуск iOS Simulator и приложения

Из каталога репозитория:

```bash
cd mobile
flutter pub get
open -a Simulator
flutter devices
```

В выводе `flutter devices` должен быть девайс вида `iPhone ... (simulator)`.

Запуск:

```bash
flutter run -d "iPhone 15"
```

Если хотите ближе к “боевому” поведению (производительность/тайминги):

```bash
flutter run --profile -d "iPhone 15"
```

Hot reload во время `flutter run`:
- `r` — hot reload
- `R` — hot restart

## 3. Запись (ограничения симулятора)

В iOS для записи микрофона обязательно требуется `NSMicrophoneUsageDescription` в `ios/Runner/Info.plist`.

На симуляторе:
- UI и переходы (start/pause/resume/stop) можно проверить.
- Реальный захват микрофона и поведение аудио-сессии (прерывания, гарнитуры, звонки) может отличаться от устройства.

Если запись не стартует:
- проверьте, что в `Info.plist` есть `NSMicrophoneUsageDescription`;
- перезапустите приложение на симуляторе;
- попробуйте другой симулятор (`flutter devices` → другое имя).

## 4. Доступ к API с симулятора (НЕ использовать localhost)

Симулятор **не** достучится до backend на Mac по `http://localhost` так, как вы ожидаете:
`localhost` внутри симулятора — это **сам симулятор**, а не ваш Mac.

Поэтому для теста API/загрузки:
- поднимайте сервер на Mac и слушайте `0.0.0.0`
- в настройках приложения указывайте URL с **IP вашего Mac** в Wi‑Fi сети

Узнать IP Mac:

```bash
ipconfig getifaddr en0   # обычно Wi‑Fi
# или
ipconfig getifaddr en1
```

Пример URL в настройках приложения:
- `http://192.168.1.10:3000` (порт — ваш)

Альтернатива: дать внешнюю ссылку на API через туннель (ngrok/cloudflared) и указать её в настройках приложения.

## 5. Чек-лист проверок (iOS Simulator)

### Базовое

- [ ] Приложение запускается без краша.
- [ ] В настройках сохраняются **логин** и **URL сервера**; после перезапуска значения на месте.

### Запись

- [ ] «Начать запись встречи» — UI переходит в режим записи, таймер идёт.
- [ ] **Пауза** / **Продолжить** — без краша.
- [ ] **Стоп** — встреча появляется в списке, длительность правдоподобная.

### Выгрузка (multipart S3 через presigned URL)

- [ ] «Выгрузить» при работающем сервере: прогресс идёт, затем статус “uploaded”.
- [ ] Обрыв сети (выключить Wi‑Fi на Mac/симулировать недоступность API): ошибка отображается, повтор возможен.

## 6. Если что-то не работает

### Симулятор не виден в `flutter devices`

- проверьте, что Xcode установлен и запускался хотя бы раз;
- запустите Simulator вручную: `open -a Simulator`;
- в Xcode: Settings → Locations → Command Line Tools (выберите вашу версию Xcode).

### Сборка iOS падает на зависимостях

Попробуйте:

```bash
cd mobile
flutter clean
flutter pub get
cd ios
pod repo update
pod install
cd ..
flutter run -d "iPhone 15"
```

