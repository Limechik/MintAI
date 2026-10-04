#include "MASttEngine.h"
#include "MAFbank.h"
#include <math.h>
#include <stdio.h>
#include <stdlib.h>

#define MASTT_SAMPLE_RATE 16000
#define MASTT_MAX_SECONDS 60
#define MASTT_MIN_SAMPLES (MASTT_SAMPLE_RATE * 3 / 10)   // 0,3 с
#define MASTT_MIN_RMS 1e-4f                              // тише — считаем тишиной

struct MASttEngine {
	MAFbank *fbank;
	// Здесь появятся веса модели и состояние декодера.
};

int MASttEngineSampleRate(void) { return MASTT_SAMPLE_RATE; }
int MASttEngineMaxSeconds(void) { return MASTT_MAX_SECONDS; }

MASttEngine *MASttEngineLoad(const char *modelPath, MASttStatus *status) {
	MASttStatus dummy;
	if (!status) status = &dummy;

	if (!modelPath || !modelPath[0]) { *status = MASTT_ERR_NO_MODEL; return NULL; }
	FILE *fp = fopen(modelPath, "rb");
	if (!fp) { *status = MASTT_ERR_NO_MODEL; return NULL; }

	// Пока формата модели нет — убеждаемся только, что файл читается и не пуст.
	int firstByte = fgetc(fp);
	fclose(fp);
	if (firstByte == EOF) { *status = MASTT_ERR_BAD_MODEL; return NULL; }

	MASttEngine *engine = (MASttEngine *)calloc(1, sizeof(MASttEngine));
	if (!engine) { *status = MASTT_ERR_MEMORY; return NULL; }

	MAFbankConfig cfg;
	MAFbankDefaultConfig(&cfg);
	cfg.sample_rate = MASTT_SAMPLE_RATE;
	engine->fbank = MAFbankCreate(&cfg);
	if (!engine->fbank) {
		free(engine);
		*status = MASTT_ERR_MEMORY;
		return NULL;
	}
	*status = MASTT_OK;
	return engine;
}

void MASttEngineFree(MASttEngine *engine) {
	if (!engine) return;
	MAFbankDestroy(engine->fbank);
	free(engine);
}

MASttStatus MASttEngineTranscribe(MASttEngine *engine,
                                  const float *samples, size_t numSamples, int sampleRate,
                                  const volatile int *cancel,
                                  char *outText, size_t outCapacity) {
	if (outText && outCapacity > 0) outText[0] = '\0';
	if (!engine || !samples || !outText || outCapacity == 0) return MASTT_ERR_BAD_INPUT;
	if (sampleRate != MASTT_SAMPLE_RATE) return MASTT_ERR_BAD_INPUT;
	if (numSamples > (size_t)MASTT_MAX_SECONDS * MASTT_SAMPLE_RATE) return MASTT_ERR_BAD_INPUT;
	if (numSamples < MASTT_MIN_SAMPLES) return MASTT_ERR_NO_SPEECH;

	double energy = 0;
	for (size_t i = 0; i < numSamples; i++) energy += (double)samples[i] * samples[i];
	if (sqrt(energy / numSamples) < MASTT_MIN_RMS) return MASTT_ERR_NO_SPEECH;

	if (cancel && *cancel) return MASTT_ERR_CANCELLED;

	int frames = MAFbankNumFrames(engine->fbank, numSamples);
	int mels = MAFbankNumMels(engine->fbank);
	if (frames <= 0) return MASTT_ERR_NO_SPEECH;

	float *features = (float *)malloc(sizeof(float) * (size_t)frames * mels);
	if (!features) return MASTT_ERR_MEMORY;
	if (MAFbankCompute(engine->fbank, samples, numSamples, features) != frames) {
		free(features);
		return MASTT_ERR_BAD_INPUT;
	}
	MAFbankNormalizeCMVN(features, frames, mels);

	if (cancel && *cancel) { free(features); return MASTT_ERR_CANCELLED; }

	// TODO: прогнать features через нейросеть и декодировать CTC в текст.
	free(features);
	return MASTT_ERR_NOT_IMPLEMENTED;
}
