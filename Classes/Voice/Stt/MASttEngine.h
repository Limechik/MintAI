#ifndef MASttEngine_h
#define MASttEngine_h

#include <stddef.h>

// Движок распознавания речи на устройстве — каркас.
//
// Что уже работает: загрузка файла модели (пока только проверка, что он есть и не
// пустой), проверка входа, извлечение признаков (MAFbank) и CMVN.
// Чего ещё нет: самой нейросети и декодера. Пока на этом месте возвращается
// MASTT_ERR_NOT_IMPLEMENTED — формат файла модели и её инференс добавятся вместе с
// выбранной моделью, интерфейс при этом не изменится.
//
// Чистый C без Foundation. Один движок — один поток (внутри рабочие буферы).

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
	MASTT_OK = 0,
	MASTT_ERR_NO_MODEL = 1,         // файла модели нет
	MASTT_ERR_BAD_MODEL = 2,        // файл есть, но не читается или пуст
	MASTT_ERR_BAD_INPUT = 3,        // неверные аргументы / не та частота дискретизации
	MASTT_ERR_NO_SPEECH = 4,        // запись слишком короткая или тихая
	MASTT_ERR_NOT_IMPLEMENTED = 5,  // инференс модели ещё не написан
	MASTT_ERR_MEMORY = 6,
	MASTT_ERR_CANCELLED = 7,
} MASttStatus;

typedef struct MASttEngine MASttEngine;

// Частота дискретизации, которую ждёт движок (Гц).
int MASttEngineSampleRate(void);

// Самая длинная запись, которую движок принимает (секунды).
int MASttEngineMaxSeconds(void);

// NULL при ошибке; причина — в *status (можно передать NULL).
MASttEngine *MASttEngineLoad(const char *modelPath, MASttStatus *status);
void MASttEngineFree(MASttEngine *engine);

// Распознаёт моно-сигнал float [-1, 1]. Текст (UTF-8, с завершающим нулём) пишется в
// outText (не больше outCapacity байт). cancel — необязательный флаг: если его
// выставили в ненулевое значение из другого потока, распознавание прерывается.
MASttStatus MASttEngineTranscribe(MASttEngine *engine,
                                  const float *samples, size_t numSamples, int sampleRate,
                                  const volatile int *cancel,
                                  char *outText, size_t outCapacity);

#ifdef __cplusplus
}
#endif

#endif
