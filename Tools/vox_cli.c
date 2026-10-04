// Консольная проверка озвучки на компьютере (то же ядро, что в приложении).
//   make -C Tools && Tools/vox_cli "В 2024 году 5% людей" out.wav [скорость] [тон] [форманты]
// Скорость 1.0 = «Обычно»; тон 1.0 стандартный, 0.8 «мужской», 1.6 «женский»;
// форманты 1.0 / 0.9 / 1.17 (значения, которые использует MAVoiceService).
#include "MAVoxCore.h"
#include <stdio.h>
#include <stdlib.h>

static void wr32(FILE *f, uint32_t v) { fwrite(&v, 4, 1, f); }
static void wr16(FILE *f, uint16_t v) { fwrite(&v, 2, 1, f); }

int main(int argc, char **argv) {
	const char *text = argc > 1 ? argv[1] : "мама мыла раму";
	const char *name = argc > 2 ? argv[2] : "speech.wav";
	float speed   = argc > 3 ? (float)atof(argv[3]) : 1.0f;
	float pitch   = argc > 4 ? (float)atof(argv[4]) : 1.0f;
	float formant = argc > 5 ? (float)atof(argv[5]) : 1.0f;

	char *norm = MAVoxNormalizeUTF8(text);
	printf("нормализовано: %s\n", norm ? norm : "(ошибка)");
	free(norm);

	short *pcm = NULL; size_t n = 0;
	int rc = MAVoxSynthesize(text, speed, pitch, formant, NULL, &pcm, &n);
	if (rc != 0) { fprintf(stderr, "ошибка синтеза: %d\n", rc); return 1; }

	uint32_t rate = (uint32_t)MAVoxSampleRate();
	FILE *f = fopen(name, "wb");
	if (!f) { perror("fopen"); return 1; }
	fwrite("RIFF", 1, 4, f); wr32(f, (uint32_t)(36 + n * 2)); fwrite("WAVEfmt ", 1, 8, f);
	wr32(f, 16); wr16(f, 1); wr16(f, 1); wr32(f, rate); wr32(f, rate * 2);
	wr16(f, 2); wr16(f, 16); fwrite("data", 1, 4, f); wr32(f, (uint32_t)(n * 2));
	if (n) fwrite(pcm, 2, n, f);
	fclose(f);
	printf("сэмплов: %zu (%.2f с), файл: %s\n", n, (double)n / rate, name);
	MAVoxFreeSamples(pcm);
	return 0;
}
