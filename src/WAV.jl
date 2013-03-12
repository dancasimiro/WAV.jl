# -*- mode: julia; -*-
require("Options")

module WAV
using OptionsMod

export wavread, wavwrite, WAVE_FORMAT_PCM, WAVE_FORMAT_IEEE_FLOAT, WAVE_FORMAT_ALAW, WAVE_FORMAT_MULAW
import Base.unbox, Base.box

# The WAV specification states that numbers are written to disk in little endian form.
write_le(stream::IO, value::Uint8) = write(stream, value)

function write_le(stream::IO, value::Uint16)
    write(stream, uint8((value & 0x00ff)     ))
    write(stream, uint8((value & 0xff00) >> 8))
end

function write_le(stream::IO, value::Uint32)
    write(stream, uint8((value & 0x000000ff)      ))
    write(stream, uint8((value & 0x0000ff00) >>  8))
    write(stream, uint8((value & 0x00ff0000) >> 16))
    write(stream, uint8((value & 0xff000000) >> 24))
end

function write_le(stream::IO, value::Uint64)
    write(stream, uint8((value & 0x00000000000000ff)      ))
    write(stream, uint8((value & 0x000000000000ff00) >>  8))
    write(stream, uint8((value & 0x0000000000ff0000) >> 16))
    write(stream, uint8((value & 0x00000000ff000000) >> 24))
    write(stream, uint8((value & 0x000000ff00000000) >> 32))
    write(stream, uint8((value & 0x0000ff0000000000) >> 40))
    write(stream, uint8((value & 0x00ff000000000000) >> 48))
    write(stream, uint8((value & 0xff00000000000000) >> 56))
end

write_le(stream::IO, value::Int16) = write_le(stream, uint16(value))
write_le(stream::IO, value::Int32) = write_le(stream, uint32(value))
write_le(stream::IO, value::Int64) = write_le(stream, uint64(value))
write_le(stream::IO, value::Float32) = write_le(stream, box(Uint32, unbox(Float32, value)))
write_le(stream::IO, value::Float64) = write_le(stream, box(Uint64, unbox(Float64, value)))

read_le(stream::IO, x::Type{Uint8}) = read(stream, x)

function read_le(stream::IO, ::Type{Uint16})
    bytes = uint16(read(stream, Uint8, 2))
    (bytes[2] << 8) | bytes[1]
end

function read_le(stream::IO, ::Type{Uint32})
    bytes = uint32(read(stream, Uint8, 4))
    (bytes[4] << 24) | (bytes[3] << 16) | (bytes[2] << 8) | bytes[1]
end

function read_le(stream::IO, ::Type{Uint64})
    bytes = uint64(read(stream, Uint8, 8))
    (bytes[8] << 56) | (bytes[7] << 48) | (bytes[6] << 40) | (bytes[5] << 32) | (bytes[4] << 24) | (bytes[3] << 16) | (bytes[2] << 8) | bytes[1]
end

read_le(stream::IO, ::Type{Int16}) = int16(read_le(stream, Uint16))
read_le(stream::IO, ::Type{Int32}) = int32(read_le(stream, Uint32))
read_le(stream::IO, ::Type{Int64}) = int64(read_le(stream, Uint64))
read_le(stream::IO, ::Type{Float32}) = box(Float32, unbox(Uint32, read_le(stream, Uint32)))
read_le(stream::IO, ::Type{Float64}) = box(Float64, unbox(Uint64, read_le(stream, Uint64)))

# Required WAV Chunk; The format chunk describes how the waveform data is stored
type WAVFormat
    compression_code::Uint16
    nchannels::Uint16
    sample_rate::Uint32
    bps::Uint32 # average bytes per second
    block_align::Uint16
    nbits::Uint16
    extra_bytes::Array{Uint8}

    data_length::Uint32
end
WAVFormat() = WAVFormat(uint16(0), uint16(0), uint32(0), uint32(0), uint16(0), uint16(0), Array(Uint8), uint32(0))
WAVFormat(comp, chan, fs, bytes, ba, nbits) = WAVFormat(comp, chan, fs, bytes, ba, nbits, Array(Uint8), uint32(0))

const WAVE_FORMAT_PCM        = 0x0001 # PCM
const WAVE_FORMAT_IEEE_FLOAT = 0x0003 # IEEE float
const WAVE_FORMAT_ALAW       = 0x0006 # A-Law
const WAVE_FORMAT_MULAW      = 0x0007 # Mu-Law
const WAVE_FORMAT_EXTENSIBLE = 0xfffe # Extension!

# used by WAVE_FORMAT_EXTENSIBLE
type WAVFormatExtension
    valid_bits_per_sample::Uint16
    channel_mask::Uint32
    sub_format::Array{Uint8} # 16 byte GUID
end
WAVFormatExtension() = WAVFormatExtension(uint16(0), uint32(0), b"")

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

function WAVFormatExtension(bytes::Array{Uint8})
    if length(bytes) != 22
        error("There are not the right number of bytes for the WAVFormat Extension")
    end
    # split bytes into valid_bits_per_sample, channel_mask, and sub_format
    # little endian...
    valid_bits_per_sample = (uint16(bytes[2]) << 8) | uint16(bytes[1])
    channel_mask = (uint32(bytes[6]) << 24) | (uint32(bytes[5]) << 16) | (uint32(bytes[4]) << 8) | uint32(bytes[3])
    sub_format = bytes[7:]
    return WAVFormatExtension(valid_bits_per_sample, channel_mask, sub_format)
end

function read_header(io::IO)
    # check if the given file has a valid RIFF header
    riff = read(io, Uint8, 4)
    if riff !=  b"RIFF"
        error("$filename is not a valid WAV file: The RIFF header is invalid")
    end

    chunk_size = read_le(io, Uint32)

    # check if this is a WAV file
    format = read(io, Uint8, 4)
    if format != b"WAVE"
        error("$filename is not a valid WAV file: the format is not WAVE")
    end
    return chunk_size
end

function write_header(io::IO, fmt::WAVFormat)
    write(io, b"RIFF") # RIFF header
    write_le(io, uint32(36 + fmt.data_length)) # chunk_size
    write(io, b"WAVE")
end

function write_header(io::IO, fmt::WAVFormat, ext_fmt::WAVFormatExtension)
    write(io, b"RIFF") # RIFF header
    write_le(io, uint32(60 + fmt.data_length)) # chunk_size
    write(io, b"WAVE")
end

function read_format(io::IO, chunk_size::Uint32)
    # can I read in all of the fields at once?
    orig_chunk_size = int(chunk_size)
    if chunk_size < 16 
        error("The WAVE Format chunk must be at least 16 bytes") 
    end 
    format = WAVFormat(read_le(io, Uint16), # Compression Code 
                       read_le(io, Uint16), # Number of Channels 
                       read_le(io, Uint32), # Sample Rate 
                       read_le(io, Uint32), # bytes per second 
                       read_le(io, Uint16), # block align 
                       read_le(io, Uint16)) # bits per sample 
    chunk_size -= 16
    if chunk_size > 0
        # TODO add error checking for size mismatches 
        extra_bytes = read_le(io, Uint16)
        format.extra_bytes = read(io, Uint8, extra_bytes)
    end
    return format 
end

function write_format(io::IO, fmt::WAVFormat, ext_length::Integer)
    # write the fmt subchunk header
    write(io, b"fmt ")
    write_le(io, uint32(16 + ext_length)) # subchunk length; 16 is size of base format chunk

    write_le(io, fmt.compression_code) # audio format (Uint16)
    write_le(io, fmt.nchannels) # number of channels (Uint16)
    write_le(io, fmt.sample_rate) # sample rate (Uint32)
    write_le(io, fmt.bps) # byte rate (Uint32)
    write_le(io, fmt.block_align) # byte align (Uint16)
    write_le(io, fmt.nbits) # number of bits per sample (UInt16)
end
write_format(io::IO, fmt::WAVFormat) = write_format(io, fmt, 0)

function write_format(io::IO, fmt::WAVFormat, ext::WAVFormatExtension)
    write_format(io, fmt, 24) # 24 is the added length needed to encode the extension
    write_le(io, uint16(22))
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
    return  Uint8
end

ieee_float_container_type(nbits::Unsigned) = (nbits == 32 ? Float32 : (nbits == 64 ? Float64 : error("$nbits bits is not supported for WAVE_FORMAT_IEEE_FLOAT.")))

function read_pcm_samples(io::IO, chunk_size::Unsigned, fmt::WAVFormat)
    const nblocks = uint(chunk_size / fmt.block_align) # each block stores fmt.nchannels channels
    samples = Array(pcm_container_type(fmt.nbits), nblocks, fmt.nchannels)
    const nbytes = iceil(fmt.nbits / 8)
    const bitshift = linspace(0, 64, 9)
    const mask = unsigned(1) << (fmt.nbits - 1)
    const signextend_mask = ~unsigned(0) << fmt.nbits
    for i = 1:size(samples, 1)
        for j = 1:size(samples, 2)
            raw_sample = read(io, Uint8, nbytes)
            my_sample = uint64(0)
            for k = 1:nbytes
                my_sample |= uint64(raw_sample[k]) << bitshift[k]
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

function read_ieee_float_samples(io::IO, chunk_size::Unsigned, fmt::WAVFormat)
    const nblocks = uint(chunk_size / fmt.block_align) # each block stores fmt.nchannels channels
    const floatType = ieee_float_container_type(fmt.nbits)
    samples = Array(floatType, nblocks, fmt.nchannels)
    for i = 1:nblocks
        for j = 1:fmt.nchannels
            samples[i, j] = read_le(io, floatType)
        end
    end
    samples
end

function read_mulaw_samples(io::IO, chunk_size::Unsigned, fmt::WAVFormat)
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
    linspace(-8159, -4064, 16);
    linspace(-3935, -2016, 16);
    linspace(-1951,  -992, 16);
    linspace( -959,  -480, 16);
    linspace( -463,  -224, 16);
    linspace( -215,   -96, 16);
    linspace(  -91,   -32, 16);
    linspace(  -29,    -2, 15);
    -1;
    0;
    linspace(    3,    30, 15);
    linspace(   35,    94, 16);
    linspace(  103,   222, 16);
    linspace(  223,   478, 16);
    linspace(  479,   990, 16);
    linspace(  991,  2014, 16);
    linspace( 2015,  4062, 16);
    linspace( 4063,  8158, 16);
     ]
    @assert length(MuLawDecompressTable) == 256
    nsamples = uint(chunk_size / fmt.block_align)
    nblocks = uint(nsamples * fmt.nchannels)
    blocks = read(io, Uint8, nblocks)
    samples = zeros(Int16, nsamples, fmt.nchannels)
    for i = 1:nsamples
        for j = 1:fmt.nchannels
            samples[i, j] = MuLawDecompressTable[clamp(blocks[(i - 1) * fmt.nchannels + j] + 1, 1, 256)]
        end
    end
    return samples
end

function read_alaw_samples(io::IO, chunk_size::Unsigned, fmt::WAVFormat)
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
    nsamples = uint(chunk_size / fmt.block_align)
    nblocks = uint(nsamples * fmt.nchannels)
    blocks = read(io, Uint8, nblocks)
    samples = zeros(Int16, nsamples, fmt.nchannels)
    for i = 1:nsamples
        for j = 1:fmt.nchannels
            index = int(blocks[(i - 1) * fmt.nchannels + j] + 1)
            # add one to value from blocks because A-law stores values from 0 to 255.
            # Julia indexing is 1-based; I need a value from 1 to 256
            samples[i, j] = ALawDecompressTable[clamp(blocks[(i - 1) * fmt.nchannels + j] + 1, 1, 256)]
        end
    end
    return samples
end

#function write_mulaw_samples(io::IO, chunk_size::Unsigned, fmt::WAVFormat)
#    const cBias = 0x84
#    const cClip = 32635
#
#    const MuLawCompressTable =
#    [
#    0,0,1,1,2,2,2,2,3,3,3,3,3,3,3,3,
#    4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,
#    5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,
#    5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,
#    6,6,6,6,6,6,6,6,6,6,6,6,6,6,6,6,
#    6,6,6,6,6,6,6,6,6,6,6,6,6,6,6,6,
#    6,6,6,6,6,6,6,6,6,6,6,6,6,6,6,6,
#    6,6,6,6,6,6,6,6,6,6,6,6,6,6,6,6,
#    7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,
#    7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,
#    7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,
#    7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,
#    7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,
#    7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,
#    7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,
#    7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7
#     ]
#
#    sign = (sample >> 8) & 0x80;
#    if sign
#        sample = (short)-sample
#    end
#    if sample > cClip
#        sample = cClip
#    end
#    sample = (short)(sample + cBias)
#    exponent = (int)MuLawCompressTable[(sample>>7) & 0xFF];
#    mantissa = (sample >> (exponent+3)) & 0x0F
#    compressedByte = ~ (sign | (exponent << 4) | mantissa)
#
#    return (unsigned char)compressedByte
#end

# PCM data is two's-complement except for resolutions of 1-8 bits, which are represented as offset binary.

# support every bit width from 1 to 8 bits
convert_pcm_to_double(samples::Array{Uint8}, nbits::Integer) = convert(Array{Float64}, samples) / (2^nbits - 1) * 2.0 - 1.0
convert_pcm_to_double(samples::Array{Int8}, nbits::Integer) = error("WAV files use offset binary for less than 9 bits")
# support every bit width from 9 to 64 bits
convert_pcm_to_double{T<:Signed}(samples::Array{T}, nbits::Integer) = convert(Array{Float64}, samples) / (2^(nbits - 1) - 1)

function read_data(io::IO, chunk_size::Uint32, fmt::WAVFormat, opts::Options)
    @defaults opts format="double"
    samples = None
    convert_to_double = x -> convert(Array{Float64}, x)
    if fmt.compression_code == WAVE_FORMAT_EXTENSIBLE
        ext_fmt = WAVFormatExtension(fmt.extra_bytes)
        if ext_fmt.sub_format == KSDATAFORMAT_SUBTYPE_PCM
            fmt.nbits = ext_fmt.valid_bits_per_sample
            samples = read_pcm_samples(io, chunk_size, fmt)
            convert_to_double = x -> convert_pcm_to_double(x, fmt.nbits)
        elseif ext_fmt.sub_format == KSDATAFORMAT_SUBTYPE_IEEE_FLOAT
            fmt.nbits = ext_fmt.valid_bits_per_sample
            samples = read_ieee_float_samples(io, chunk_size, fmt)
        else
            error("$ext_fmt -- WAVE_FORMAT_EXTENSIBLE Not done yet!")
        end
    elseif fmt.compression_code == WAVE_FORMAT_PCM
        samples = read_pcm_samples(io, chunk_size, fmt)
        convert_to_double = x -> convert_pcm_to_double(x, fmt.nbits)
    elseif fmt.compression_code == WAVE_FORMAT_IEEE_FLOAT
        samples = read_ieee_float_samples(io, chunk_size, fmt)
    elseif fmt.compression_code == WAVE_FORMAT_MULAW
        samples = read_mulaw_samples(io, chunk_size, fmt)
    elseif fmt.compression_code == WAVE_FORMAT_ALAW
        samples = read_alaw_samples(io, chunk_size, fmt)
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
    const nbytes = iceil(fmt.nbits / 8)
    const bitshift = linspace(0, 64, 9)
    const minval = fmt.nbits > 8 ? -2^(fmt.nbits - 1) : -2^(fmt.nbits)
    const maxval = fmt.nbits > 8 ? 2^(fmt.nbits - 1) - 1 : 2^(fmt.nbits) - 1
    for i = 1:size(samples, 1)
        for j = 1:size(samples, 2)
            my_sample = clamp(samples[i, j], minval, maxval)
            # shift my_sample into the N most significant bits
            my_sample <<= nbytes * 8 - fmt.nbits
            mask = uint64(0xff)
            for k = 1:nbytes
                write_le(io, uint8((my_sample & mask) >> bitshift[k]))
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
        samples = convert(Array{Uint8}, round((samples + 1.0) / 2.0 * (2^fmt.nbits - 1)))
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
        else
            error("$ext_fmt -- WAVE_FORMAT_EXTENSIBLE Not done yet!")
        end
    elseif fmt.compression_code == WAVE_FORMAT_PCM
        return write_pcm_samples(io, fmt, samples)
    elseif fmt.compression_code == WAVE_FORMAT_IEEE_FLOAT
        return write_ieee_float_samples(io, fmt, samples)
    else
        error("$(fmt.compression_code) is an unsupported compression code.")
    end
end

get_data_range(samples::Array, subrange) = samples
get_data_range(samples::Array, subrange::Int) = samples[1:subrange, :]
get_data_range(samples::Array, subrange::Real) = samples[1:convert(Int, subrange), :]
get_data_range(samples::Array, subrange::Range1{Int}) = samples[subrange, :]
get_data_range(samples::Array, subrange::Range1{Real}) = samples[convert(Range1{Int}, subrange), :]

function wavread(io::IO, opts::Options)
    @defaults opts subrange=Any format="double"
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
        subchunk_id = read(io, Uint8, 4)
        subchunk_size = read_le(io, Uint32)
        chunk_size -= 8 + subchunk_size
        # check the subchunk ID
        if subchunk_id == b"fmt "
            fmt = read_format(io, subchunk_size)
        elseif subchunk_id == b"data"
            if format == "size"
                @check_used opts
                return int(subchunk_size / fmt.block_align), int(fmt.nchannels)
            end
            samples = read_data(io, subchunk_size, fmt, opts)
        else
            # return unknown sub-chunks?
            # Note: Ignoring unknown sub chunks for now
            skip(io, subchunk_size)
        end
    end
    samples = get_data_range(samples, subrange)
    @check_used opts
    return samples, fmt.sample_rate, fmt.nbits, None
end

function wavread(filename::String, opts::Options)
    @defaults opts subrange=Any format="double"
    io = open(filename, "r")
    finalizer(io, close)
    @check_used opts
    return wavread(io, opts)
end

# These are the MATLAB compatible signatures
wavread(filename::String) = wavread(filename, @options)
wavread(io::IO) = wavread(io, @options)
wavread(filename::String, fmt::String) = wavread(filename, @options format=fmt)
wavread(filename::String, N::Int) = wavread(filename, @options subrange=N)
wavread(filename::String, N::Range1{Int}) = wavread(filename, @options subrange=N)
wavread(filename::String, N::Int, fmt::String) = wavread(filename, @options subrange=N format=fmt)
wavread(filename::String, N::Range1{Int}, fmt::String) = wavread(filename, @options subrange=N format=fmt)

function wavwrite(samples::Array, io::IO, opts::Options)
    @defaults opts Fs=8000 nbits=16 compression=WAVE_FORMAT_PCM
    fmt = WAVFormat()
    fmt.compression_code = compression
    fmt.nchannels = size(samples, 2)
    fmt.sample_rate = Fs
    fmt.nbits = iceil(nbits / 8) * 8
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
        else
            error("Unsupported extension sub format.")
        end
        write_header(io, fmt, ext)
        write_format(io, fmt, ext)
    else
        write_header(io, fmt)
        write_format(io, fmt)
    end

    # write the data subchunk header
    write(io, b"data")
    write_le(io, fmt.data_length) # Uint32
    write_data(io, fmt, ext, samples)

    # The file is not flushed unless I explicitly call it here
    flush(io)
    @check_used opts
end

function wavwrite(samples::Array, filename::String, opts::Options)
    @defaults opts Fs=8000 nbits=16 compression=WAVE_FORMAT_PCM
    io = open(filename, "w")
    finalizer(io, close)
    @check_used opts
    return wavwrite(samples, io, opts)
end

wavwrite(y::Array, filename::String) = wavwrite(y, filename, @options)
wavwrite(y::Array, io::IO) = wavwrite(y, io, @options)
wavwrite(y::Array, f::Real, filename::String) = wavwrite(y, filename, @options Fs=f)
wavwrite(y::Array, f::Real, N::Real, filename::String) = wavwrite(y, filename, @options Fs=f nbits=N)

# support for writing native arrays...
wavwrite{T<:Integer}(y::Array{T}, io::IO) = wavwrite(y, io, @options nbits=sizeof(T)*8)
wavwrite{T<:Integer}(y::Array{T}, filename::String) = wavwrite(y, filename, @options nbits=sizeof(T)*8)
wavwrite(y::Array{Int32}, io::IO) = wavwrite(y, io, @options nbits=24)
wavwrite(y::Array{Int32}, filename::String) = wavwrite(y, filename, @options nbits=24)
wavwrite{T<:FloatingPoint}(y::Array{T}, io::IO) = wavwrite(y, io, @options nbits=sizeof(T)*8 compression=WAVE_FORMAT_IEEE_FLOAT)
wavwrite{T<:FloatingPoint}(y::Array{T}, filename::String) = wavwrite(y, filename, @options nbits=sizeof(T)*8 compression=WAVE_FORMAT_IEEE_FLOAT)

end # module
