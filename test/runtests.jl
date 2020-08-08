## -*-Julia-*-
## Test suite for Julia's WAV module
import WAV
using Test

# These float array comparison functions are from dists.jl
function absdiff(current::AbstractArray{T}, target::AbstractArray{T}) where T <: Real
    @test all(size(current) == size(target))
    maximum(abs.(current - target))
end

function reldiff(current::T, target::T) where T <: Real
    abs.((current - target)/(bool(target) ? target : 1))
end

function reldiff(current::AbstractArray{T}, target::AbstractArray{T}) where T <: Real
    @test all(size(current) == size(target))
    maximum([reldiff(current[i], target[i]) for i in 1:numel(target)])
end

## example from README, modified to use an IO buffer
@testset "1" begin
    x = [0:7999;]
    y = sin.(2 * pi * x / 8000)
    io = IOBuffer()
    WAV.wavwrite(y, io, Fs=8000)
    seek(io, 0)
    y, Fs = WAV.wavread(io)
    y = cos.(2 * pi * x / 8000)
    WAV.wavappend(y, io)
    seek(io, 0)
    y, Fs = WAV.wavread(io)
end

@testset "2" begin
    x = [0:7999;]
    y = sin.(2 * pi * x / 8000)
    WAV.wavwrite(y, "example.wav", Fs=8000)
    y, Fs = WAV.wavread("example.wav")
    y = cos.(2 * pi * x / 8000)
    WAV.wavappend(y, "example.wav")
    y, Fs = WAV.wavread("example.wav")
    @test length(y) == (2 * length(x))
    rm("example.wav")
end

## default arguments, GitHub Issue #10
@testset "3" begin
    tmp=rand(Float32,(10,2))
    io = IOBuffer()
    WAV.wavwrite(tmp, io; nbits=32)
    seek(io, 0)
    y, fs, nbits, extra = WAV.wavread(io; format="native")
    @test typeof(y) == Array{Float32, 2}
    @test fs == 8000.0
    @test nbits == 32
    fmt = WAV.getformat(extra)
    @test WAV.isformat(fmt, WAV.WAVE_FORMAT_IEEE_FLOAT)
end

## malformed subchunk header, GitHub Issue #18
@testset "4" begin
    # Create a malformed WAV file
    samples = rand(Float32, (10, 1))
    io = IOBuffer()

    compression = WAV.get_default_compression(samples)
    nbits = WAV.get_default_precision(samples, compression)

    nchannels = size(samples, 2)
    sample_rate = 8000
    nbits = ceil(Integer, nbits / 8) * 8
    block_align = nbits / 8 * nchannels
    bps = sample_rate * block_align
    data_length::UInt32 = size(samples, 1) * block_align

    fmt = WAV.WAVFormat(compression,
                        nchannels,
                        sample_rate,
                        bps,
                        block_align,
                        nbits,
                        WAV.WAVFormatExtension())

    WAV.write_header(io, UInt32(data_length + 37)) # 37 instead of 36 is the broken part
    WAV.write_format(io, fmt)

    # write the data subchunk header
    WAV.write(io, b"data")
    WAV.write_le(io, data_length) # UInt32
    WAV.write_data(io, fmt, samples)

    seek(io, 0)
    y, fs, nbits, opt = WAV.wavread(io, format="native")
    @test fs == 8000
    @test nbits == 32
    fmt = WAV.getformat(opt)
    @test fmt.compression_code == compression
    @test fmt.nchannels == nchannels
    @test fmt.sample_rate == sample_rate
    @test fmt.bytes_per_second == bps
    @test fmt.block_align == block_align
    @test WAV.isformat(fmt, compression)
    @test WAV.bits_per_sample(fmt) == nbits
    @test samples == y
end

@testset "5" begin
    tmp=rand(Float64,(10,2))
    io = IOBuffer()
    WAV.wavwrite(tmp, io; nbits=64)
    seek(io, 0)
    y, fs, nbits, extra = WAV.wavread(io; format="native")
    @test typeof(y) == Array{Float64, 2}
    @test fs == 8000.0
    @test nbits == 64
    fmt = WAV.getformat(extra)
    @test WAV.isformat(fmt, WAV.WAVE_FORMAT_IEEE_FLOAT)
    @test WAV.isformat(fmt, WAV.WAVE_FORMAT_EXTENSIBLE)
end

@testset "6" begin
    tmp=rand(Float32,(10,2))
    io = IOBuffer()
    WAV.wavwrite(tmp, io; compression=WAV.WAVE_FORMAT_IEEE_FLOAT)
    seek(io, 0)
    y, fs, nbits, extra = WAV.wavread(io; format="native")
    @test typeof(y) == Array{Float32, 2}
    @test fs == 8000.0
    @test nbits == 32
    @test WAV.isformat(WAV.getformat(extra), WAV.WAVE_FORMAT_IEEE_FLOAT)
end

function testread(io, ::Type{T}, sz) where T <: Real
    a = Array{T}(undef, sz)
    read!(io, a)
    return a
end

@testset "7"  begin
## Test wavread and wavwrite
## Generate some wav files for writing and reading
for fs = (8000,11025,22050,44100,48000,96000,192000), nbits = (1,7,8,9,12,16,20,24,32,64), nsamples = [0; 10 .^ (1:4)], nchans = 1:4
    ## Test wav files
    ## The tolerance is based on the number of bits used to encode the file in wavwrite
    tol = 2.0 / (2.0^(nbits - 1))

    in_data = rand(nsamples, nchans)
    if nsamples > 0
        @test maximum(in_data) <= 1.0
        @test minimum(in_data) >= -1.0
    end
    io = IOBuffer()
    WAV.wavwrite(in_data, io, Fs=fs, nbits=nbits, compression=WAV.WAVE_FORMAT_PCM)
    file_size = position(io)

    ## Check for the common header identifiers
    seek(io, 0)
    @test testread(io, UInt8, 4) == b"RIFF"
    @test WAV.read_le(io, UInt32) == file_size - 8
    @test testread(io, UInt8, 4) == b"WAVE"

    ## Check that wavread works on the wavwrite produced memory
    seek(io, 0)
    sz = WAV.wavread(io, format="size")
    @test sz == (nsamples, nchans)

    seek(io, 0)
    out_data, out_fs, out_nbits, out_extra = WAV.wavread(io)
    @test length(out_data) == nsamples * nchans
    @test size(out_data, 1) == nsamples
    @test size(out_data, 2) == nchans
    @test typeof(out_data) == Array{Float64, 2}
    @test out_fs == fs
    @test out_nbits == nbits
    fmt = WAV.getformat(out_extra)
    @test WAV.bits_per_sample(fmt) == nbits
    @test WAV.isformat(fmt, WAV.WAVE_FORMAT_PCM)
    @test fmt.nchannels == nchans
    if nsamples > 0
        @test absdiff(out_data, in_data) < tol
    end
    if nchans > 2
        @test WAV.isformat(fmt, WAV.WAVE_FORMAT_EXTENSIBLE)
    end

    ## test the "subrange" option.
    if nsamples > 0
        seek(io, 0)
        # Don't convert to Int, test if passing a float (nsamples/2) behaves as expected
        subsamples = min(10, trunc(Int, nsamples / 2))
        out_data, out_fs, out_nbits, out_extra = WAV.wavread(io, subrange=subsamples)
        @test length(out_data) == subsamples * nchans
        @test size(out_data, 1) == subsamples
        @test size(out_data, 2) == nchans
        @test typeof(out_data) == Array{Float64, 2}
        @test out_fs == fs
        @test out_nbits == nbits
        fmt = WAV.getformat(out_extra)
        @test WAV.bits_per_sample(fmt) == nbits
        @test WAV.isformat(fmt, WAV.WAVE_FORMAT_PCM)
        @test fmt.nchannels == nchans
        @test absdiff(out_data, in_data[1:subsamples, :]) < tol

        seek(io, 0)
        sr = convert(Int, min(5, trunc(Int, nsamples / 2))):convert(Int, min(23, nsamples - 1))
        out_data, out_fs, out_nbits, out_extra = WAV.wavread(io, subrange=sr)
        @test length(out_data) == length(sr) * nchans
        @test size(out_data, 1) == length(sr)
        @test size(out_data, 2) == nchans
        @test typeof(out_data) == Array{Float64, 2}
        @test out_fs == fs
        @test out_nbits == nbits
        fmt = WAV.getformat(out_extra)
        @test WAV.bits_per_sample(fmt) == nbits
        @test WAV.isformat(fmt, WAV.WAVE_FORMAT_PCM)
        @test fmt.nchannels == nchans
        @test absdiff(out_data, in_data[sr, :]) < tol
    end
end
end

@testset "8" begin

## Test wavappend
x0=rand(2,3)
x1=rand(3,3)
x2=rand(4,3)
io = IOBuffer()
WAV.wavwrite(x0, io)
WAV.wavappend(x1, io)
WAV.wavappend(x2, io)
seek(io, 0)
x, fs, nbits, extra = WAV.wavread(io)
@test x == [x0; x1; x2]

## Test correct reading of 44-byte headers when using `wavappend()`
number_bits = 16
number_channels = 2
number_samples = 16000
sampling_frequency = 16000
x0 = rand(number_samples, number_channels)
x1 = rand(2*number_samples, number_channels)
io = IOBuffer()
### Write first chunk to wav-file
WAV.wavwrite(
    x0,
    io,
    Fs=sampling_frequency,
    nbits=number_bits,
    compression=WAV.WAVE_FORMAT_PCM)
seek(io, 4)
chunk_size_old = WAV.read_le(io, UInt32)
seek(io, 40)
data_length_old = WAV.read_le(io, UInt32)
### Append second chunk to wav-file
WAV.wavappend(
    x1,
    io)
seek(io, 4)
chunk_size_new = WAV.read_le(io, UInt32)
seek(io, 40)
data_length_new = WAV.read_le(io, UInt32)
### Compare data lengths.
data_length_old_in_samples =
    round(Int32, data_length_old/(number_channels*number_bits)*8)
data_length_new_in_samples =
    round(Int32, data_length_new/(number_channels*number_bits)*8)
@test data_length_new_in_samples == 3*data_length_old_in_samples
@test (chunk_size_new-36) == 3*(chunk_size_old-36)

## Test native encoding of 8 bits
for nchans = (1,2,4)
    in_data_8 = reshape(typemin(UInt8):typemax(UInt8), (trunc(Int, 256 / nchans), nchans))
    io = IOBuffer()
    WAV.wavwrite(in_data_8, io)

    seek(io, 0)
    out_data_8, fs, nbits, extra = WAV.wavread(io, format="native")
    @test fs == 8000
    @test nbits == 8
    fmt = WAV.getformat(extra)
    @test WAV.bits_per_sample(fmt) == nbits
    @test WAV.isformat(fmt, WAV.WAVE_FORMAT_PCM)
    @test fmt.nchannels == nchans
    @test in_data_8 == out_data_8
end

## Test native encoding of 16 bits
for nchans = (1,2,4)
    in_data_16 = reshape(typemin(Int16):typemax(Int16), (trunc(Int, 65536 / nchans), nchans))
    io = IOBuffer()
    WAV.wavwrite(in_data_16, io)

    seek(io, 0)
    out_data_16, fs, nbits, extra = WAV.wavread(io, format="native")
    @test fs == 8000
    @test nbits == 16
    fmt = WAV.getformat(extra)
    @test WAV.bits_per_sample(fmt) == nbits
    @test WAV.isformat(fmt, WAV.WAVE_FORMAT_PCM)
    @test fmt.nchannels == nchans
    @test in_data_16 == out_data_16
end

## Test native encoding of 24 bits
for nchans = (1,2,4)
    in_data_24 = convert(Array{Int32}, reshape(-63:64, trunc(Int, 128 / nchans), nchans))
    io = IOBuffer()
    WAV.wavwrite(in_data_24, io)

    seek(io, 0)
    out_data_24, fs, nbits, extra = WAV.wavread(io, format="native")
    @test fs == 8000
    @test nbits == 24
    fmt = WAV.getformat(extra)
    @test WAV.bits_per_sample(fmt) == nbits
    @test WAV.isformat(fmt, WAV.WAVE_FORMAT_PCM)
    @test fmt.nchannels == nchans
    @test in_data_24 == out_data_24
end

## Test encoding 32 bit values
for nchans = (1,2,4)
    in_data_single = convert(Array{Float32}, reshape(range(-1.0, stop=1.0, length=128), trunc(Int, 128 / nchans), nchans))
    io = IOBuffer()
    WAV.wavwrite(in_data_single, io)

    seek(io, 0)
    out_data_single, fs, nbits, extra = WAV.wavread(io, format="native")
    @test fs == 8000
    @test nbits == 32
    fmt = WAV.getformat(extra)
    @test WAV.bits_per_sample(fmt) == nbits
    @test WAV.isformat(fmt, WAV.WAVE_FORMAT_IEEE_FLOAT)
    @test fmt.nchannels == nchans
    @test in_data_single == out_data_single
end

## Test encoding 32 bit values outside the [-1, 1] range
for nchans = (1,2,4)
    nsamps = trunc(Int, 128 / nchans)
    in_data_single = convert(Array{Float32}, reshape(-63:64, nsamps, nchans))
    io = IOBuffer()
    WAV.wavwrite(in_data_single, io)

    seek(io, 0)
    out_data_single, fs, nbits, extra = WAV.wavread(io, format="native")
    @test fs == 8000
    @test nbits == 32
    fmt = WAV.getformat(extra)
    @test WAV.bits_per_sample(fmt) == nbits
    @test WAV.isformat(fmt, WAV.WAVE_FORMAT_IEEE_FLOAT)
    @test fmt.nchannels == nchans
    @test [in_data_single[i, j] for i = 1:nsamps, j = 1:nchans] == out_data_single
end

## Test encoding 64 bit values
for nchans = (1,2,4)
    in_data_single = convert(Array{Float64}, reshape(range(-1.0, stop=1.0, length=128), trunc(Int, 128 / nchans), nchans))
    io = IOBuffer()
    WAV.wavwrite(in_data_single, io)

    seek(io, 0)
    out_data_single, fs, nbits, extra = WAV.wavread(io, format="native")
    @test fs == 8000
    @test nbits == 64
    fmt = WAV.getformat(extra)
    @test WAV.bits_per_sample(fmt) == nbits
    @test fmt.nchannels == nchans
    @test WAV.isformat(fmt, WAV.WAVE_FORMAT_IEEE_FLOAT)
    @test in_data_single == out_data_single
end

## Test encoding 64 bit values outside the [-1, 1] range
for nchans = (1,2,4)
    nsamps = trunc(Int, 128 / nchans)
    in_data_single = convert(Array{Float64}, reshape(-63:64, nsamps, nchans))
    io = IOBuffer()
    WAV.wavwrite(in_data_single, io)

    seek(io, 0)
    out_data_single, fs, nbits, extra = WAV.wavread(io, format="native")
    @test fs == 8000
    @test nbits == 64
    fmt = WAV.getformat(extra)
    @test WAV.bits_per_sample(fmt) == nbits
    @test WAV.isformat(fmt, WAV.WAVE_FORMAT_IEEE_FLOAT)
    @test fmt.nchannels == nchans
    @test [in_data_single[i, j] for i = 1:nsamps, j = 1:nchans] == out_data_single
end

### Test A-Law and Mu-Law
for nbits = (8, 16), nsamples = [0; 10 .^ (1:4)], nchans = 1:4, fmt=(WAV.WAVE_FORMAT_ALAW, WAV.WAVE_FORMAT_MULAW)
    fs = 8000.0
    tol = 2.0 / (2.0^6)
    in_data = rand(nsamples, nchans)
    if nsamples > 0
        @test maximum(in_data) <= 1.0
        @test minimum(in_data) >= -1.0
    end
    io = IOBuffer()
    WAV.wavwrite(in_data, io, Fs=fs, nbits=nbits, compression=fmt)
    file_size = position(io)

    ## Check for the common header identifiers
    seek(io, 0)
    @test testread(io, UInt8, 4) == b"RIFF"
    @test WAV.read_le(io, UInt32) == file_size - 8
    @test testread(io, UInt8, 4) == b"WAVE"

    ## Check that wavread works on the wavwrite produced memory
    seek(io, 0)
    sz = WAV.wavread(io, format="size")
    @test sz == (nsamples, nchans)

    seek(io, 0)
    out_data, out_fs, out_nbits, out_extra = WAV.wavread(io)
    @test length(out_data) == nsamples * nchans
    @test size(out_data, 1) == nsamples
    @test size(out_data, 2) == nchans
    @test typeof(out_data) == Array{Float64, 2}
    @test out_fs == fs
    @test out_nbits == 8
    out_fmt = WAV.getformat(out_extra)
    @test WAV.bits_per_sample(out_fmt) == 8
    @test out_fmt.nchannels == nchans
    @test WAV.isformat(out_fmt, fmt)
    if nchans > 2
        @test WAV.isformat(out_fmt, WAV.WAVE_FORMAT_EXTENSIBLE)
    else
        @test !WAV.isformat(out_fmt, WAV.WAVE_FORMAT_EXTENSIBLE)
    end
    if nsamples > 0
        @test absdiff(out_data, in_data) < tol
    end

    ## test the "subrange" option.
    if nsamples > 0
        seek(io, 0)
        # Don't convert to Int, test if passing a float (nsamples/2) behaves as expected
        subsamples = min(10, trunc(Int, nsamples / 2))
        out_data, out_fs, out_nbits, out_extra = WAV.wavread(io, subrange=subsamples)
        @test length(out_data) == subsamples * nchans
        @test size(out_data, 1) == subsamples
        @test size(out_data, 2) == nchans
        @test typeof(out_data) == Array{Float64, 2}
        @test out_fs == fs
        @test out_nbits == 8
        out_fmt = WAV.getformat(out_extra)
        @test WAV.bits_per_sample(out_fmt) == 8
        @test out_fmt.nchannels == nchans
        @test WAV.isformat(out_fmt, fmt)
        @test absdiff(out_data, in_data[1:subsamples, :]) < tol

        seek(io, 0)
        sr = convert(Int, min(5, trunc(Int, nsamples / 2))):convert(Int, min(23, nsamples - 1))
        out_data, out_fs, out_nbits, out_extra = WAV.wavread(io, subrange=sr)
        @test length(out_data) == length(sr) * nchans
        @test size(out_data, 1) == length(sr)
        @test size(out_data, 2) == nchans
        @test typeof(out_data) == Array{Float64, 2}
        @test out_fs == fs
        @test out_nbits == 8
        out_fmt = WAV.getformat(out_extra)
        @test WAV.bits_per_sample(out_fmt) == 8
        @test out_fmt.nchannels == nchans
        @test WAV.isformat(out_fmt, fmt)
        @test absdiff(out_data, in_data[sr, :]) < tol
    end
end

### Test float formatting
for nbits = (32, 64), nsamples = [0; 10 .^ (1:4)], nchans = 1:2, fmt=(WAV.WAVE_FORMAT_IEEE_FLOAT)
    fs = 8000.0
    tol = 1e-6
    in_data = rand(nsamples, nchans)
    if nsamples > 0
        @test maximum(in_data) <= 1.0
        @test minimum(in_data) >= -1.0
    end
    io = IOBuffer()
    WAV.wavwrite(in_data, io, Fs=fs, nbits=nbits, compression=fmt)
    file_size = position(io)

    ## Check for the common header identifiers
    seek(io, 0)
    @test testread(io, UInt8, 4) == b"RIFF"
    @test WAV.read_le(io, UInt32) == file_size - 8
    @test testread(io, UInt8, 4) == b"WAVE"

    ## Check that wavread works on the wavwrite produced memory
    seek(io, 0)
    sz = WAV.wavread(io, format="size")
    @test sz == (nsamples, nchans)

    seek(io, 0)
    out_data, out_fs, out_nbits, out_extra = WAV.wavread(io)
    @test length(out_data) == nsamples * nchans
    @test size(out_data, 1) == nsamples
    @test size(out_data, 2) == nchans
    @test typeof(out_data) == Array{Float64, 2}
    @test out_fs == fs
    @test out_nbits == nbits
    @test WAV.bits_per_sample(WAV.getformat(out_extra)) == nbits
    @test WAV.isformat(WAV.getformat(out_extra), WAV.WAVE_FORMAT_IEEE_FLOAT)
    @test WAV.getformat(out_extra).nchannels == nchans
    if nsamples > 0
        @test absdiff(out_data, in_data) < tol
    end

    ## test the "subrange" option.
    if nsamples > 0
        seek(io, 0)
        # Don't convert to Int, test if passing a float (nsamples/2) behaves as expected
        subsamples = min(10, trunc(Int, nsamples / 2))
        out_data, out_fs, out_nbits, out_extra = WAV.wavread(io, subrange=subsamples)
        @test length(out_data) == subsamples * nchans
        @test size(out_data, 1) == subsamples
        @test size(out_data, 2) == nchans
        @test typeof(out_data) == Array{Float64, 2}
        @test out_fs == fs
        @test out_nbits == nbits
        @test WAV.bits_per_sample(WAV.getformat(out_extra)) == nbits
        @test WAV.getformat(out_extra).nchannels == nchans
        @test WAV.isformat(WAV.getformat(out_extra), WAV.WAVE_FORMAT_IEEE_FLOAT)
        @test absdiff(out_data, in_data[1:subsamples, :]) < tol

        seek(io, 0)
        sr = convert(Int, min(5, trunc(Int, nsamples / 2))):convert(Int, min(23, nsamples - 1))
        out_data, out_fs, out_nbits, out_extra = WAV.wavread(io, subrange=sr)
        @test length(out_data) == length(sr) * nchans
        @test size(out_data, 1) == length(sr)
        @test size(out_data, 2) == nchans
        @test typeof(out_data) == Array{Float64, 2}
        @test out_fs == fs
        @test out_nbits == nbits
        @test WAV.bits_per_sample(WAV.getformat(out_extra)) == nbits
        @test WAV.isformat(WAV.getformat(out_extra), WAV.WAVE_FORMAT_IEEE_FLOAT)
        @test WAV.getformat(out_extra).nchannels == nchans
        @test absdiff(out_data, in_data[sr, :]) < tol
    end
end
end

### Read unknown chunks, GitHub Issue #50
@testset "9" begin
    fs = 8000.0
    in_data = rand(1024, 2)
    io = IOBuffer()
    in_chunks = [WAV.WAVChunk(:test, [0x1, 0x2, 0x3])]
    WAV.wavwrite(in_data, io, Fs=fs, chunks=in_chunks)

    seek(io, 0)
    data, fs, nbits, ext = WAV.wavread(io)

    @test findfirst(c -> c.id == :test, ext) > 0
    test_chunk = ext[findfirst(c -> c.id == :test, ext)]
    @test test_chunk.id == in_chunks[1].id
    @test test_chunk.data == in_chunks[1].data
    @test length(data) == length(in_data)
    @test isapprox(data, in_data; atol=1.0e-6)
end

### Multiple LIST chunks, GitHub Issue #55
@testset "10" begin
    fs = 8000.0
    in_data = rand(1024, 2)
    io = IOBuffer()
    in_chunks = [WAV.WAVChunk(:LIST, [0x1, 0x2, 0x3]), WAV.WAVChunk(:LIST, [0x4, 0x5, 0x6])]
    WAV.wavwrite(in_data, io, Fs=fs, chunks=in_chunks)

    seek(io, 0)
    data, fs, nbits, ext = WAV.wavread(io)

    @test length(findall(c -> c.id == :LIST, ext)) == length(in_chunks)
    list_chunks = ext[findall(c -> c.id == :LIST, ext)]
    for (c, i) in zip(list_chunks, in_chunks)
        @test c.id == i.id
        @test c.data == i.data
    end
    @test length(data) == length(in_data)
    @test isapprox(data, in_data; atol=1.0e-6)
end

# Test WAVMarker and WavChunk
@testset "11" begin
    io = IOBuffer()
    fs = 16000
    samples = rand(fs)
    markers = Dict{UInt32, WAV.WAVMarker}()
    markers[1] = WAV.WAVMarker("Foo", 42, 1337)
    markers[2] = WAV.WAVMarker("Bar", 1337, 42)

    marker_chunks = WAV.wav_cue_write(markers)

    title = "Never Gonna Give You Up"
    artist = "Rick Astley"
    tags = Dict{Symbol, String}()
    tags[:INAM] = title
    tags[:IART] = artist
    tag_chunks = WAV.wav_info_write(tags)

    out_chunks = [tag_chunks; marker_chunks]

    WAV.wavwrite(samples, io, Fs=fs, nbits=16, compression=WAV.WAVE_FORMAT_PCM, chunks=out_chunks)
    seek(io, 0)

    x, fs, bits, in_chunks = WAV.wavread(io)
    in_markers = WAV.wav_cue_read(in_chunks)

    @test length(in_markers) == length(markers)
    for k in keys(in_markers)
        @test in_markers[k].label == markers[k].label
        @test in_markers[k].start_time == markers[k].start_time
        @test in_markers[k].duration == markers[k].duration
    end

    in_info = WAV.wav_info_read(in_chunks)
    @test in_info[:INAM] == title
    @test in_info[:IART] == artist
end

### WAVArray
struct TestHtmlDisplay <: AbstractDisplay
    io::IOBuffer
end
function display(d::TestHtmlDisplay, mime::MIME"text/html", x)
    print(d.io, repr(mime, x))
end

@testset "12" begin
    io = IOBuffer()
    wa = WAV.WAVArray(8000, sin.(1:256 * 8000.0 / 1024));
    myio = IOBuffer()
    display(TestHtmlDisplay(myio), MIME"text/html"(), wa)
    @test occursin(r"audio controls", String(take!(copy(myio))))
end

### playback
if !haskey(ENV, "CI")
    @testset "13" begin
        fs = 44100.0
        t = 0.0:fs-1.0;
        left_data  = sin.(2pi * 500.0 * t / fs) * 1e-1;
        right_data = sin.(2pi * 800.0 * t / fs) * 1e-1;
        # 500 Hz mono
        @test WAV.wavplay(left_data, fs) === nothing;
        # 500 Hz left, 800 Hz right stereo
        @test WAV.wavplay([left_data right_data], fs) === nothing;
    end
end
