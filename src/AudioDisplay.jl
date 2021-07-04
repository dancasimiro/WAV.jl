import Base.show
using Base64: base64encode

struct WAVArray{T,N}
    Fs::Number
    data::AbstractArray{T,N}
    caption::AbstractString
end

WAVArray(Fs::Number, data::AbstractArray) = WAVArray(Fs, data, "")

function WAVArray(io::IO, caption::AbstractString; subrange=(:), format="double")
    data, Fs = wavread(io, subrange=subrange, format=format)
    return WAVArray(Fs, data, caption)
end

WAVArray(io::IO; subrange=(:), format="double") = WAVArray(io::IO, ""; subrange=subrange, format=format)

function WAVArray(filename::AbstractString, caption::AbstractString; subrange=(:), format="double")
    data, Fs = wavread(filename, subrange=subrange, format=format)
    return WAVArray(Fs, data, caption)
end

WAVArray(filename::AbstractString; subrange=(:), format="double") = WAVArray(filename, ""; subrange=subrange, format=format)

wavwrite(x::WAVArray, io::IO) = wavwrite(x.data, io; Fs=x.Fs)

function show(io::IO, ::MIME"text/html", x::WAVArray)
    buf = IOBuffer()
    wavwrite(x, buf)
    data = base64encode(String(take!(copy(buf))))
    markup = """<figure>
                $(ifelse(x.caption !== "", "<figcaption>$(x.caption)</figcaption>", ""))
                    <audio controls="controls" {autoplay}>
                    <source src="data:audio/wav;base64,$data" type="audio/wav" />
                    Your browser does not support the audio element.
                    </audio>
                </figure>"""
    print(io, markup)
end
