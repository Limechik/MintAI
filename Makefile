export THEOS_DEVICE_IP =

# Собираем под armv7 (iPhone/iPad с iOS 6.1). Добавь armv7s при необходимости.
ARCHS = armv7
TARGET = iphone:clang:6.1:6.0

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = MintAI

# ldid -S по умолчанию подписывает без entitlements вообще — из-за этого
# Keychain (API-ключи) не переживает перезапуск приложения. Подписываем
# с явным application-identifier/keychain-access-groups.
MintAI_CODESIGN_FLAGS = -Sentitlements.plist

MintAI_FILES = \
	main.m \
	Classes/App/MAAppDelegate.m \
	Classes/App/MALocalization.m \
	Classes/App/MATheme.m \
	Classes/App/MAThemedTableViewController.m \
	Classes/Chat/MAChatViewController.m \
	Classes/Chat/MAChatMessageCell.m \
	Classes/Chat/MAChatImageCell.m \
	Classes/Chat/MAPhotoBubbleView.m \
	Classes/Chat/MAChatItem.m \
	Classes/Chat/MAWallpaperStore.m \
	Classes/Chat/MAMarkdownRenderer.m \
	Classes/Settings/MASettingsViewController.m \
	Classes/Settings/MAProvidersSettingsViewController.m \
	Classes/Settings/MAInstructionsSettingsViewController.m \
	Classes/Settings/MAVoiceSettingsViewController.m \
	Classes/Settings/MAAppearanceSettingsViewController.m \
	Classes/Settings/MALanguageSettingsViewController.m \
	Classes/Settings/MAInstructionsStore.m \
	Classes/Settings/MAPrivacySettings.m \
	Classes/Crypto/MAVault.m \
	Classes/Lock/MAAppLock.m \
	Classes/Lock/MAPINViewController.m \
	Classes/Settings/MAInstructionsViewController.m \
	Classes/History/MAChatSession.m \
	Classes/History/MAChatHistoryStore.m \
	Classes/History/MAChatHistoryViewController.m \
	Classes/Providers/MAMessage.m \
	Classes/Providers/MAConfigurableProvider.m \
	Classes/Providers/MAHTTPClient.m \
	Classes/Providers/MAOpenAICompatibleProvider.m \
	Classes/Providers/MADeepSeekProvider.m \
	Classes/Providers/MAOpenAIProvider.m \
	Classes/Providers/MAOpenRouterProvider.m \
	Classes/Providers/MAMistralProvider.m \
	Classes/Providers/MAGeminiProvider.m \
	Classes/Providers/MAOpenCodeZenProvider.m \
	Classes/Providers/MALocalProvider.m \
	Classes/Providers/MACustomProvider.m \
	Classes/Providers/MAClaudeProvider.m \
	Classes/Providers/MAProviderRegistry.m \
	Classes/Providers/MAOpenAICompatibleImageProvider.m \
	Classes/Providers/MAOpenAIImageProvider.m \
	Classes/Providers/MAOpenRouterImageProvider.m \
	Classes/Providers/MACustomImageProvider.m \
	Classes/Providers/MAImageProviderRegistry.m \
	Classes/Providers/MAKeychain.m \
	Classes/Settings/MAProviderDetailViewController.m \
	Classes/Settings/MAModelPickerViewController.m \
	Classes/Voice/MAVoiceProvider.m \
	Classes/Voice/MAVoiceService.m \
	Classes/Voice/Vox/MAVoxCore.c \
	Classes/Voice/Vox/FormantCore.c \
	Classes/Voice/Vox/Phonemes.c \
	Classes/Voice/Vox/Stress.c \
	Classes/Voice/Stt/MAFbank.c \
	Classes/Voice/Stt/MAWav.c \
	Classes/Voice/Stt/MASttEngine.c \
	Classes/Voice/Stt/MAOnDeviceRecognizer.m

# Распознавание на устройстве (Classes/Voice/Stt): признаки, WAV, каркас движка. Десктопная
# проверка — Tools/ (make -C Tools test).
# Озвучку делает собственный формантный синтезатор VoxSynth (Classes/Voice/Vox):
# чистый C, без внешних зависимостей и файлов данных. Десктопная проверка — Tools/.

MintAI_CFLAGS = -fobjc-arc -Wall \
	-IClasses \
	-IClasses/App \
	-IClasses/Chat \
	-IClasses/Settings \
	-IClasses/History \
	-IClasses/Crypto \
	-IClasses/Lock \
	-IClasses/Providers \
	-IClasses/Voice \
	-IClasses/Voice/Vox \
	-IClasses/Voice/Stt \
	-fwrapv
MintAI_FRAMEWORKS = UIKit Foundation CoreGraphics Security QuartzCore AVFoundation
# Тулчейн clang 10 (Linux) генерирует вызовы __cxa_guard_* для статических
# локальных переменных, а стандартную библиотеку C++ в чистый ObjC-проект сам не
# подключает. Без этого линковка падает с "Undefined symbols ___cxa_guard_acquire".
# Если SDK не находит libstdc++, замени на -lc++.
MintAI_LDFLAGS = -lstdc++

include $(THEOS_MAKE_PATH)/application.mk

# Установка на подключённое по USB устройство (нужен ideviceinstaller или ssh):
# make package install
