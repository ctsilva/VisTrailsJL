"""
HTTPFile Module

Fetches content from an HTTP/HTTPS URL.
Equivalent to Python VisTrails' HTTPFile module.
"""

using HTTP

"""
HTTPFile <: Module

Fetches a file from a URL and makes it available as output.

Parameters:
- url::String - The URL to fetch

Outputs:
- file::String - The content of the fetched file
"""
struct HTTPFileModule <: Module
    # Module state (set by compute)
end

"""
    compute(mod::ModuleInstance, ::Type{HTTPFileModule})

Execute the HTTPFile module - fetch content from URL.
"""
function compute(mod::ModuleInstance, ::Type{HTTPFileModule})
    # Get URL parameter
    url = mod.parameters["url"]

    println("Fetching: ", url)

    # Fetch content
    try
        response = HTTP.get(url)
        content = String(response.body)

        # Set output
        mod.outputs["file"] = content

        mod.uptodate = true
        mod.cache_state = :valid

        return mod.outputs
    catch e
        println("Error fetching URL: ", e)
        rethrow(e)
    end
end

"""
    register_httpfile!()

Register HTTPFile module in the module registry.
"""
function register_httpfile!()
    descriptor = ModuleDescriptor(
        "org.vistrails.vistrails.basic",  # package
        "HTTPFile",                        # name
        HTTPFileModule,                    # type
        InputPort[],                       # no inputs
        [OutputPort("file", String)],      # outputs
        [("url", String)]                  # parameters
    )

    register_module!(descriptor)
end
