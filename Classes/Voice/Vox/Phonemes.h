// Phonemes.h — побуквенное преобразование русского текста в сегменты синтеза.
// Пока БЕЗ полноценного G2P: нет ударений, редукции и оглушения.
#ifndef PHONEMES_H
#define PHONEMES_H
#include "FormantCore.h"

// text — UTF-32 (кодовые точки). В out нужно место минимум на 8*n+16 сегментов.
// speed: 1.0 — обычный темп, 1.3 — быстрее.
size_t PHTextToSegments(const uint32_t *text, size_t n,
                        FCSegment *out, size_t cap, float speed);
#endif
