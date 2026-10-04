#include "Phonemes.h"
#include "Stress.h"
#include <stdlib.h>

enum { K_STOP, K_FRIC, K_AFFR, K_NASAL, K_LAT, K_TRILL, K_GLIDE };
enum { I_NEUTRAL, I_HARD, I_SOFT };   // "врождённая" твёрдость/мягкость
enum { VPOS_STRESSED, VPOS_PRETONIC1, VPOS_REDUCED };  // позиция гласной относительно ударения

typedef struct {
    uint32_t cp; int kind; int voiced; int inh;
    float f1, f2, f3;          // формантный "locus" места образования
    float nf, nbw, namp;       // шум: центр, полоса, громкость
    float ms;
} Cons;

static const Cons kCons[] = {
 /* п */ {0x43F,K_STOP, 0,I_NEUTRAL, 250, 800,2300, 1200,2000,2.0,  0},
 /* б */ {0x431,K_STOP, 1,I_NEUTRAL, 250, 800,2300, 1200,2000,1.6,  0},
 /* т */ {0x442,K_STOP, 0,I_NEUTRAL, 250,1800,2800, 4500,2500,1.2,  0},
 /* д */ {0x434,K_STOP, 1,I_NEUTRAL, 250,1800,2800, 4500,2500,1.0,  0},
 /* к */ {0x43A,K_STOP, 0,I_NEUTRAL, 250,1500,2300, 2300,1500,1.3,  0},
 /* г */ {0x433,K_STOP, 1,I_NEUTRAL, 250,1500,2300, 2300,1500,1.1,  0},
 /* ф */ {0x444,K_FRIC, 0,I_NEUTRAL, 300,1000,2300, 5000,4500,1.2, 90},
 /* в */ {0x432,K_FRIC, 1,I_NEUTRAL, 300,1000,2300, 5000,4500,1.3, 70},
 /* с */ {0x441,K_FRIC, 0,I_NEUTRAL, 300,1800,2800, 6500,2500,1.0,100},
 /* з */ {0x437,K_FRIC, 1,I_NEUTRAL, 300,1800,2800, 6500,2500,0.55,85},
 /* ш */ {0x448,K_FRIC, 0,I_HARD,    300,1600,2500, 2700,1400,1.9,110},
 /* ж */ {0x436,K_FRIC, 1,I_HARD,    300,1600,2500, 2700,1400,1.7, 95},
 /* щ */ {0x449,K_FRIC, 0,I_SOFT,    300,2000,2900, 3500,1800,1.3,140},
 /* х */ {0x445,K_FRIC, 0,I_NEUTRAL, 300,1500,2400, 2000,3000,2.4, 90},
 /* ц */ {0x446,K_AFFR, 0,I_HARD,    250,1800,2800, 6000,2500,1.3, 90},
 /* ч */ {0x447,K_AFFR, 0,I_SOFT,    250,2000,2900, 3300,1600,1.7, 80},
 /* м */ {0x43C,K_NASAL,1,I_NEUTRAL, 250,1100,2400, 0,0,0,  80},
 /* н */ {0x43D,K_NASAL,1,I_NEUTRAL, 250,1500,2500, 0,0,0,  80},
 /* л */ {0x43B,K_LAT,  1,I_NEUTRAL, 350,1000,2600, 0,0,0,  70},
 /* р */ {0x440,K_TRILL,1,I_NEUTRAL, 400,1300,2300, 0,0,0,  80},
 /* й */ {0x439,K_GLIDE,1,I_SOFT,    280,2100,3000, 0,0,0,  65},
};
#define NCONS (sizeof(kCons)/sizeof(kCons[0]))

typedef struct { FCSegment *out; size_t n, cap; float speed; } Ctx;

static FCSegment mk(float f1, float f2, float f3, float voice, float noise,
                    float nf, float nbw, float am, float ms, float trans) {
    FCSegment s;
    s.f1 = f1; s.f2 = f2; s.f3 = f3; s.f0 = 120;
    s.voiceAmp = voice; s.noiseAmp = noise; s.noiseF = nf; s.noiseBw = nbw;
    s.am = am; s.ms = ms; s.trans = trans;
    return s;
}
static void push(Ctx *c, FCSegment s) {
    if (c->n >= c->cap) return;
    s.ms /= c->speed; s.trans /= c->speed;
    c->out[c->n++] = s;
}
static void pause_(Ctx *c, float ms) {
    push(c, mk(500, 1500, 2500, 0, 0, 0, 0, 0, ms, 20));
}
static void glide(Ctx *c, float ms) {                   // звук "й"
    push(c, mk(280, 2100, 3000, 0.6f, 0, 0, 0, 0, ms, 35));
}

static uint32_t lower(uint32_t ch) {
    if (ch >= 0x410 && ch <= 0x42F) return ch + 0x20;
    if (ch == 0x401) return 0x451;                       // Ё
    return ch;
}
static int isSoftTrigger(uint32_t c) {                   // е ё и ю я ь
    return c == 0x435 || c == 0x451 || c == 0x438 || c == 0x44E || c == 0x44F || c == 0x44C;
}
static int isIotated(uint32_t c) { return c == 0x435 || c == 0x451 || c == 0x44E || c == 0x44F; }
static int isVowelCP(uint32_t c) {
    switch (c) {
        case 0x430: case 0x43E: case 0x443: case 0x44B: case 0x44D:
        case 0x438: case 0x435: case 0x451: case 0x44E: case 0x44F:
            return 1;
    }
    return 0;
}
// Буквы, из которых состоит "слово" для целей ударения/лексики (гласные + й + ъ/ь).
static int isWordCP(uint32_t c) { return (c >= 0x430 && c <= 0x44F) || c == 0x451; }

// --- Оглушение/озвончение: парные согласные и их "партнёры" по глухости/звонкости ---
static uint32_t partnerCP(uint32_t c) {
    switch (c) {
        case 0x431: return 0x43F; case 0x43F: return 0x431; // б <-> п
        case 0x434: return 0x442; case 0x442: return 0x434; // д <-> т
        case 0x433: return 0x43A; case 0x43A: return 0x433; // г <-> к
        case 0x436: return 0x448; case 0x448: return 0x436; // ж <-> ш
        case 0x437: return 0x441; case 0x441: return 0x437; // з <-> с
        case 0x432: return 0x444; case 0x444: return 0x432; // в <-> ф
    }
    return 0; // ц ч щ х — глухие без звонкой пары, не участвуют
}
static int isVFcp(uint32_t c) { return c == 0x432 || c == 0x444; }             // в, ф — особый случай
static int isVoicelessNoPair(uint32_t c) { return c == 0x446 || c == 0x447 || c == 0x449 || c == 0x445; } // ц ч щ х
static int inherentVoiced(uint32_t c) {                  // "родная" звонкость по написанию
    return c == 0x431 || c == 0x434 || c == 0x433 || c == 0x436 || c == 0x437 || c == 0x432;
}

// Регрессивная ассимиляция по глухости/звонкости, вправо-влево по слову.
// out[k] (k — абсолютный индекс в low[]) = 1 звонкий / 0 глухой / -1 неприменимо
// (гласная, сонорный, ц/ч/щ/х не меняются, но х/ц/ч/щ передают глухость дальше влево).
// "в"/"ф" сами могут быть уподоблены соседним звукам, но НЕ навязывают свою
// звонкость предыдущему согласному (классическое исключение для русского).
// На конце слова, если дальше нет глухого разрыва, ударение слова"final devoicing"
// применяется по умолчанию (оглушение), если только следующее слово не начинается
// на б/г/д/ж/з — тогда конечный согласный, наоборот, озвончается.
#define GOV_NONE (-1)
static void resolveVoicing(const uint32_t *low, size_t n, size_t i, size_t j, int *outV) {
    int gov = GOV_NONE;
    if (j > i) {
        uint32_t last = low[j - 1];
        int lastIsObstruent = partnerCP(last) != 0 || isVoicelessNoPair(last);
        if (lastIsObstruent) {
            size_t k = j;
            while (k < n && (low[k] == ' ' || low[k] == '\t')) k++;
            int voicedNext = 0;
            if (k < n && isWordCP(low[k])) {
                uint32_t c0 = low[k];
                voicedNext = (c0 == 0x431 || c0 == 0x433 || c0 == 0x434 || c0 == 0x436 || c0 == 0x437);
            }
            gov = voicedNext ? 1 : 0;
        }
    }
    for (size_t k = j; k-- > i; ) {
        uint32_t ch = low[k];
        if (ch == 0x44C || ch == 0x44A) {
            outV[k] = -1;      // ь/ъ не звук — прозрачны для цепочки, governor не трогаем
        } else if (isVFcp(ch)) {
            int base = inherentVoiced(ch);
            outV[k] = (gov != GOV_NONE) ? gov : base;
            // "в"/"ф" не передают звонкость дальше влево — governor не меняем.
        } else if (isVoicelessNoPair(ch)) {
            outV[k] = 0;
            gov = 0;
        } else if (partnerCP(ch) != 0) {
            int base = inherentVoiced(ch);
            int v = (gov != GOV_NONE) ? gov : base;
            outV[k] = v;
            gov = v;
        } else {
            outV[k] = -1;      // гласная или сонорный — реальный звук, разрывает цепочку
            gov = GOV_NONE;
        }
    }
}

static const Cons *findCons(uint32_t c) {
    for (size_t i = 0; i < NCONS; i++) if (kCons[i].cp == c) return &kCons[i];
    return 0;
}

// Целевые форманты/длительность/громкость гласной с учётом позиции относительно ударения.
// Безударные гласные в русском реально меняют качество (аканье/иканье), а не только громкость —
// без этого речь звучит "по слогам" и неестественно даже с правильным местом ударения.
static void vowelTarget(uint32_t ch, int pos, float *f1, float *f2, float *f3, float *dur, float *amp) {
    float b1, b2, b3; int akan = 0, ikan = 0;
    switch (ch) {
        case 0x430: case 0x44F: b1=700; b2=1200; b3=2500; akan=1; break; // а я
        case 0x43E: case 0x451: b1=500; b2=900;  b3=2500; akan=1; break; // о ё
        case 0x443: case 0x44E: b1=350; b2=800;  b3=2400; break;         // у ю
        case 0x438:             b1=300; b2=2200; b3=3000; break;         // и
        case 0x44D: case 0x435: b1=500; b2=1800; b3=2500; ikan=1; break; // э е
        case 0x44B:             b1=320; b2=1500; b3=2400; break;         // ы
        default:                b1=500; b2=1500; b3=2500; break;
    }
    if (pos == VPOS_STRESSED) { *f1=b1; *f2=b2; *f3=b3; *dur=115; *amp=0.8f; return; }
    if (akan) {                       // аканье: безударные о/а сближаются, дальше от ударения — сильнее
        if (pos == VPOS_PRETONIC1) { *f1=650; *f2=1300; *f3=2400; *dur=80; *amp=0.55f; }
        else                       { *f1=500; *f2=1400; *f3=2400; *dur=55; *amp=0.40f; }
        return;
    }
    if (ikan) {                       // иканье: безударные е/э тянутся к и
        if (pos == VPOS_PRETONIC1) { *f1=400; *f2=2000; *f3=2800; *dur=80; *amp=0.55f; }
        else                       { *f1=400; *f2=1800; *f3=2700; *dur=55; *amp=0.40f; }
        return;
    }
    // и/у/ю/ы почти не меняют качество — только короче и тише
    if (pos == VPOS_PRETONIC1) { *f1=b1; *f2=b2; *f3=b3; *dur=90; *amp=0.65f; }
    else                       { *f1=b1; *f2=b2; *f3=b3; *dur=65; *amp=0.50f; }
}

static void emitCons(Ctx *c, const Cons *k, int soft) {
    float f1 = k->f1, f2 = k->f2, f3 = k->f3, nf = k->nf, nbw = k->nbw;
    if (soft && k->inh == I_NEUTRAL) {                   // палатализация
        if (f2 < 2200) f2 += 0.6f * (2200 - f2);
        if (f3 < 2900) f3 = 2900;
        nf *= 1.15f;
    }
    switch (k->kind) {
    case K_STOP:
        push(c, mk(f1, f2, f3, k->voiced ? 0.18f : 0, 0, 0, 0, 0, k->voiced ? 60 : 70, 30));
        push(c, mk(400, f2, f3, k->voiced ? 0.2f : 0, k->namp, nf, nbw, 0, soft ? 18 : 13, 6));
        break;
    case K_FRIC:
        push(c, mk(f1, f2, f3, k->voiced ? 0.3f : 0, k->namp, nf, nbw, 0, k->ms, 30));
        break;
    case K_AFFR:
        push(c, mk(f1, f2, f3, 0, 0, 0, 0, 0, 45, 30));
        push(c, mk(f1, f2, f3, 0, k->namp, nf, nbw, 0, k->ms, 5));
        break;
    case K_NASAL:
        push(c, mk(f1, f2, f3, 0.45f, 0, 0, 0, 0, k->ms, 30));
        break;
    case K_LAT:
        push(c, mk(soft ? 330 : f1, f2, f3, 0.6f, 0, 0, 0, 0, k->ms, 30));
        break;
    case K_TRILL:
        push(c, mk(f1, f2, f3, 0.6f, 0, 0, 0, 0.85f, k->ms, 30));
        break;
    case K_GLIDE:
        glide(c, k->ms);
        break;
    }
}

// Обрабатывает один "словесный" фрагмент [i, j) в low[], зная номер ударной гласной
// и результат ассимиляции по глухости/звонкости (voice[], тот же индекс, что и low[]).
static void emitWord(Ctx *c, const uint32_t *low, const int *voice, size_t i, size_t j, int stressIdx) {
    int boundary = 1, prevSoft = 0;
    uint32_t lastCons = 0, lastSign = 0;
    int vseen = 0;

    for (size_t k = i; k < j; k++) {
        uint32_t ch = low[k];
        uint32_t next = (k + 1 < j) ? low[k + 1] : 0;

        if (isVowelCP(ch)) {
            vseen++;
            uint32_t eff = ch;
            if ((isIotated(ch) && boundary) || (ch == 0x438 && lastSign == 0x44C)) {
                glide(c, 55);
                prevSoft = 0;
            }
            if (ch == 0x438 && (lastCons == 0x448 || lastCons == 0x436 || lastCons == 0x446)) {
                eff = 0x44B;                              // жи, ши, ци -> ы
            }
            int pos = (vseen == stressIdx) ? VPOS_STRESSED
                    : (vseen == stressIdx - 1) ? VPOS_PRETONIC1
                    : VPOS_REDUCED;
            float f1, f2, f3, dur, amp;
            vowelTarget(eff, pos, &f1, &f2, &f3, &dur, &amp);
            if (prevSoft && f2 < 1500) f2 += 0.3f * (2200 - f2);
            push(c, mk(f1, f2, f3, amp, 0, 0, 0, 0, dur, 35));
            boundary = 1; prevSoft = 0; lastSign = 0; lastCons = 0;
            continue;
        }
        const Cons *k2 = findCons(ch);
        if (k2) {
            int v = voice[k];
            if (v >= 0 && v != k2->voiced) {               // ассимиляция сменила звонкость
                uint32_t partner = partnerCP(ch);
                if (partner) { const Cons *p = findCons(partner); if (p) k2 = p; }
            }
            int soft = (k2->inh == I_SOFT) || (k2->inh == I_NEUTRAL && isSoftTrigger(next));
            emitCons(c, k2, soft);
            prevSoft = soft; lastCons = ch; boundary = 0; lastSign = 0;
            continue;
        }
        if (ch == 0x44C || ch == 0x44A) { boundary = 1; lastSign = ch; continue; } // ь ъ
    }
}

size_t PHTextToSegments(const uint32_t *text, size_t n,
                        FCSegment *out, size_t cap, float speed) {
    Ctx c = { out, 0, cap, speed > 0 ? speed : 1.0f };
    uint32_t *low = malloc(n ? n * sizeof(uint32_t) : 1);
    int *voice = malloc(n ? n * sizeof(int) : 1);
    for (size_t i = 0; i < n; i++) low[i] = lower(text[i]);

    size_t i = 0;
    while (i < n) {
        uint32_t ch = low[i];
        if (isWordCP(ch)) {
            size_t j = i;
            while (j < n && isWordCP(low[j])) j++;
            size_t total = 0;
            for (size_t k = i; k < j; k++) if (isVowelCP(low[k])) total++;

            int stress = STFindStress(&low[i], j - i);
            if (stress == 0) stress = (int)total;          // резерв: ударение на последний слог
            if (stress > (int)total) stress = (int)total;
            if (stress < 1) stress = 1;

            resolveVoicing(low, n, i, j, voice);
            emitWord(&c, low, voice, i, j, stress);
            i = j;
            continue;
        }
        if (ch == ' ' || ch == '\n' || ch == '\t') pause_(&c, 100);
        else if (ch == '.' || ch == '!' || ch == '?') pause_(&c, 260);
        else if (ch == ',' || ch == ';' || ch == ':' || ch == '-') pause_(&c, 160);
        i++;
    }
    pause_(&c, 80);
    free(low);
    free(voice);

    // Интонация: плавное снижение тона по фразе.
    float total = 0, t = 0;
    for (size_t k = 0; k < c.n; k++) total += out[k].ms;
    for (size_t k = 0; k < c.n; k++) {
        out[k].f0 = 125.0f * (1.0f - 0.15f * (total > 0 ? t / total : 0));
        t += out[k].ms;
    }
    return c.n;
}
