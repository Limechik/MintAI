#include "MAFbank.h"
#include <math.h>
#include <stdlib.h>
#include <string.h>

#define MAFBANK_MAX_MELS 256
#define MAFBANK_MAX_FFT 8192
#define MAFBANK_MIN_ENERGY 1e-10f

struct MAFbank {
	MAFbankConfig cfg;
	int bins;               // fft_size / 2 + 1
	float *window;          // frame_length
	float *twiddleCos;      // fft_size / 2
	float *twiddleSin;      // fft_size / 2
	int *bitrev;            // fft_size
	float *melWeights;      // num_mels * bins (плотно: просто и достаточно быстро)
	int *melFirst;          // первая ненулевая полоса для каждого фильтра
	int *melLast;           // последняя (включительно)
	float *frame;           // fft_size
	float *re;              // fft_size
	float *im;              // fft_size
	float *power;           // bins
};

void MAFbankDefaultConfig(MAFbankConfig *config) {
	if (!config) return;
	config->sample_rate = 16000;
	config->frame_length = 400;
	config->frame_shift = 160;
	config->fft_size = 512;
	config->num_mels = 80;
	config->low_freq = 20.0f;
	config->high_freq = 0.0f;
	config->preemphasis = 0.97f;
}

static float hzToMel(float hz) { return 2595.0f * log10f(1.0f + hz / 700.0f); }

static int isPowerOfTwo(int v) { return v > 0 && (v & (v - 1)) == 0; }

static int validConfig(const MAFbankConfig *c) {
	if (c->sample_rate <= 0 || c->frame_length <= 0 || c->frame_shift <= 0) return 0;
	if (!isPowerOfTwo(c->fft_size) || c->fft_size < c->frame_length || c->fft_size > MAFBANK_MAX_FFT) return 0;
	if (c->num_mels < 1 || c->num_mels > MAFBANK_MAX_MELS) return 0;
	float nyquist = c->sample_rate / 2.0f;
	float high = c->high_freq > 0 ? c->high_freq : nyquist;
	if (c->low_freq < 0 || c->low_freq >= high || high > nyquist) return 0;
	if (c->preemphasis < 0 || c->preemphasis >= 1.0f) return 0;
	return 1;
}

void MAFbankDestroy(MAFbank *f) {
	if (!f) return;
	free(f->window); free(f->twiddleCos); free(f->twiddleSin); free(f->bitrev);
	free(f->melWeights); free(f->melFirst); free(f->melLast);
	free(f->frame); free(f->re); free(f->im); free(f->power);
	free(f);
}

MAFbank *MAFbankCreate(const MAFbankConfig *config) {
	if (!config || !validConfig(config)) return NULL;

	MAFbank *f = (MAFbank *)calloc(1, sizeof(MAFbank));
	if (!f) return NULL;
	f->cfg = *config;
	const int n = config->fft_size;
	const int mels = config->num_mels;
	f->bins = n / 2 + 1;

	f->window = (float *)malloc(sizeof(float) * config->frame_length);
	f->twiddleCos = (float *)malloc(sizeof(float) * (n / 2));
	f->twiddleSin = (float *)malloc(sizeof(float) * (n / 2));
	f->bitrev = (int *)malloc(sizeof(int) * n);
	f->melWeights = (float *)calloc((size_t)mels * f->bins, sizeof(float));
	f->melFirst = (int *)malloc(sizeof(int) * mels);
	f->melLast = (int *)malloc(sizeof(int) * mels);
	f->frame = (float *)malloc(sizeof(float) * n);
	f->re = (float *)malloc(sizeof(float) * n);
	f->im = (float *)malloc(sizeof(float) * n);
	f->power = (float *)malloc(sizeof(float) * f->bins);
	if (!f->window || !f->twiddleCos || !f->twiddleSin || !f->bitrev || !f->melWeights ||
	    !f->melFirst || !f->melLast || !f->frame || !f->re || !f->im || !f->power) {
		MAFbankDestroy(f);
		return NULL;
	}

	// Окно Ханна (периодическое).
	for (int i = 0; i < config->frame_length; i++) {
		f->window[i] = 0.5f - 0.5f * cosf(2.0f * (float)M_PI * i / config->frame_length);
	}

	for (int i = 0; i < n / 2; i++) {
		double a = -2.0 * M_PI * i / n;
		f->twiddleCos[i] = (float)cos(a);
		f->twiddleSin[i] = (float)sin(a);
	}

	int bits = 0;
	while ((1 << bits) < n) bits++;
	for (int i = 0; i < n; i++) {
		int r = 0;
		for (int b = 0; b < bits; b++) if (i & (1 << b)) r |= 1 << (bits - 1 - b);
		f->bitrev[i] = r;
	}

	// Треугольные mel-фильтры: края и центры равномерно по шкале mel.
	float high = config->high_freq > 0 ? config->high_freq : config->sample_rate / 2.0f;
	float melLow = hzToMel(config->low_freq), melHigh = hzToMel(high);
	float melStep = (melHigh - melLow) / (mels + 1);
	float binHz = (float)config->sample_rate / n;

	for (int m = 0; m < mels; m++) {
		float left = melLow + m * melStep;
		float center = left + melStep;
		float right = center + melStep;
		int first = -1, last = -1;
		float *w = f->melWeights + (size_t)m * f->bins;
		for (int k = 0; k < f->bins; k++) {
			float mel = hzToMel(k * binHz);
			float v = 0;
			if (mel > left && mel < center) v = (mel - left) / (center - left);
			else if (mel >= center && mel < right) v = (right - mel) / (right - center);
			if (v > 0) {
				w[k] = v;
				if (first < 0) first = k;
				last = k;
			}
		}
		// Очень узкий фильтр может не попасть ни в один бин — пусть будет пустым, но безопасным.
		f->melFirst[m] = first < 0 ? 0 : first;
		f->melLast[m] = first < 0 ? -1 : last;
	}
	return f;
}

int MAFbankNumMels(const MAFbank *f) { return f ? f->cfg.num_mels : 0; }

int MAFbankNumFrames(const MAFbank *f, size_t numSamples) {
	if (!f || numSamples < (size_t)f->cfg.frame_length) return 0;
	return (int)(1 + (numSamples - f->cfg.frame_length) / f->cfg.frame_shift);
}

// Комплексное БПФ по основанию 2 на месте (вход уже в порядке бит-реверса).
static void fft(MAFbank *f) {
	const int n = f->cfg.fft_size;
	float *re = f->re, *im = f->im;
	for (int len = 2; len <= n; len <<= 1) {
		int half = len >> 1, stride = n / len;
		for (int start = 0; start < n; start += len) {
			for (int k = 0; k < half; k++) {
				float wr = f->twiddleCos[k * stride], wi = f->twiddleSin[k * stride];
				int a = start + k, b = a + half;
				float tr = re[b] * wr - im[b] * wi;
				float ti = re[b] * wi + im[b] * wr;
				re[b] = re[a] - tr; im[b] = im[a] - ti;
				re[a] += tr;        im[a] += ti;
			}
		}
	}
}

int MAFbankCompute(MAFbank *f, const float *samples, size_t numSamples, float *out) {
	if (!f || (numSamples > 0 && !samples)) return -1;
	int frames = MAFbankNumFrames(f, numSamples);
	if (frames > 0 && !out) return -1;

	const int n = f->cfg.fft_size, len = f->cfg.frame_length, mels = f->cfg.num_mels;
	for (int t = 0; t < frames; t++) {
		const float *src = samples + (size_t)t * f->cfg.frame_shift;

		float mean = 0;
		for (int i = 0; i < len; i++) mean += src[i];
		mean /= len;
		for (int i = 0; i < len; i++) f->frame[i] = src[i] - mean;

		// Предыскажение: от конца к началу, чтобы использовать ещё не изменённых соседей.
		for (int i = len - 1; i > 0; i--) f->frame[i] -= f->cfg.preemphasis * f->frame[i - 1];
		f->frame[0] -= f->cfg.preemphasis * f->frame[0];

		for (int i = 0; i < n; i++) {
			int dst = f->bitrev[i];
			f->re[dst] = i < len ? f->frame[i] * f->window[i] : 0.0f;
			f->im[dst] = 0.0f;
		}
		fft(f);
		for (int k = 0; k < f->bins; k++) f->power[k] = f->re[k] * f->re[k] + f->im[k] * f->im[k];

		float *row = out + (size_t)t * mels;
		for (int m = 0; m < mels; m++) {
			const float *w = f->melWeights + (size_t)m * f->bins;
			float e = 0;
			for (int k = f->melFirst[m]; k <= f->melLast[m]; k++) e += w[k] * f->power[k];
			row[m] = logf(e > MAFBANK_MIN_ENERGY ? e : MAFBANK_MIN_ENERGY);
		}
	}
	return frames;
}

void MAFbankNormalizeCMVN(float *features, int numFrames, int numMels) {
	if (!features || numFrames <= 0 || numMels <= 0) return;
	for (int m = 0; m < numMels; m++) {
		double sum = 0, sumSq = 0;
		for (int t = 0; t < numFrames; t++) {
			double v = features[(size_t)t * numMels + m];
			sum += v; sumSq += v * v;
		}
		double mean = sum / numFrames;
		double var = sumSq / numFrames - mean * mean;
		float inv = var > 1e-10 ? (float)(1.0 / sqrt(var)) : 1.0f;
		for (int t = 0; t < numFrames; t++) {
			float *p = &features[(size_t)t * numMels + m];
			*p = (float)((*p - mean) * inv);
		}
	}
}
