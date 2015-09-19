import Base.writemime
using Compat

type WAVArray{T,N}
    Fs::UInt32
    data::Array{T,N}
end

wavwrite(x::WAVArray, io::IO) = wavwrite(x.data, io; Fs=x.Fs)

function writemime(io::IO, ::MIME"text/html", x::WAVArray)
    buf = IOBuffer()
    wavwrite(x, buf)
    data = base64(bytestring(buf))
    markup = """<audio controls="controls" {autoplay}>
                <source src="data:audio/wav;base64,$data" type="audio/wav" />
                Your browser does not support the audio element.
                </audio>"""
    print(io, markup)
end
