WAV.jl
======

[![WAV](http://pkg.julialang.org/badges/WAV_1.0.svg)](http://pkg.julialang.org/?pkg=WAV&ver=1.0)
[![Build Status](https://travis-ci.org/dancasimiro/WAV.jl.png)](https://travis-ci.org/dancasimiro/WAV.jl)
[![Windows Build Status](https://ci.appveyor.com/api/projects/status/github/dancasimiro/wav.jl?branch=master&svg=true)](https://ci.appveyor.com/project/dancasimiro/wav-jl)
[![Coverage Status](https://coveralls.io/repos/dancasimiro/WAV.jl/badge.png)](https://coveralls.io/r/dancasimiro/WAV.jl)

This is a Julia package to read and write the WAV audio file format.

Installation
------------

    julia> Pkg.add("WAV")

Getting Started
---------------

WAV provides `wavread`, `wavwrite`, and `wavappend` commands to read,
write, and append WAV files. Here is an example to get you started. It
generates some data, writes it to a file and then reads the data back.
`wavplay` is also provided for simple audio playback.

```jlcon
julia> using WAV
julia> x = [0:7999;]
julia> y = sin.(2 * pi * x / 8000)
julia> wavwrite(y, "example.wav", Fs=8000)
julia> y, fs = wavread("example.wav")
julia> y = cos.(2 * pi * x / 8000)
julia> wavappend(y, "example.wav")
julia> y, fs = wavread("example.wav")
julia> wavplay(y, fs)
```

wavread
-------

This function reads the samples from a WAV file. The samples are converted to floating
point values in the range from -1.0 to 1.0 by default.

```julia
function wavread(io::IO; subrange=Any, format="double")
function wavread(filename::String; subrange=Any, format="double")
```

The available options, and the default values, are:

* ``format`` (default = ``double``): changes the format of the returned samples. The string
  ``double`` returns double precision floating point values in the range -1.0 to 1.0. The string
  ``native`` returns the values as encoded in the file. The string ``size`` returns the number
  of samples in the file, rather than the actual samples.
* ``subrange`` (default = ``Any``): controls which samples are returned. The default, ``Any``
  returns all of the samples. Passing a number (``Real``), ``N``, will return the first ``N``
  samples of each channel. Passing a range (``Range1{Real}``), ``R``, will return the samples
  in that range of each channel.

The returned values are:

* ``y``: The acoustic samples; A matrix is returned for files that contain multiple channels.
* ``Fs``: The sampling frequency
* ``nbits``: The number of bits used to encode each sample
* ``opt``: A vector of ```WAVChunk``` of optional chunks found in the WAV file.

The elements in the ``opt`` vector depend on the contents
of the WAV file.

A ``WAVChunk`` is defined as
```julia
mutable struct WAVChunk
    id::Symbol
    data::Vector{UInt8}
end
```

where the ID is the four-character chunk ID. All valid WAV files will contain a ``fmt`` chunk,
with ID ``Symbol("fmt ")`` (note the trailing space).

In order to obtain the contents of the format chunk,
call ``getformat(opt)``. This will return an instance of type
``WAVFormat``. The ``WAVFormat`` type is defined as:

```julia
struct WAVFormat
    compression_code::UInt16
    nchannels::UInt16
    sample_rate::UInt32
    bytes_per_second::UInt32 # average bytes per second
    block_align::UInt16
    nbits::UInt16
    ext::WAVFormatExtension
end
```

The ```ext``` field of type ```WAVFormatExtension``` is defined as:

```julia
struct WAVFormatExtension
    nbits::UInt16 # overrides nbits in WAVFormat type
    channel_mask::UInt32
    sub_format::Array{UInt8, 1} # 16 byte GUID
    WAVFormatExtension() = new(0, 0, Array(UInt8, 0))
    WAVFormatExtension(nb, cm, sb) = new(nb, cm, sb)
end
```

You can use the ```isformat``` function to test how the samples are
encoded, without worrying about the ```WAVFormatExtension```
type. Extended WAV files were added to deal with some ambiguity in the
original specification.

```julia
isformat(fmt::WAVFormat, code)
```

The ```isformat``` function takes the ``WAVFormat`` object returned by
``getformat`` and one of ```WAV_FORMAT_```
constants, respectively. The function returns ```true``` when the
samples are encoded in the specified ```code```.

The following functions are also defined to make this function compatible with MATLAB:

```julia
wavread(filename::String, fmt::String) = wavread(filename, format=fmt)
wavread(filename::String, N::Int) = wavread(filename, subrange=N)
wavread(filename::String, N::Range1{Int}) = wavread(filename, subrange=N)
wavread(filename::String, N::Int, fmt::String) = wavread(filename, subrange=N, format=fmt)
wavread(filename::String, N::Range1{Int}, fmt::String) = wavread(filename, subrange=N, format=fmt)
```

wavwrite
--------

Writes samples to a RIFF/WAVE file io object. The ``io`` argument
accepts either an ``IO`` object or a filename (``String``). The
function assumes that the sample rate is 8 kHz and uses 16 bits to
encode each sample. Both of these values can be changed with the
options parameter. Each column of the data represents a different
channel. Stereo files should contain two columns. The options are
passed via an ``Options`` object (see the :ref:`options page
<options-module>`).

```julia
function wavwrite(samples::Array, io::IO; Fs=8000, nbits=16, compression=WAVE_FORMAT_PCM, chunks::Vector{WAVChunk}=WAVChunk[])
function wavwrite(samples::Array, filename::String; Fs=8000, nbits=16, compression=WAVE_FORMAT_PCM, chunks::Vector{WAVChunk}=WAVChunk[])
```

The available options, and the default values, are:

   * ``Fs`` (default = ``8000``): sampling frequency
   * ``nbits`` (default = ``16``): number of bits used to encode each
     sample
   * ``compression`` (default = ``WAV_FORMAT_PCM``): controls the type of encoding used in the file
   * ``chunks`` (default = ``WAVChunk[]``): a vector of ``WAVChunk`` objects to be written to the file (in addition to the format chunk). See below for some utilities for creating ``CUE`` and ``INFO``
   chunks.

The type of the input array, samples, also affects the generated
file. "Native" WAVE files are written when integers are passed into
wavwrite. This means that the literal values are written into the
file. The input ranges are as follows for integer samples.

| N Bits | y Data Type | y Data Range           | Output Format |
|--------|-------------|------------------------|---------------|
| 8      | uint8       | 0 <= y <= 255          | uint8         |
| 16     | int16       | –32768 <= y <= +32767  | int16         |
| 24     | int32       | –2^23 <= y <= 2^23 – 1 | int32         |

If samples contains floating point values, the input data ranges
are the following.

| N Bits | y Data Type      | y Data Range       | Output Format |
|--------|------------------|--------------------|---------------|
| 8      | single or double |  –1.0 <= y < +1.0  | uint8         |
| 16     | single or double |  –1.0 <= y < +1.0  | int16         |
| 24     | single or double |  –1.0 <= y < +1.0  | int32         |
| 32     | single or double |  –1.0 <= y <= +1.0 | single        |

Floating point (single and double precision) values are written to the
file unaltered. The library will not modify the data range or representation.

The following functions are also defined to make this function
compatible with MATLAB:

```julia
wavwrite(y::Array, f::Real, filename::String) = wavwrite(y, filename, Fs=f)
wavwrite(y::Array, f::Real, N::Real, filename::String) = wavwrite(y, filename, Fs=f, nbits=N)
wavwrite(y::Array{T}, io::IO) where {T<:Integer} = wavwrite(y, io, nbits=sizeof(T)*8)
wavwrite(y::Array{T}, filename::String) where {T<:Integer} = wavwrite(y, filename, nbits=sizeof(T)*8)
wavwrite(y::Array{Int32}, io::IO) = wavwrite(y, io, nbits=24)
wavwrite(y::Array{Int32}, filename::String) = wavwrite(y, filename, nbits=24)
wavwrite(y::Array{T}, io::IO) where {T<:FloatingPoint} = wavwrite(y, io, nbits=sizeof(T)*8, compression=WAVE_FORMAT_IEEE_FLOAT)
wavwrite(y::Array{T}, filename::String) where {T<:FloatingPoint} = wavwrite(y, filename, nbits=sizeof(T)*8, compression=WAVE_FORMAT_IEEE_FLOAT)
```

wavappend
---------

Append samples to an existing WAV file.  All parameters (data type and range, output format, number of bits, number of channels, etc.) are assumed to match.

```julia
function wavappend(samples::Array, io::IO)
function wavappend(samples::Array, filename::String)
```

wavplay
-------

Playing audio back is also supported. The supported backends are:
AudioQueue (MacOSX) and Pulse Audio (Linux, libpulse-simple). There is
not a native backend for Windows yet.

```julia
function wavplay(samples::Array, fs::Number)
```

WAVChunk
---

Experimental support for reading and writing ``CUE`` and ``INFO`` chunks has been added in
version 1. The function
```julia
wav_cue_read(chunks::Vector{WAVChunk})
```
takes a ``Vector{WAVChunk}`` (as returned by ``wavread``) and returns a ``Vector{WAVMarker}``,
where a ``WAVMarker`` is defined as:
```julia
mutable struct WAVMarker
    label::String
    start_time::UInt32
    duration::UInt32
end
```

Where ``start_time`` and ``duration`` are in samples.
You can also turn ``WAVMarker``s into a ``Vector{WAVChunk}`` (as accepted by ``wavwrite``) by calling
```julia
wav_cue_write(markers::Dict{UInt32, WAVMarker})
```
where the key for the dictionary is the ID of the marker to be written to file.

Similar functions exist for ``INFO`` chunks, namely
```julia
wav_info_write(tags::Dict{Symbol, String})::Vector{WAVChunk}
wav_info_read(chunks::Vector{WAVChunk})::Dict{Symbol, String}
```

where the keys for the ``Dict{Symbol, String}`` should be four-character RIFF INFO tag IDs as specified [here](https://www.sno.phy.queensu.ca/~phil/exiftool/TagNames/RIFF.html#Info). The values of the dictionary
correspond to the tag data.

Other Julia Audio Packages
-----------------------

[AudioIO](https://github.com/ssfrr/AudioIO.jl) is another audio
library in the Julia ecosystem. It supports more file formats
(including WAV) and implements a more powerful playback
interface. However, the license is more restrictive (GPL) because
of a dependence on [libsndfile](http://www.mega-nerd.com/libsndfile/).

Additionally, [FLAC.jl](https://github.com/dmbates/FLAC.jl) includes
an ```mmap``` based WAV [reader](https://github.com/dmbates/FLAC.jl/blob/master/src/WAV.jl).
