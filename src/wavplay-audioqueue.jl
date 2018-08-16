# -*- mode: julia; -*-
module WAVPlay
import ..wavplay

const OSStatus = Int32
const CFTypeRef = Ptr{Cvoid}
const CFRunLoopRef = Ptr{Cvoid}
const CFStringRef = Ptr{Cvoid}
const AudioQueueRef = Ptr{Cvoid}

# format IDs
const kAudioFormatLinearPCM = # "lpcm"
convert(UInt32, 'l') << 24 |
convert(UInt32, 'p') << 16 |
convert(UInt32, 'c') << 8  |
convert(UInt32, 'm') << 0

# format flags
const kAudioFormatFlagIsFloat               = (1 << 0)
const kAudioFormatFlagIsBigEndian           = (1 << 1)
const kAudioFormatFlagIsSignedInteger       = (1 << 2)
const kAudioFormatFlagIsPacked              = (1 << 3)
const kAudioFormatFlagIsAlignedHigh         = (1 << 4)
const kAudioFormatFlagIsNonInterleaved      = (1 << 5)
const kAudioFormatFlagIsNonMixable          = (1 << 6)
const kAudioFormatFlagsAreAllClear          = (1 << 31)

# Apple Core Audio Type
struct AudioStreamPacketDescription
    mStartOffset::Int64
    mVariableFramesInPacket::UInt32
    mDataByteSize::UInt32
end

struct SMPETime
    mSubframes::Int16
    mSubframeDivisor::Int16
    mCounter::UInt32
    mType::UInt32
    mFlags::UInt32
    mHours::Int16
    mMinimum::Int16
    mSeconds::Int16
    mFrames::Int16

    SMPETime() = new(0, 0, 0, 0, 0, 0, 0, 0, 0)
end

struct AudioTimeStamp
    mSampleTime::Float64
    mHostTime::UInt64
    mRateScalar::Float64
    mWordClockTime::UInt64
    mSMPETime::SMPETime
    mFlags::UInt32
    mReserved::UInt32

    AudioTimeStamp(fs) = new(fs, 0, 0, 0, SMPETime(), 0, 0)
end

# Apple Core Audio Type
mutable struct AudioQueueBuffer
    mAudioDataBytesCapacity::UInt32
    mAudioData::Ptr{Cvoid}
    mAudioDataByteSize::UInt32
    mUserData::Ptr{Cvoid}
    mPacketDescriptionCapacity::UInt32
    mPacketDescription::Ptr{AudioStreamPacketDescription}
    mPacketDescriptionCount::UInt32
end

const AudioQueueBufferRef = Ptr{AudioQueueBuffer}

const kNumberBuffers = 3
const CoreFoundation =
    "/System/Library/Frameworks/CoreFoundation.framework/Versions/A/CoreFoundation"
const AudioToolbox =
    "/System/Library/Frameworks/AudioToolbox.framework/Versions/A/AudioToolbox"

CFRunLoopGetCurrent() = ccall((:CFRunLoopGetCurrent, CoreFoundation), CFRunLoopRef, ())
CFRunLoopRun() = ccall((:CFRunLoopRun, CoreFoundation), Cvoid, ())
CFRunLoopStop(rl) = ccall((:CFRunLoopStop, CoreFoundation), Cvoid, (CFRunLoopRef, ), rl)
getCoreFoundationRunLoopDefaultMode() =
    unsafe_load(cglobal((:kCFRunLoopDefaultMode, CoreFoundation), CFStringRef))

# Apple Core Audio Type
struct AudioStreamBasicDescription
    mSampleRate::Float64
    mFormatID::UInt32
    mFormatFlags::UInt32
    mBytesPerPacket::UInt32
    mFramesPerPacket::UInt32
    mBytesPerFrame::UInt32
    mChannelsPerFrame::UInt32
    mBitsPerChannel::UInt32
    mReserved::UInt32

    AudioStreamBasicDescription(fs, fmtID, fmtFlags, bytesPerPacket,
                                framesPerPacket, bytesPerFrame, channelsPerFrame,
                                bitsPerChannel) = new(fs,
                                                      fmtID,
                                                      fmtFlags,
                                                      bytesPerPacket,
                                                      framesPerPacket,
                                                      bytesPerFrame,
                                                      channelsPerFrame,
                                                      bitsPerChannel,
                                                      0)
end

mutable struct AudioQueueData
    samples::Array
    aq::AudioQueueRef
    offset::Int
    nSamples::Int
    nBuffersEnqueued::UInt
    runLoop::CFRunLoopRef

    AudioQueueData(samples) = new(samples, convert(AudioQueueRef, 0), 1,
                                  size(samples, 1), 0, convert(CFRunLoopRef, 0))
end

function AudioQueueFreeBuffer(aq::AudioQueueRef, buf::AudioQueueBufferRef)
    result = ccall((:AudioQueueFreeBuffer, AudioToolbox),
                   OSStatus,
                   (AudioQueueRef, AudioQueueBufferRef), aq, buf)
    if result != 0
        error("AudioQueueFreeBuffer failed with $result")
    end
end

# @function   AudioQueueAllocateBuffer
# @abstract   Asks an audio queue to allocate a buffer.
# @discussion
#     Once allocated, the pointer to the buffer and the buffer's size are fixed and cannot be
#     changed. The mAudioDataByteSize field in the audio queue buffer structure,
#     AudioQueueBuffer, is initially set to 0.
#
# @param      inAQ
#     The audio queue you want to allocate a buffer.
# @param      inBufferByteSize
#     The desired size of the new buffer, in bytes. An appropriate buffer size depends on the
#     processing you will perform on the data as well as on the audio data format.
# @param      outBuffer
#     On return, points to the newly created audio buffer. The mAudioDataByteSize field in the
#     audio queue buffer structure, AudioQueueBuffer, is initially set to 0.
# @result     An OSStatus result code.
function AudioQueueAllocateBuffer(aq)
    newBuffer = Array{AudioQueueBufferRef, 1}(undef, 1)
    result =
        ccall((:AudioQueueAllocateBuffer, AudioToolbox), OSStatus,
              (AudioQueueRef, UInt32, Ptr{AudioQueueBufferRef}),
              aq, 4096, newBuffer)
    if result != 0
        error("AudioQueueAllocateBuffer failed with $result")
    end
    buf = newBuffer[1]
    return buf
end

function AudioQueueEnqueueBuffer(aq, bufPtr, data)
    buffer = unsafe_load(bufPtr)
    @assert buffer.mAudioDataBytesCapacity / sizeof(eltype(data)) >= length(data)

    nChannels = size(data, 2)
    coreAudioData = convert(Ptr{eltype(data)}, buffer.mAudioData)
    for i = 1:size(data, 1) # for each sample
        coreAudioIndex = (nChannels * (i - 1))
        for j = 1:nChannels
            unsafe_store!(coreAudioData, data[i, j], coreAudioIndex + j)
        end
    end
    buffer.mAudioDataByteSize = sizeof(data)

    unsafe_store!(bufPtr, buffer)
    result = ccall((:AudioQueueEnqueueBuffer, AudioToolbox),
                   OSStatus,
                   (AudioQueueRef, AudioQueueBufferRef, UInt32, Ptr{Cvoid}),
                   aq, bufPtr, 0, C_NULL)
    if result != 0
        error("AudioQueueEnqueueBuffer failed with $result")
    end
end

function enqueueBuffer(userData, buf)
    if userData.offset >= userData.nSamples
        return false
    end
    nsamples::Int = 512
    chans = ndims(userData.samples)
    if chans > 2
        error("Playback of $chans-channel files is not supported")
    end
    if chans == 2
        nsamples /= size(userData.samples, 2)
    end
    nsamples -= 1
    end_offset = min(userData.offset + nsamples, userData.nSamples)
    idx = ntuple(i -> i > 1 ? (1:size(userData.samples, i)) : (userData.offset:end_offset),
                 ndims(userData.samples))
    AudioQueueEnqueueBuffer(userData.aq, buf, getindex(userData.samples, idx...))
    userData.offset = end_offset
    userData.nBuffersEnqueued += 1
    return true
end

function allocateAllBuffers(userData)
    buffers = AudioQueueBufferRef[]
    for i = 1:kNumberBuffers
        buf = AudioQueueAllocateBuffer(userData.aq)
        push!(buffers, buf)
    end
    return buffers
end

function playCallback(data_::Ptr{AudioQueueData}, aq::AudioQueueRef, buf::AudioQueueBufferRef)
    userData = unsafe_load(data_)
    userData.nBuffersEnqueued -= 1
    if !enqueueBuffer(userData, buf)
        AudioQueueFreeBuffer(aq, buf)
        if userData.nBuffersEnqueued == 0
            AudioQueueStop(aq, false)
            CFRunLoopStop(userData.runLoop) # can I tell it to stop when work is done?
        end
    end
    unsafe_store!(data_, userData)
    return
end

# @function   AudioQueueNewOutput
# @abstract   Creates a new audio queue for playing audio data.
# @discussion
#     To create an playback audio queue, you allocate buffers, then queue buffers (using
#     AudioQueueEnqueueBuffer). The callback receives buffers and typically queues them again.
#     To schedule a buffer for playback, providing parameter and start time information, call
#     AudioQueueEnqueueBufferWithParameters.
#
# @param      inFormat
#     A pointer to a structure describing the format of the audio data to be played. For
#     linear PCM, only interleaved formats are supported. Compressed formats are supported.
# @param      inCallbackProc
#     A pointer to a callback function to be called when the audio queue has finished playing
#     a buffer.
# @param      inUserData
#     A value or pointer to data that you specify to be passed to the callback function.
# @param      inCallbackRunLoop
#     The event loop on which inCallbackProc is to be called. If you specify NULL, the
#     callback is called on one of the audio queue's internal threads.
# @param      inCallbackRunLoopMode
#     The run loop mode in which to call the callback. Typically, you pass
#     kCFRunLoopCommonModes. (NULL also specifies kCFRunLoopCommonModes). Other
#     possibilities are implementation specific. You can choose to create your own thread with
#     your own run loops. For more information on run loops, see Run Loops or CFRunLoop
#     Reference.
# @param      inFlags
#     Reserved for future use. Pass 0.
# @param      outAQ
#     On return, this variable contains a pointer to the newly created playback audio queue
#     object.
# @result     An OSStatus result code.
function AudioQueueNewOutput(format::AudioStreamBasicDescription, userData::AudioQueueData)
    runLoop = CFRunLoopGetCurrent()
    userData.runLoop = runLoop
    runLoopMode = getCoreFoundationRunLoopDefaultMode()

    newAudioQueue = Array{AudioQueueRef, 1}(undef, 1)
    cCallbackProc = @cfunction(playCallback, Cvoid,
                               (Ptr{AudioQueueData}, AudioQueueRef, AudioQueueBufferRef))
    result =
        ccall((:AudioQueueNewOutput, AudioToolbox), OSStatus,
              (Ptr{AudioStreamBasicDescription}, Ptr{Cvoid}, Ptr{AudioQueueData}, CFRunLoopRef, CFStringRef, UInt32, Ptr{AudioQueueRef}),
              Ref(format), cCallbackProc, Ref(userData), runLoop, runLoopMode, 0, newAudioQueue)
    if result != 0
        error("AudioQueueNewOutput failed with $result")
    end
    return newAudioQueue[1]
end

function AudioQueueDispose(aq::AudioQueueRef, immediate::Bool)
    result = ccall((:AudioQueueDispose, AudioToolbox),
                   OSStatus,
                   (AudioQueueRef, Bool), aq, immediate)
    if result != 0
        error("AudioQueueDispose failed with $result")
    end
end

# @function   AudioQueueStart
# @abstract   Begins playing or recording audio.
# @discussion
#     If the audio hardware is not already running, this function starts it.
# @param      inAQ
#     The audio queue to start.
# @param      inStartTime
#     A pointer to the time at which the audio queue should start. If you specify the time
#     using the mSampleTime field of the AudioTimeStamp structure, the sample time is
#     referenced to the sample frame timeline of the associated audio device. May be NULL.
# @result     An OSStatus result code.
function AudioQueueStart(aq)
    result = ccall((:AudioQueueStart, AudioToolbox), OSStatus,
                   (AudioQueueRef, Ptr{AudioTimeStamp}), aq, C_NULL)
    if result != 0
        error("AudioQueueStart failed with $result")
    end
end

# @function   AudioQueueStop
# @abstract   Stops playing or recording audio.
# @discussion
#     This function resets the audio queue and stops the audio hardware associated with the
#     queue if it is not in use by other audio services. Synchronous stops occur immediately,
#     regardless of previously buffered audio data. Asynchronous stops occur after all queued
#     buffers have been played or recorded.
# @param      inAQ
#     The audio queue to stop.
# @param      inImmediate
#     If you pass true, the stop request occurs immediately (that is, synchronously), and the
#     function returns when the audio queue has stopped. Buffer callbacks are invoked during
#     the stopping. If you pass false, the function returns immediately, but the queue does
#     not stop until all its queued buffers are played or filled (that is, the stop occurs
#     asynchronously). Buffer callbacks are invoked as necessary until the queue actually
#     stops. Also, a playback audio queue callback calls this function when there is no more
#     audio to play.
#
#     Note that when stopping immediately, all pending buffer callbacks are normally invoked
#     during the process of stopping. But if the calling thread is responding to a buffer
#     callback, then it is possible for additional buffer callbacks to occur after
#     AudioQueueStop returns.
# @result     An OSStatus result code.
function AudioQueueStop(aq, immediate)
    result = ccall((:AudioQueueStop, AudioToolbox), OSStatus,
                   (AudioQueueRef, Bool), aq, immediate)
    if result != 0
        error("AudioQueueStop failed with $result")
    end
end

function getFormatFlags(el)
    flags = kAudioFormatFlagsAreAllClear
    if el <: AbstractFloat
        flags |= kAudioFormatFlagIsFloat
    elseif el <: Integer
        flags |= kAudioFormatFlagIsSignedInteger
    end
    return flags
end

# LEUI8, LEI16, LEI24, LEI32, LEF32, LEF64, 'ulaw', 'alaw'
function getFormatForData(data, fs)
    elType = eltype(data)
    fmtFlags = getFormatFlags(elType)
    elSize = sizeof(elType)
    nChannels = size(data, 2)
    return AudioStreamBasicDescription(fs,
                                       kAudioFormatLinearPCM,
                                       fmtFlags,
                                       elSize * nChannels,  # bytes per packet
                                       1,                   # frames per packet
                                       elSize * nChannels,  # bytes per frame
                                       nChannels,           # channels per frame
                                       elSize * 8)          # bits per channel
end

function wavplay(data, fs)
    userData = AudioQueueData(data)
    userData.aq = AudioQueueNewOutput(getFormatForData(data, fs), userData)
    for buf in allocateAllBuffers(userData)
        enqueueBuffer(userData, buf)
    end
    AudioQueueStart(userData.aq)

    CFRunLoopRun()
    AudioQueueDispose(userData.aq, true)
end
end # module
