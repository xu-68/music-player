#include "FlamingoDecoder.h"
#include <AudioToolbox/AudioToolbox.h>
#include <CoreFoundation/CoreFoundation.h>
#include <libavformat/avformat.h>
#include <libavcodec/avcodec.h>
#include <libswresample/swresample.h>
#include <libavutil/opt.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

static void property(CFMutableDictionaryRef dict, const char *key, const char *value) {
    if (!value) return;
    CFStringRef k = CFStringCreateWithCString(NULL, key, kCFStringEncodingUTF8);
    CFStringRef v = CFStringCreateWithCString(NULL, value, kCFStringEncodingUTF8);
    if (k && v) CFDictionarySetValue(dict, k, v);
    if (k) CFRelease(k);
    if (v) CFRelease(v);
}

static int write_frame(SwrContext *swr, AudioFileID file, AVFrame *frame,
                       int rate, int channels, SInt64 *offset) {
    int capacity = swr_get_out_samples(swr, frame ? frame->nb_samples : 0);
    if (capacity <= 0) return 0;
    uint8_t *samples = NULL;
    int result = av_samples_alloc(&samples, NULL, channels, capacity, AV_SAMPLE_FMT_FLT, 0);
    if (result < 0) return result;
    int count = swr_convert(swr, &samples, capacity,
                            frame ? (const uint8_t **)frame->extended_data : NULL,
                            frame ? frame->nb_samples : 0);
    if (count < 0) { av_freep(&samples); return count; }
    UInt32 size = (UInt32)count * (UInt32)channels * sizeof(float);
    UInt32 written = size;
    OSStatus status = AudioFileWriteBytes(file, false, *offset, &written, samples);
    av_freep(&samples);
    if (status != noErr || written != size) return AVERROR(EIO);
    *offset += written;
    return count;
}

int flamingo_decode(const char *input, const char *output, const char *metadata,
                    const char *cover, char *error, int error_capacity) {
    AVFormatContext *format = NULL;
    AVCodecContext *codec = NULL;
    AVPacket *packet = NULL;
    AVFrame *frame = NULL;
    SwrContext *swr = NULL;
    AudioFileID file = NULL;
    CFURLRef url = NULL;
    CFMutableDictionaryRef tags = NULL;
    int result = avformat_open_input(&format, input, NULL, NULL);
    if (result < 0) goto done;
    result = avformat_find_stream_info(format, NULL);
    if (result < 0) goto done;
    int stream = av_find_best_stream(format, AVMEDIA_TYPE_AUDIO, -1, -1, NULL, 0);
    if (stream < 0) { result = stream; goto done; }
    AVCodecParameters *parameters = format->streams[stream]->codecpar;
    const AVCodec *decoder = avcodec_find_decoder(parameters->codec_id);
    if (!decoder) { result = AVERROR_DECODER_NOT_FOUND; goto done; }
    codec = avcodec_alloc_context3(decoder);
    if (!codec) { result = AVERROR(ENOMEM); goto done; }
    result = avcodec_parameters_to_context(codec, parameters);
    if (result < 0) goto done;
    result = avcodec_open2(codec, decoder, NULL);
    if (result < 0) goto done;
    int channels = codec->ch_layout.nb_channels;
    int rate = codec->sample_rate;
    if (channels <= 0 || channels > 32 || rate <= 0) { result = AVERROR_INVALIDDATA; goto done; }
    AVChannelLayout layout;
    av_channel_layout_copy(&layout, &codec->ch_layout);
    result = swr_alloc_set_opts2(&swr, &layout, AV_SAMPLE_FMT_FLT, rate,
                               &codec->ch_layout, codec->sample_fmt, rate, 0, NULL);
    av_channel_layout_uninit(&layout);
    if (result < 0 || (result = swr_init(swr)) < 0) goto done;
    AudioStreamBasicDescription description = {0};
    description.mSampleRate = rate;
    description.mFormatID = kAudioFormatLinearPCM;
    description.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked;
    description.mChannelsPerFrame = channels;
    description.mBitsPerChannel = 32;
    description.mFramesPerPacket = 1;
    description.mBytesPerFrame = description.mBytesPerPacket = channels * sizeof(float);
    url = CFURLCreateFromFileSystemRepresentation(NULL, (const UInt8 *)output, strlen(output), false);
    if (!url || AudioFileCreateWithURL(url, kAudioFileCAFType, &description, kAudioFileFlags_EraseFile, &file) != noErr) {
        result = AVERROR(EIO); goto done;
    }
    tags = CFDictionaryCreateMutable(NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    AVDictionaryEntry *entry = NULL;
    while ((entry = av_dict_get(format->metadata, "", entry, AV_DICT_IGNORE_SUFFIX))) property(tags, entry->key, entry->value);
    entry = NULL;
    while ((entry = av_dict_get(format->streams[stream]->metadata, "", entry, AV_DICT_IGNORE_SUFFIX))) property(tags, entry->key, entry->value);
    property(tags, "codec", decoder->name);
    char number[80];
    snprintf(number, sizeof(number), "%d", rate); property(tags, "sampleRate", number);
    snprintf(number, sizeof(number), "%d", parameters->bits_per_raw_sample); property(tags, "bitsPerSample", number);
    snprintf(number, sizeof(number), "%lld", (long long)format->bit_rate); property(tags, "bitRate", number);
    for (unsigned i = 0; i < format->nb_streams; i++) {
        AVStream *s = format->streams[i];
        if ((s->disposition & AV_DISPOSITION_ATTACHED_PIC) && s->attached_pic.size > 0) {
            FILE *image = fopen(cover, "wb");
            if (image) { fwrite(s->attached_pic.data, 1, s->attached_pic.size, image); fclose(image); }
            break;
        }
    }
    packet = av_packet_alloc(); frame = av_frame_alloc();
    if (!packet || !frame) { result = AVERROR(ENOMEM); goto done; }
    SInt64 offset = 0;
    int finished = 0;
    while (!finished) {
        int read = av_read_frame(format, packet);
        if (read < 0 && read != AVERROR_EOF) { result = read; goto done; }
        if (read == AVERROR_EOF) finished = 1;
        if (!finished && packet->stream_index != stream) { av_packet_unref(packet); continue; }
        result = avcodec_send_packet(codec, finished ? NULL : packet);
        av_packet_unref(packet);
        if (result < 0 && result != AVERROR_EOF) goto done;
        while ((result = avcodec_receive_frame(codec, frame)) >= 0) {
            result = write_frame(swr, file, frame, rate, channels, &offset);
            av_frame_unref(frame);
            if (result < 0) goto done;
        }
        if (result != AVERROR(EAGAIN) && result != AVERROR_EOF) goto done;
    }
    while ((result = write_frame(swr, file, NULL, rate, channels, &offset)) > 0) {}
    if (result < 0) goto done;
    snprintf(number, sizeof(number), "%.6f", (double)offset / (rate * channels * sizeof(float)));
    property(tags, "duration", number);
    CFDataRef data = CFPropertyListCreateData(NULL, tags, kCFPropertyListXMLFormat_v1_0, 0, NULL);
    if (!data) { result = AVERROR(EIO); goto done; }
    FILE *plist = fopen(metadata, "wb");
    if (!plist) { CFRelease(data); result = AVERROR(EIO); goto done; }
    size_t count = fwrite(CFDataGetBytePtr(data), 1, CFDataGetLength(data), plist);
    fclose(plist);
    result = count == (size_t)CFDataGetLength(data) ? 0 : AVERROR(EIO);
    CFRelease(data);
done:
    if (file) AudioFileClose(file);
    if (url) CFRelease(url);
    if (tags) CFRelease(tags);
    av_frame_free(&frame); av_packet_free(&packet);
    swr_free(&swr); avcodec_free_context(&codec); avformat_close_input(&format);
    if (result < 0) {
        unlink(output); unlink(metadata); unlink(cover);
        if (error && error_capacity > 0) av_strerror(result, error, error_capacity);
    }
    return result;
}
