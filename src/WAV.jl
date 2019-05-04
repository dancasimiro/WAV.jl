# -*- mode: julia; -*-
Base.__precompile__(true)
module WAV
export wavread, wavwrite, wavappend, wavplay
export WAVChunk, WAVMarker, wav_cue_read, wav_cue_write, wav_info_write, wav_info_read
export WAVArray, WAVFormatExtension, WAVFormat
export isextensible, isformat, bits_per_sample
export WAVE_FORMAT_PCM, WAVE_FORMAT_IEEE_FLOAT, WAVE_FORMAT_ALAW, WAVE_FORMAT_MULAW
import Libdl
using FileIO
using Logging

function __init__()
    module_dir = dirname(@__FILE__)
    try 
        # check we haven't already imported this package into the namespace
        # this will throw an error otherwise
        WAV
    catch e
        if isa(e, UndefVarError) && e.var == :WAV
            if Libdl.find_library(["libpulse-simple", "libpulse-simple.so.0"]) != ""
                include(joinpath(module_dir, "wavplay-pulse.jl"))
            elseif Libdl.find_library(["AudioToolbox"],
                                      ["/System/Library/Frameworks/AudioToolbox.framework/Versions/A"]) != ""
                include(joinpath(module_dir, "wavplay-audioqueue.jl"))
            else
                wavplay(data, fs) = @warn "wavplay is not currently implemented on $(Sys.KERNEL)"
            end
        else
            throw(e)
        end
    end
    nothing
end

include("AudioDisplay.jl")
include("WAVChunk.jl")
wavplay(fname) = wavplay(wavread(fname)[1:2]...)

# The WAV specification states that numbers are written to disk in little endian form.
write_le(stream::IO, value) = write(stream, htol(value))
read_le(stream::IO, x::Type{T}) where {T} = ltoh(read(stream, T))

# used by WAVE_FORMAT_EXTENSIBLE
struct WAVFormatExtension
    nbits::UInt16 # overrides nbits in WAVFormat type
    channel_mask::UInt32
    sub_format::Array{UInt8, 1} # 16 byte GUID
    WAVFormatExtension() = new(0, 0, UInt8[])
    WAVFormatExtension(nb, cm, sb) = new(nb, cm, sb)
end

# Required WAV Chunk; The format chunk describes how the waveform data is stored
struct WAVFormat
    compression_code::UInt16
    nchannels::UInt16
    sample_rate::UInt32
    bytes_per_second::UInt32 # average bytes per second
    block_align::UInt16
    nbits::UInt16
    ext::WAVFormatExtension
    WAVFormat() = new(WAVE_FORMAT_PCM, 0, 0, 0, 16, 0, WAVFormatExtension())
    WAVFormat(cc, nchan, fs, bps, ba, nb, e) = new(cc, nchan, fs, bps, ba, nb, e)
end

const WAVE_FORMAT_PCM        = 0x0001 # PCM
const WAVE_FORMAT_IEEE_FLOAT = 0x0003 # IEEE float
const WAVE_FORMAT_ALAW       = 0x0006 # A-Law
const WAVE_FORMAT_MULAW      = 0x0007 # Mu-Law
const WAVE_FORMAT_EXTENSIBLE = 0xfffe # Extension!

isextensible(fmt::WAVFormat) = (fmt.compression_code == WAVE_FORMAT_EXTENSIBLE)
bits_per_sample(fmt::WAVFormat) = isextensible(fmt) ? fmt.ext.nbits : fmt.nbits


# DEFINE_GUIDSTRUCT("00000001-0000-0010-8000-00aa00389b71", KSDATAFORMAT_SUBTYPE_PCM);
const KSDATAFORMAT_SUBTYPE_PCM = [
0x01, 0x00, 0x00, 0x00,
0x00, 0x00,
0x10, 0x00,
0x80, 0x00,
0x00, 0xaa, 0x00, 0x38, 0x9b, 0x71
                                  ]
# DEFINE_GUIDSTRUCT("00000003-0000-0010-8000-00aa00389b71", KSDATAFORMAT_SUBTYPE_IEEE_FLOAT);
const KSDATAFORMAT_SUBTYPE_IEEE_FLOAT = [
0x03, 0x00, 0x00, 0x00,
0x00, 0x00,
0x10, 0x00,
0x80, 0x00,
0x00, 0xaa, 0x00, 0x38, 0x9b, 0x71
                                         ]
# DEFINE_GUID(KSDATAFORMAT_SUBTYPE_MULAW, 0x00000007, 0x0000, 0x0010, 0x80, 0x00, 0x00, 0xaa, 0x00, 0x38, 0x9b, 0x71);
const KSDATAFORMAT_SUBTYPE_MULAW = [
0x07, 0x00, 0x00, 0x00,
0x00, 0x00,
0x10, 0x00,
0x80, 0x00,
0x00, 0xaa, 0x00, 0x38, 0x9b, 0x71
                                    ]
#DEFINE_GUID(KSDATAFORMAT_SUBTYPE_ALAW, 0x00000006, 0x0000, 0x0010, 0x80, 0x00, 0x00, 0xaa, 0x00, 0x38, 0x9b, 0x71);
const KSDATAFORMAT_SUBTYPE_ALAW = [
0x06, 0x00, 0x00, 0x00,
0x00, 0x00,
0x10, 0x00,
0x80, 0x00,
0x00, 0xaa, 0x00, 0x38, 0x9b, 0x71
                                   ]
function getformat(chunks::Vector{WAVChunk})::WAVFormat
    data = chunks[findfirst(c -> c.id == Symbol("fmt "), chunks)].data
    buf = IOBuffer(data[5:end])
    return read_format(buf, convert(UInt32, length(data[5:end])))
end

function isformat(fmt::WAVFormat, code)
    if code != WAVE_FORMAT_EXTENSIBLE && isextensible(fmt)
        subtype = UInt8[]
        if code == WAVE_FORMAT_PCM
            subtype = KSDATAFORMAT_SUBTYPE_PCM
        elseif code == WAVE_FORMAT_IEEE_FLOAT
            subtype = KSDATAFORMAT_SUBTYPE_IEEE_FLOAT
        elseif code == WAVE_FORMAT_ALAW
            subtype = KSDATAFORMAT_SUBTYPE_ALAW
        elseif code == WAVE_FORMAT_MULAW
            subtype = KSDATAFORMAT_SUBTYPE_MULAW
        else
            return false
        end
        return subtype == fmt.ext.sub_format
    end
    return fmt.compression_code == code
end

function WAVFormatExtension(bytes)
    if isempty(bytes)
        return WAVFormatExtension()
    end
    # split bytes into valid_bits_per_sample, channel_mask, and sub_format
    valid_bits_per_sample = (convert(UInt16, bytes[2]) << 8) | convert(UInt16, bytes[1])
    channel_mask = (convert(UInt32, bytes[6]) << 24) | (convert(UInt32, bytes[5]) << 16) | (convert(UInt32, bytes[4]) << 8) | convert(UInt32, bytes[3])
    sub_format = bytes[7:end]
    return WAVFormatExtension(valid_bits_per_sample, channel_mask, sub_format)
end

function read_header(io::IO)
    # check if the given file has a valid RIFF header
    riff = Vector{UInt8}(undef, 4)
    read!(io, riff)
    if riff !=  b"RIFF"
        error("Invalid WAV file: The RIFF header is invalid")
    end

    chunk_size = read_le(io, UInt32)

    # check if this is a WAV file
    format = Vector{UInt8}(undef, 4)
    read!(io, format)
    if format != b"WAVE"
        error("Invalid WAV file: the format is not WAVE")
    end
    return chunk_size
end

function write_header(io::IO, data_length::UInt32)
    write(io, b"RIFF") # RIFF header
    write_le(io, data_length) # chunk_size
    write(io, b"WAVE")
end
write_standard_header(io, data_length) = write_header(io, UInt32(data_length + 36))
write_extended_header(io, data_length) = write_header(io, UInt32(data_length + 60))

function read_format(io::IO, chunk_size::UInt32)
    # can I read in all of the fields at once?
    orig_chunk_size = convert(Int, chunk_size)
    if chunk_size < 16
        error("The WAVE Format chunk must be at least 16 bytes")
    end
    compression_code = read_le(io, UInt16)
    nchannels = read_le(io, UInt16)
    sample_rate = read_le(io, UInt32)
    bytes_per_second = read_le(io, UInt32)
    block_align = read_le(io, UInt16)
    nbits = read_le(io, UInt16)
    ext = UInt8[]
    chunk_size -= 16
    if chunk_size > 0
        extra_bytes_length = read_le(io, UInt16)
        if extra_bytes_length == 22
            ext = Vector{UInt8}(undef, extra_bytes_length)
            read!(io, ext)
        end
    end
    return WAVFormat(compression_code,
                     nchannels,
                     sample_rate,
                     bytes_per_second,
                     block_align,
                     nbits,
                     WAVFormatExtension(ext))
end

function format_length(fmt::WAVFormat)
    len = 16 # 16 is size of base format chunk
    if isextensible(fmt)
        len += 24 # 24 is the added length needed to encode the extension
    end
    return len
end

function write_format(io::IO, fmt::WAVFormat)
    len = format_length(fmt)
    # write the fmt subchunk header
    write(io, b"fmt ")
    write_le(io, convert(UInt32, len)) # subchunk length

    write_le(io, fmt.compression_code) # audio format (UInt16)
    write_le(io, fmt.nchannels) # number of channels (UInt16)
    write_le(io, fmt.sample_rate) # sample rate (UInt32)
    write_le(io, fmt.bytes_per_second) # byte rate (UInt32)
    write_le(io, fmt.block_align) # byte align (UInt16)
    write_le(io, fmt.nbits) # number of bits per sample (UInt16)

    if isextensible(fmt)
        write_le(io, convert(UInt16, 22))
        write_le(io, fmt.ext.nbits)
        write_le(io, fmt.ext.channel_mask)
        @assert length(fmt.ext.sub_format) == 16
        write(io, fmt.ext.sub_format)
    end
end

function WAVChunk(fmt::WAVFormat)
    io = IOBuffer()
    write_format(io, fmt)
    data = take!(io)[5:end]
    WAVChunk(Symbol("fmt "), data)
end

function pcm_container_type(nbits::Unsigned)
    if nbits > 32
        return Int64
    elseif nbits > 16
        return Int32
    elseif nbits > 8
        return Int16
    end
    return  UInt8
end

ieee_float_container_type(nbits) = (nbits == 32 ? Float32 : (nbits == 64 ? Float64 : error("$nbits bits is not supported for WAVE_FORMAT_IEEE_FLOAT.")))

function read_pcm_samples(io::IO, fmt::WAVFormat, subrange)
    nbits = bits_per_sample(fmt)
    if isempty(subrange)
        return Array{pcm_container_type(nbits), 2}(undef, 0, fmt.nchannels)
    end
    samples = Array{pcm_container_type(nbits), 2}(undef, length(subrange), fmt.nchannels)
    sample_type = eltype(samples)
    nbytes = ceil(Integer, nbits / 8)
    bitshift = [0x0, 0x8, 0x10, 0x18, 0x20, 0x28, 0x30, 0x38, 0x40]
    mask = UInt64(0x1) << (nbits - 1)
    if nbits <= 8
        mask = UInt64(0)
    end
    skip(io, convert(UInt, (first(subrange) - 1) * nbytes * fmt.nchannels))
    for i = 1:size(samples, 1)
        for j = 1:size(samples, 2)
            raw_sample = Vector{UInt8}(undef, nbytes)
            read!(io, raw_sample)
            my_sample = UInt64(0)
            for k = 1:nbytes
                my_sample |= convert(UInt64, raw_sample[k]) << bitshift[k]
            end
            my_sample >>= nbytes * 8 - nbits
            # sign extend negative values
            my_sample = xor(my_sample, mask) - mask
            samples[i, j] = convert(sample_type, signed(my_sample))
        end
    end
    samples
end

function read_ieee_float_samples(io::IO, fmt::WAVFormat, subrange, ::Type{floatType}) where {floatType}
    if isempty(subrange)
        return Array{floatType, 2}(undef, 0, fmt.nchannels)
    end
    nblocks = length(subrange)
    samples = Array{floatType, 2}(undef, fmt.nchannels, nblocks)
    nbits = bits_per_sample(fmt)
    skip(io, convert(UInt, (first(subrange) - 1) * (nbits / 8) * fmt.nchannels))
    @inbounds for i = 1:nblocks
        for j = 1:fmt.nchannels
            samples[j, i] = read_le(io, floatType)
        end
    end
    copy(samples')
end

# take the loop variable type out of the loop
function read_ieee_float_samples(io::IO, fmt::WAVFormat, subrange)
    floatType = ieee_float_container_type(bits_per_sample(fmt))
    read_ieee_float_samples(io, fmt, subrange, floatType)
end

function read_companded_samples(io::IO, fmt::WAVFormat, subrange, table)
    if isempty(subrange)
        return Array{eltype(table), 2}(undef, 0, fmt.nchannels)
    end
    nblocks = length(subrange)
    samples = Array{eltype(table), 2}(undef, nblocks, fmt.nchannels)
    skip(io, convert(UInt, (first(subrange) - 1) * fmt.nchannels))
    for i = 1:nblocks
        for j = 1:fmt.nchannels
            # add one to value from blocks because A-law stores values from 0 to 255.
            compressedByte::UInt8 = read(io, UInt8)
            # Julia indexing is 1-based; I need a value from 1 to 256
            samples[i, j] = table[compressedByte + 1]
        end
    end
    return samples
end

function read_mulaw_samples(io::IO, fmt::WAVFormat, subrange)
    # Quantized μ-law algorithm -- Use a look up table to convert
    # From Wikipedia, ITU-T Recommendation G.711 and G.191 specify the following intervals:
    #
    # ---------------------------------------+--------------------------------
    #  14 bit Binary Linear input code       | 8 bit Compressed code
    # ---------------------------------------+--------------------------------
    # +8158 to +4063 in 16 intervals of 256  |  0x80 + interval number
    # +4062 to +2015 in 16 intervals of 128  |  0x90 + interval number
    # +2014 to +991 in 16 intervals of 64    |  0xA0 + interval number
    # +990 to +479 in 16 intervals of 32     |  0xB0 + interval number
    # +478 to +223 in 16 intervals of 16     |  0xC0 + interval number
    # +222 to +95 in 16 intervals of 8       |  0xD0 + interval number
    # +94 to +31 in 16 intervals of 4        |  0xE0 + interval number
    # +30 to +1 in 15 intervals of 2         |  0xF0 + interval number
    # 0                                      |  0xFF
    # −1                                     |  0x7F
    # −31 to −2 in 15 intervals of 2         |  0x70 + interval number
    # −95 to −32 in 16 intervals of 4        |  0x60 + interval number
    # −223 to −96 in 16 intervals of 8       |  0x50 + interval number
    # −479 to −224 in 16 intervals of 16     |  0x40 + interval number
    # −991 to −480 in 16 intervals of 32     |  0x30 + interval number
    # −2015 to −992 in 16 intervals of 64    |  0x20 + interval number
    # −4063 to −2016 in 16 intervals of 128  |  0x10 + interval number
    # −8159 to −4064 in 16 intervals of 256  |  0x00 + interval number
    # ---------------------------------------+--------------------------------
    MuLawDecompressTable =
    [
    -32124,-31100,-30076,-29052,-28028,-27004,-25980,-24956,
    -23932,-22908,-21884,-20860,-19836,-18812,-17788,-16764,
    -15996,-15484,-14972,-14460,-13948,-13436,-12924,-12412,
    -11900,-11388,-10876,-10364, -9852, -9340, -8828, -8316,
    -7932, -7676, -7420, -7164, -6908, -6652, -6396, -6140,
    -5884, -5628, -5372, -5116, -4860, -4604, -4348, -4092,
    -3900, -3772, -3644, -3516, -3388, -3260, -3132, -3004,
    -2876, -2748, -2620, -2492, -2364, -2236, -2108, -1980,
    -1884, -1820, -1756, -1692, -1628, -1564, -1500, -1436,
    -1372, -1308, -1244, -1180, -1116, -1052,  -988,  -924,
    -876,  -844,  -812,  -780,  -748,  -716,  -684,  -652,
    -620,  -588,  -556,  -524,  -492,  -460,  -428,  -396,
    -372,  -356,  -340,  -324,  -308,  -292,  -276,  -260,
    -244,  -228,  -212,  -196,  -180,  -164,  -148,  -132,
    -120,  -112,  -104,   -96,   -88,   -80,   -72,   -64,
    -56,   -48,   -40,   -32,   -24,   -16,    -8,     -1,
    32124, 31100, 30076, 29052, 28028, 27004, 25980, 24956,
    23932, 22908, 21884, 20860, 19836, 18812, 17788, 16764,
    15996, 15484, 14972, 14460, 13948, 13436, 12924, 12412,
    11900, 11388, 10876, 10364,  9852,  9340,  8828,  8316,
    7932,  7676,  7420,  7164,  6908,  6652,  6396,  6140,
    5884,  5628,  5372,  5116,  4860,  4604,  4348,  4092,
    3900,  3772,  3644,  3516,  3388,  3260,  3132,  3004,
    2876,  2748,  2620,  2492,  2364,  2236,  2108,  1980,
    1884,  1820,  1756,  1692,  1628,  1564,  1500,  1436,
    1372,  1308,  1244,  1180,  1116,  1052,   988,   924,
    876,   844,   812,   780,   748,   716,   684,   652,
    620,   588,   556,   524,   492,   460,   428,   396,
    372,   356,   340,   324,   308,   292,   276,   260,
    244,   228,   212,   196,   180,   164,   148,   132,
    120,   112,   104,    96,    88,    80,    72,    64,
    56,    48,    40,    32,    24,    16,     8,     0
     ]
    @assert length(MuLawDecompressTable) == 256
    return read_companded_samples(io, fmt, subrange, MuLawDecompressTable)
end

function read_alaw_samples(io::IO, fmt::WAVFormat, subrange)
    # Quantized A-law algorithm -- Use a look up table to convert
    ALawDecompressTable =
    [
    -5504, -5248, -6016, -5760, -4480, -4224, -4992, -4736,
    -7552, -7296, -8064, -7808, -6528, -6272, -7040, -6784,
    -2752, -2624, -3008, -2880, -2240, -2112, -2496, -2368,
    -3776, -3648, -4032, -3904, -3264, -3136, -3520, -3392,
    -22016,-20992,-24064,-23040,-17920,-16896,-19968,-18944,
    -30208,-29184,-32256,-31232,-26112,-25088,-28160,-27136,
    -11008,-10496,-12032,-11520,-8960, -8448, -9984, -9472,
    -15104,-14592,-16128,-15616,-13056,-12544,-14080,-13568,
    -344,  -328,  -376,  -360,  -280,  -264,  -312,  -296,
    -472,  -456,  -504,  -488,  -408,  -392,  -440,  -424,
    -88,   -72,   -120,  -104,  -24,   -8,    -56,   -40,
    -216,  -200,  -248,  -232,  -152,  -136,  -184,  -168,
    -1376, -1312, -1504, -1440, -1120, -1056, -1248, -1184,
    -1888, -1824, -2016, -1952, -1632, -1568, -1760, -1696,
    -688,  -656,  -752,  -720,  -560,  -528,  -624,  -592,
    -944,  -912,  -1008, -976,  -816,  -784,  -880,  -848,
    5504,  5248,  6016,  5760,  4480,  4224,  4992,  4736,
    7552,  7296,  8064,  7808,  6528,  6272,  7040,  6784,
    2752,  2624,  3008,  2880,  2240,  2112,  2496,  2368,
    3776,  3648,  4032,  3904,  3264,  3136,  3520,  3392,
    22016, 20992, 24064, 23040, 17920, 16896, 19968, 18944,
    30208, 29184, 32256, 31232, 26112, 25088, 28160, 27136,
    11008, 10496, 12032, 11520, 8960,  8448,  9984,  9472,
    15104, 14592, 16128, 15616, 13056, 12544, 14080, 13568,
    344,   328,   376,   360,   280,   264,   312,   296,
    472,   456,   504,   488,   408,   392,   440,   424,
    88,    72,   120,   104,    24,     8,    56,    40,
    216,   200,   248,   232,   152,   136,   184,   168,
    1376,  1312,  1504,  1440,  1120,  1056,  1248,  1184,
    1888,  1824,  2016,  1952,  1632,  1568,  1760,  1696,
    688,   656,   752,   720,   560,   528,   624,   592,
    944,   912,  1008,   976,   816,   784,   880,   848
     ]
    @assert length(ALawDecompressTable) == 256
    return read_companded_samples(io, fmt, subrange, ALawDecompressTable)
end

function compress_sample_mulaw(sample)
    MuLawCompressTable =
    [
    0,0,1,1,2,2,2,2,3,3,3,3,3,3,3,3,
    4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,
    5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,
    5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,
    6,6,6,6,6,6,6,6,6,6,6,6,6,6,6,6,
    6,6,6,6,6,6,6,6,6,6,6,6,6,6,6,6,
    6,6,6,6,6,6,6,6,6,6,6,6,6,6,6,6,
    6,6,6,6,6,6,6,6,6,6,6,6,6,6,6,6,
    7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,
    7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,
    7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,
    7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,
    7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,
    7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,
    7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,
    7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7
     ]
    @assert length(MuLawCompressTable) == 256
    cBias = 0x84
    cClip = 32635

    sampleSign = (sample >>> 8) & 0x80
    if sampleSign != 0
        sample = -sample
    end
    if sample > cClip
        sample = cClip
    end
    sample = sample + cBias
    sampleExponent = MuLawCompressTable[(sample >>> 7) + 1]
    mantissa = (sample >> (sampleExponent+3)) & 0x0F
    UInt8((~ (sampleSign | (sampleExponent << 4) | mantissa)) & 0xff)
end

function compress_sample_alaw(sample)
    ALawCompressTable =
    [
    1,1,2,2,3,3,3,3,
    4,4,4,4,4,4,4,4,
    5,5,5,5,5,5,5,5,
    5,5,5,5,5,5,5,5,
    6,6,6,6,6,6,6,6,
    6,6,6,6,6,6,6,6,
    6,6,6,6,6,6,6,6,
    6,6,6,6,6,6,6,6,
    7,7,7,7,7,7,7,7,
    7,7,7,7,7,7,7,7,
    7,7,7,7,7,7,7,7,
    7,7,7,7,7,7,7,7,
    7,7,7,7,7,7,7,7,
    7,7,7,7,7,7,7,7,
    7,7,7,7,7,7,7,7,
    7,7,7,7,7,7,7,7
     ]
    @assert length(ALawCompressTable) == 128
    cBias = 0x84
    cClip = 32635
    sampleSign = ((~sample >>> 8) & 0x80)
    if sampleSign == 0
        sample = -sample
    end
    if sample > cClip
        sample = cClip
    end
    compressedByte = 0
    if sample >= 256
        sampleExponent = ALawCompressTable[((sample >>> 8) & 0x7f) + 1]
        mantissa = (sample >>> (sampleExponent + 3) ) & 0x0f
        compressedByte = ((sampleExponent << 4) | mantissa) & 0xff
    else
        compressedByte = (sample >>> 4) & 0xff
    end
    compressedByte = xor(xor(sampleSign, 0x55), compressedByte)
    UInt8(compressedByte & 0xff)
end


function write_companded_samples(io::IO, samples::AbstractArray{T}, compander::Function) where T <: Integer
    for i = 1:size(samples, 1)
        for j = 1:size(samples, 2)
            write_le(io, compander(samples[i, j]))
        end
    end
end

function write_companded_samples(io::IO, samples::AbstractArray{T}, compander::Function) where T <: AbstractFloat
    samples = convert(Array{Int16}, round.(samples * typemax(Int16)))
    write_companded_samples(io, samples, compander)
end

# PCM data is two's-complement except for resolutions of 1-8 bits, which are represented as offset binary.

# support every bit width from 1 to 8 bits
convert_pcm_to_double(samples::AbstractArray{UInt8}, nbits::Integer) = convert(Array{Float64}, samples) ./ (2.0^nbits - 1) .* 2.0 .- 1.0
convert_pcm_to_double(::AbstractArray{Int8}, ::Integer) = error("WAV files use offset binary for less than 9 bits")
# support every bit width from 9 to 64 bits
convert_pcm_to_double(samples::AbstractArray{T}, nbits::Integer) where T <: Signed = convert(Array{Float64}, samples) / (2.0^(nbits - 1) - 1)

function read_data(io::IO, chunk_size, fmt::WAVFormat, format, subrange)
    # "format" is the format of values, while "fmt" is the WAV file level format
    convert_to_double = x -> convert(Array{Float64}, x)

    if subrange === Nothing
        Base.depwarn("`wavread(..., subrange=Nothing)` is deprecated, use `wavread(..., subrange=:)` instead.", :read_data)
        subrange = (:)
    end
    if subrange === (:)
        # each block stores fmt.nchannels channels
        subrange = 1:convert(UInt, chunk_size / fmt.block_align)
    end
    if isformat(fmt, WAVE_FORMAT_PCM)
        samples = read_pcm_samples(io, fmt, subrange)
        convert_to_double = x -> convert_pcm_to_double(x, bits_per_sample(fmt))
    elseif isformat(fmt, WAVE_FORMAT_IEEE_FLOAT)
        samples = read_ieee_float_samples(io, fmt, subrange)
    elseif isformat(fmt, WAVE_FORMAT_MULAW)
        samples = read_mulaw_samples(io, fmt, subrange)
        convert_to_double = x -> convert_pcm_to_double(x, 16)
    elseif isformat(fmt, WAVE_FORMAT_ALAW)
        samples = read_alaw_samples(io, fmt, subrange)
        convert_to_double = x -> convert_pcm_to_double(x, 16)
    else
        error("$(fmt.compression_code) is an unsupported compression code!")
    end
    if format == "double"
        samples = convert_to_double(samples)
    end
    samples
end

function write_pcm_samples(io::IO, fmt::WAVFormat, samples::AbstractArray{T}) where T <: Integer
    nbits = bits_per_sample(fmt)
    # number of bytes per sample
    nbytes = ceil(Integer, nbits / 8)
    for i = 1:size(samples, 1)
        for j = 1:size(samples, 2)
            my_sample = samples[i, j]
            # shift my_sample into the N most significant bits
            my_sample <<= nbytes * 8 - nbits
            for k = 1:nbytes
                write_le(io, convert(UInt8, my_sample & 0xff))
                my_sample = my_sample >> 8
            end
        end
    end
end

function write_pcm_samples(io::IO, fmt::WAVFormat, samples::AbstractArray{T}) where T <: AbstractFloat
    nbits = bits_per_sample(fmt)
    # Scale the floating point values to the PCM range
    if nbits > 8
        # two's complement
        samples = convert(Array{pcm_container_type(nbits)}, round.(samples * (2.0^(nbits - 1) - 1)))
    else
        # offset binary
        samples = convert(Array{UInt8}, round.((samples .+ 1.0) / 2.0 * (2.0^nbits - 1)))
    end
    return write_pcm_samples(io, fmt, samples)
end

function write_ieee_float_samples(io::IO, samples)
    # Interleave the channel samples before writing to the stream.
    for i = 1:size(samples, 1) # for each sample
        for j = 1:size(samples, 2) # for each channel
            write_le(io, samples[i, j])
        end
    end
end

# take the loop variable type out of the loop
function write_ieee_float_samples(io::IO, fmt::WAVFormat, samples)
    floatType = ieee_float_container_type(bits_per_sample(fmt))
    write_ieee_float_samples(io, convert(Array{floatType}, samples))
end

function write_data(io::IO, fmt::WAVFormat, samples::AbstractArray)
    if isformat(fmt, WAVE_FORMAT_PCM)
        return write_pcm_samples(io, fmt, samples)
    elseif isformat(fmt, WAVE_FORMAT_IEEE_FLOAT)
        return write_ieee_float_samples(io, fmt, samples)
    elseif isformat(fmt, WAVE_FORMAT_MULAW)
        return write_companded_samples(io, samples, compress_sample_mulaw)
    elseif isformat(fmt, WAVE_FORMAT_ALAW)
        return write_companded_samples(io, samples, compress_sample_alaw)
    else
        error("$(fmt.compression_code) is an unsupported compression code.")
    end
end

make_range(subrange) = subrange
make_range(subrange::Number) = 1:convert(Int, subrange)

function wavread(io::IO; subrange=(:), format="double")
    chunk_size = read_header(io)
    samples = Array{Float64, 1}()
    nbits = 0
    sample_rate = Float32(0.0)
    opt = WAVChunk[]

    # Note: This assumes that the format chunk is written in the file before the data chunk. The
    # specification does not require this assumption, but most real files are written that way.

    # Subtract the size of the format field from chunk_size; now it holds the size
    # of all the sub-chunks
    chunk_size -= 4
    # GitHub Issue #18: Check if there is enough data to read another chunk
    subchunk_header_size = 4 + sizeof(UInt32)
    fmt = WAVFormat()
    while chunk_size >= subchunk_header_size
        # Read subchunk ID and size
        subchunk_id = Vector{UInt8}(undef, 4)
        read!(io, subchunk_id)
        subchunk_size = read_le(io, UInt32)
        if subchunk_size > chunk_size
            chunk_size = 0
            break
        end
        chunk_size -= subchunk_header_size + subchunk_size
        # check the subchunk ID
        if subchunk_id == b"fmt "
            fmt = read_format(io, subchunk_size)
            sample_rate = Float32(fmt.sample_rate)
            nbits = bits_per_sample(fmt)
            push!(opt, WAVChunk(fmt))
        elseif subchunk_id == b"data"
            if format == "size"
                return convert(Int, subchunk_size / fmt.block_align), convert(Int, fmt.nchannels)
            end
            samples = read_data(io, subchunk_size, fmt, format, make_range(subrange))
        else
            subchunk_data = Vector{UInt8}(undef, subchunk_size)
            read!(io, subchunk_data)
            push!(opt, WAVChunk(Symbol(subchunk_id), subchunk_data))
        end
    end
    return samples, sample_rate, nbits, opt
end

function wavread(filename::AbstractString; subrange=(:), format="double")
    open(filename, "r") do io
        wavread(io, subrange=subrange, format=format)
    end
end

# These are the MATLAB compatible signatures
wavread(filename::AbstractString, fmt::AbstractString) = wavread(filename, format=fmt)
wavread(filename::AbstractString, n) = wavread(filename, subrange=n)
wavread(filename::AbstractString, n, fmt) = wavread(filename, subrange=n, format=fmt)

get_default_compression(::AbstractArray{T}) where T <: Integer = WAVE_FORMAT_PCM
get_default_compression(::AbstractArray{T}) where T<:AbstractFloat = WAVE_FORMAT_IEEE_FLOAT
get_default_pcm_precision(::AbstractArray{UInt8}) = 8
get_default_pcm_precision(::AbstractArray{Int16}) = 16
get_default_pcm_precision(::Any) = 24

function get_default_precision(samples, compression)
    if compression == WAVE_FORMAT_ALAW || compression == WAVE_FORMAT_MULAW
        return 8
    elseif compression == WAVE_FORMAT_IEEE_FLOAT
        return 32
    end
    get_default_pcm_precision(samples)
end

function wavwrite(samples::AbstractArray, io::IO; Fs=8000, nbits=0, compression=0,
                  chunks::Vector{WAVChunk}=WAVChunk[])
    if compression == 0
        compression = get_default_compression(samples)
    elseif compression == WAVE_FORMAT_ALAW || compression == WAVE_FORMAT_MULAW
        nbits = 8
    end
    if nbits == 0
        nbits = get_default_precision(samples, compression)
    end
    compression_code = compression
    nchannels = size(samples, 2)
    sample_rate = Fs
    my_nbits = ceil(Integer, nbits / 8) * 8
    block_align = my_nbits / 8 * nchannels
    bps = sample_rate * block_align
    data_length::UInt32 = size(samples, 1) * block_align
    extra_length::UInt32 = 8 * length(chunks) + sum([length(c.data) for c in chunks])
    ext = WAVFormatExtension()

    if nchannels > 2 || my_nbits > 16 || my_nbits != nbits
        compression_code = WAVE_FORMAT_EXTENSIBLE
        valid_bits_per_sample = nbits
        channel_mask = 0
        sub_format = UInt8[]
        if compression == WAVE_FORMAT_PCM
            sub_format = KSDATAFORMAT_SUBTYPE_PCM
        elseif compression == WAVE_FORMAT_IEEE_FLOAT
            sub_format = KSDATAFORMAT_SUBTYPE_IEEE_FLOAT
        elseif compression == WAVE_FORMAT_ALAW
            sub_format = KSDATAFORMAT_SUBTYPE_ALAW
        elseif compression == WAVE_FORMAT_MULAW
            sub_format = KSDATAFORMAT_SUBTYPE_MULAW
        else
            error("Unsupported extension sub format: $compression")
        end
        ext = WAVFormatExtension(valid_bits_per_sample, channel_mask, sub_format)
        write_extended_header(io, data_length + extra_length)
    else
        write_standard_header(io, data_length + extra_length)
    end
    fmt = WAVFormat(compression_code,
                    nchannels,
                    sample_rate,
                    bps,
                    block_align,
                    my_nbits,
                    ext)
    write_format(io, fmt)

    for eachchunk in chunks
        write(io, eachchunk.id)
        write_le(io, UInt32(length(eachchunk.data)))
        for eachbyte in eachchunk.data
            write(io, eachbyte)
        end
    end

    # write the data subchunk header
    write(io, b"data")
    write_le(io, data_length) # UInt32
    write_data(io, fmt, samples)
end

function wavwrite(samples::AbstractArray, filename::AbstractString; Fs=8000, nbits=0, compression=0,
                  chunks::Vector{WAVChunk}=WAVChunk[])
    open(filename, "w") do io
        wavwrite(samples, io, Fs=Fs, nbits=nbits, compression=compression, chunks=chunks)
    end
end

function wavappend(samples::AbstractArray, io::IO)
    seekstart(io)
    chunk_size = read_header(io)
    subchunk_id = Vector{UInt8}(undef, 4)
    read!(io, subchunk_id)
    subchunk_size = read_le(io, UInt32)
    if subchunk_id != b"fmt "
        error("First chunk is not the format")
    end
    fmt = read_format(io, subchunk_size)

    if fmt.nchannels != size(samples,2)
        error("Number of channels do not match")
    end

    # Compute data length of current chunk to-be-appended.
    data_length = size(samples, 1) * fmt.block_align
    # Update `chunksize`: add length of new data.
    seek(io,4)
    write_le(io, convert(UInt32, chunk_size + data_length))
    # Get `subchunk2size`.
    seek(io, 24 + subchunk_size)
    data_length_old = read_le(io, UInt32)
    # Update `subchunk2size`: add length of new data.
    seek(io, 24 + subchunk_size)
    write_le(io, convert(UInt32, data_length_old + data_length))

    seekend(io)
    write_data(io, fmt, samples)
end

function wavappend(samples::AbstractArray, filename::AbstractString)
    open(filename, "a+") do io
        wavappend(samples,io)
    end
end

wavwrite(y::AbstractArray, f::Real, filename::AbstractString) = wavwrite(y, filename, Fs=f)
wavwrite(y::AbstractArray, f::Real, n::Real, filename::AbstractString) = wavwrite(y, filename, Fs=f, nbits=n)

# support for writing native arrays...
wavwrite(y::AbstractArray{T}, io::IO) where T <: Integer = wavwrite(y, io, nbits=sizeof(T)*8)
wavwrite(y::AbstractArray{T}, filename::AbstractString) where T <: Integer = wavwrite(y, filename, nbits=sizeof(T)*8)
wavwrite(y::AbstractArray{Int32}, io::IO) = wavwrite(y, io, nbits=24)
wavwrite(y::AbstractArray{Int32}, filename::AbstractString) = wavwrite(y, filename, nbits=24)
wavwrite(y::AbstractArray{T}, io::IO) where T <: AbstractFloat = wavwrite(y, io, nbits=sizeof(T)*8, compression=WAVE_FORMAT_IEEE_FLOAT)
wavwrite(y::AbstractArray{T}, filename::AbstractString) where T <: AbstractFloat = wavwrite(y, filename, nbits=sizeof(T)*8, compression=WAVE_FORMAT_IEEE_FLOAT)

# FileIO integration support
load(s::Stream{format"WAV"}; kwargs...) = wavread(s.io; kwargs...)
save(s::Stream{format"WAV"}, data; kwargs...) = wavwrite(data, s.io; kwargs...)

load(f::File{format"WAV"}; kwargs...) = wavread(f.filename; kwargs...)
save(f::File{format"WAV"}, data; kwargs...) = wavwrite(data, f.filename; kwargs...)

end # module
