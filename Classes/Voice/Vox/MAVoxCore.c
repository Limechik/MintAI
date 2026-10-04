#include "MAVoxCore.h"
#include "FormantCore.h"
#include "Phonemes.h"
#include <math.h>
#include <stdlib.h>
#include <string.h>

#define kVoxRate 22050

// Ядро выдаёт тихий сигнал (RMS ≈ -30 дБFS), а громкость заметно зависит от тона и формант
// (женский стиль втрое громче мужского). Базовое усиление приводит стандартный голос к
// RMS ≈ -20 дБFS; поправка по параметрам голоса выравнивает три стиля из настроек
// (подобрана по измерениям на нескольких фразах). Усиление фиксированное, а не по сигналу,
// чтобы громкость не «прыгала» между соседними кусками текста.
#define kVoxBaseGain 2.75f

#pragma mark - Векторы

typedef struct { uint32_t *d; size_t n, cap; int oom; } U32Vec;
typedef struct { int16_t  *d; size_t n, cap; int oom; } PCMVec;

static void u32Push(U32Vec *v, uint32_t c) {
	if (v->oom) return;
	if (v->n == v->cap) {
		size_t nc = v->cap ? v->cap * 2 : 256;
		uint32_t *g = (uint32_t *)realloc(v->d, nc * sizeof(uint32_t));
		if (!g) { v->oom = 1; return; }
		v->d = g; v->cap = nc;
	}
	v->d[v->n++] = c;
}

static int pcmAppend(PCMVec *v, const int16_t *src, size_t count) {
	if (v->oom) return -5;
	if (v->n + count > v->cap) {
		size_t nc = v->cap ? v->cap : 65536;
		while (nc < v->n + count) nc *= 2;
		int16_t *g = (int16_t *)realloc(v->d, nc * sizeof(int16_t));
		if (!g) { v->oom = 1; return -5; }
		v->d = g; v->cap = nc;
	}
	memcpy(v->d + v->n, src, count * sizeof(int16_t));
	v->n += count;
	return 0;
}

#pragma mark - UTF-8 <-> UTF-32

// Невалидные байты заменяются пробелом. Результат не длиннее входа (в кодовых точках).
static size_t utf8Decode(const unsigned char *s, size_t len, uint32_t *o) {
	size_t n = 0, i = 0;
	while (i < len) {
		uint32_t c = s[i];
		size_t need;
		uint32_t cp;
		if (c < 0x80) { o[n++] = c; i++; continue; }
		else if ((c & 0xE0) == 0xC0) { need = 1; cp = c & 0x1F; }
		else if ((c & 0xF0) == 0xE0) { need = 2; cp = c & 0x0F; }
		else if ((c & 0xF8) == 0xF0) { need = 3; cp = c & 0x07; }
		else { o[n++] = ' '; i++; continue; }

		int ok = (i + need < len);
		for (size_t k = 1; ok && k <= need; k++) {
			if ((s[i + k] & 0xC0) != 0x80) ok = 0;
			else cp = (cp << 6) | (s[i + k] & 0x3F);
		}
		if (!ok) { o[n++] = ' '; i++; continue; }
		o[n++] = cp;
		i += need + 1;
	}
	return n;
}

static void u32PushUTF8Literal(U32Vec *v, const char *s) {
	size_t len = strlen(s);
	uint32_t tmp[64];
	if (len > 64) len = 64; // литералы из таблиц ниже заведомо короче
	size_t n = utf8Decode((const unsigned char *)s, len, tmp);
	for (size_t i = 0; i < n; i++) u32Push(v, tmp[i]);
}

static size_t utf8Encode(uint32_t c, char *o) {
	if (c < 0x80)    { o[0] = (char)c; return 1; }
	if (c < 0x800)   { o[0] = (char)(0xC0 | (c >> 6)); o[1] = (char)(0x80 | (c & 0x3F)); return 2; }
	if (c < 0x10000) { o[0] = (char)(0xE0 | (c >> 12)); o[1] = (char)(0x80 | ((c >> 6) & 0x3F)); o[2] = (char)(0x80 | (c & 0x3F)); return 3; }
	o[0] = (char)(0xF0 | (c >> 18)); o[1] = (char)(0x80 | ((c >> 12) & 0x3F));
	o[2] = (char)(0x80 | ((c >> 6) & 0x3F)); o[3] = (char)(0x80 | (c & 0x3F));
	return 4;
}

#pragma mark - Классификация символов

static int isDigitCP(uint32_t c) { return c >= '0' && c <= '9'; }
static int isAsciiLetterCP(uint32_t c) { return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z'); }
static int isCyrLetterCP(uint32_t c) { return (c >= 0x410 && c <= 0x44F) || c == 0x401 || c == 0x451; }
static int isAnyLetterCP(uint32_t c) { return isAsciiLetterCP(c) || isCyrLetterCP(c); }
static int isApostropheCP(uint32_t c) { return c == '\'' || c == 0x2019; }

#pragma mark - Числа словами (именительный падеж, мужской род)

static const char *const kOnesM[10] = {"", "один", "два", "три", "четыре", "пять", "шесть", "семь", "восемь", "девять"};
static const char *const kOnesF[10] = {"", "одна", "две", "три", "четыре", "пять", "шесть", "семь", "восемь", "девять"};
static const char *const kTeens[10] = {"десять", "одиннадцать", "двенадцать", "тринадцать", "четырнадцать",
                                       "пятнадцать", "шестнадцать", "семнадцать", "восемнадцать", "девятнадцать"};
static const char *const kTens[10]  = {"", "", "двадцать", "тридцать", "сорок", "пятьдесят",
                                       "шестьдесят", "семьдесят", "восемьдесят", "девяносто"};
static const char *const kHund[10]  = {"", "сто", "двести", "триста", "четыреста", "пятьсот",
                                       "шестьсот", "семьсот", "восемьсот", "девятьсот"};
static const char *const kScale[4][3] = {
	{"", "", ""},
	{"тысяча", "тысячи", "тысяч"},
	{"миллион", "миллиона", "миллионов"},
	{"миллиард", "миллиарда", "миллиардов"},
};
static const char *const kPercent[3] = {"процент", "процента", "процентов"};

// 0 — «один …», 1 — «два/три/четыре …», 2 — «пять … / 11–14».
static int pluralForm(uint64_t n) {
	uint64_t m100 = n % 100, m10 = n % 10;
	if (m100 >= 11 && m100 <= 14) return 2;
	if (m10 == 1) return 0;
	if (m10 >= 2 && m10 <= 4) return 1;
	return 2;
}

// Слово с пробелом перед ним, если предыдущий символ не пробел.
static void emitWord(U32Vec *v, const char *w) {
	if (v->n > 0 && v->d[v->n - 1] != ' ') u32Push(v, ' ');
	u32PushUTF8Literal(v, w);
}

// Число до 999 999 999 999 включительно.
static void emitNumber(U32Vec *v, uint64_t n) {
	if (n == 0) { emitWord(v, "ноль"); return; }
	int groups[4];
	for (int g = 0; g < 4; g++) { groups[g] = (int)(n % 1000); n /= 1000; }
	for (int g = 3; g >= 0; g--) {
		int x = groups[g];
		if (!x) continue;
		int h = x / 100, t = (x / 10) % 10, o = x % 10;
		if (h) emitWord(v, kHund[h]);
		if (t == 1) {
			emitWord(v, kTeens[o]);
		} else {
			if (t >= 2) emitWord(v, kTens[t]);
			if (o) emitWord(v, g == 1 ? kOnesF[o] : kOnesM[o]); // «одна/две тысячи»
		}
		if (g > 0) emitWord(v, kScale[g][pluralForm((uint64_t)x)]);
	}
}

static void emitDigitWord(U32Vec *v, uint32_t digit) {
	emitWord(v, digit == '0' ? "ноль" : kOnesM[digit - '0']);
}

#pragma mark - Латиница -> кириллица (грубая транслитерация)

typedef struct { const char *lat; const char *cyr; } TrEntry;

static const TrEntry kTr2[] = {
	{"sh", "ш"}, {"ch", "ч"}, {"th", "з"}, {"ph", "ф"}, {"kh", "х"}, {"zh", "ж"},
	{"ck", "к"}, {"qu", "кв"}, {"ee", "и"}, {"ea", "и"}, {"oo", "у"}, {"ou", "ау"},
	{"ay", "эй"}, {"ai", "эй"}, {"ey", "эй"}, {"oy", "ой"}, {"ng", "нг"}, {"wh", "в"},
};
#define NTR2 (sizeof(kTr2) / sizeof(kTr2[0]))

static const char *const kTr1[26] = {
	"а", "б", "к", "д", "е", "ф", "г", "х", "и", "дж", "к", "л", "м",
	"н", "о", "п", "к", "р", "с", "т", "у", "в", "в", "кс", "и", "з",
};

static void translit(const uint32_t *w, size_t len, U32Vec *out) {
	char *s = (char *)malloc(len + 1);
	if (!s) { out->oom = 1; return; }
	size_t m = 0;
	for (size_t i = 0; i < len; i++) {
		if (isApostropheCP(w[i])) continue; // don't -> «дон»
		s[m++] = (char)(w[i] | 0x20);       // только ASCII-буквы, регистр не важен
	}

	// Чтобы слитно идущая кириллица не склеилась с транслитом в одно слово.
	if (out->n > 0 && isCyrLetterCP(out->d[out->n - 1])) u32Push(out, ' ');

	for (size_t i = 0; i < m; ) {
		int done = 0;
		if (i + 1 < m) {
			for (size_t k = 0; k < NTR2; k++) {
				if (s[i] == kTr2[k].lat[0] && s[i + 1] == kTr2[k].lat[1]) {
					u32PushUTF8Literal(out, kTr2[k].cyr);
					i += 2; done = 1; break;
				}
			}
		}
		if (done) continue;
		char ch = s[i];
		const char *r = kTr1[ch - 'a'];
		if (ch == 'c' && i + 1 < m && (s[i + 1] == 'e' || s[i + 1] == 'i' || s[i + 1] == 'y')) r = "с";
		u32PushUTF8Literal(out, r);
		i++;
	}
	free(s);
}

#pragma mark - Нормализация текста

static void normalizeText(const uint32_t *in, size_t n, U32Vec *out) {
	size_t i = 0;
	while (i < n) {
		uint32_t c = in[i];

		if (isDigitCP(c)) {
			size_t j = i;
			while (j < n && isDigitCP(in[j])) j++;
			size_t len = j - i;

			uint64_t value = 0;
			int haveValue = 0;
			// Длинные числа и числа с ведущим нулём («007», номера) читаем по цифрам.
			if (len <= 12 && !(len > 1 && in[i] == '0')) {
				for (size_t k = i; k < j; k++) value = value * 10 + (in[k] - '0');
				haveValue = 1;
				emitNumber(out, value);
			} else {
				for (size_t k = i; k < j; k++) emitDigitWord(out, in[k]);
			}

			int hasFraction = 0;
			if (j + 1 < n && (in[j] == '.' || in[j] == ',') && isDigitCP(in[j + 1])) {
				hasFraction = 1;
				emitWord(out, in[j] == '.' ? "точка" : "запятая");
				size_t k = j + 1;
				while (k < n && isDigitCP(in[k])) { emitDigitWord(out, in[k]); k++; }
				j = k;
			}

			// «5%» и «5 %» -> «пять процентов».
			size_t k = j;
			if (k < n && in[k] == ' ') k++;
			if (k < n && in[k] == '%') {
				emitWord(out, hasFraction ? kPercent[1] : (haveValue ? kPercent[pluralForm(value)] : kPercent[2]));
				j = k + 1;
			}

			if (j < n && isAnyLetterCP(in[j])) u32Push(out, ' '); // «5кг» — не склеивать со следующим словом
			i = j;
			continue;
		}

		if (isAsciiLetterCP(c)) {
			size_t j = i;
			while (j < n) {
				if (isAsciiLetterCP(in[j])) { j++; continue; }
				if (isApostropheCP(in[j]) && j > i && j + 1 < n && isAsciiLetterCP(in[j + 1])) { j++; continue; }
				break;
			}
			translit(in + i, j - i, out);
			i = j;
			continue;
		}

		if (c == '%') { emitWord(out, kPercent[0]); i++; continue; }

		u32Push(out, c);
		i++;
	}
}

#pragma mark - Синтез

static float clampf_(float v, float lo, float hi, float fallback) {
	if (!(v == v)) return fallback; // NaN
	if (v < lo) return lo;
	if (v > hi) return hi;
	return v;
}

static int containsCyrillic(const uint32_t *t, size_t len) {
	for (size_t i = 0; i < len; i++) if (isCyrLetterCP(t[i])) return 1;
	return 0;
}

// Одно предложение -> PCM, добавляется в pcm.
static int renderSlice(const uint32_t *t, size_t len, float speed, float pitch, float formant, PCMVec *pcm) {
	size_t cap = 8 * len + 16;
	FCSegment *segs = (FCSegment *)malloc(cap * sizeof(FCSegment));
	if (!segs) return -5;

	size_t ns = PHTextToSegments(t, len, segs, cap, speed);
	for (size_t k = 0; k < ns; k++) {
		segs[k].f0 *= pitch;
		if (formant != 1.0f) {
			segs[k].f1 *= formant;
			segs[k].f2 *= formant;
			segs[k].f3 *= formant;
		}
	}

	size_t total = FCTotalSamples(segs, ns, (float)kVoxRate) + 100;
	int16_t *buf = (int16_t *)calloc(total, sizeof(int16_t));
	if (!buf) { free(segs); return -5; }

	size_t got = FCRender(segs, ns, buf, total, (float)kVoxRate);

	float gain = kVoxBaseGain * powf(pitch, -0.9f) * powf(formant, -0.8f);
	for (size_t k = 0; k < got; k++) {
		float y = (float)buf[k] * gain;
		buf[k] = (int16_t)(y > 32767.0f ? 32767.0f : (y < -32768.0f ? -32768.0f : y));
	}

	int rc = pcmAppend(pcm, buf, got);
	free(buf);
	free(segs);
	return rc;
}

int MAVoxSampleRate(void) { return kVoxRate; }

int MAVoxSynthesize(const char *utf8Text, float speed, float pitchScale, float formantScale,
                    volatile int *cancelFlag, short **outSamples, size_t *outSampleCount) {
	if (outSamples) *outSamples = NULL;
	if (outSampleCount) *outSampleCount = 0;
	if (!utf8Text || !outSamples || !outSampleCount) return -3;

	speed        = clampf_(speed, 0.5f, 2.5f, 1.0f);
	pitchScale   = clampf_(pitchScale, 0.5f, 2.5f, 1.0f);
	formantScale = clampf_(formantScale, 0.7f, 1.5f, 1.0f);

	size_t bytes = strlen(utf8Text);
	uint32_t *raw = (uint32_t *)malloc((bytes + 1) * sizeof(uint32_t));
	if (!raw) return -5;
	size_t rawCount = utf8Decode((const unsigned char *)utf8Text, bytes, raw);

	U32Vec norm = {0};
	normalizeText(raw, rawCount, &norm);
	free(raw);
	if (norm.oom) { free(norm.d); return -5; }

	PCMVec pcm = {0};
	int rc = 0;
	size_t start = 0, i = 0;
	while (rc == 0 && start < norm.n) {
		// Граница предложения: перевод строки либо .!? перед пробелом/концом текста
		// («т.д.», «3.14», «site.com» посреди слова предложение не рвут).
		size_t end = norm.n;
		for (i = start; i < norm.n; i++) {
			uint32_t c = norm.d[i];
			if (c == '\n') { end = i + 1; break; }
			if (c == '.' || c == '!' || c == '?') {
				size_t j = i + 1;
				while (j < norm.n && (norm.d[j] == '.' || norm.d[j] == '!' || norm.d[j] == '?')) j++;
				if (j >= norm.n || norm.d[j] == ' ' || norm.d[j] == '\t' || norm.d[j] == '\n') { end = j; break; }
				i = j - 1;
			}
		}

		if (cancelFlag && *cancelFlag) { rc = -4; break; }
		if (containsCyrillic(norm.d + start, end - start)) {
			rc = renderSlice(norm.d + start, end - start, speed, pitchScale, formantScale, &pcm);
		}
		start = end;
	}
	free(norm.d);

	if (rc != 0) { free(pcm.d); return rc; }
	if (cancelFlag && *cancelFlag) { free(pcm.d); return -4; }

	*outSamples = (short *)pcm.d; // int16_t == short на всех целевых платформах
	*outSampleCount = pcm.n;
	if (pcm.n == 0) { free(pcm.d); *outSamples = NULL; }
	return 0;
}

void MAVoxFreeSamples(short *samples) { free(samples); }

char *MAVoxNormalizeUTF8(const char *utf8Text) {
	if (!utf8Text) return NULL;
	size_t bytes = strlen(utf8Text);
	uint32_t *raw = (uint32_t *)malloc((bytes + 1) * sizeof(uint32_t));
	if (!raw) return NULL;
	size_t rawCount = utf8Decode((const unsigned char *)utf8Text, bytes, raw);

	U32Vec norm = {0};
	normalizeText(raw, rawCount, &norm);
	free(raw);
	if (norm.oom) { free(norm.d); return NULL; }

	char *out = (char *)malloc(norm.n * 4 + 1);
	if (!out) { free(norm.d); return NULL; }
	size_t len = 0;
	for (size_t k = 0; k < norm.n; k++) len += utf8Encode(norm.d[k], out + len);
	out[len] = 0;
	free(norm.d);
	return out;
}
