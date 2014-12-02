# -*- mode: julia; -*-
module WAV
export wavread, wavwrite, wavappend, wavplay, WAVArray
export WAVE_FORMAT_PCM, WAVE_FORMAT_IEEE_FLOAT, WAVE_FORMAT_ALAW, WAVE_FORMAT_MULAW
import Base.unbox, Base.box
using Compat

if find_library(["libpulse-simple"]) != ""
    include("wavplay-pulse.jl")
elseif find_library(["AudioToolbox"],
                    ["/System/Library/Frameworks/AudioToolbox.framework/Versions/A"]) != ""
    include("wavplay-audioqueue.jl")
else
    wavplay() = warn("wavplay is not currently implemented on $OS_NAME")
end
wavplay(fname) = wavplay(wavread(fname)...)

include("AudioDisplay.jl")

# The WAV specification states that numbers are written to disk in little endian form.
write_le(stream::IO, value::UInt8) = write(stream, value)

function write_le(stream::IO, value::UInt16)
    write(stream, UInt8((value & 0x00ff)     ))
    write(stream, UInt8((value & 0xff00) >> 8))
end

function write_le(stream::IO, value::UInt32)
    write(stream, UInt8((value & 0x000000ff)      ))
    write(stream, UInt8((value & 0x0000ff00) >>  8))
    write(stream, UInt8((value & 0x00ff0000) >> 16))
    write(stream, UInt8((value & 0xff000000) >> 24))
end

function write_le(stream::IO, value::UInt64)
    write(stream, UInt8((value & 0x00000000000000ff)      ))
    write(stream, UInt8((value & 0x000000000000ff00) >>  8))
    write(stream, UInt8((value & 0x0000000000ff0000) >> 16))
    write(stream, UInt8((value & 0x00000000ff000000) >> 24))
    write(stream, UInt8((value & 0x000000ff00000000) >> 32))
    write(stream, UInt8((value & 0x0000ff0000000000) >> 40))
    write(stream, UInt8((value & 0x00ff000000000000) >> 48))
    write(stream, UInt8((value & 0xff00000000000000) >> 56))
end

write_le(stream::IO, value::Int16) = write_le(stream, UInt16(value))
write_le(stream::IO, value::Int32) = write_le(stream, UInt32(value))
write_le(stream::IO, value::Int64) = write_le(stream, UInt64(value))
write_le(stream::IO, value::Float32) = write_le(stream, box(UInt32, unbox(Float32, value)))
write_le(stream::IO, value::Float64) = write_le(stream, box(UInt64, unbox(Float64, value)))

read_le(stream::IO, x::Type{UInt8}) = read(stream, x)

function read_le(stream::IO, ::Type{UInt16})
    const bytes::Array{UInt16, 1} = read(stream, UInt8, 2)
    (bytes[2] << 8) | bytes[1]
end

function read_le(stream::IO, ::Type{UInt32})
    const bytes::Array{UInt32, 1} = read(stream, UInt8, 4)
    (bytes[4] << 24) | (bytes[3] << 16) | (bytes[2] << 8) | bytes[1]
end

function read_le(stream::IO, ::Type{UInt64})
    const bytes::Array{UInt64, 1} = read(stream, UInt8, 8)
    (bytes[8] << 56) | (bytes[7] << 48) | (bytes[6] << 40) | (bytes[5] << 32) | (bytes[4] << 24) | (bytes[3] << 16) | (bytes[2] << 8) | bytes[1]
end

read_le(stream::IO, ::Type{Int16}) = Int16(read_le(stream, UInt16))
read_le(stream::IO, ::Type{Int32}) = Int32(read_le(stream, UInt32))
read_le(stream::IO, ::Type{Int64}) = Int64(read_le(stream, UInt64))
read_le(stream::IO, ::Type{Float32}) = box(Float32, unbox(UInt32, read_le(stream, UInt32)))
read_le(stream::IO, ::Type{Float64}) = box(Float64, unbox(UInt64, read_le(stream, UInt64)))

# Required WAV Chunk; The format chunk describes how the waveform data is stored
type WAVFormat
    compression_code::UInt16
    nchannels::UInt16
    sample_rate::UInt32
    bps::UInt32 # average bytes per second
    block_align::UInt16
    nbits::UInt16
    extra_bytes::Array{UInt8, 1}

    data_length::UInt32

    WAVFormat() = new(0, 0, 0, 0, 0, 0, [], 0)
    WAVFormat(comp, chan, fs, bytes, ba, nbits) = new(comp, chan, fs, bytes, ba, nbits, [], 0)
end

const WAVE_FORMAT_PCM        = 0x0001 # PCM
const WAVE_FORMAT_IEEE_FLOAT = 0x0003 # IEEE float
const WAVE_FORMAT_ALAW       = 0x0006 # A-Law
const WAVE_FORMAT_MULAW      = 0x0007 # Mu-Law
const WAVE_FORMAT_EXTENSIBLE = 0xfffe # Extension!

# used by WAVE_FORMAT_EXTENSIBLE
type WAVFormatExtension
    valid_bits_per_sample::UInt16
    channel_mask::UInt32
    sub_format::Array{UInt8, 1} # 16 byte GUID

    WAVFormatExtension() = new(0, 0, b"")
    WAVFormatExtension(vbsp, cm, sb) = new(vbsp, cm, sb)
end

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

function WAVFormatExtension(bytes::Array{UInt8})
    if length(bytes) != 22
        error("There are not the right number of bytes for the WAVFormat Extension")
    end
    # split bytes into valid_bits_per_sample, channel_mask, and sub_format
    valid_bits_per_sample = (UInt16(bytes[2]) << 8) | UInt16(bytes[1])
    channel_mask = (UInt32(bytes[6]) << 24) | (UInt32(bytes[5]) << 16) | (UInt32(bytes[4]) << 8) | UInt32(bytes[3])
    sub_format = bytes[7:end]
    return WAVFormatExtension(valid_bits_per_sample, channel_mask, sub_format)
end

function read_header(io::IO)
    # check if the given file has a valid RIFF header
    riff = read(io, UInt8, 4)
    if riff !=  b"RIFF"
        error("Invalid WAV file: The RIFF header is invalid")
    end

    chunk_size = read_le(io, UInt32)

    # check if this is a WAV file
    format = read(io, UInt8, 4)
    if format != b"WAVE"
        error("Invalid WAV file: the format is not WAVE")
    end
    return chunk_size
end

function write_header(io::IO, fmt::WAVFormat, base_chunk_size)
    write(io, b"RIFF") # RIFF header
    write_le(io, UInt32(base_chunk_size + fmt.data_length)) # chunk_size
    write(io, b"WAVE")
end
write_standard_header(io, fmt) = write_header(io, fmt, 36)
write_extended_header(io, fmt) = write_header(io, fmt, 60)

function read_format(io::IO, chunk_size::UInt32)
    # can I read in all of the fields at once?
    orig_chunk_size = Int(chunk_size)
    if chunk_size < 16
        error("The WAVE Format chunk must be at least 16 bytes")
    end
    format = WAVFormat(read_le(io, UInt16), # Compression Code
                       read_le(io, UInt16), # Number of Channels
                       read_le(io, UInt32), # Sample Rate
                       read_le(io, UInt32), # bytes per second
                       read_le(io, UInt16), # block align
                       read_le(io, UInt16)) # bits per sample
    chunk_size -= 16
    if chunk_size > 0
        # TODO add error checking for size mismatches
        extra_bytes = read_le(io, UInt16)
        format.extra_bytes = read(io, UInt8, extra_bytes)
    end
    return format
end

function write_format(io::IO, fmt::WAVFormat, ext_length::Integer)
    # write the fmt subchunk header
    write(io, b"fmt ")
    write_le(io, UInt32(16 + ext_length)) # subchunk length; 16 is size of base format chunk

    write_le(io, fmt.compression_code) # audio format (UInt16)
    write_le(io, fmt.nchannels) # number of channels (UInt16)
    write_le(io, fmt.sample_rate) # sample rate (UInt32)
    write_le(io, fmt.bps) # byte rate (UInt32)
    write_le(io, fmt.block_align) # byte align (UInt16)
    write_le(io, fmt.nbits) # number of bits per sample (UInt16)
end
write_format(io::IO, fmt::WAVFormat) = write_format(io, fmt, 0)

function write_format(io::IO, fmt::WAVFormat, ext::WAVFormatExtension)
    write_format(io, fmt, 24) # 24 is the added length needed to encode the extension
    write_le(io, UInt16(22))
    write_le(io, ext.valid_bits_per_sample)
    write_le(io, ext.channel_mask)
    @assert length(ext.sub_format) == 16
    write(io, ext.sub_format)
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
    if isempty(subrange)
        return Array(pcm_container_type(fmt.nbits), 0, fmt.nchannels)
    end
    samples = Array(pcm_container_type(fmt.nbits), length(subrange), fmt.nchannels)
    const nbytes = ceil(Integer, fmt.nbits / 8)
    const bitshift::Array{UInt} = linspace(0, 64, 9)
    const mask = unsigned(1) << (fmt.nbits - 1)
    const signextend_mask = ~unsigned(0) << fmt.nbits
    skip(io, UInt((first(subrange) - 1) * nbytes * fmt.nchannels))
    for i = 1:size(samples, 1)
        for j = 1:size(samples, 2)
            raw_sample = read(io, UInt8, nbytes)
            my_sample = UInt64(0)
            for k = 1:nbytes
                my_sample |= UInt64(raw_sample[k]) << bitshift[k]
            end
            my_sample >>= nbytes * 8 - fmt.nbits
            # sign extend negative values
            if fmt.nbits > 8 && (my_sample & mask > 0)
                my_sample |= signextend_mask
            end
            samples[i, j] = convert(eltype(samples), my_sample)
        end
    end
    samples
end

function read_ieee_float_samples(io::IO, fmt::WAVFormat, subrange)
    const floatType = ieee_float_container_type(fmt.nbits)
    if isempty(subrange)
        return Array(floatType, 0, fmt.nchannels)
    end
    const nblocks = length(subrange)
    samples = Array(floatType, nblocks, fmt.nchannels)
    skip(io, UInt((first(subrange) - 1) * (fmt.nbits / 8) * fmt.nchannels))
    for i = 1:nblocks
        for j = 1:fmt.nchannels
            samples[i, j] = read_le(io, floatType)
        end
    end
    samples
end

function read_companded_samples(io::IO, fmt::WAVFormat, subrange, table)
    if isempty(subrange)
        return Array(eltype(table), 0, fmt.nchannels)
    end
    const nblocks = length(subrange)
    samples = Array(eltype(table), nblocks, fmt.nchannels)
    skip(io, UInt((first(subrange) - 1) * fmt.nchannels))
    for i = 1:nblocks
        for j = 1:fmt.nchannels
            # add one to value from blocks because A-law stores values from 0 to 255.
            const compressedByte::UInt8 = clamp(read_le(io, UInt8), 0, 255)
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
    const MuLawDecompressTable =
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
    const ALawDecompressTable =
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
    const MuLawCompressTable =
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
    const cBias = 0x84
    const cClip = 32635

    const sign = (sample >>> 8) & 0x80
    if sign != 0
        sample = -sample
    end
    if sample > cClip
        sample = cClip
    end
    sample = sample + cBias
    const exponent = MuLawCompressTable[(sample >>> 7) + 1]
    const mantissa = (sample >> (exponent+3)) & 0x0F
    (~ (sign | (exponent << 4) | mantissa)) & 0xff
end

function compress_sample_alaw(sample)
    const ALawCompressTable =
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
    const cBias = 0x84
    const cClip = 32635
    const sign = ((~sample >>> 8) & 0x80)
    if sign == 0
        sample = -sample
    end
    if sample > cClip
        sample = cClip
    end
    compressedByte = 0
    if sample >= 256
        const exponent = ALawCompressTable[((sample >>> 8) & 0x7f) + 1]
        const mantissa = (sample >>> (exponent + 3) ) & 0x0f
        compressedByte = ((exponent << 4) | mantissa) & 0xff
    else
        compressedByte = (sample >>> 4) & 0xff
    end
    compressedByte $= (sign $ 0x55)
    compressedByte & 0xff
end


function write_companded_samples{T<:Integer}(io::IO, samples::Array{T}, compander::Function)
    for i = 1:size(samples, 1)
        for j = 1:size(samples, 2)
            const compressedByte = compander(samples[i, j])
            write_le(io, convert(UInt8, compressedByte))
        end
    end
end

function write_companded_samples{T<:FloatingPoint}(io::IO, samples::Array{T}, compander::Function)
    samples = convert(Array{Int16}, round(samples * typemax(Int16)))
    write_companded_samples(io, samples, compander)
end

# PCM data is two's-complement except for resolutions of 1-8 bits, which are represented as offset binary.

# support every bit width from 1 to 8 bits
convert_pcm_to_double(samples::Array{UInt8}, nbits::Integer) = convert(Array{Float64}, samples) ./ (2^nbits - 1) .* 2.0 .- 1.0
convert_pcm_to_double(::Array{Int8}, ::Integer) = error("WAV files use offset binary for less than 9 bits")
# support every bit width from 9 to 64 bits
convert_pcm_to_double{T<:Signed}(samples::Array{T}, nbits::Integer) = convert(Array{Float64}, samples) / (2^(nbits - 1) - 1)

function read_data(io::IO, chunk_size, fmt::WAVFormat, format, subrange)
    # "format" is the format of values, while "fmt" is the WAV file level format
    samples = None
    convert_to_double = x -> convert(Array{Float64}, x)

    if subrange === None
        # each block stores fmt.nchannels channels
        subrange = 1:UInt(chunk_size / fmt.block_align)
    end
    if fmt.compression_code == WAVE_FORMAT_EXTENSIBLE
        ext_fmt = WAVFormatExtension(fmt.extra_bytes)
        if ext_fmt.sub_format == KSDATAFORMAT_SUBTYPE_PCM
            fmt.nbits = ext_fmt.valid_bits_per_sample
            samples = read_pcm_samples(io, fmt, subrange)
            convert_to_double = x -> convert_pcm_to_double(x, fmt.nbits)
        elseif ext_fmt.sub_format == KSDATAFORMAT_SUBTYPE_IEEE_FLOAT
            fmt.nbits = ext_fmt.valid_bits_per_sample
            samples = read_ieee_float_samples(io, fmt, subrange)
        elseif ext_fmt.sub_format == KSDATAFORMAT_SUBTYPE_ALAW
            fmt.nbits = 8
            samples = read_alaw_samples(io, fmt, subrange)
        elseif ext_fmt.sub_format == KSDATAFORMAT_SUBTYPE_MULAW
            fmt.nbits = 8
            samples = read_mulaw_samples(io, fmt, subrange)
        else
            error("$ext_fmt -- WAVE_FORMAT_EXTENSIBLE Not done yet!")
        end
    elseif fmt.compression_code == WAVE_FORMAT_PCM
        samples = read_pcm_samples(io, fmt, subrange)
        convert_to_double = x -> convert_pcm_to_double(x, fmt.nbits)
    elseif fmt.compression_code == WAVE_FORMAT_IEEE_FLOAT
        samples = read_ieee_float_samples(io, fmt, subrange)
    elseif fmt.compression_code == WAVE_FORMAT_MULAW
        samples = read_mulaw_samples(io, fmt, subrange)
        convert_to_double = x -> convert_pcm_to_double(x, 16)
    elseif fmt.compression_code == WAVE_FORMAT_ALAW
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

function write_pcm_samples{T<:Integer}(io::IO, fmt::WAVFormat, samples::Array{T})
    # number of bytes per sample
    const nbytes = ceil(Integer, fmt.nbits / 8)
    const bitshift::Array{UInt} = linspace(0, 64, 9)
    const minval = fmt.nbits > 8 ? -2^(fmt.nbits - 1) : -2^(fmt.nbits)
    const maxval = fmt.nbits > 8 ? 2^(fmt.nbits - 1) - 1 : 2^(fmt.nbits) - 1
    for i = 1:size(samples, 1)
        for j = 1:size(samples, 2)
            my_sample = clamp(samples[i, j], minval, maxval)
            # shift my_sample into the N most significant bits
            my_sample <<= nbytes * 8 - fmt.nbits
            mask = convert(typeof(my_sample), 0xff)
            for k = 1:nbytes
                write_le(io, UInt8((my_sample & mask) >> bitshift[k]))
                mask <<= 8
            end
        end
    end
end

function write_pcm_samples{T<:FloatingPoint}(io::IO, fmt::WAVFormat, samples::Array{T})
    # Scale the floating point values to the PCM range
    if fmt.nbits > 8
        # two's complement
        samples = convert(Array{pcm_container_type(fmt.nbits)}, round(samples * (2^(fmt.nbits - 1) - 1)))
    else
        # offset binary
        samples = convert(Array{UInt8}, round((samples .+ 1.0) / 2.0 * (2^fmt.nbits - 1)))
    end
    return write_pcm_samples(io, fmt, samples)
end

function write_ieee_float_samples{T<:FloatingPoint}(io::IO, fmt::WAVFormat, samples::Array{T})
    const floatType = ieee_float_container_type(fmt.nbits)
    samples = convert(Array{floatType}, samples)
    const minval = convert(floatType, -1.0)
    const maxval = convert(floatType, 1.0)
    # Interleave the channel samples before writing to the stream.
    for i = 1:size(samples, 1) # for each sample
        for j = 1:size(samples, 2) # for each channel
            write_le(io, clamp(samples[i, j], minval, maxval))
        end
    end
end

function write_data(io::IO, fmt::WAVFormat, ext_fmt::WAVFormatExtension, samples::Array)
    if fmt.compression_code == WAVE_FORMAT_EXTENSIBLE
        if ext_fmt.sub_format == KSDATAFORMAT_SUBTYPE_PCM
            fmt.nbits = ext_fmt.valid_bits_per_sample
            return write_pcm_samples(io, fmt, samples)
        elseif ext_fmt.sub_format == KSDATAFORMAT_SUBTYPE_IEEE_FLOAT
            fmt.nbits = ext_fmt.valid_bits_per_sample
            return write_ieee_float_samples(io, fmt, samples)
        elseif ext_fmt.sub_format == KSDATAFORMAT_SUBTYPE_ALAW
            fmt.nbits = 8
            return write_companded_samples(io, samples, compress_sample_alaw)
        elseif ext_fmt.sub_format == KSDATAFORMAT_SUBTYPE_MULAW
            fmt.nbits = 8
            return write_companded_samples(io, samples, compress_sample_mulaw)
        else
            error("$ext_fmt -- WAVE_FORMAT_EXTENSIBLE Not done yet!")
        end
    elseif fmt.compression_code == WAVE_FORMAT_PCM
        return write_pcm_samples(io, fmt, samples)
    elseif fmt.compression_code == WAVE_FORMAT_IEEE_FLOAT
        return write_ieee_float_samples(io, fmt, samples)
    elseif fmt.compression_code == WAVE_FORMAT_MULAW
        return write_companded_samples(io, samples, compress_sample_mulaw)
    elseif fmt.compression_code == WAVE_FORMAT_ALAW
        return write_companded_samples(io, samples, compress_sample_alaw)
    else
        error("$(fmt.compression_code) is an unsupported compression code.")
    end
end

make_range(subrange) = subrange
make_range(subrange::Number) = 1:convert(Int, subrange)
make_range(subrange::Range1) = convert(Range1{Int}, subrange)

function wavread(io::IO; subrange=None, format="double")
    chunk_size = read_header(io)
    fmt = WAVFormat()
    samples = Array(Float64)

    # Note: This assumes that the format chunk is written in the file before the data chunk. The
    # specification does not require this assumption, but most real files are written that way.

    # Subtract the size of the format field from chunk_size; now it holds the size
    # of all the sub-chunks
    chunk_size -= 4
    while chunk_size > 0
        # Read subchunk ID and size
        subchunk_id = read(io, UInt8, 4)
        subchunk_size = read_le(io, UInt32)
        chunk_size -= 8 + subchunk_size
        # check the subchunk ID
        if subchunk_id == b"fmt "
            fmt = read_format(io, subchunk_size)
        elseif subchunk_id == b"data"
            if format == "size"
                return Int(subchunk_size / fmt.block_align), Int(fmt.nchannels)
            end
            samples = read_data(io, subchunk_size, fmt, format, make_range(subrange))
        else
            # return unknown sub-chunks?
            # Note: Ignoring unknown sub chunks for now
            skip(io, subchunk_size)
        end
    end
    return samples, fmt.sample_rate, fmt.nbits, None
end

function wavread(filename::String; subrange=None, format="double")
    io = open(filename, "r")
    finalizer(io, close)
    const result = wavread(io, subrange=subrange, format=format)
    close(io)
    return result
end

# These are the MATLAB compatible signatures
wavread(filename::String, fmt::String) = wavread(filename, format=fmt)
wavread(filename::String, n::Int) = wavread(filename, subrange=n)
wavread(filename::String, n::Range1) = wavread(filename, subrange=n)
wavread(filename::String, n::Int, fmt::String) = wavread(filename, subrange=n, format=fmt)
wavread(filename::String, n::Range1, fmt::String) = wavread(filename, subrange=n, format=fmt)

get_default_compression{T<:Integer}(::Array{T}) = WAVE_FORMAT_PCM
get_default_compression{T<:FloatingPoint}(::Array{T}) = WAVE_FORMAT_IEEE_FLOAT
get_default_pcm_precision(::Array{UInt8}) = 8
get_default_pcm_precision(::Array{Int16}) = 16
get_default_pcm_precision(::Any) = 24

function get_default_precision(samples, compression)
    if compression == WAVE_FORMAT_ALAW || compression == WAVE_FORMAT_MULAW
        return 8
    elseif compression == WAVE_FORMAT_IEEE_FLOAT
        return 32
    end
    get_default_pcm_precision(samples)
end

function wavwrite(samples::Array, io::IO; Fs=8000, nbits=0, compression=0)
    if compression == 0
        compression = get_default_compression(samples)
    elseif compression == WAVE_FORMAT_ALAW || compression == WAVE_FORMAT_MULAW
        nbits = 8
    end
    if nbits == 0
        nbits = get_default_precision(samples, compression)
    end
    fmt = WAVFormat()
    fmt.compression_code = compression
    fmt.nchannels = size(samples, 2)
    fmt.sample_rate = Fs
    fmt.nbits = ceil(Integer, nbits / 8) * 8
    fmt.block_align = fmt.nbits / 8 * fmt.nchannels
    fmt.bps = fmt.sample_rate * fmt.block_align
    fmt.data_length = size(samples, 1) * fmt.block_align

    ext = WAVFormatExtension()
    if fmt.nchannels > 2 || fmt.nbits > 16 || fmt.nbits != nbits
        fmt.compression_code = WAVE_FORMAT_EXTENSIBLE
        ext.valid_bits_per_sample = nbits
        ext.channel_mask = 0
        if compression == WAVE_FORMAT_PCM
            ext.sub_format = KSDATAFORMAT_SUBTYPE_PCM
        elseif compression == WAVE_FORMAT_IEEE_FLOAT
            ext.sub_format = KSDATAFORMAT_SUBTYPE_IEEE_FLOAT
        elseif compression == WAVE_FORMAT_ALAW
            ext.sub_format = KSDATAFORMAT_SUBTYPE_ALAW
        elseif compression == WAVE_FORMAT_MULAW
            ext.sub_format = KSDATAFORMAT_SUBTYPE_MULAW
        else
            error("Unsupported extension sub format: $compression")
        end
        write_extended_header(io, fmt)
        write_format(io, fmt, ext)
    else
        write_standard_header(io, fmt)
        write_format(io, fmt)
    end

    # write the data subchunk header
    write(io, b"data")
    write_le(io, fmt.data_length) # UInt32
    write_data(io, fmt, ext, samples)
end

function wavwrite(samples::Array, filename::String; Fs=8000, nbits=0, compression=0)
    io = open(filename, "w")
    finalizer(io, close)
    const result = wavwrite(samples, io, Fs=Fs, nbits=nbits, compression=compression)
    close(io)
    return result
end

function wavappend(samples::Array, io::IO)
    seekstart(io)
    chunk_size = read_header(io)
    subchunk_id = read(io, UInt8, 4)
    subchunk_size = read_le(io, UInt32)
    if subchunk_id != b"fmt "
        error("First chunk is not the format")
    end
    fmt = read_format(io, subchunk_size)
    ext = WAVFormatExtension(fmt.extra_bytes)

    if fmt.nchannels != size(samples,2)
        error("Number of channels do not match")
    end

    fmt.data_length = size(samples, 1) * fmt.block_align

    seek(io,4)
    write_le(io, UInt32(chunk_size + fmt.data_length))

    seek(io,64)
    subchunk_size = read_le(io, UInt32)
    seek(io,64)
    write_le(io, UInt32(subchunk_size + fmt.data_length))

    seekend(io)
    write_data(io, fmt, ext, samples)
end

function wavappend(samples::Array, filename::String)
    io = open(filename, true,true,false,false,true)  # r, w, & a
    finalizer(io, close)
    const result = wavappend(samples,io)
    close(io)
    return result
end

wavwrite(y::Array, f::Real, filename::String) = wavwrite(y, filename, Fs=f)
wavwrite(y::Array, f::Real, n::Real, filename::String) = wavwrite(y, filename, Fs=f, nbits=n)

# support for writing native arrays...
wavwrite{T<:Integer}(y::Array{T}, io::IO) = wavwrite(y, io, nbits=sizeof(T)*8)
wavwrite{T<:Integer}(y::Array{T}, filename::String) = wavwrite(y, filename, nbits=sizeof(T)*8)
wavwrite(y::Array{Int32}, io::IO) = wavwrite(y, io, nbits=24)
wavwrite(y::Array{Int32}, filename::String) = wavwrite(y, filename, nbits=24)
wavwrite{T<:FloatingPoint}(y::Array{T}, io::IO) = wavwrite(y, io, nbits=sizeof(T)*8, compression=WAVE_FORMAT_IEEE_FLOAT)
wavwrite{T<:FloatingPoint}(y::Array{T}, filename::String) = wavwrite(y, filename, nbits=sizeof(T)*8, compression=WAVE_FORMAT_IEEE_FLOAT)

end # module
