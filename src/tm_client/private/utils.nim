import strutils
import json
import cgi
import times

proc stripTrailingSlash*(url: string): string =
    ## Strips the trailing slash from a URL or path and returns the result

    if url.endsWith('/'):
        return url.substr(0, url.len()-2)
    else:
        return url

proc jsonValueToQueryParamValue*(json: JsonNode, nullAsBlank: bool = false): string =
    ## Returns the provided JSON value as a query param value

    case json.kind:
        of JNull: return if nullAsBlank: "" else: "null"
        of JBool: return $json.getBool()
        of JInt: return $json.getInt()
        of JFloat: return $json.getFloat()
        of JString: return encodeUrl(json.getStr())
        else: return encodeUrl($json)

proc jsonToQueryParams*(json: JsonNode, nullAsBlank: bool = false): string =
    ## Converts the provided JSON to query params, minus the beginning "?"
    
    var first = true
    for key, value in json.pairs:
        if(first):
            first = false
        else:
            result.add("&")
        
        result.add(key&"="&jsonValueToQueryParamValue(value, nullAsBlank))

proc isoStringToDateTime*(str: string): DateTime =
    ## Parses an ISO date string into a DateTime object

    try:
        return parse(str, "yyyy-MM-dd'T'HH:mm:ss'.'ffffff'Z'", utc())
    except TimeParseError:
        # Ignore first error, try the next
        return parse(str, "yyyy-MM-dd'T'HH:mm:ss'.'fff'Z'", utc())

proc dateTimeToIsoString*(date: DateTime): string =
    ## Formats a DateTime object as an ISO date string
    
    date.format("yyyy-MM-dd'T'HH:mm:ss'.'fff'Z'")
    
    
proc jsonNodeSeqToStringSeq*(elems: seq[JsonNode]): seq[string] =
    ## Converts the provided JsonNode sequence into a string sequence

    result = newSeq[string](elems.len)
    for i, elem in elems:
        result[i] = elem.getStr

proc jsonArrayToStringSeq*(json: JsonNode): seq[string] =
    ## Converts the provided JSON array into a string sequence

    if json.kind == JArray:
        return json.to(seq[string])
    else:
        raise newException(JsonKindError, "Provided JsonNode is not of kind JArray")

proc stringSeqToJsonArray*(strs: seq[string]): JsonNode =
    ## Converts the provided string sequence into a JSON array
    
    var nodes = newSeq[JsonNode](strs.len())
    for i, str in strs:
        nodes[i] = newJString(str)
    
    return JsonNode(
        kind: JArray,
        elems: nodes
    )