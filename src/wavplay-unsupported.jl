# -*- mode: julia; -*-
module WAVPlay
import ..wavplay
wavplay(data, fs) = warn("wavplay is not currently implemented on $OS_NAME")
end # module
