# -*- mode: julia; -*-
module WAVPlay
import ..wavplay

import Libdl

# typedef enum pa_sample_format
const PA_SAMPLE_U8        =  0 # Unsigned 8 Bit PCM
const PA_SAMPLE_ALAW      =  1 # 8 Bit a-Law
const PA_SAMPLE_ULAW      =  2 # 8 Bit mu-Law
const PA_SAMPLE_S16LE     =  3 # Signed 16 Bit PCM, little endian (PC)
const PA_SAMPLE_S16BE     =  4 # Signed 16 Bit PCM, big endian
const PA_SAMPLE_FLOAT32LE =  5 # 32 Bit IEEE floating point, little endian (PC), range -1.0 to 1.0
const PA_SAMPLE_FLOAT32BE =  6 # 32 Bit IEEE floating point, big endian, range -1.0 to 1.0
const PA_SAMPLE_S32LE     =  7 # Signed 32 Bit PCM, little endian (PC)
const PA_SAMPLE_S32BE     =  8 # Signed 32 Bit PCM, big endian
const PA_SAMPLE_S24LE     =  9 # Signed 24 Bit PCM packed, little endian (PC). \since 0.9.15
const PA_SAMPLE_S24BE     = 10 # Signed 24 Bit PCM packed, big endian. \since 0.9.15
const PA_SAMPLE_S24_32LE  = 11 # Signed 24 Bit PCM in LSB of 32 Bit words, little endian (PC). \since 0.9.15
const PA_SAMPLE_S24_32BE  = 12 # Signed 24 Bit PCM in LSB of 32 Bit words, big endian. \since 0.9.15

struct pa_sample_spec
    format::Int32
    rate::UInt32
    channels::UInt8
end

struct pa_channel_map
    channels::UInt8

    # map data (max 32 channels)
    map0::Cint
    map1::Cint
    map2::Cint
    map3::Cint
    map4::Cint
    map5::Cint
    map6::Cint
    map7::Cint
    map8::Cint
    map9::Cint
    map10::Cint
    map11::Cint
    map12::Cint
    map13::Cint
    map14::Cint
    map15::Cint
    map16::Cint
    map17::Cint
    map18::Cint
    map19::Cint
    map20::Cint
    map21::Cint
    map22::Cint
    map23::Cint
    map24::Cint
    map25::Cint
    map26::Cint
    map27::Cint
    map28::Cint
    map29::Cint
    map30::Cint
    map31::Cint

    pa_channel_map() = new(0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
end

struct pa_buffer_attr
    maxlength::UInt32
    tlength::UInt32
    prebuf::UInt32
    minreq::UInt32
    fragsize::UInt32
end

const pa_simple = Ptr{Cvoid}
const LibPulseSimple = Libdl.find_library(["libpulse-simple", "libpulse-simple.so.0"])
const PA_STREAM_PLAYBACK = 1
const PA_CHANNEL_MAP_AIFF = 0
const PA_CHANNEL_MAP_DEFAULT = PA_CHANNEL_MAP_AIFF

function wavplay(data, fs)
    nChannels = size(data,2)
    ss = pa_sample_spec(PA_SAMPLE_FLOAT32LE, fs, nChannels)

    # Manually layout the samples.
    # convert doesn't lay out the samples as pulse audio expects
    samples = Array{Float32, 1}(undef, size(data, 1) * size(data, 2))
    idx = 1
    for i = 1:size(data, 1)
        for j = 1:size(data, 2)
            samples[idx] = convert(Float32, data[i, j])
            idx += 1
        end
    end

    s = ccall((:pa_simple_new, LibPulseSimple),
              pa_simple,
              (Cstring,
               Cstring,
               Cint,
               Cstring,
               Cstring,
               Ptr{pa_sample_spec},
               Ptr{pa_channel_map},
               Ptr{pa_buffer_attr},
               Ptr{Cint}),
              C_NULL, # Use the default server
              "Julia WAV.jl",  # Application name
              PA_STREAM_PLAYBACK,
              C_NULL, # Use the default device
              "wavplay", # description of stream
              Ref(ss),
              C_NULL, # Use default channel map
              C_NULL, # Use default buffering attributes
              C_NULL) # Ignore error code
    if s == C_NULL
        error("pa_simple_new failed")
    end

    write_ret = ccall((:pa_simple_write, LibPulseSimple),
                      Cint,
                      (pa_simple, Ptr{Cvoid}, Csize_t, Ptr{Cint}),
                      s, samples, sizeof(samples), C_NULL)
    if write_ret != 0
        error("pa_simple_write failed with $write_ret")
    end

    drain_ret = ccall((:pa_simple_drain, LibPulseSimple),
                      Cint,
                      (pa_simple, Ptr{Cint}), s, C_NULL)
    if drain_ret != 0
        error("pa_simple_drain failed with $drain_ret")
    end

    ccall((:pa_simple_free, LibPulseSimple), Cvoid, (pa_simple,), s)
end
end # module
