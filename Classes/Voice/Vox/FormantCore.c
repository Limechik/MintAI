#include "FormantCore.h"
#include <math.h>

typedef struct { float a, b, c, y1, y2; } Res;

static void resSet(Res *r, float f, float bw, float fs) {
    if (f > fs * 0.45f) f = fs * 0.45f;
    if (f < 50.0f) f = 50.0f;
    float e = expf(-(float)M_PI * bw / fs);
    r->c = -e * e;
    r->b = 2.0f * e * cosf(2.0f * (float)M_PI * f / fs);
    r->a = 1.0f - r->b - r->c;
}
static inline float resRun(Res *r, float x) {
    float y = r->a * x + r->b * r->y1 + r->c * r->y2;
    r->y2 = r->y1; r->y1 = y;
    return y;
}

// Импульс голосового источника (модель Розенберга).
static float glottal(float p) {
    const float Tp = 0.40f, Tn = 0.16f;
    if (p < Tp)      return 0.5f * (1.0f - cosf((float)M_PI * p / Tp));
    if (p < Tp + Tn) return cosf((float)M_PI * 0.5f * (p - Tp) / Tn);
    return 0.0f;
}
static inline float lerp(float a, float b, float t) { return a + (b - a) * t; }
static inline float minf_(float a, float b) { return a < b ? a : b; }

size_t FCTotalSamples(const FCSegment *segs, size_t count, float fs) {
    size_t t = 0;
    for (size_t i = 0; i < count; i++) t += (size_t)(segs[i].ms * 0.001f * fs);
    return t;
}

size_t FCRender(const FCSegment *segs, size_t count,
                int16_t *out, size_t cap, float fs) {
    if (!count) return 0;
    Res r1 = {0}, r2 = {0}, r3 = {0}, rn = {0};
    FCSegment cur = segs[0];
    cur.voiceAmp = 0; cur.noiseAmp = 0; cur.am = 0;
    float phase = 0, prevG = 0, trillPh = 0;
    size_t pos = 0;
    uint32_t rng = 22222;

    for (size_t s = 0; s < count; s++) {
        FCSegment from = cur, to = segs[s];
        size_t n = (size_t)(to.ms * 0.001f * fs);
        float trF = minf_(to.trans * 0.001f * fs, n * 0.9f);   // переход формант
        float trA = minf_(0.008f * fs, n * 0.5f);              // переход громкости (8 мс)
        if (to.noiseAmp > 0) { cur.noiseF = to.noiseF; cur.noiseBw = to.noiseBw; }
        cur.am = to.am;

        for (size_t i = 0; i < n && pos < cap; i++) {
            float tf = trF > 1 ? minf_(1.0f, (float)i / trF) : 1.0f;
            float ta = trA > 1 ? minf_(1.0f, (float)i / trA) : 1.0f;
            cur.f1 = lerp(from.f1, to.f1, tf);
            cur.f2 = lerp(from.f2, to.f2, tf);
            cur.f3 = lerp(from.f3, to.f3, tf);
            cur.f0 = lerp(from.f0, to.f0, tf);
            cur.voiceAmp = lerp(from.voiceAmp, to.voiceAmp, ta);
            cur.noiseAmp = lerp(from.noiseAmp, to.noiseAmp, ta);

            if ((i & 31) == 0) {
                resSet(&r1, cur.f1, 80.0f,  fs);
                resSet(&r2, cur.f2, 100.0f, fs);
                resSet(&r3, cur.f3, 150.0f, fs);
                if (cur.noiseBw > 0) resSet(&rn, cur.noiseF, cur.noiseBw, fs);
            }

            phase += cur.f0 / fs;
            if (phase >= 1.0f) phase -= 1.0f;
            float g = glottal(phase);
            float src = (g - prevG) * 2.0f;
            prevG = g;

            rng = rng * 1664525u + 1013904223u;
            float white = ((rng >> 9) / 4194304.0f - 1.0f);

            // голос
            float v = resRun(&r1, src + white * 0.02f);
            v = resRun(&r2, v);
            v = resRun(&r3, v);
            float va = cur.voiceAmp;
            if (cur.am > 0) {                       // дрожание для "р"
                trillPh += 26.0f / fs;
                if (trillPh >= 1.0f) trillPh -= 1.0f;
                va *= 1.0f - cur.am * (0.5f + 0.5f * sinf(2.0f * (float)M_PI * trillPh));
            }
            float y = v * va;

            // шум (у звонких — модулируется голосом)
            if (cur.noiseAmp > 0) {
                float nz = resRun(&rn, white) * cur.noiseAmp * 0.05f;
                if (cur.voiceAmp > 0.05f) nz *= 0.5f + g;
                y += nz;
            }
            if (y > 1.0f) y = 1.0f; else if (y < -1.0f) y = -1.0f;
            out[pos++] = (int16_t)(y * 30000.0f);
        }
    }
    return pos;
}
