#include "audio.h"

#include <stdlib.h>

#include <AudioToolbox/AudioToolbox.h>

#define NUM_AUDIO_BUF 16
#define BUFFER_SIZE 4096
#define SILENT_SIZE 4096
#define FAKE_SIZE  0
bool isMuted = false;
bool isStart = false;

AudioQueueBufferRef silence_buf;
typedef struct RecycleChain {
    AudioQueueBufferRef *curt;
    struct RecycleChain *next;
}RecycleChain;

typedef struct RecycleChainMgr {
	RecycleChain *rc;
	RecycleChain *first;
	RecycleChain *last_to_queue;
	//AudioQueueBufferRef *last_use;
}RecycleChainMgr;

struct audio {
    AudioQueueRef q;
    AudioQueueBufferRef audio_buf[NUM_AUDIO_BUF];
	char *mem[NUM_AUDIO_BUF * 2];
	RecycleChainMgr rcm;
	int32_t fail_num;
    int32_t in_use;
};

static void audio_queue_callback(void *opaque, AudioQueueRef queue, AudioQueueBufferRef buffer)
{
    struct audio *ctx = (struct audio *) opaque;
    
    if (ctx == NULL)
        return;
    
	if (ctx->in_use > 0)
	{
        ctx->in_use -= buffer->mAudioDataByteSize;
	}
	
    if(buffer != silence_buf) buffer->mAudioDataByteSize = FAKE_SIZE;
	RecycleChain *tmp = ctx->rcm.last_to_queue->next;
	if ( /*(*tmp->curt)->mAudioDataByteSize != FAKE_SIZE &&*/ tmp != ctx->rcm.first)
	{
		//while(ctx->rcm.last_to_queue->next != ctx->rcm.first)
		//{
		  AudioQueueEnqueueBuffer(ctx->q, (*(ctx->rcm.last_to_queue->next->curt)), 0, NULL);
		  ctx->rcm.last_to_queue = ctx->rcm.last_to_queue->next;
		//}
	}
	else //if ((*ctx->rcm.last_use)->mAudioDataByteSize == FAKE_SIZE)
	{
		AudioQueueEnqueueBuffer(ctx->q, silence_buf, 0, NULL);
		AudioQueueEnqueueBuffer(ctx->q, silence_buf, 0, NULL);
		AudioQueueEnqueueBuffer(ctx->q, silence_buf, 0, NULL);
		/*AudioQueueStop(ctx->q, true);
		isStart = false;
		ctx->in_use = 0;*/
	}
	
	/*if(ctx->rcm.last_to_queue->curt == &buffer && ctx->rcm.last_to_queue->next == ctx->rcm.first) // && (*ctx->rcm.first->curt)->mAudioDataByteSize == FAKE_SIZE)
	{
		AudioQueueStop(ctx->q, true);
		isStart = false;
		ctx->in_use = 0;
	}*/
	
	
	//ctx->rcm.last->curt = &buffer;
	
    
	
    /*if (ctx->in_use == 0)
        AudioQueueStop(ctx->q, true);*/
}

void audio_init(struct audio **ctx_out)
{
    struct audio *ctx = *ctx_out = calloc(1, sizeof(struct audio));
    RecycleChain *rcTraverse = NULL;
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

	//ctx->rcm.first = ctx->audio_buf[0];
	//ctx->rcm.first  = ctx->audio_buf[NUM_AUDIO_BUF-1];
	ctx->rcm.rc = (RecycleChain *)(&ctx->mem[0]);
	ctx->rcm.first = ctx->rcm.rc;
	rcTraverse = ctx->rcm.rc;
    // Create buffers for the queue
    for (int32_t x = 0; x < NUM_AUDIO_BUF; x++) {
        AudioQueueAllocateBuffer(ctx->q, BUFFER_SIZE, &ctx->audio_buf[x]);
        ctx->audio_buf[x]->mAudioDataByteSize = FAKE_SIZE;
		
		rcTraverse->curt = &ctx->audio_buf[x];
		if( x != NUM_AUDIO_BUF - 1)
		{
			rcTraverse->next = (RecycleChain *)(&ctx->mem[2*(x+1)]);
			rcTraverse = rcTraverse->next;
		}
		else
		{
			//ctx->rcm.first = rcTraverse;
			rcTraverse->next = ctx->rcm.rc;
		}
		
    }
	isStart = false;
	ctx->fail_num = 0;
	ctx->in_use = 0;
	
	char silence[SILENT_SIZE] = {0};
	AudioQueueAllocateBuffer(ctx->q, SILENT_SIZE, &silence_buf);
	memcpy(silence_buf->mAudioData, &silence[0], SILENT_SIZE);
    silence_buf->mAudioDataByteSize = SILENT_SIZE;
}

void audio_destroy(struct audio **ctx_out)
{
    if (!ctx_out || !*ctx_out)
        return;
    
    struct audio *ctx = *ctx_out;
    //AudioQueueStop(ctx->q, true);
	
    for (int32_t x = 0; x < NUM_AUDIO_BUF; x++) {
        if (ctx->audio_buf[x])
            AudioQueueFreeBuffer(ctx->q, ctx->audio_buf[x]);
    }
    
    if (ctx->q)
        AudioQueueDispose(ctx->q, true);

    free(ctx);
    *ctx_out = NULL;
	isStart = false;
	AudioQueueFreeBuffer(ctx->q, silence_buf);
}

void audio_clear(struct audio **ctx_out)
{
    if (!ctx_out || !*ctx_out)
        return;
    
	//RecycleChain *rcTraverse = NULL;
    struct audio *ctx = *ctx_out;
    if (ctx->q)
        AudioQueueStop(ctx->q, true);
    
	//rcTraverse = ctx->rcm.rc;
	for (int32_t x = 0; x < NUM_AUDIO_BUF; x++) {
        ctx->audio_buf[x]->mAudioDataByteSize = FAKE_SIZE;
		/*rcTraverse->curt = &ctx->audio_buf[x];
		if( x != NUM_AUDIO_BUF - 1)
		{
			rcTraverse->next = (RecycleChain *)(&ctx->mem[2*(x+1)]);
			rcTraverse = rcTraverse->next;
		}
		else
		{
			ctx->rcm.first = rcTraverse;
			rcTraverse->next = NULL;
		}*/
    }
	isStart = false;
	ctx->in_use = 0;
	ctx->fail_num = 0;
}

void audio_cb(const int16_t *pcm, uint32_t frames, void *opaque)
{
    if ( frames == 0 || opaque == NULL || isMuted )
		return;
	
	struct audio *ctx = (struct audio *) opaque;
    AudioQueueBufferRef *find_idle = NULL;
	
	find_idle = ctx->rcm.first->curt;
	if ((*find_idle)->mAudioDataByteSize != FAKE_SIZE)
	{
		++ctx->fail_num;
		if(ctx->fail_num > 10) audio_clear(&ctx);	
		return;
	}
	
    memcpy((*find_idle)->mAudioData, pcm, frames * 4);
    (*find_idle)->mAudioDataByteSize = frames * 4;
	
	if(!isStart)
	{
		ctx->rcm.last_to_queue = ctx->rcm.first;
		AudioQueueEnqueueBuffer(ctx->q, (*find_idle), 0, NULL);
	}

	ctx->fail_num = 0;
	ctx->rcm.first = ctx->rcm.first->next;
	//ctx->rcm.last_use = find_idle;
	
	ctx->in_use += frames;
	//if (!isStart && (ctx->in_use > 1600))
	if (ctx->in_use > 1000)
	{
		AudioQueueStart(ctx->q, NULL);
		isStart = true;
	}
}

void audio_mute(bool muted, const void *opaque)
{
	if (isMuted == muted) return;
	isMuted = muted;
	isStart = false;
	if (opaque == NULL)	return;
	
	struct audio *ctx = (struct audio *) opaque;
	if(ctx->q == NULL) return;
	if(isMuted)
	{
		AudioQueuePause(ctx->q);
		audio_clear(&ctx);
	}
}
