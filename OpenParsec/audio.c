#include "audio.h"

#include <stdlib.h>

#include <AudioToolbox/AudioToolbox.h>

#define NUM_AUDIO_BUF 16
#define BUFFER_SIZE 4096
#define SILENT_SIZE 4096
#define FAKE_SIZE  0
#define ALLOW_DELAY 8
#define LOWEST_NUM_BUFFER 3
bool isMuted = false;
bool isStart = false;
int lastbuf = 0;

unsigned int silence_inqueue = 0;
unsigned int silence_outqueue = 0;

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
	int loc[NUM_AUDIO_BUF];
	RecycleChainMgr rcm;
	int32_t fail_num;
    int32_t in_use;
};

static void audio_queue_callback(void *opaque, AudioQueueRef queue, AudioQueueBufferRef buffer)
{
    struct audio *ctx = (struct audio *) opaque;
    int deltaBuf = 0;
	//int silence_use_count = (int)(silence_buf->mUserData);
	
    if (ctx == NULL)
        return;
    
	if (ctx->in_use > 0)
	{
        ctx->in_use -= buffer->mAudioDataByteSize;
	}
	
    if(buffer != silence_buf)
	{
		buffer->mAudioDataByteSize = FAKE_SIZE;
		lastbuf = *((int *)(buffer->mUserData));	
	}
	else
	{
		//silence_use_count = 0;	
		//silence_buf->mUserData = (void *)(0);
		++silence_outqueue;
	}
	
	if (isMuted) return;
	
	deltaBuf = *((int *)((*ctx->rcm.first->curt)->mUserData));
	deltaBuf = deltaBuf - lastbuf - 1;
	if (deltaBuf < 0) deltaBuf += NUM_AUDIO_BUF;
	
	while(ctx->rcm.last_to_queue->next != ctx->rcm.first)
	{
		AudioQueueEnqueueBuffer(ctx->q, (*(ctx->rcm.last_to_queue->next->curt)), 0, NULL);
		ctx->rcm.last_to_queue = ctx->rcm.last_to_queue->next;
	}
	
	if (deltaBuf + silence_inqueue < LOWEST_NUM_BUFFER + silence_outqueue)
	{
		int numAddBuffer = ((silence_inqueue >= silence_outqueue) ? (LOWEST_NUM_BUFFER - deltaBuf - (int)(silence_inqueue-silence_outqueue)) : (LOWEST_NUM_BUFFER - deltaBuf - (int)((unsigned int)(0xFFFFFFFF)-silence_outqueue + silence_inqueue + 1)));
		if (numAddBuffer > LOWEST_NUM_BUFFER)
		{
			numAddBuffer = LOWEST_NUM_BUFFER - deltaBuf;
		}
		else
		{
			silence_inqueue = silence_outqueue = 0;
		}
		for (int i=0; i<numAddBuffer; ++i)
		{
			AudioQueueEnqueueBuffer(ctx->q, silence_buf, 0, NULL);
		}
		if (numAddBuffer > 0) silence_inqueue += numAddBuffer;
	}
	
	//RecycleChain *tmp = ctx->rcm.last_to_queue->next;
	//if ( /*(*tmp->curt)->mAudioDataByteSize != FAKE_SIZE &&*/ tmp != ctx->rcm.first)
	//if (deltaBuf > ALLOW_DELAY)
	//{
	//	//while(ctx->rcm.last_to_queue->next != ctx->rcm.first)
	//	for (int i = 0; i < deltaBuf - ALLOW_DELAY + 1; ++i)
	//	{
	//	    AudioQueueEnqueueBuffer(ctx->q, (*(ctx->rcm.last_to_queue->next->curt)), 0, NULL);
	//	    ctx->rcm.last_to_queue = ctx->rcm.last_to_queue->next;
	//	}
	//}
	//else
	//{
	//	int silence_use_count = (int)(silence_buf->mUserData);
	//	if ( deltaBuf > 0 )
	//	{
	//		AudioQueueEnqueueBuffer(ctx->q, (*(ctx->rcm.last_to_queue->next->curt)), 0, NULL);
	//	    ctx->rcm.last_to_queue = ctx->rcm.last_to_queue->next;
	//	}
	//	else if (silence_use_count == 0)
	//	{
	//		AudioQueueEnqueueBuffer(ctx->q, silence_buf, 0, NULL);
	//		//int tmp = (int)(silence_buf->mUserData);
	//		//++tmp;
	//		silence_buf->mUserData = (void *)(1);
	//	}
	//}
	//else //if ((*ctx->rcm.last_use)->mAudioDataByteSize == FAKE_SIZE)
	//{
	//	AudioQueueEnqueueBuffer(ctx->q, silence_buf, 0, NULL);
	//	AudioQueueEnqueueBuffer(ctx->q, silence_buf, 0, NULL);
	//	AudioQueueEnqueueBuffer(ctx->q, silence_buf, 0, NULL);
	//	/*AudioQueueStop(ctx->q, true);
	//	isStart = false;
	//	ctx->in_use = 0;*/
	//}
	
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
		ctx->loc[x] = x;
		ctx->audio_buf[x]->mUserData = (void *)(&ctx->loc[x]);
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
	
	silence_inqueue = silence_outqueue = 0;
	char silence[SILENT_SIZE] = {0};
	AudioQueueAllocateBuffer(ctx->q, SILENT_SIZE, &silence_buf);
	memcpy(silence_buf->mAudioData, &silence[0], SILENT_SIZE);
    silence_buf->mAudioDataByteSize = SILENT_SIZE;
	silence_buf->mUserData = NULL;
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
	silence_inqueue = silence_outqueue = 0;
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
	silence_inqueue = silence_outqueue = 0;
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
