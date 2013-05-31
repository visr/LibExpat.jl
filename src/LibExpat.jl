module LibExpat

import Base: getindex, show

include("lX_common_h.jl")
include("lX_defines_h.jl")
include("lX_expat_h.jl")
include("lX_exports_h.jl")

@c Ptr{XML_LChar} XML_ErrorString (Cint,) libexpat

export ParsedData, XPHandle, xp_make_parser, xp_geterror, xp_close, xp_parse, find

DEBUG = false

macro DBG_PRINT (s)
    quote
        if (DEBUG) 
            println($s); 
        end
    end
end

type ParsedData
    # XML Tag
    name::String
    # Dict of tag attributes as name-value pairs
    attr::Dict{String,String}
    # List of child elements.
    elements::Vector{Union(ParsedData,String)}
    parent::ParsedData
    
    ParsedData() = ParsedData("")
    function ParsedData(name)
        pd=new(
            name,
            Dict{String, String}(),
            Union(ParsedData,String)[])
        pd.parent=pd
        pd
    end
end

function show(io::IO, pd::ParsedData)
    print(io,'<',pd.name)
    for (name,value) in pd.attr
        print(io,' ',name,'=','"',replace(value,'"',"&quot;"),'"')
    end
    if length(pd.elements) == 0
        print(io,'/','>')
    else
        print(io,'>')
        for ele in pd.elements
            if isa(ele, ParsedData)
                show(io, ele)
            else
                print(io, replace(ele,'<',"&lt;"))
            end
        end
        print(io,'<','/',pd.name,'>')
    end
end
function string_value(pd::ParsedData)
    str = ""
    for node in pd.elements
        if isa(node, String)
            str *= node
        elseif isa(node,ParsedData)
            str *= string_value(node)
        end
    end
    str
end


type XPHandle
  parser::Union(XML_Parser,Nothing)
  pdata::ParsedData
  in_cdata::Bool
  
  XPHandle(p) = new(p, ParsedData(""), false)
end


function xp_make_parser(sep='\0') 
    p::XML_Parser = (sep == '\0') ? XML_ParserCreate(C_NULL) : XML_ParserCreateNS(C_NULL, sep);
    if (p == C_NULL) error("XML_ParserCreate failed") end

    xph = XPHandle(p)
    p_xph = pointer_from_objref(xph)
    XML_SetUserData(p, p_xph);
    
    XML_SetCdataSectionHandler(p, cb_start_cdata, cb_end_cdata)
    XML_SetCharacterDataHandler(p, cb_cdata)
    XML_SetCommentHandler(p, cb_comment)
    XML_SetDefaultHandler(p, cb_default)
    XML_SetDefaultHandlerExpand(p, cb_default_expand)
    XML_SetElementHandler(p, cb_start_element, cb_end_element)
#    XML_SetExternalEntityRefHandler(p, f_ExternaEntity)
    XML_SetNamespaceDeclHandler(p, cb_start_namespace, cb_end_namespace)
#    XML_SetNotationDeclHandler(p, f_NotationDecl)
#    XML_SetNotStandaloneHandler(p, f_NotStandalone)
#    XML_SetProcessingInstructionHandler(p, f_ProcessingInstruction)
#    XML_SetUnparsedEntityDeclHandler(p, f_UnparsedEntityDecl)
#    XML_SetStartDoctypeDeclHandler(p, f_StartDoctypeDecl) 

    return xph
end


function xp_geterror(xph::XPHandle)
    p = xph.parser
    ec = XML_GetErrorCode(p)
    
    if ec != 0 
        @DBG_PRINT (XML_GetErrorCode(p))
        @DBG_PRINT (bytestring(XML_ErrorString(XML_GetErrorCode(p))))
        
        return  ( bytestring(XML_ErrorString(XML_GetErrorCode(p))), 
                XML_GetCurrentLineNumber(p), 
                XML_GetCurrentColumnNumber(p) + 1, 
                XML_GetCurrentByteIndex(p) + 1
            )
     else
        return  ( "", 0, 0, 0)
     end 
     
end


function xp_close (xph::XPHandle) 
  if (xph.parser != nothing)    XML_ParserFree(xph.parser) end
  xph.parser = nothing
end


function start_cdata (p_xph::Ptr{Void}) 
    xph = unsafe_pointer_to_objref(p_xph)::XPHandle
#    @DBG_PRINT ("Found StartCdata")
    xph.in_cdata = true
    return
end
cb_start_cdata = cfunction(start_cdata, Void, (Ptr{Void},))

function end_cdata (p_xph::Ptr{Void}) 
    xph = unsafe_pointer_to_objref(p_xph)::XPHandle
#    @DBG_PRINT ("Found EndCdata")
    xph.in_cdata = false
    return;
end
cb_end_cdata = cfunction(end_cdata, Void, (Ptr{Void},))


function cdata (p_xph::Ptr{Void}, s::Ptr{Uint8}, len::Cint)
    xph = unsafe_pointer_to_objref(p_xph)::XPHandle
  
    txt = bytestring(s, int(len))
    push!(xph.pdata.elements, txt)
    
#    @DBG_PRINT ("Found CData : " * txt)
    return;
end
cb_cdata = cfunction(cdata, Void, (Ptr{Void},Ptr{Uint8}, Cint))


function comment (p_xph::Ptr{Void}, data::Ptr{Uint8}) 
    xph = unsafe_pointer_to_objref(p_xph)::XPHandle
    txt = bytestring(data)
    @DBG_PRINT ("Found comment : " * txt)
    return;
end
cb_comment = cfunction(comment, Void, (Ptr{Void},Ptr{Uint8}))


function default (p_xph::Ptr{Void}, data::Ptr{Uint8}, len::Cint)
    xph = unsafe_pointer_to_objref(p_xph)::XPHandle
    txt = bytestring(data)
#    @DBG_PRINT ("Default : " * txt)
    return;
end
cb_default = cfunction(default, Void, (Ptr{Void},Ptr{Uint8}, Cint))


function default_expand (p_xph::Ptr{Void}, data::Ptr{Uint8}, len::Cint)
    xph = unsafe_pointer_to_objref(p_xph)::XPHandle
    txt = bytestring(data)
#    @DBG_PRINT ("Default Expand : " * txt)
    return;
end
cb_default_expand = cfunction(default_expand, Void, (Ptr{Void},Ptr{Uint8}, Cint))


function start_element (p_xph::Ptr{Void}, name::Ptr{Uint8}, attrs_in::Ptr{Ptr{Uint8}})
    xph = unsafe_pointer_to_objref(p_xph)::XPHandle
    name = bytestring(name)
#    @DBG_PRINT ("Start Elem name : $name,  current element: $(xph.pdata.name) ")
    
    new_elem = ParsedData(name)
    new_elem.parent = xph.pdata 

    push!(xph.pdata.elements, new_elem)
    @DBG_PRINT ("Added $name to $(xph.name)")

    xph.pdata = new_elem
    
    if (attrs_in != C_NULL)
        i = 1
        attr = unsafe_load(attrs_in, i)
        while (attr != C_NULL)
            k = bytestring(attr)
            
            i=i+1
            attr = unsafe_load(attrs_in, i)
            
            if (attr == C_NULL) error("Attribute does not have a name!") end
            v = bytestring(attr)
            
            new_elem.attr[k] = v

            @DBG_PRINT ("$k, $v in $name")
            
            i=i+1
            attr = unsafe_load(attrs_in, i)
        end
    end
    
    return
end
cb_start_element = cfunction(start_element, Void, (Ptr{Void},Ptr{Uint8}, Ptr{Ptr{Uint8}}))


function end_element (p_xph::Ptr{Void}, name::Ptr{Uint8})
    xph = unsafe_pointer_to_objref(p_xph)::XPHandle
    txt = bytestring(name)
#    @DBG_PRINT ("End element: $txt, current element: $(xph.pdata.name) ")
    
    xph.pdata = xph.pdata.parent
    
    return;
end
cb_end_element = cfunction(end_element, Void, (Ptr{Void},Ptr{Uint8}))


function start_namespace (p_xph::Ptr{Void}, prefix::Ptr{Uint8}, uri::Ptr{Uint8}) 
    xph = unsafe_pointer_to_objref(p_xph)::XPHandle
    prefix = bytestring(prefix)
    uri = bytestring(uri)
    @DBG_PRINT ("start namespace prefix : $prefix, uri: $uri")
    return;
end
cb_start_namespace = cfunction(start_namespace, Void, (Ptr{Void},Ptr{Uint8}, Ptr{Uint8}))


function end_namespace (p_xph::Ptr{Void}, prefix::Ptr{Uint8})
    xph = unsafe_pointer_to_objref(p_xph)::XPHandle
    prefix = bytestring(prefix)
    @DBG_PRINT ("end namespace prefix : $prefix")
    return;
end
cb_end_namespace = cfunction(end_namespace, Void, (Ptr{Void},Ptr{Uint8}))


# Unsupported callbacks: External Entity, NotationDecl, Not Stand Alone, Processing, UnparsedEntityDecl, StartDocType
# SetBase and GetBase



function xp_parse(txt::String)
    xph = nothing
    xph = xp_make_parser()
    
    try
        rc = XML_Parse(xph.parser, txt, length(txt), 1)
        if (rc != XML_STATUS_OK) error("Error parsing document : $rc") end
        
        # The root element will only have a single child element in a well formed XML
        return xph.pdata.elements[1]
    catch e
        stre = string(e)
        (err, line, column, pos) = xp_geterror(xph)
        @DBG_PRINT ("$e, $err, $line, $column, $pos")
        rethrow("$e, $err, $line, $column, $pos")
    
    finally
        if (xph != nothing) xp_close(xph) end
    end
end


function find{T<:String}(pd::ParsedData, path::T)
    # What are we looking for?
    what = :node
    attr = ""

    pathext = split(path, "#")
    if (length(pathext)) > 2 error("Invalid path syntax") 
    elseif (length(pathext) == 2)
        if (pathext[2] == "string")
            what = :string
        else
            error("Unknown extension : [$(pathext[2])]")
        end
    end

    xp= Array((Symbol,Any),0)
    if path[1] == '/'
        # This will treat the incoming pd as the root of the tree
        push!(xp, (:root,nothing))
        pathext[1] = pathext[1][2:end]
        #else - it will start searching the children....
    end

    nodes = split(pathext[1], "/")
    idx = false
    descendant = :child
    for n in nodes
        idx = false
        if length(n) == 0
            if descendant == :descendant
                error("too many / in a row")
            end
            descendant = :descendant
            continue
        end
        # Check to see if it is an index into an array has been requested, else default to 1
        m =  match(r"([\:\w]+)\s*(\[\s*(\d+)\s*\])?\s*(\{\s*(\w+)\s*\})?", n)

        if ((m == nothing) || (length(m.captures) != 5))
            error("Invalid name $n")
        else
            node = m.captures[1]
            push!(xp, (descendant,nothing))
            descendant = :child
            push!(xp, (:name,SubString{T}(convert(T,node),1,length(node))))
 
            if m.captures[5] != nothing
                if (n == nodes[end])
                    what = :attr
                end
                attr = m.captures[5]
                push!(xp, (:attribute,SubString{T}(convert(T,attr),1,length(attr))))
            end

            if m.captures[3] != nothing
                push!(xp, (:position,(:(=),int(m.captures[3]))))
                idx = true
            end
        end
    end
    
    pd = xpath(pd, XPath{T}(xp))
    if what == :node
        if idx
            if length(pd) == 1
                return pd[1]
            else
                return nothing
            end
        else
            # If caller did not specify an index, return a list of leaf nodes.
            return pd
        end
    elseif length(pd) == 0
        return nothing

    elseif length(pd) != 1
        error("More than one instance of $pd, please specify an index")

    else
        pd = pd[1]
        if what == :string
            return string_value(pd)

        elseif what == :attr
            return pd.attr[attr]

        else
            error("Unknown request type")
        end
    end

    return nothing
end 

include("xpath.jl")

end
