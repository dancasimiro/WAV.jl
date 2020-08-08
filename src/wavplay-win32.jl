# -*- mode: julia; -*-
module WAVPlay
import WAV: wavplay, wavwrite

# some standard Win32 API types and constants, see [MS-DTYP]
const BOOL = Cint
const DWORD = Culong
const TRUE = 1
# PlaySound flags from Winmm.h
const SND_SYNC      = 0x0
const SND_ASYNC     = 0x1
const SND_NODEFAULT = 0x2
const SND_MEMORY    = 0x4
const SND_FILENAME  = 0x20000

function wavplay(data, fs)
    # produce an in-memory WAV file ...
    buf=IOBuffer()
    wavwrite(data, buf, Fs=fs)
    wav = take!(buf)
    # ... and pass it to PlaySound
    success = ccall((:PlaySoundA, "Winmm.dll"), stdcall, BOOL,
                    (Ptr{Cvoid}, Ptr{Cvoid}, DWORD),
                    wav, C_NULL, SND_MEMORY | SND_SYNC | SND_NODEFAULT)
    Base.windowserror("PlaySound", success != TRUE)
end
end # module
