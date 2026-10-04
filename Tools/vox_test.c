// Проверки ядра озвучки: нормализация текста, граничные случаи, отмена, потоки.
// Запуск: make test  (собирается с AddressSanitizer + UBSan)
#include "MAVoxCore.h"
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

static int failures = 0;
#define CHECK(cond, ...) do { if (!(cond)) { failures++; printf("  FAIL: "); printf(__VA_ARGS__); printf("\n"); } } while (0)

static void expectNorm(const char *in, const char *want) {
	char *got = MAVoxNormalizeUTF8(in);
	int ok = got && strcmp(got, want) == 0;
	CHECK(ok, "«%s» -> «%s», ожидалось «%s»", in, got ? got : "(null)", want);
	free(got);
}

static size_t synthCount(const char *text, float speed, float pitch, float formant) {
	short *pcm = NULL; size_t n = 0;
	int rc = MAVoxSynthesize(text, speed, pitch, formant, NULL, &pcm, &n);
	CHECK(rc == 0, "синтез «%s» вернул %d", text, rc);
	MAVoxFreeSamples(pcm);
	return n;
}

static void *threadMain(void *arg) {
	short *pcm = NULL; size_t n = 0;
	MAVoxSynthesize("В 2024 году 5% людей сказали привет.", 1.0f, 1.0f, 1.0f, NULL, &pcm, &n);
	unsigned long long sum = 0;
	for (size_t i = 0; i < n; i++) sum = sum * 131 + (unsigned short)pcm[i];
	MAVoxFreeSamples(pcm);
	((unsigned long long *)arg)[0] = sum;
	((unsigned long long *)arg)[1] = n;
	return NULL;
}

int main(void) {
	printf("нормализация\n");
	expectNorm("2024", "две тысячи двадцать четыре");
	expectNorm("0", "ноль");
	expectNorm("21000", "двадцать одна тысяча");
	expectNorm("2000", "две тысячи");
	expectNorm("1000000", "один миллион");
	expectNorm("2000000", "два миллиона");
	expectNorm("115", "сто пятнадцать");
	expectNorm("999999999999", "девятьсот девяносто девять миллиардов девятьсот девяносто девять миллионов девятьсот девяносто девять тысяч девятьсот девяносто девять");
	expectNorm("5%", "пять процентов");
	expectNorm("1%", "один процент");
	expectNorm("22 %", "двадцать два процента");
	expectNorm("11%", "одиннадцать процентов");
	expectNorm("3.14", "три точка один четыре");
	expectNorm("3,5%", "три запятая пять процента");
	expectNorm("007", "ноль ноль семь");
	expectNorm("1234567890123", "один два три четыре пять шесть семь восемь девять ноль один два три");
	expectNorm("5кг", "пять кг");
	expectNorm("hello", "хелло");
	expectNorm("API", "апи");
	expectNorm("GPT4", "гпт четыре");
	expectNorm("don't", "донт");
	expectNorm("city", "сити");
	expectNorm("Привет, мир!", "Привет, мир!");
	expectNorm("Это iPhone 15.", "Это ифоне пятнадцать.");
	expectNorm("", "");

	printf("синтез\n");
	size_t hello = synthCount("Привет, мир!", 1.0f, 1.0f, 1.0f);
	double sec = (double)hello / MAVoxSampleRate();
	CHECK(sec > 0.5 && sec < 5.0, "«Привет, мир!» длится %.2f с", sec);

	size_t plain = synthCount("год", 1.0f, 1.0f, 1.0f);
	size_t numeric = synthCount("2024 год", 1.0f, 1.0f, 1.0f);
	CHECK(numeric > plain * 2, "число не озвучилось: %zu vs %zu сэмплов", numeric, plain);

	size_t slow = synthCount("Съешь же ещё этих мягких французских булок.", 1.0f, 1.0f, 1.0f);
	size_t fast = synthCount("Съешь же ещё этих мягких французских булок.", 2.0f, 1.0f, 1.0f);
	CHECK(fast < slow * 0.65 && fast > slow * 0.35, "скорость x2: %zu vs %zu", fast, slow);

	size_t twoSent = synthCount("Привет. Мир.", 1.0f, 1.0f, 1.0f);
	CHECK(twoSent > 0, "два предложения пусты");
	size_t abbr = synthCount("т.д.", 1.0f, 1.0f, 1.0f);
	CHECK(abbr > 0, "«т.д.» пусто");

	printf("граничные случаи\n");
	{
		short *pcm = (short *)1; size_t n = 99;
		int rc = MAVoxSynthesize("😊 ★ ***", 1, 1, 1, NULL, &pcm, &n);
		CHECK(rc == 0 && n == 0 && pcm == NULL, "только символы: rc=%d n=%zu", rc, n);
		pcm = (short *)1; n = 99;
		rc = MAVoxSynthesize("", 1, 1, 1, NULL, &pcm, &n);
		CHECK(rc == 0 && n == 0 && pcm == NULL, "пустая строка: rc=%d n=%zu", rc, n);
		rc = MAVoxSynthesize(NULL, 1, 1, 1, NULL, &pcm, &n);
		CHECK(rc == -3, "NULL-текст: rc=%d", rc);
		rc = MAVoxSynthesize("привет", 1, 1, 1, NULL, NULL, &n);
		CHECK(rc == -3, "NULL-выход: rc=%d", rc);
	}
	synthCount("\xff\xfe привет \xc3 мир \xe2\x82", 1, 1, 1);            // битый UTF-8
	synthCount("привет", NAN, INFINITY, -5.0f);                           // мусорные параметры
	synthCount("привет", 0.0f, 0.0f, 0.0f);
	synthCount("\n\n\n привет \n\n мир \n", 1, 1, 1);                      // переводы строк
	synthCount("а", 1, 1, 1);
	synthCount("ъ ь ъь", 1, 1, 1);

	{
		volatile int cancel = 1; short *pcm = NULL; size_t n = 0;
		int rc = MAVoxSynthesize("Привет. Как дела? Хорошо.", 1, 1, 1, &cancel, &pcm, &n);
		CHECK(rc == -4 && pcm == NULL && n == 0, "отмена: rc=%d", rc);
	}

	{   // длинный текст без знаков препинания и с ними
		size_t len = 3000;
		char *big = (char *)malloc(len * 2 + 8);
		size_t p = 0;
		for (size_t i = 0; i < len / 6; i++) { memcpy(big + p, "слово ", 11); p += 11; }
		big[p] = 0;
		size_t n = synthCount(big, 1.5f, 1.6f, 1.17f);
		CHECK(n > 100000, "длинный текст: %zu сэмплов", n);
		free(big);
	}

	{   // громкость: нет клиппинга и есть сигнал
		short *pcm = NULL; size_t n = 0;
		MAVoxSynthesize("Съешь же ещё этих мягких французских булок, да выпей чаю.", 1, 1, 1, NULL, &pcm, &n);
		int peak = 0; double energy = 0;
		for (size_t i = 0; i < n; i++) { int a = abs(pcm[i]); if (a > peak) peak = a; energy += (double)pcm[i] * pcm[i]; }
		CHECK(peak > 2000 && peak <= 32767, "пик %d", peak);
		CHECK(sqrt(energy / n) > 300, "слишком тихо: rms %.0f", sqrt(energy / n));
		MAVoxFreeSamples(pcm);
	}

	printf("громкость стилей\n");
	{
		static const char *phrases[] = {
			"Съешь же ещё этих мягких французских булок, да выпей чаю.",
			"Привет! Как твои дела сегодня? Погода хорошая.",
			"Мама мыла раму. Молоко и хлеб в магазине.",
			"Сегодня в Москве будет солнечно, температура около двадцати градусов.",
		};
		static const float styles[3][2] = { {1.0f, 1.0f}, {0.8f, 0.9f}, {1.6f, 1.17f} }; // стандарт, мужской, женский
		double rmsStyle[3] = {0, 0, 0};
		for (int s = 0; s < 3; s++) {
			for (int k = 0; k < 4; k++) {
				short *pcm = NULL; size_t n = 0;
				MAVoxSynthesize(phrases[k], 1, styles[s][0], styles[s][1], NULL, &pcm, &n);
				double e = 0; int peak = 0;
				for (size_t i = 0; i < n; i++) { e += (double)pcm[i] * pcm[i]; if (abs(pcm[i]) > peak) peak = abs(pcm[i]); }
				rmsStyle[s] += sqrt(e / n) / 4;
				CHECK(peak < 32000, "стиль %d, фраза %d: пик %d — риск клиппинга", s, k, peak);
				MAVoxFreeSamples(pcm);
			}
		}
		for (int s = 0; s < 3; s++) {
			double db = 20 * log10(rmsStyle[s] / rmsStyle[0]);
			printf("  стиль %d: RMS %.0f (%+.1f дБ к стандартному)\n", s, rmsStyle[s], db);
			CHECK(fabs(db) < 2.0, "стиль %d громкость отличается на %.1f дБ", s, db);
		}
		double stdDb = 20 * log10(rmsStyle[0] / 32768.0);
		CHECK(stdDb > -24.0 && stdDb < -16.0, "общий уровень %.1f дБFS", stdDb);
	}

	printf("потоки\n");
	{
		pthread_t th[4]; unsigned long long res[4][2];
		for (int i = 0; i < 4; i++) pthread_create(&th[i], NULL, threadMain, res[i]);
		for (int i = 0; i < 4; i++) pthread_join(th[i], NULL);
		for (int i = 1; i < 4; i++)
			CHECK(res[i][0] == res[0][0] && res[i][1] == res[0][1], "поток %d дал другой результат", i);
	}

	printf(failures ? "\nПРОВАЛЕНО: %d\n" : "\nвсе проверки пройдены\n", failures);
	return failures ? 1 : 0;
}
