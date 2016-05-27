import Base.show
using Compat
import Compat.String

type WAVArray{T,N}
    Fs::Number
    data::AbstractArray{T,N}
end

wavwrite(x::WAVArray, io::IO) = wavwrite(x.data, io; Fs=x.Fs)

function show(io::IO, ::MIME"text/html", x::WAVArray)
    buf = IOBuffer()
    wavwrite(x, buf)
    data = base64encode(@compat String(buf))
    markup = """<audio controls="controls" {autoplay}>
                <source src="data:audio/wav;base64,$data" type="audio/wav" />
                Your browser does not support the audio element.
                </audio>"""
    print(io, markup)
end
