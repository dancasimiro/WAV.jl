WAV.jl
======

This is a Julia package to read and write the WAV audio file format.

Installation
------------

    julia> Pkg.add("WAV")

Getting Started
---------------

WAV provides `wavread` and `wavwrite` commands to read and write WAV files. First, you need to load the WAV package by typing `using WAV`. You can copy an existing file with the following

```jlcon
julia> using WAV
julia> x = [0:7999]
julia> y = sin(2 * pi * x / 8000)
julia> wavwrite(y, "example.wav", Fs=8000)
julia> y, Fs = wavread("example.wav")
```

wavread
-------

This function reads the samples from a WAV file. The samples are converted to floating
point values in the range from -1.0 to 1.0 by default.

> function wavread(io::IO; subrange=Any, format="double")
> function wavread(filename::String; subrange=Any, format="double")

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
* ``extra``: Any additional bytes used to encode the samples (is always ``None``)

   The following functions are also defined to make this function compatible with MATLAB:

> wavread(filename::String, fmt::String) = wavread(filename, format=fmt)
> wavread(filename::String, N::Int) = wavread(filename, subrange=N)
> wavread(filename::String, N::Range1{Int}) = wavread(filename, subrange=N)
> wavread(filename::String, N::Int, fmt::String) = wavread(filename, subrange=N, format=fmt)
> wavread(filename::String, N::Range1{Int}, fmt::String) = wavread(filename, subrange=N, format=fmt)

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

> function wavwrite(samples::Array, io::IO; Fs=8000, nbits=16, compression=WAVE_FORMAT_PCM)
> function wavwrite(samples::Array, filename::String; Fs=8000, nbits=16, compression=WAVE_FORMAT_PCM)

The available options, and the default values, are:

   * ``Fs`` (default = ``8000``): sampling frequency
   * ``nbits`` (default = ``16``): number of bits used to encode each
     sample
   * ``compression (default = ``WAV_FORMAT_PCM``)``: controls the type of encoding used in the file

The type of the input array, samples, also affects the generated
file. "Native" WAVE files are written when integers are passed into
wavwrite. This means that the literal values are written into the
file. The input ranges are as follows for integer samples.

======       ===========     ======================   =============
N Bits       y Data Type     y Data Range             Output Format
======       ===========     ======================   =============
8            uint8           0 <= y <= 255            uint8
16           int16           –32768 <= y <= +32767    int16
24           int32           –2^23 <= y <= 2^23 – 1   int32
======       ===========     ======================   =============

If samples contains floating point values, the input data ranges
are the following.

======    ================   =================   =============
N Bits    y Data Type        y Data Range        Output Format
======    ================   =================   =============
8         single or double   –1.0 <= y < +1.0    uint8
16        single or double   –1.0 <= y < +1.0    int16
24        single or double   –1.0 <= y < +1.0    int32
32        single or double   –1.0 <= y <= +1.0   single
======    ================   =================   =============

The following functions are also defined to make this function
compatible with MATLAB:

> wavwrite(y::Array, f::Real, filename::String) = wavwrite(y, filename, Fs=f)
> wavwrite(y::Array, f::Real, N::Real, filename::String) = wavwrite(y, filename, Fs=f, nbits=N)
> wavwrite{T<:Integer}(y::Array{T}, io::IO) = wavwrite(y, io, nbits=sizeof(T)*8)
> wavwrite{T<:Integer}(y::Array{T}, filename::String) = wavwrite(y, filename, nbits=sizeof(T)*8)
> wavwrite(y::Array{Int32}, io::IO) = wavwrite(y, io, nbits=24)
> wavwrite(y::Array{Int32}, filename::String) = wavwrite(y, filename, nbits=24)
> wavwrite{T<:FloatingPoint}(y::Array{T}, io::IO) = wavwrite(y, io, nbits=sizeof(T)*8, compression=WAVE_FORMAT_IEEE_FLOAT)
> wavwrite{T<:FloatingPoint}(y::Array{T}, filename::String) = wavwrite(y, filename, nbits=sizeof(T)*8, compression=WAVE_FORMAT_IEEE_FLOAT)
