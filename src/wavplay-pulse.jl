# -*- mode: julia; -*-
immutable PulseSample
    format::Int32
    rate::Uint32
    channels::Uint8
end

wavplay(fname) = wavplay(wavread(fname)...)

function wavplay(data, Fs, args...)
    ss = PulseSample(5,Fs,size(data,2))
    data = convert(Array{Float32}, data)

    err = Cint[0]
    s = ccall((:pa_simple_new, "libpulse-simple"), 
        Ptr{Void}, (Ptr{Void}, Ptr{Uint8}, Cint, Ptr{Void}, Ptr{Uint8}, 
        Ptr{PulseSample}, Ptr{Void}, Ptr{Void}, Ptr{Cint}), 
        0,"hey",1,0,"playback",&ss,0,0,err)
    assert(s != C_NULL)


    assert(0 == ccall((:pa_simple_write, "libpulse-simple"), Int32, 
        (Ptr{Void}, Ptr{Void}, Cssize_t, Ptr{Cint}),
        s, data, sizeof(data), err))

    assert(0 == ccall((:pa_simple_drain, "libpulse-simple"), Int32, 
        (Ptr{Void}, Ptr{Cint}), s, err))
    nothing
end
