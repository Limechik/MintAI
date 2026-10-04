#ifndef MAWav_h
#define MAWav_h

#include <stddef.h>
#include <stdint.h>

// Разбор WAV (PCM 16 бит) из памяти — для записи, которую делает AVAudioRecorder.
// Чистый C без Foundation. Устойчив к лишним чанкам (FLLR, LIST…) и к заголовку, в
// котором размер данных не дописан (0 или больше реального).

#ifdef __cplusplus
extern "C" {
#endif

enum {
	MAWAV_OK = 0,
	MAWAV_ERR_NOT_WAV = -1,      // нет RIFF/WAVE или обрезанный заголовок
	MAWAV_ERR_UNSUPPORTED = -2,  // не PCM 16 бит
	MAWAV_ERR_NO_DATA = -3,      // нет чанков fmt или data
};

typedef struct {
	int sample_rate;
	int channels;
	size_t data_offset;  // смещение первого отсчёта от начала файла
	size_t data_bytes;   // сколько байт данных реально лежит в файле
} MAWavInfo;

int MAWavParse(const uint8_t *bytes, size_t length, MAWavInfo *info);

// Число кадров (отсчётов на канал) в данных.
size_t MAWavFrameCount(const MAWavInfo *info);

// Декодирует в моно float [-1, 1) (каналы усредняются). Пишет не больше capacity
// отсчётов, возвращает сколько записано.
size_t MAWavDecodeMono(const uint8_t *bytes, size_t length, const MAWavInfo *info,
                       float *out, size_t capacity);

#ifdef __cplusplus
}
#endif

#endif
