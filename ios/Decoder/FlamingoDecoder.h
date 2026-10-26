#ifndef FLAMINGO_DECODER_H
#define FLAMINGO_DECODER_H
// Read container/stream tags and attached artwork without decoding audio.
int flamingo_probe(const char *input, const char *metadata, const char *cover,
                   char *error, int error_capacity);
// Local files only. Output is interleaved 32-bit float PCM in a CAF container.
int flamingo_decode(const char *input, const char *output, const char *metadata,
                    const char *cover, char *error, int error_capacity);
#endif
