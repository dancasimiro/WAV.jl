using FileIO
import FileIO.load
import FileIO.save

function load(s::Stream{format"WAV"})
    seek(s, 0)
    wavread(s)
end

function save(f::File{format"WAV"}, data; fs=44100)
    wavwrite(data, fs, f)
end
