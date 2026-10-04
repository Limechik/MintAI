#include "MAWav.h"
#include <string.h>

static uint32_t rd32(const uint8_t *p) {
	return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}
static uint16_t rd16(const uint8_t *p) {
	return (uint16_t)(p[0] | (p[1] << 8));
}

int MAWavParse(const uint8_t *bytes, size_t length, MAWavInfo *info) {
	if (!bytes || !info || length < 12) return MAWAV_ERR_NOT_WAV;
	if (memcmp(bytes, "RIFF", 4) != 0 || memcmp(bytes + 8, "WAVE", 4) != 0) return MAWAV_ERR_NOT_WAV;

	int haveFmt = 0, haveData = 0;
	uint16_t tag = 0, bits = 0, channels = 0;
	uint32_t rate = 0;
	size_t dataOffset = 0, dataBytes = 0;

	size_t pos = 12;
	while (length - pos >= 8) {   // pos <= length гарантируется ниже
		const uint8_t *chunk = bytes + pos;
		uint32_t size = rd32(chunk + 4);
		size_t body = pos + 8;
		size_t remaining = length - body;

		if (memcmp(chunk, "fmt ", 4) == 0) {
			if (size >= 16 && remaining >= 16) {
				tag = rd16(chunk + 8);
				channels = rd16(chunk + 10);
				rate = rd32(chunk + 12);
				bits = rd16(chunk + 22);
				// WAVE_FORMAT_EXTENSIBLE: настоящий формат — первые два байта SubFormat GUID.
				if (tag == 0xFFFE && size >= 26 && remaining >= 26) tag = rd16(chunk + 8 + 24);
				haveFmt = 1;
			}
		} else if (memcmp(chunk, "data", 4) == 0) {
			dataOffset = body;
			// Размер 0 или больше реального — рекордер не успел дописать заголовок.
			dataBytes = (size == 0 || size > remaining) ? remaining : size;
			haveData = 1;
		}
		if (haveFmt && haveData) break;

		// Следующий чанк (с выравниванием на чётную границу); защита от переполнения.
		size_t advance = (size_t)size + (size & 1u);
		if (advance > remaining) break;
		pos = body + advance;
	}

	if (!haveFmt || !haveData) return MAWAV_ERR_NO_DATA;
	if (tag != 1 || bits != 16 || channels < 1 || channels > 8 || rate == 0) return MAWAV_ERR_UNSUPPORTED;

	info->sample_rate = (int)rate;
	info->channels = channels;
	info->data_offset = dataOffset;
	info->data_bytes = dataBytes;
	return MAWAV_OK;
}

size_t MAWavFrameCount(const MAWavInfo *info) {
	if (!info || info->channels < 1) return 0;
	return info->data_bytes / ((size_t)info->channels * 2);
}

size_t MAWavDecodeMono(const uint8_t *bytes, size_t length, const MAWavInfo *info,
                       float *out, size_t capacity) {
	if (!bytes || !info || !out || info->channels < 1) return 0;
	if (info->data_offset > length || info->data_bytes > length - info->data_offset) return 0;

	size_t frames = MAWavFrameCount(info);
	if (frames > capacity) frames = capacity;
	const uint8_t *p = bytes + info->data_offset;
	const int ch = info->channels;
	for (size_t i = 0; i < frames; i++) {
		int sum = 0;
		for (int c = 0; c < ch; c++) sum += (int16_t)rd16(p + (i * ch + c) * 2);
		out[i] = (float)sum / (32768.0f * ch);
	}
	return frames;
}
