# MintAI

**[Русский](#ru)** | **[English](#en)**

---

<a id="ru"></a>

## Русский

Нативный ИИ-клиент для старых iPhone и iPad на **iOS 6.1** (armv7), собирается через [Theos](https://theos.dev).
Чат с любым OpenAI-совместимым сервером, Claude и Gemini, генерация картинок, озвучка ответов встроенным синтезатором речи и интерфейс в стиле iOS 6.

- Версия: 0.1.1
- Пакет / Bundle ID: `com.lime.mintai`
- Автор: Lime
- Минимальная iOS: 6.0, целевая: 6.1
- Языки интерфейса: русский (по умолчанию) и English

### Возможности

**Чат**
- Провайдеры: DeepSeek, OpenAI, Claude, OpenRouter, Mistral, Gemini, OpenCode Zen и Custom (любой сервер с OpenAI-совместимым API).
- Markdown в ответах: заголовки, **жирный** и *курсив*, `код` и блоки кода, цитаты, списки, ссылки (только визуально, без нажатия) и разделители. Рендерится в `NSAttributedString` без сторонних библиотек.
- Фото в пузырях как в Сообщениях iOS 6: картинка обрезается по контуру пузыря вместе с хвостиком. Так выглядят и прикреплённые фото, и сгенерированные картинки.
- Прикрепление фото через «+» (галерея или камера).
- Свои обои чата (из галереи или с камеры).
- Клавиатура убирается тапом по ленте или началом прокрутки.
- История бесед: сохраняется автоматически, беседу можно открыть и продолжить.
- «Инструкция» (custom instructions): общий системный промпт для всех провайдеров. Уходит в каждый запрос первым сообщением, в ленту и историю не попадает, отключается переключателем без потери текста.

**Изображения**
- Провайдеры генерации: OpenAI (DALL·E), OpenRouter (Image API, модель по умолчанию `google/gemini-2.5-flash-image`) и Custom.
- Ключ у картинок свой, отдельный от чатового.

**Голос**
- Озвучка ответов встроенным формантным синтезатором **VoxSynth**: работает без сети, ключей и серверов.
- Автоозвучка всех ответов, три тембра (Стандартный / Мужской / Женский), три скорости.
- Запись голоса кнопкой микрофона в чате. Распознавание на устройстве пока в разработке (см. ниже).

**Оформление**
- Тёмная тема: в iOS 6 системной нет, поэтому все цвета берутся из `MATheme`. Переключается на лету.
- Язык интерфейса RU/EN переключается на лету, без перезапуска.

**Безопасность**
- API-ключи хранятся в Keychain, а не в `NSUserDefaults`.

### Требования

- [Theos](https://theos.dev) и переменная `THEOS` (например `export THEOS=/opt/theos`).
- iOS SDK 6.1 в `$THEOS/sdks/iPhoneOS6.1.sdk`.
- Устройство с iOS 6.x и джейлбрейком (приложение подписывается через `ldid` и ставится как `.deb`).
- Обычный `cc` на компьютере (macOS/Linux) для десктопных тестов.

### Сборка и установка

```bash
export THEOS=/opt/theos
make package            # соберёт .deb в ./packages
make package install    # соберёт и установит на устройство
```

Для установки по сети или USB задайте адрес устройства в `Makefile` (`THEOS_DEVICE_IP`) или в окружении:

```bash
export THEOS_DEVICE_IP=192.168.0.10
make package install
```

Архитектура по умолчанию — `armv7`; при необходимости добавьте `armv7s` в `ARCHS`.

Приложение подписывается через `ldid` с файлом `entitlements.plist` (`application-identifier` и
`keychain-access-groups`, оба равны `com.lime.mintai`). Без entitlements Keychain, а с ним и API-ключи,
не переживают перезапуск приложения. Если меняете Bundle ID, меняйте его синхронно в `control`,
`Resources/Info.plist` и `entitlements.plist`.

### Первый запуск

1. Откройте **Settings → Чат** и выберите провайдера.
2. Введите API-ключ (и при необходимости адрес сервера и модель). Для Custom укажите URL сервера с OpenAI-совместимым API.
3. Вернитесь в **Chat** и пишите. Провайдера можно переключить и кнопкой «Провайдер» прямо в чате.

### Структура проекта

```
MintAI/
├── Makefile, control, entitlements.plist, main.m
├── Resources/                 иконки, картинки интерфейса, Info.plist, en.lproj/Localizable.strings
├── Classes/
│   ├── App/                   AppDelegate, вкладки, локализация, тема (MATheme)
│   ├── Chat/                  экран чата, ячейки, пузыри с фото, markdown, обои
│   ├── History/               сохранённые беседы
│   ├── Providers/             протокол MAProvider и реализации, провайдеры картинок, HTTP-клиент, Keychain
│   ├── Settings/              корневое меню и экраны категорий
│   └── Voice/
│       ├── Vox/               формантный синтезатор речи (чистый C)
│       └── Stt/               признаки, WAV, каркас движка распознавания (чистый C + ObjC-обёртка)
└── Tools/                     десктопные тесты и утилиты для Vox и Stt
```

### Как расширять

**Новый чат-провайдер.** Реализуйте протокол `MAProvider`. Если сервер OpenAI-совместимый, наследуйтесь от
`MAOpenAICompatibleProvider`, как DeepSeek, Mistral и другие. Затем зарегистрируйте провайдера в `MAProviderRegistry`.

**Новый провайдер картинок.** Если у сервера другой формат Image API, наследуйтесь от
`MAOpenAICompatibleImageProvider` и переопределите `imagesURLString` и `requestBodyWithPrompt:size:`
(пример — `MAOpenRouterImageProvider`), затем зарегистрируйте в `MAImageProviderRegistry`.

**Новая строка интерфейса.** Ключ перевода — сам русский текст: `MALocalizedString(@"...")`.
Английский вариант добавьте в `Resources/en.lproj/Localizable.strings` парой `"русский" = "english";`.
Если перевода нет, показывается русский.

**Новый экран настроек.** Наследуйтесь от `MAThemedTableViewController`, идентификаторы ячеек
grouped-таблиц оборачивайте в `MAThemedReuseID()`. Новая категория на корневом экране — case в
`MASettingsCategory` и строка в `kAICategories` / `kAppCategories`.

**Новый цвет темы.** Добавьте свойство в `MATheme` и берите цвет оттуда, а не из констант `UIColor`.

### Озвучка (VoxSynth)

VoxSynth — мой формантный синтезатор русской речи. Ядро лежит в `Classes/Voice/Vox`
(`FormantCore`, `Phonemes`, `Stress`), поверх него обёртка `MAVoxCore`, которая добавляет:

- цифры в слова («2024» → «две тысячи двадцать четыре», «5%» → «пять процентов», «3,5» → «три запятая пять»), всегда в именительном падеже и мужском роде;
- латиницу русской транслитерацией («GPT4» → «гпт четыре»), это не английский синтезатор;
- разбиение текста на предложения, интонация идёт по предложению;
- тембры = высота тона + масштаб формант, громкость тембров выровнена (около −20 дБFS);
- скорость 140 / 170 / 210 = `speed` 0.82 / 1.0 / 1.24.

Воспроизведение: WAV в памяти → `AVAudioPlayer`, очередь кусков и отмена живут в `MAVoiceService`.

Известные ограничения: словарь ударений небольшой (~300 словоформ, остальное — «на последнюю гласную»),
омографы не различаются, вопросительной интонации нет, сокращения не раскрываются.
Словарь расширяется в `Classes/Voice/Vox/Stress.c`. Что добавляет обёртка по сравнению с голым ядром и почему
не используется проигрыватель на AudioQueue из исходного кода VoxSynth — в `Classes/Voice/Vox/README-Vox.md`.

### Распознавание речи на устройстве (в разработке)

В `Classes/Voice/Stt` лежит каркас, всё на чистом C, кроме обёртки:

- `MAFbank` — log-mel признаки (кадр 25 мс, шаг 10 мс, FFT 512, 80 полос, окно Ханна, предыскажение) и CMVN;
- `MAWav` — разбор WAV из памяти (PCM 16 кГц, 16 бит, моно; лишние чанки, недописанный заголовок и стерео обрабатываются);
- `MASttEngine` — C API `Load` / `Transcribe` / `Free`, проверка входа, лимит 60 с, флаг отмены;
- `MAOnDeviceRecognizer` — ObjC-обёртка: фоновая очередь, ленивая загрузка модели, ответ на main thread. Файл модели: `Documents/stt/model.bin`.

**Чего ещё нет:** самой нейросети. `MASttEngineTranscribe` доходит до признаков и возвращает
`MASTT_ERR_NOT_IMPLEMENTED`. Формат весов и инференс будут добавлены вместе с выбранной моделью. На armv7 с iOS 6.1
реалистичны только очень маленькие модели. Пункт «Микрофон» в настройках «Голос» убран, поэтому выбор режима
распознавания в интерфейсе пока недоступен.

### Проверка без устройства

Голосовое ядро и каркас распознавания проверяются на компьютере под ASan + UBSan:

```bash
make -C Tools test      # vox_test + stt_test
make -C Tools           # собрать утилиты
Tools/vox_cli "В 2024 году 5% людей" out.wav [скорость] [тон] [форманты]
```

### Планы

1. Распознавание на устройстве: выбрать модель, формат весов и инференс в `MASttEngine`, затем при необходимости NEON и языковая модель.
2. Свайп-переименование или ручное редактирование заголовка сессии в истории.

### Автор

**Lime**

- Telegram: [@LimeDeveloper](https://t.me/LimeDeveloper)
- Исходный код: [github.com/Limechik/MintAI](https://github.com/Limechik/MintAI)

---

<a id="en"></a>

## English

A native AI client for old iPhones and iPads running **iOS 6.1** (armv7), built with [Theos](https://theos.dev).
Chat with any OpenAI-compatible server, Claude and Gemini, image generation, spoken replies via a built-in speech synthesizer, and an iOS 6-style interface.

- Version: 0.1.1
- Package / Bundle ID: `com.lime.mintai`
- Author: Lime
- Minimum iOS: 6.0, target: 6.1
- Interface languages: Russian (default) and English

### Features

**Chat**
- Providers: DeepSeek, OpenAI, Claude, OpenRouter, Mistral, Gemini, OpenCode Zen, and Custom (any server with an OpenAI-compatible API).
- Markdown in replies: headings, **bold** and *italic*, `inline code` and code blocks, quotes, lists, links (visual only, not tappable), and dividers. Rendered to `NSAttributedString` without third-party libraries.
- Photos in bubbles just like iOS 6 Messages: the image is clipped to the bubble outline, tail included. This applies to both attached photos and generated images.
- Attach photos via "+" (gallery or camera).
- Custom chat wallpaper (from the gallery or camera).
- The keyboard is dismissed by tapping the feed or by starting to scroll.
- Conversation history: saved automatically; any conversation can be reopened and continued.
- "Instructions" (custom instructions): a shared system prompt for all providers. It is sent as the first message of every request, does not appear in the feed or history, and can be switched off with a toggle without losing the text.

**Images**
- Generation providers: OpenAI (DALL·E), OpenRouter (Image API, default model `google/gemini-2.5-flash-image`), and Custom.
- Images use their own API key, separate from the chat key.

**Voice**
- Replies are spoken by the built-in formant synthesizer **VoxSynth**: it works without a network, keys, or servers.
- Auto-speak for all replies, three voices (Standard / Male / Female), three speeds.
- Voice recording with the microphone button in the chat. On-device recognition is still in development (see below).

**Appearance**
- Dark theme: iOS 6 has no system one, so all colors come from `MATheme`. Switches on the fly.
- The RU/EN interface language switches on the fly, without a restart.

**Security**
- API keys are stored in the Keychain, not in `NSUserDefaults`.

### Requirements

- [Theos](https://theos.dev) and the `THEOS` environment variable (e.g. `export THEOS=/opt/theos`).
- iOS SDK 6.1 in `$THEOS/sdks/iPhoneOS6.1.sdk`.
- A jailbroken device running iOS 6.x (the app is signed with `ldid` and installed as a `.deb`).
- A regular `cc` on your computer (macOS/Linux) for desktop tests.

### Build and Install

```bash
export THEOS=/opt/theos
make package            # builds the .deb into ./packages
make package install    # builds and installs onto the device
```

To install over the network or USB, set the device address in the `Makefile` (`THEOS_DEVICE_IP`) or in the environment:

```bash
export THEOS_DEVICE_IP=192.168.0.10
make package install
```

The default architecture is `armv7`; add `armv7s` to `ARCHS` if needed.

The app is signed with `ldid` using `entitlements.plist` (`application-identifier` and
`keychain-access-groups`, both equal to `com.lime.mintai`). Without the entitlements, the Keychain, and with it the API keys,
do not survive an app restart. If you change the Bundle ID, change it consistently in `control`,
`Resources/Info.plist`, and `entitlements.plist`.

### First Launch

1. Open **Settings → Chat** and choose a provider.
2. Enter the API key (and the server address and model, if needed). For Custom, specify the URL of a server with an OpenAI-compatible API.
3. Go back to **Chat** and start writing. You can also switch the provider with the "Provider" button right in the chat.

### Project Structure

```
MintAI/
├── Makefile, control, entitlements.plist, main.m
├── Resources/                 icons, UI images, Info.plist, en.lproj/Localizable.strings
├── Classes/
│   ├── App/                   AppDelegate, tabs, localization, theme (MATheme)
│   ├── Chat/                  chat screen, cells, photo bubbles, markdown, wallpaper
│   ├── History/               saved conversations
│   ├── Providers/             MAProvider protocol and implementations, image providers, HTTP client, Keychain
│   ├── Settings/              root menu and category screens
│   └── Voice/
│       ├── Vox/               formant speech synthesizer (pure C)
│       └── Stt/               features, WAV, recognition engine skeleton (pure C + ObjC wrapper)
└── Tools/                     desktop tests and utilities for Vox and Stt
```

### How to Extend

**New chat provider.** Implement the `MAProvider` protocol. If the server is OpenAI-compatible, subclass
`MAOpenAICompatibleProvider`, like DeepSeek, Mistral, and others do. Then register the provider in `MAProviderRegistry`.

**New image provider.** If the server uses a different Image API format, subclass
`MAOpenAICompatibleImageProvider` and override `imagesURLString` and `requestBodyWithPrompt:size:`
(see `MAOpenRouterImageProvider` for an example), then register it in `MAImageProviderRegistry`.

**New interface string.** The translation key is the Russian text itself: `MALocalizedString(@"...")`.
Add the English version to `Resources/en.lproj/Localizable.strings` as a `"русский" = "english";` pair.
If there is no translation, the Russian text is shown.

**New settings screen.** Subclass `MAThemedTableViewController` and wrap cell identifiers of
grouped tables in `MAThemedReuseID()`. A new category on the root screen is a case in
`MASettingsCategory` plus a row in `kAICategories` / `kAppCategories`.

**New theme color.** Add a property to `MATheme` and take the color from there rather than from `UIColor` constants.

### Speech Synthesis (VoxSynth)

VoxSynth is my formant synthesizer for Russian speech. The core lives in `Classes/Voice/Vox`
(`FormantCore`, `Phonemes`, `Stress`), with the `MAVoxCore` wrapper on top of it, which adds:

- digits to words ("2024" → "две тысячи двадцать четыре", "5%" → "пять процентов", "3,5" → "три запятая пять"), always in the nominative case and masculine gender;
- Latin text via Russian transliteration ("GPT4" → "гпт четыре"); this is not an English synthesizer;
- splitting text into sentences, with intonation applied per sentence;
- voices = pitch + formant scaling, with voice loudness equalized (around −20 dBFS);
- speed 140 / 170 / 210 = `speed` 0.82 / 1.0 / 1.24.

Playback: in-memory WAV → `AVAudioPlayer`; the chunk queue and cancellation live in `MAVoiceService`.

Known limitations: the stress dictionary is small (~300 word forms; everything else is stressed "on the last vowel"),
homographs are not distinguished, there is no question intonation, and abbreviations are not expanded.
The dictionary can be extended in `Classes/Voice/Vox/Stress.c`. What the wrapper adds compared to the bare core, and why
the AudioQueue-based player from the original VoxSynth source is not used, is described in `Classes/Voice/Vox/README-Vox.md`.

### On-Device Speech Recognition (in development)

`Classes/Voice/Stt` contains a skeleton, all in pure C except for the wrapper:

- `MAFbank` — log-mel features (25 ms frame, 10 ms hop, FFT 512, 80 bands, Hann window, pre-emphasis) and CMVN;
- `MAWav` — in-memory WAV parsing (PCM 16 kHz, 16-bit, mono; extra chunks, incomplete headers, and stereo are handled);
- `MASttEngine` — C API `Load` / `Transcribe` / `Free`, input validation, a 60 s limit, a cancel flag;
- `MAOnDeviceRecognizer` — ObjC wrapper: background queue, lazy model loading, result delivered on the main thread. Model file: `Documents/stt/model.bin`.

**What's still missing:** the neural network itself. `MASttEngineTranscribe` gets as far as the features and returns
`MASTT_ERR_NOT_IMPLEMENTED`. The weights format and inference will be added together with the chosen model. On armv7 with iOS 6.1,
only very small models are realistic. The "Microphone" item in the "Voice" settings has been removed, so choosing a
recognition mode is not yet available in the interface.

### Testing Without a Device

The voice core and the recognition skeleton are tested on a computer under ASan + UBSan:

```bash
make -C Tools test      # vox_test + stt_test
make -C Tools           # build the utilities
Tools/vox_cli "В 2024 году 5% людей" out.wav [speed] [pitch] [formants]
```

### Roadmap

1. On-device recognition: choose a model, weights format, and inference in `MASttEngine`, then NEON and a language model if needed.
2. Swipe-to-rename or manual editing of a session title in the history.

### Author

**Lime**

- Telegram: [@LimeDeveloper](https://t.me/LimeDeveloper)
- Source code: [github.com/Limechik/MintAI](https://github.com/Limechik/MintAI)
