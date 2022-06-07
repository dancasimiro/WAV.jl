WAV.jl
======

[![Build status](https://github.com/dancasimiro/WAV.jl/workflows/CI/badge.svg)](https://github.com/dancasimiro/WAV.jl/actions)
[![codecov](https://codecov.io/gh/dancasimiro/WAV.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/dancasimiro/WAV.jl)

This is a Julia package to read and write the [WAV audio file
format](https://en.wikipedia.org/wiki/WAV).

WAV provides `wavread`, `wavwrite` and `wavappend` functions to read,
write, and append to WAV files. The function `wavplay` provides simple
audio playback.

These functions behave similarly to the former MATLAB functions of the
same name.

Installation
------------

    julia> ]
    pkg> add WAV

Getting Started
---------------

The following example generates waveform data for a one second long 1
kHz sine tone, at a sampling frequency of 8 kHz, writes it to a WAV
file and then reads the data back. It then appends a 2 kHz tone to the
same file and plays the result.

```julia
using WAV
fs = 8e3
t = 0.0:1/fs:prevfloat(1.0)
f = 1e3
y = sin.(2pi * f * t) * 0.1
wavwrite(y, "example.wav", Fs=fs)

y, fs = wavread("example.wav")
y = sin.(2pi * 2f * t) * 0.1
wavappend(y, "example.wav")

y, fs = wavread("example.wav")
wavplay(y, fs)
```

News
----

Experimental support for reading and writing ``CUE`` and ``INFO``
chunks has been added in version 1, via the functions `wav_cue_read`,
`wav_cue_write`, `wav_info_read`, `wav_info_write`. See their
respective help text for details.

Other Julia Audio Packages
--------------------------

[LibSndFile](https://github.com/JuliaAudio/LibSndFile.jl) is another
Julia audio file library. It supports more file formats (including
WAV), all based on
[libsndfile](http://www.mega-nerd.com/libsndfile/).  
[PortAudio](https://github.com/JuliaAudio/PortAudio.jl) provides a 
more powerful playback interface and even allows recording. 
