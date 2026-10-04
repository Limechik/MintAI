# Десктопная сборка голосового ядра для проверки (не часть Theos-сборки приложения).
VOX = ../Classes/Voice/Vox
SRC = $(VOX)/MAVoxCore.c $(VOX)/FormantCore.c $(VOX)/Phonemes.c $(VOX)/Stress.c
CFLAGS = -O2 -std=gnu99 -Wall -Wextra -Wno-unknown-pragmas -I$(VOX)
STT = ../Classes/Voice/Stt
STT_SRC = $(STT)/MAFbank.c $(STT)/MAWav.c $(STT)/MASttEngine.c

all: vox_cli vox_test stt_test
vox_cli: vox_cli.c $(SRC)
	cc $(CFLAGS) -o $@ vox_cli.c $(SRC) -lm
vox_test: vox_test.c $(SRC)
	cc $(CFLAGS) -fsanitize=address,undefined -fno-sanitize-recover=undefined -g -o $@ vox_test.c $(SRC) -lm
stt_test: stt_test.c $(STT_SRC)
	cc $(CFLAGS) -I$(STT) -fsanitize=address,undefined -fno-sanitize-recover=undefined -g -o $@ stt_test.c $(STT_SRC) -lm
test: vox_test stt_test
	./vox_test
	./stt_test
clean:
	rm -f vox_cli vox_test stt_test *.wav
