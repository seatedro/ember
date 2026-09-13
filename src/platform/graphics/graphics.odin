package graphics

BACKEND :: #config(EMBER_BACKEND, "metal" when ODIN_OS == .Darwin else "opengl")
#assert(BACKEND == "opengl" || BACKEND == "metal", "EMBER_BACKEND must be opengl or metal")
METAL :: BACKEND == "metal"
#assert(!METAL || ODIN_OS == .Darwin, "Metal requires macOS")
