#include "audio.h"

#include <stdlib.h>

#include <AudioToolbox/AudioToolbox.h>

#define NUM_AUDIO_BUF 24
#define BUFFER_SIZE 4096

bool isMuted = false;

struct audio {
    AudioQueueRef q;
    AudioQueueBufferRef audio_buf[NUM_AUDIO_BUF];
    int32_t buf_index;
    int32_t in_use;
};

static void audio_queue_callback(void *opaque, AudioQueueRef queue, AudioQueueBufferRef buffer)
{
    struct audio *ctx = (struct audio *) opaque;
    
    if (ctx == NULL)
        return;
    
    buffer->mAudioDataByteSize = 0;
    if (ctx->in_use > 0)
        ctx->in_use--;
    
    if (ctx->in_use == 0)
        AudioQueueStop(ctx->q, true);
}

void audio_init(struct audio **ctx_out)
{
    struct audio *ctx = *ctx_out = calloc(1, sizeof(struct audio));
    
    AudioStreamBasicDescription format;
    format.mSampleRate = 48000;
    format.mFormatID = kAudioFormatLinearPCM;
    format.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
    format.mFramesPerPacket = 1;
    format.mChannelsPerFrame = 2;
    format.mBitsPerChannel = 16;
    format.mBytesPerPacket = 4;
    format.mBytesPerFrame = 4;
    
    // Create and audio playback queue
    AudioQueueNewOutput(&format, audio_queue_callback, (void *) ctx, nil, nil, 0, &ctx->q);
    
    // Create buffers for the queue
    for (int32_t x = 0; x < NUM_AUDIO_BUF; x++) {
        AudioQueueAllocateBuffer(ctx->q, BUFFER_SIZE, &ctx->audio_buf[x]);
        ctx->audio_buf[x]->mAudioDataByteSize = BUFFER_SIZE;
    }
}

void audio_destroy(struct audio **ctx_out)
{
    if (!ctx_out || !*ctx_out)
        return;
    
    struct audio *ctx = *ctx_out;
    
    for (int32_t x = 0; x < NUM_AUDIO_BUF; x++) {
        if (ctx->audio_buf[x])
            AudioQueueFreeBuffer(ctx->q, ctx->audio_buf[x]);
    }
    
    if (ctx->q)
        AudioQueueDispose(ctx->q, true);

    free(ctx);
    *ctx_out = NULL;
}

void audio_cb(const int16_t *pcm, uint32_t frames, void *opaque)
{
    struct audio *ctx = (struct audio *) opaque;
    
    if (ctx == NULL || isMuted)
        return;
    
    // Use the first available buffer is one is free
    int32_t found = -1;
    for (int32_t x = 0; x < NUM_AUDIO_BUF; x++) {
        if (ctx->audio_buf[x]->mAudioDataByteSize == 0 || ctx->audio_buf[x]->mAudioDataByteSize == BUFFER_SIZE) {
            found = x;
            break;
        }
    }
    
    if (found < 0)
        return;
    
    // Enqueue the sample for playback
    memcpy(ctx->audio_buf[found]->mAudioData, pcm, frames * 4);
    ctx->audio_buf[found]->mAudioDataByteSize = frames * 4;
    
    AudioQueueEnqueueBuffer(ctx->q, ctx->audio_buf[found], 0, NULL);
    
    ctx->in_use++;
        
    if (ctx->in_use > 10)
        AudioQueueStart(ctx->q, NULL);
}

void audio_mute(bool muted)
{
	isMuted = muted;
}
