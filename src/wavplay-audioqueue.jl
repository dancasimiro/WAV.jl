# -*- mode: julia; -*-

const kNumberBuffers = 3

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
function playcallback(data_::Ptr{AudioQueueData}, aq, buffer)
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
    nothing
end

function wavplay(data, Fs, args...)
    warn("wavplay is not ready yet")

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