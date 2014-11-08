# -*- mode: julia; -*-

const kNumberBuffers = 3

# Apple Core Audio Type
immutable AudioStreamBasicDescription
    mSampleRate::Float64
    mFormatID::Uint32
    mFormatFlags::Uint32
    mBytesPerPacket::Uint32
    mFramesPerPacket::Uint32
    mBytesPerFrame::Uint32
    mChannelsPerFrame::Uint32
    mBitsPerChannel::Uint32
    mReserved::Uint32
end

immutable AudioQueueData
    samples
#    AudioStreamBasicDescription   mDataFormat;                    // 2
#    AudioQueueRef                 mQueue;                         // 3
#    AudioQueueBufferRef           mBuffers[kNumberBuffers];       // 4
#    AudioFileID                   mAudioFile;                     // 5
#    UInt32                        bufferByteSize;                 // 6
#    SInt64                        mCurrentPacket;                 // 7
#    UInt32                        mNumPacketsToRead;              // 8
#    AudioStreamPacketDescription  *mPacketDescs;                  // 9
#    bool                          mIsRunning;                     // 10
end

#aq::AudioQueueRef, buffer::AudioQueueBufferRef
function playCallback(data_::Ptr{AudioQueueData}, aq::Ptr{Void}, buffer::Ptr{Void})
    data = unsafe_load(data_)

    """
    if (pAqData->mIsRunning == 0) return;                     // 2
    UInt32 numBytesReadFromFile;                              // 3
    UInt32 numPackets = pAqData->mNumPacketsToRead;           // 4
    AudioFileReadPackets (
        pAqData->mAudioFile,
        false,
        &numBytesReadFromFile,
        pAqData->mPacketDescs, 
        pAqData->mCurrentPacket,
        &numPackets,
        inBuffer->mAudioData 
    );
    if (numPackets > 0) {                                     // 5
        inBuffer->mAudioDataByteSize = numBytesReadFromFile;  // 6
       AudioQueueEnqueueBuffer ( 
            pAqData->mQueue,
            inBuffer,
            (pAqData->mPacketDescs ? numPackets : 0),
            pAqData->mPacketDescs
        );
        pAqData->mCurrentPacket += numPackets;                // 7 
    } else {
        AudioQueueStop (
            pAqData->mQueue,
            false
        );
        pAqData->mIsRunning = false; 
    }
        """
end

typealias OSStatus Int32

function wavplay(data, Fs, args...)
    warn("wavplay is not ready yet")

    dataFormat = 1
    data = AudioQueueData(None)
    runLoop = None
    runLoopModes = None
    queue = None
    const outputCallback_c = cfunction(playCallback, Void, (Ptr{Void}, Ptr{Void}, Ptr{Void}))
    result = ccall((:AudioQueueNewOutput, "/System/Library/Frameworks/AudioToolbox.framework/Versions/A/AudioToolbox"),
    OSStatus,
    (Ptr{AudioStreamBasicDescription}, Ptr{Void}, Ptr{Void}, Ptr{Void}, Ptr{Void}, Uint32, Ptr{Void}),
    dataFormat, outputCallback_c, data, runLoop, runLoopModes, 0, queue)

    """
AudioQueueNewOutput (                                // 1
    &aqData.mDataFormat,                             // 2
    HandleOutputBuffer,                              // 3
    &aqData,                                         // 4
    CFRunLoopGetCurrent (),                          // 5
    kCFRunLoopCommonModes,                           // 6
    0,                                               // 7
    &aqData.mQueue                                   // 8
);

AudioQueueDispose (                            // 1
    aqData.mQueue,                             // 2
    true                                       // 3
);
        """
end