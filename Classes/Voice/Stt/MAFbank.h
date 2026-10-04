#ifndef MAFbank_h
#define MAFbank_h

#include <stddef.h>

// Признаки для распознавания речи: логарифм энергий в mel-полосах (log-mel fbank).
// Чистый C без Foundation — проверяется на компьютере отдельно от приложения
// (см. Tools/stt_test.c).
//
// Вход — моно-сигнал float в диапазоне [-1, 1]. Для каждого кадра:
//   вычесть среднее -> предыскажение -> окно Ханна -> |FFT|^2 -> mel-фильтры -> log.
// Кадры берутся без добивки края: вход короче одного окна даёт 0 кадров.
//
// Параметры (длина кадра, число полос) определяются моделью, которая будет
// подключена; значения по умолчанию — типичные для речевых моделей 16 кГц.
//
// Один MAFbank хранит рабочие буферы, поэтому НЕ потокобезопасен: один экземпляр —
// один поток. Разные экземпляры друг другу не мешают.

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
	int sample_rate;    // Гц (по умолчанию 16000)
	int frame_length;   // длина окна в отсчётах (400 = 25 мс)
	int frame_shift;    // шаг окна в отсчётах (160 = 10 мс)
	int fft_size;       // степень двойки, >= frame_length (512)
	int num_mels;       // число mel-полос (80)
	float low_freq;     // нижняя граница полос, Гц (20)
	float high_freq;    // верхняя граница, Гц; <= 0 — половина частоты дискретизации
	float preemphasis;  // коэффициент предыскажения (0.97)
} MAFbankConfig;

typedef struct MAFbank MAFbank;

void MAFbankDefaultConfig(MAFbankConfig *config);

// NULL, если параметры некорректны (fft_size не степень двойки или меньше окна,
// шаг/окно/полосы <= 0, low >= high, high выше Найквиста) или не хватило памяти.
MAFbank *MAFbankCreate(const MAFbankConfig *config);
void MAFbankDestroy(MAFbank *fbank);

int MAFbankNumMels(const MAFbank *fbank);

// Сколько кадров получится из numSamples отсчётов.
int MAFbankNumFrames(const MAFbank *fbank, size_t numSamples);

// Считает признаки. out — массив float на MAFbankNumFrames(...) * num_mels,
// кадр за кадром (frame-major). Возвращает число кадров или -1 при ошибке аргументов.
int MAFbankCompute(MAFbank *fbank, const float *samples, size_t numSamples, float *out);

// Нормализация среднего и дисперсии по каждой полосе внутри высказывания (CMVN).
void MAFbankNormalizeCMVN(float *features, int numFrames, int numMels);

#ifdef __cplusplus
}
#endif

#endif
