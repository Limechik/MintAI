// Проверки распознавания на устройстве: признаки (MAFbank), разбор WAV (MAWav),
// каркас движка (MASttEngine). Запуск: make test  (AddressSanitizer + UBSan)
#include "MAFbank.h"
#include "MAWav.h"
#include "MASttEngine.h"
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static int failures = 0;
#define CHECK(cond, ...) do { if (!(cond)) { failures++; printf("  FAIL: "); printf(__VA_ARGS__); printf("\n"); } } while (0)

static float *sine(size_t n, float hz, float amp) {
	float *x = (float *)malloc(sizeof(float) * n);
	for (size_t i = 0; i < n; i++) x[i] = amp * sinf(2.0f * (float)M_PI * hz * i / 16000.0f);
	return x;
}

// ---------- MAFbank ----------

static void testFbankConfig(void) {
	printf("fbank: параметры\n");
	MAFbankConfig c;
	MAFbankDefaultConfig(&c);
	MAFbank *ok = MAFbankCreate(&c);
	CHECK(ok != NULL, "дефолтный конфиг должен создаваться");
	CHECK(MAFbankNumMels(ok) == 80, "80 полос по умолчанию");
	MAFbankDestroy(ok);

	MAFbankConfig bad;
	bad = c; bad.fft_size = 500;     CHECK(MAFbankCreate(&bad) == NULL, "fft не степень двойки");
	bad = c; bad.fft_size = 256;     CHECK(MAFbankCreate(&bad) == NULL, "fft меньше окна");
	bad = c; bad.frame_shift = 0;    CHECK(MAFbankCreate(&bad) == NULL, "нулевой шаг");
	bad = c; bad.num_mels = 0;       CHECK(MAFbankCreate(&bad) == NULL, "нет полос");
	bad = c; bad.num_mels = 100000;  CHECK(MAFbankCreate(&bad) == NULL, "слишком много полос");
	bad = c; bad.low_freq = 9000;    CHECK(MAFbankCreate(&bad) == NULL, "low выше Найквиста");
	bad = c; bad.high_freq = 9000;   CHECK(MAFbankCreate(&bad) == NULL, "high выше Найквиста");
	bad = c; bad.preemphasis = 1.0f; CHECK(MAFbankCreate(&bad) == NULL, "предыскажение >= 1");
	CHECK(MAFbankCreate(NULL) == NULL, "NULL-конфиг");
}

static void testFbankFrames(void) {
	printf("fbank: число кадров\n");
	MAFbankConfig c; MAFbankDefaultConfig(&c);
	MAFbank *f = MAFbankCreate(&c);
	CHECK(MAFbankNumFrames(f, 0) == 0, "0 отсчётов");
	CHECK(MAFbankNumFrames(f, 399) == 0, "короче окна");
	CHECK(MAFbankNumFrames(f, 400) == 1, "ровно окно");
	CHECK(MAFbankNumFrames(f, 559) == 1, "до второго шага");
	CHECK(MAFbankNumFrames(f, 560) == 2, "второй кадр");
	CHECK(MAFbankNumFrames(f, 16000) == 98, "секунда = 98 кадров, а не %d", MAFbankNumFrames(f, 16000));
	float shortBuf[100] = {0};
	CHECK(MAFbankCompute(f, shortBuf, 100, NULL) == 0, "короткий вход без буфера вывода — 0 кадров");
	CHECK(MAFbankCompute(f, NULL, 0, NULL) == 0, "пустой вход");
	float dummy[1];
	CHECK(MAFbankCompute(f, NULL, 16000, dummy) == -1, "NULL-сэмплы при непустой длине");
	CHECK(MAFbankCompute(NULL, dummy, 16000, dummy) == -1, "NULL-fbank");
	MAFbankDestroy(f);
}

static void testFbankTone(void) {
	printf("fbank: частота тона попадает в свою полосу\n");
	MAFbankConfig c; MAFbankDefaultConfig(&c);
	MAFbank *f = MAFbankCreate(&c);
	const float freqs[] = { 300, 1000, 2500, 6000 };
	for (int t = 0; t < 4; t++) {
		size_t n = 16000;
		float *x = sine(n, freqs[t], 0.5f);
		int frames = MAFbankNumFrames(f, n);
		float *feat = (float *)malloc(sizeof(float) * frames * 80);
		CHECK(MAFbankCompute(f, x, n, feat) == frames, "кадры");

		const float *row = feat + (size_t)(frames / 2) * 80;
		int best = 0;
		for (int m = 1; m < 80; m++) if (row[m] > row[best]) best = m;

		// Ожидаемая полоса: центр m — на mel = melLow + (m+1)*step.
		float melLow = 2595.0f * log10f(1 + 20.0f / 700), melHigh = 2595.0f * log10f(1 + 8000.0f / 700);
		float melTone = 2595.0f * log10f(1 + freqs[t] / 700);
		float expect = (melTone - melLow) / ((melHigh - melLow) / 81.0f) - 1.0f;
		CHECK(fabsf(best - expect) <= 1.5f, "%g Гц: полоса %d, ожидалась около %.1f", freqs[t], best, expect);
		free(x); free(feat);
	}
	MAFbankDestroy(f);
}

static void testFbankSilenceAndFinite(void) {
	printf("fbank: тишина, постоянная составляющая, конечность\n");
	MAFbankConfig c; MAFbankDefaultConfig(&c);
	MAFbank *f = MAFbankCreate(&c);
	size_t n = 8000;
	float *zero = (float *)calloc(n, sizeof(float));
	int frames = MAFbankNumFrames(f, n);
	float *feat = (float *)malloc(sizeof(float) * frames * 80);
	MAFbankCompute(f, zero, n, feat);
	int allFloor = 1, finite = 1;
	for (int i = 0; i < frames * 80; i++) {
		if (fabsf(feat[i] - logf(1e-10f)) > 1e-3f) allFloor = 0;
		if (!isfinite(feat[i])) finite = 0;
	}
	CHECK(allFloor && finite, "тишина должна давать пол логарифма и конечные числа");

	// Постоянное смещение вычитается: результат как у тишины.
	for (size_t i = 0; i < n; i++) zero[i] = 0.3f;
	MAFbankCompute(f, zero, n, feat);
	float maxv = -1e9f;
	for (int i = 0; i < frames * 80; i++) if (feat[i] > maxv) maxv = feat[i];
	CHECK(maxv < logf(1e-6f), "DC не должен давать энергии (макс %.2f)", maxv);

	// Полный размах и клиппинг не ломают числа.
	for (size_t i = 0; i < n; i++) zero[i] = (i & 1) ? 1.0f : -1.0f;
	MAFbankCompute(f, zero, n, feat);
	finite = 1;
	for (int i = 0; i < frames * 80; i++) if (!isfinite(feat[i])) finite = 0;
	CHECK(finite, "полный размах -> конечные значения");
	free(zero); free(feat);
	MAFbankDestroy(f);
}

static void testFbankDeterminismAndReuse(void) {
	printf("fbank: повторяемость\n");
	MAFbankConfig c; MAFbankDefaultConfig(&c);
	MAFbank *f = MAFbankCreate(&c);
	size_t n = 12345;
	float *x = sine(n, 700, 0.4f);
	for (size_t i = 0; i < n; i++) x[i] += 0.1f * sinf(0.37f * i);
	int frames = MAFbankNumFrames(f, n);
	float *a = (float *)malloc(sizeof(float) * frames * 80);
	float *b = (float *)malloc(sizeof(float) * frames * 80);
	MAFbankCompute(f, x, n, a);
	// Между вызовами считаем другое — буферы внутри не должны «протекать».
	float *other = sine(5000, 3000, 0.9f);
	float *tmp = (float *)malloc(sizeof(float) * MAFbankNumFrames(f, 5000) * 80);
	MAFbankCompute(f, other, 5000, tmp);
	free(tmp);
	MAFbankCompute(f, x, n, b);
	CHECK(memcmp(a, b, sizeof(float) * frames * 80) == 0, "два прогона одного сигнала различаются");
	free(x); free(a); free(b); free(other);
	MAFbankDestroy(f);
}

static void testCMVN(void) {
	printf("fbank: CMVN\n");
	const int T = 50, M = 4;
	float feat[50 * 4];
	for (int t = 0; t < T; t++) for (int m = 0; m < M; m++) feat[t * M + m] = (float)(m * 10 + (t % 7) * (m + 1));
	// Постоянная полоса: дисперсия 0 — не должно быть NaN/inf.
	for (int t = 0; t < T; t++) feat[t * M + 3] = 5.0f;
	MAFbankNormalizeCMVN(feat, T, M);
	for (int m = 0; m < M; m++) {
		double sum = 0, sq = 0;
		for (int t = 0; t < T; t++) { double v = feat[t * M + m]; CHECK(isfinite(v), "конечность"); sum += v; sq += v * v; }
		CHECK(fabs(sum / T) < 1e-4, "среднее полосы %d = %g", m, sum / T);
		if (m != 3) CHECK(fabs(sq / T - 1.0) < 1e-3, "дисперсия полосы %d = %g", m, sq / T);
	}
	MAFbankNormalizeCMVN(NULL, 5, 5);   // не падает
	MAFbankNormalizeCMVN(feat, 0, 4);
}

// ---------- MAWav ----------

static void put16(uint8_t *p, unsigned v) { p[0] = v & 255; p[1] = (v >> 8) & 255; }
static void put32(uint8_t *p, unsigned v) { put16(p, v & 0xFFFF); put16(p + 2, v >> 16); }

// Собирает WAV: fmt-чанк, перед data — «мусорные» чанки (нечётный размер с выравниванием).
static uint8_t *makeWav(const int16_t *pcm, size_t frames, int channels, int bits, int rate,
                        int junkChunks, int declareDataSize, size_t *outLen) {
	size_t dataBytes = frames * channels * 2;
	size_t cap = 12 + 24 + junkChunks * (8 + 5 + 1) + 8 + dataBytes + 16;
	uint8_t *w = (uint8_t *)calloc(cap, 1);
	size_t p = 0;
	memcpy(w, "RIFF", 4); put32(w + 4, 0); memcpy(w + 8, "WAVE", 4); p = 12;
	memcpy(w + p, "fmt ", 4); put32(w + p + 4, 16);
	put16(w + p + 8, 1); put16(w + p + 10, channels); put32(w + p + 12, rate);
	put32(w + p + 16, rate * channels * bits / 8); put16(w + p + 20, channels * bits / 8); put16(w + p + 22, bits);
	p += 24;
	for (int j = 0; j < junkChunks; j++) {
		memcpy(w + p, "FLLR", 4); put32(w + p + 4, 5); p += 8;
		memset(w + p, 0xAB, 5); p += 5; p += 1;   // байт выравнивания
	}
	memcpy(w + p, "data", 4); put32(w + p + 4, declareDataSize >= 0 ? (unsigned)declareDataSize : (unsigned)dataBytes);
	p += 8;
	for (size_t i = 0; i < frames * channels; i++) put16(w + p + i * 2, (uint16_t)pcm[i]);
	p += dataBytes;
	*outLen = p;
	put32(w + 4, (unsigned)(p - 8));
	return w;
}

static void testWav(void) {
	printf("wav\n");
	int16_t pcm[6] = { 0, 16384, -16384, 32767, -32768, 8192 };
	size_t len; MAWavInfo info;

	uint8_t *w = makeWav(pcm, 6, 1, 16, 16000, 0, -1, &len);
	CHECK(MAWavParse(w, len, &info) == MAWAV_OK, "обычный WAV");
	CHECK(info.sample_rate == 16000 && info.channels == 1 && MAWavFrameCount(&info) == 6, "поля: %d Гц, %d кан, %zu кадров", info.sample_rate, info.channels, MAWavFrameCount(&info));
	float out[8];
	size_t got = MAWavDecodeMono(w, len, &info, out, 8);
	CHECK(got == 6, "декодировано %zu", got);
	CHECK(fabsf(out[1] - 0.5f) < 1e-6f && fabsf(out[2] + 0.5f) < 1e-6f && out[4] == -1.0f && out[3] < 1.0f, "значения отсчётов");
	CHECK(MAWavDecodeMono(w, len, &info, out, 3) == 3, "ограничение по capacity");
	free(w);

	// Лишние чанки с нечётным размером перед data (FLLR и т.п.).
	w = makeWav(pcm, 6, 1, 16, 16000, 3, -1, &len);
	CHECK(MAWavParse(w, len, &info) == MAWAV_OK && MAWavFrameCount(&info) == 6, "чанки FLLR пропускаются");
	free(w);

	// Рекордер не дописал размер: 0 и «слишком много».
	w = makeWav(pcm, 6, 1, 16, 16000, 0, 0, &len);
	CHECK(MAWavParse(w, len, &info) == MAWAV_OK && MAWavFrameCount(&info) == 6, "размер data = 0 -> до конца файла");
	free(w);
	w = makeWav(pcm, 6, 1, 16, 16000, 0, 0x7FFFFFF0, &len);
	CHECK(MAWavParse(w, len, &info) == MAWAV_OK && MAWavFrameCount(&info) == 6, "размер data больше файла -> зажимается");
	free(w);

	// Стерео усредняется.
	int16_t st[4] = { 1000, 3000, -2000, -4000 };
	w = makeWav(st, 2, 2, 16, 44100, 0, -1, &len);
	CHECK(MAWavParse(w, len, &info) == MAWAV_OK && info.channels == 2 && MAWavFrameCount(&info) == 2, "стерео");
	got = MAWavDecodeMono(w, len, &info, out, 8);
	CHECK(got == 2 && fabsf(out[0] - 2000.0f / 32768.0f) < 1e-6f && fabsf(out[1] + 3000.0f / 32768.0f) < 1e-6f, "среднее каналов");
	free(w);

	// Отказы.
	w = makeWav(pcm, 6, 1, 8, 16000, 0, -1, &len);
	CHECK(MAWavParse(w, len, &info) == MAWAV_ERR_UNSUPPORTED, "8 бит не поддерживаем");
	free(w);
	uint8_t junk[64]; memset(junk, 0x55, sizeof junk);
	CHECK(MAWavParse(junk, sizeof junk, &info) == MAWAV_ERR_NOT_WAV, "мусор");
	CHECK(MAWavParse(junk, 5, &info) == MAWAV_ERR_NOT_WAV, "обрезанный заголовок");
	CHECK(MAWavParse(NULL, 0, &info) == MAWAV_ERR_NOT_WAV, "NULL");
	w = makeWav(pcm, 6, 1, 16, 16000, 0, -1, &len);
	CHECK(MAWavParse(w, 30, &info) == MAWAV_ERR_NO_DATA, "файл оборван до data");
	// Любое усечение не должно падать (проверяется ASan).
	for (size_t cut = 0; cut <= len; cut++) { MAWavInfo i2; MAWavParse(w, cut, &i2); }
	free(w);

	// Враждебный размер чанка: огромный size у нестандартного чанка.
	w = makeWav(pcm, 6, 1, 16, 16000, 1, -1, &len);
	put32(w + 12 + 24 + 4, 0xFFFFFFF0u);   // размер FLLR
	CHECK(MAWavParse(w, len, &info) == MAWAV_ERR_NO_DATA, "переполняющий размер чанка не ломает разбор");
	free(w);
}

// ---------- MASttEngine ----------

static void writeFile(const char *path, const void *data, size_t n) {
	FILE *fp = fopen(path, "wb");
	if (n) fwrite(data, 1, n, fp);
	fclose(fp);
}

static void testEngine(void) {
	printf("движок\n");
	MASttStatus st;
	CHECK(MASttEngineSampleRate() == 16000, "частота");
	CHECK(MASttEngineLoad(NULL, &st) == NULL && st == MASTT_ERR_NO_MODEL, "NULL-путь");
	CHECK(MASttEngineLoad("/nonexistent/model.bin", &st) == NULL && st == MASTT_ERR_NO_MODEL, "нет файла");
	CHECK(MASttEngineLoad("/nonexistent/model.bin", NULL) == NULL, "status можно не передавать");

	char path[] = "/tmp/stt_test_model_XXXXXX";
	int fd = mkstemp(path); close(fd);
	writeFile(path, NULL, 0);
	CHECK(MASttEngineLoad(path, &st) == NULL && st == MASTT_ERR_BAD_MODEL, "пустой файл модели");
	writeFile(path, "MODEL", 5);
	MASttEngine *e = MASttEngineLoad(path, &st);
	CHECK(e != NULL && st == MASTT_OK, "непустой файл загружается");
	unlink(path);

	char text[64];
	size_t n = 16000;
	float *tone = sine(n, 440, 0.3f);
	float *quiet = (float *)calloc(n, sizeof(float));
	volatile int cancel = 0;

	CHECK(MASttEngineTranscribe(e, tone, n, 16000, NULL, text, sizeof text) == MASTT_ERR_NOT_IMPLEMENTED, "речеподобный сигнал доходит до декодера");
	CHECK(MASttEngineTranscribe(e, quiet, n, 16000, NULL, text, sizeof text) == MASTT_ERR_NO_SPEECH, "тишина");
	CHECK(MASttEngineTranscribe(e, tone, 1000, 16000, NULL, text, sizeof text) == MASTT_ERR_NO_SPEECH, "слишком коротко");
	CHECK(MASttEngineTranscribe(e, tone, n, 44100, NULL, text, sizeof text) == MASTT_ERR_BAD_INPUT, "не та частота");
	CHECK(MASttEngineTranscribe(e, NULL, n, 16000, NULL, text, sizeof text) == MASTT_ERR_BAD_INPUT, "NULL-сэмплы");
	CHECK(MASttEngineTranscribe(e, tone, n, 16000, NULL, text, 0) == MASTT_ERR_BAD_INPUT, "нулевой буфер текста");
	CHECK(MASttEngineTranscribe(NULL, tone, n, 16000, NULL, text, sizeof text) == MASTT_ERR_BAD_INPUT, "NULL-движок");
	cancel = 1;
	CHECK(MASttEngineTranscribe(e, tone, n, 16000, &cancel, text, sizeof text) == MASTT_ERR_CANCELLED, "флаг отмены");
	cancel = 0;
	CHECK(text[0] == '\0' || 1, "текст не определён при ошибке");

	size_t tooLong = (size_t)(MASttEngineMaxSeconds() + 1) * 16000;
	float *big = (float *)calloc(tooLong, sizeof(float));
	for (size_t i = 0; i < tooLong; i++) big[i] = 0.2f * sinf(0.05f * i);
	CHECK(MASttEngineTranscribe(e, big, tooLong, 16000, NULL, text, sizeof text) == MASTT_ERR_BAD_INPUT, "длиннее лимита");
	free(big); free(tone); free(quiet);
	MASttEngineFree(e);
	MASttEngineFree(NULL);
}

int main(void) {
	testFbankConfig();
	testFbankFrames();
	testFbankTone();
	testFbankSilenceAndFinite();
	testFbankDeterminismAndReuse();
	testCMVN();
	testWav();
	testEngine();
	if (failures) { printf("\nПровалено проверок: %d\n", failures); return 1; }
	printf("\nвсе проверки пройдены\n");
	return 0;
}
