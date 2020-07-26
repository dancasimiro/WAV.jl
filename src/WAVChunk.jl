"""
`WAVChunk(id, data)` represents a RIFF chunk.
Symbol `id` is the four-character chunk ID.
"""
struct WAVChunk
    id::Symbol
    data::Vector{UInt8}
end

"""
A marker in a .wav file. `start_time` and `duration` are in samples.
"""
mutable struct WAVMarker
    label::String
    start_time::UInt32
    duration::UInt32
end

function read32(data0::UInt8, data1::UInt8, data2::UInt8, data3::UInt8)::UInt32
    UInt32(data0) | (UInt32(data1) << 8) | (UInt32(data2) << 16) | (UInt32(data3) << 24)
end

function write32(data::UInt32)::Vector{UInt8}
    [ UInt8((data>>0) & 0xff), UInt8((data>>8) & 0xff), UInt8((data>>16) & 0xff), UInt8((data>>24) & 0xff) ]
end

function write16(data::UInt16)::Vector{UInt8}
    [ UInt8((data>>0) & 0xff), UInt8((data>>8) & 0xff) ]
end

function read_adtl(markers::Dict{UInt32, WAVMarker}, adtl::Vector{UInt8})
    title  = String(adtl[1:4])
    size   = read32(adtl[5:8 ]...)
    cue_id = read32(adtl[9:12]...)

    # The adtl entry must have even length. Therefore, if the reported length
    # is odd, actually read an extra byte.
    if size % 2 == 1
        size += 1
    end

    marker = get(markers, cue_id, nothing)
    if marker == nothing
        marker = WAVMarker("", 0, 0)
        markers[cue_id] = marker
    end

    if title == "labl"
        i = 13;
        while (adtl[i] != 0)
            i += 1;
        end
        marker.label = String(adtl[13:(i-1)])
    elseif title == "ltxt"
        marker.duration = read32(adtl[13:16]...)
    end
    adtl[(size+5+4):end]
end

"""Read the contents of the LIST chunk to extract marker names and durations"""
function read_list(markers::Dict{UInt32, WAVMarker}, list::Vector{UInt8})
    if list[1:4] == b"adtl"
        adtl = list[5:end]
        while (length(adtl) >= 12)
            adtl = read_adtl(markers, adtl)
        end
    end
end

"""Read the contents of the cue chunk to extract marker start times"""
function read_cue(markers::Dict{UInt32, WAVMarker}, cue::Vector{UInt8})
    ncue = read32(cue[1:4]...)
    cue = cue[5:end]
    for i = 1:ncue
        cue_id = read32(cue[1:4]...)

        marker = get(markers, cue_id, nothing)
        if marker == nothing
            marker = WAVMarker("", 0, 0)
            markers[cue_id] = marker
        end
        marker.start_time = read32(cue[21:24]...)
        st = marker.start_time

        cue = cue[25:end]
    end
end

"""
    wav_cue_read(chunks::Vector{WAVChunk})

Takes a `Vector{WAVChunk}` (as returned by `wavread`) and returns
a `Vector{WAVMarker}`, where a `WAVMarker` is defined as:

```julia
mutable struct WAVMarker
    label::String
    start_time::UInt32
    duration::UInt32
end
```

Field values `start_time` and `duration` are in samples.

# Example
```julia
using WAV
x, fs, bits, in_chunks = wavread("in.wav")
markers = wav_cue_read(in_chunks)
```
"""
function wav_cue_read(chunks::Vector{WAVChunk})
    markers = Dict{UInt32, WAVMarker}()

    # See if list and cue chunks are present
    list_chunks = chunks[findall(c -> c.id == :LIST, chunks)]
    cue_chunks = chunks[findall(c -> c.id == Symbol("cue "), chunks)]

    for l in list_chunks
        read_list(markers, l.data)
    end

    for c in cue_chunks
        read_cue(markers, c.data)
    end

    markers
end

function write_cue(markers::Dict{UInt32, WAVMarker})
    cue = write32(UInt32(length(markers)))
    for (cue_id, marker) in markers
        cue =   [   cue;
                    write32(cue_id);
                    write32(marker.start_time);
                    b"data";
                    write32(UInt32(0));
                    write32(UInt32(0));
                    write32(marker.start_time)
                ]
    end
    cue
end

function write_marker_list(markers::Dict{UInt32, WAVMarker})
    list = b"adtl"

    # Create all the labl entries
    for (cue_id, marker) in markers
        labl = [write32(cue_id); codeunits(marker.label); 0x0]

        # The note and label entries must have an even number of bytes.
        # So, for the null terminated text in the label and note, we add a minimum of
        # one null terminator, but if that creates an odd number of bytes in the labl
        # or note entry, then add a second null terminator.
        if (length(labl) % 2) == 1
            labl = [labl; 0x0]
        end

        list = [list; b"labl"; write32(UInt32(length(labl))); labl]
    end

    # Create all the ltxt entries
    for (cue_id, marker) in markers
        ltxt =  [   write32(cue_id);
                    write32(marker.duration);
                    b"rgn ";
                    write16(UInt16(0)); # country
                    write16(UInt16(0)); # language
                    write16(UInt16(0)); # dialect
                    write16(UInt16(0))  # codepage
                ]
        list = [list; b"ltxt"; write32(UInt32(length(ltxt))); ltxt]
    end
    list
end

"""
    wav_info_write(tags::Dict{Symbol, String})::Vector{WAVChunk}

Converts a dictionary of INFO tags into a list of WAV chunks
appropriate for passing to `wavwrite`.

`tags` is a dictionary where the keys are symbols representing four-character
RIFF INFO tag IDs as specified in
https://www.sno.phy.queensu.ca/~phil/exiftool/TagNames/RIFF.html#Info
The values of the dictionary correspond to the tag data.
"""
function wav_info_write(tags::Dict{Symbol, String})
    info_data = b"INFO"

    # Create all the tag entries
    for t in keys(tags)
        tag = [codeunits(tags[t]); 0x0]

        # The tag entries must have an even number of bytes.
        # So, for the null terminated text in the tag, we add a minimum of
        # one null terminator, but if that creates an odd number of bytes in the tag
        # or note entry, then add a second null terminator.
        if (length(tag) % 2) == 1
            tag = [tag; 0x0]
        end

        info_data = [info_data; codeunits(String(t)); write32(UInt32(length(tag))); tag]
    end
    [WAVChunk(:LIST, info_data)]
end

function read_tag(tags::Dict{Symbol, String}, t::Vector{UInt8})
    tag_id = Symbol(String(t[1:4]))
    size   = read32(t[5:8 ]...)

    # The adtl entry must have even length. Therefore, if the reported length
    # is odd, actually read an extra byte.
    if size % 2 == 1
        size += 1
    end

    i = 9
    while t[i] != 0
        i += 1
    end
    tags[tag_id] = String(t[9:(i-1)])

    # Skip the null terminator
    t[(i+1):end]
end

"""
    wav_info_read(chunks::Vector{WAVChunk})::Dict{Symbol, String}

Given a list of chunks as returned by `wavread`, return a
Dict{Symbol, String} where the keys are symbols representing
four-character RIFF INFO tag IDs as specified in
https://www.sno.phy.queensu.ca/~phil/exiftool/TagNames/RIFF.html#Info
"""
function wav_info_read(chunks::Vector{WAVChunk})
    tags = Dict{Symbol, String}()

    list_chunks = chunks[findall(c -> c.id == :LIST, chunks)]
    for l in list_chunks
        list_data = l.data
        if list_data[1:4] == b"INFO"
            list_data = list_data[5:end]
            while (length(list_data) >= 12)
                list_data = read_tag(tags, list_data)
            end
        end
    end

    tags
end


"""
    wav_cue_write(markers::Dict{UInt32, WAVMarker})

Turns `WAVMarker`s into a `Vector{WAVChunk}` (as accepted by
`wavwrite`). The key for the dictionary is the ID of the marker to be
written to file.

Example:
```julia
out_chunks = wav_cue_write(markers)
wavwrite(x, "out.wav", Fs=fs, nbits=16, compression=WAVE_FORMAT_PCM, chunks=out_chunks)
```
"""
function wav_cue_write(markers::Dict{UInt32, WAVMarker})
    chunks = WAVChunk[]
    push!(chunks, WAVChunk(Symbol("cue "), write_cue(markers)))
    push!(chunks, WAVChunk(:LIST, write_marker_list(markers)))
    chunks
end
