// FormantCore.h — собственное ядро формантного синтеза.
// Источники: голос (импульс гортани) -> каскад резонаторов F1..F3,
//            шум -> отдельный полосовой резонатор (для с, ш, х, взрывов).
#ifndef FORMANT_CORE_H
#define FORMANT_CORE_H
#include <stddef.h>
#include <stdint.h>

typedef struct {
    float f1, f2, f3;    // форманты, Гц (интерполируются от предыдущего сегмента)
    float f0;            // основной тон, Гц
    float voiceAmp;      // громкость голоса 0..1
    float noiseAmp;      // громкость шума 0..~1
    float noiseF;        // центр полосы шума, Гц
    float noiseBw;       // ширина полосы шума, Гц
    float am;            // глубина дрожания голоса (для "р"), 0..1
    float ms;            // длительность, мс
    float trans;         // время перехода формант из предыдущего сегмента, мс
} FCSegment;

// Сколько сэмплов понадобится для сегментов.
size_t FCTotalSamples(const FCSegment *segs, size_t count, float sampleRate);

// Рендер в 16-бит моно PCM. Возвращает число записанных сэмплов.
size_t FCRender(const FCSegment *segs, size_t count,
                int16_t *out, size_t capacity, float sampleRate);
#endif
