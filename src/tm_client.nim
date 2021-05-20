## Module that provides an asynchronous client for TwineMedia and utilities for interacting with it

import tm_client/enums
import tm_client/exceptions
import tm_client/objects
import tm_client/utils

import json
import strutils
import mimetypes
import httpclient
import asyncdispatch
import cgi
import options
import times

proc hasPermission*(perms: seq[string], permission: string): bool =
    ## Returns whether the specified permission is in the provided array of permissions
    
    result = false

    # Skip if the user doesn't have any permissions
    if perms.len > 0:
        # Check if the user has the permission
        if perms.contains(permission) or perms.contains("$permission.all") or perms.contains("*"):
            result = true
        elif permission.contains('.'):
            # Check permission tree
            var perm = ""
            let split = permission.split('.')
            for child in split:
                perm &= child&"."
                for p in perms:
                    if p == perm&"*":
                        result = true
                        break

                if result:
                    break

type TMClient* = ref object of RootObj
    ## Stores client credentials and information

    rootUrl*: string
    token*: string
    account*: TMSelfAccountInfo

method hasPermission*(this: TMClient, permission: string): bool {.base.} =
    ## Returns whether the account associated with this client has the specified permission.
    ## Requires that fetchSelfAccountInfo(client) has been called on this client at least once prior.
    
    if this.account.isAdmin:
        return true
    else:
        return this.account.permissions.hasPermission(permission)

method idToDownloadUrl*(this: TMClient, id: string, filename: string = ""): string {.base.} =
    ## Takes in a media file ID and optionally a filename and returns its download URL

    if filename.len > 0:
        return this.rootUrl&"/download/"&id&"/"&filename
    else:
        return this.rootUrl&"/download/"&id

method idToThumbnailUrl*(this: TMClient, id: string): string {.base.} =
    ## Takes in a media file ID and returns its thumbnail URL (URL will only work if the media file has a thumbnail)

    return this.rootUrl&"/thumbnail/"&id

method mediaJsonToObj(this: TMClient, json: JsonNode): TMMedia {.base.} =
    # Pull out some data that will be referenced more than once
    let id = json["id"].getStr
    let filename = json["filename"].getStr
    let hasThumbnail = json["thumbnail"].getBool

    # Convert children (if present) to TMMedia objects
    let childElems = if json.hasKey("children"): json["children"].getElems else: newSeq[JsonNode](0)
    var children = if childElems.len > 0: newSeq[TMMedia](childElems.len) else: newSeq[TMMedia](0)
    for i, child in childElems:
        children[i] = this.mediaJsonToObj(child)

    # Convert parent if present
    let parent = if json.hasKey("parent"): @[this.mediaJsonToObj(json["parent"])] else: newSeq[TMMedia](0)
    
    # Create object
    return TMMedia(
        id: id,
        name: json["name"].getStr,
        filename: filename,
        creatorId: json["creator"].getInt,
        creatorName: json["creator_name"].getStr,
        size: json["size"].getBiggestInt,
        mime: json["mime"].getStr,
        createdOn: json["created_on"].getStr.isoStringToDateTime,
        modifiedOn: json["modified_on"].getStr.isoStringToDateTime,
        fileHash: json["file_hash"].getStr,
        hasThumbnail: hasThumbnail,
        thumbnailUrl: if hasThumbnail: this.idToThumbnailUrl(id) else: "",
        downloadUrl: this.idToDownloadUrl(id, filename),
        tags: json["tags"].jsonArrayToStringSeq,
        isProcessing: json["processing"].getBool,
        processError: json{"process_error"}.getStr(""),
        description: json{"description"}.getStr(""),
        children: children,
        parent: parent
    )

method listJsonToObj(this: TMClient, json: JsonNode): TMList {.base.} =
    # Resolve optional values
    let tagsJson = json{"source_tags"}
    let tags = if tagsJson == nil or tagsJson.kind == JNull:
        none[seq[string]]()
    else:
        some(tagsJson.jsonArrayToStringSeq)
    let excludeTagsJson = json{"source_exclude_tags"}
    let excludeTags = if excludeTagsJson == nil or excludeTagsJson.kind == JNull:
        none[seq[string]]()
    else:
        some(excludeTagsJson.jsonArrayToStringSeq)
    
    let createdBeforeJson = json{"source_created_before"}
    let createdBefore: Option[DateTime] = if createdBeforeJson == nil or createdBeforeJson.kind == JNull:
        none[DateTime]()
    else:
        some(createdBeforeJson.getStr.isoStringToDateTime)
    let createdAfterJson = json{"source_created_after"}
    let createdAfter: Option[DateTime] = if createdAfterJson == nil or createdAfterJson.kind == JNull:
        none[DateTime]()
    else:
        some(createdAfterJson.getStr.isoStringToDateTime)
    
    let mimeJson = json{"source_mime"}
    let mime = if mimeJson == nil or mimeJson.kind == JNull:
        none[string]()
    else:
        some(mimeJson.getStr)
    
    let showAllUserFilesJson = json{"show_all_user_files"}
    let showAllUserFiles = if showAllUserFilesJson == nil or showAllUserFilesJson.kind == JNull:
        none[bool]()
    else:
        some(showAllUserFilesJson.getBool)
    
    let itemCountJson = json{"item_count"}
    let itemCount = if itemCountJson == nil or itemCountJson.kind == JNull or itemCountJson.getInt < 0:
        none[int]()
    else:
        some(itemCountJson.getInt)
    
    let containsMediaJson = json{"contains_media"}
    let containsMedia = if containsMediaJson == nil or containsMediaJson.kind == JNull:
        none[bool]()
    else:
        some(containsMediaJson.getBool)

    return TMList(
        id: json["id"].getStr,
        name: json["name"].getStr,
        description: json["description"].getStr,
        creatorId: json["creator"].getInt,
        creatorName: json["creator_name"].getStr,
        listType: TMListType(json["type"].getInt),
        listVisibility: TMListVisibility(json["visibility"].getInt),
        createdOn: json["created_on"].getStr.isoStringToDateTime,
        modifiedOn: json["modified_on"].getStr.isoStringToDateTime,
        sourceTags: tags,
        sourceExcludeTags: excludeTags,
        sourceCreatedBefore: createdBefore,
        sourceCreatedAfter: createdAfter,
        sourceMime: mime,
        showAllUserFiles: showAllUserFiles,
        itemCount: itemCount,
        containsMedia: containsMedia
    )

method handleApiResponse(this: TMClient, http: AsyncHttpClient, httpRes: AsyncResponse): Future[JsonNode] {.base, async.} =
    ## Takes in an HTTP response, validates it, and returns the body as JSON

    # Make sure 200 status is returned
    if httpRes.status.startsWith("200"):
        # Get body and parse JSON
        let json = parseJson(await httpRes.body())
        
        # Get status
        let status = json["status"].getStr

        # Create client or handle bad status
        if status == "success":
            result = json
        elif status == "error":
            http.close()

            let error = json{"error"}.getStr("No error field in response")
            if error == "File does not exist":
                raise newException(MediaNotFoundError, error)
            else:
                raise newException(ErrorStatusError, "API returned error \"$1\""%error)
        else:
            http.close()
            raise newException(UnknownStatusError, "API returned unknown status \"$1\""%status)

        # Finally close connection
        http.close()
    elif httpRes.status.startsWith("401"):
        http.close()
        raise newException(UnauthorizedError, "API returned Unauthorized (HTTP status 401)")
    else:
        http.close()
        raise newException(BadStatusCodeError, "API returned HTTP status "&httpRes.status)

method request*(this: TMClient, httpMethod: HttpMethod, path: string, data: JsonNode = %* {}): Future[JsonNode] {.base, async.} =
    ## Performs a request with a relative API path (must start with "/") and optionally data to be sent as either query parameters or POST body

    # Work out headers and URL for request
    var headers: HttpHeaders
    var url = this.rootUrl&"/api/v1"&path
    if httpMethod == HttpPost:
        headers = newHttpHeaders({
            "Authorization": "Bearer "&this.token,
            "Content-Type": "application/x-www-form-urlencoded"
        })
    else:
        url &= "?"&jsonToQueryParams(data)
        headers = newHttpHeaders({
            "Authorization": "Bearer "&this.token
        })
    
    # Create client
    let http = newAsyncHttpClient(headers = headers)

    # Create request
    let httpRes = await (if httpMethod == HttpPost: http.request(url, httpMethod, data.jsonToQueryParams) else: http.request(url, httpMethod))
    
    return await this.handleApiResponse(http, httpRes)

method uploadFile(
        this: TMClient,
        path: string,
        name: Option[string] = none[string](),
        description: Option[string] = none[string](),
        tags: Option[seq[string]] = none[seq[string]](),
        noThumbnail: bool = false,
        doNotProcess: bool = false
    ): Future[string] {.base, async.} =
    ## Uploads a file and returns its ID
    
    # Setup headers
    var headers = @[
        ("Authorization", "Bearer "&this.token)
    ]
    if name.isSome:
        headers.add(("X-FILE-NAME", encodeUrl(name.get)))
    if description.isSome:
        headers.add(("X-FILE-DESCRIPTION", encodeUrl(description.get)))
    if tags.isSome:
        headers.add(("X-FILE-TAGS", encodeUrl($tags.get.stringSeqToJsonArray)))
    if noThumbnail:
        headers.add(("X-NO-THUMBNAIL", "true"))
    if doNotProcess:
        headers.add(("X-NO-PROCESS", "true"))

    # Setup multipart data
    let mimes = newMimetypes()
    let data = newMultipartData()
    data.addFiles({ "file": path }, mimeDb = mimes)
    
    # Create client
    let http = newAsyncHttpClient(headers = newHttpHeaders(headers))

    # Upload file
    let httpRes = await http.request(this.rootUrl&"/api/v1/media/upload", HttpPost, multipart = data)
    
    # Get response
    let res = await this.handleApiResponse(http, httpRes)

    # Return new file's ID
    return res["id"].getStr

method createStandardList(this: TMClient, id: string, name: string, description: string, visibility: TMListVisibility): Future[void] {.base, async.} =
    ## Create a new standard list
    
    discard await this.request(HttpPost, "/lists/create", %*{
        "type": StandardList.ord,
        "name": name,
        "description": description,
        "visibility": visibility.ord
    })

method createAutomaticallyPopulatedList(
        this: TMClient,
        id: string,
        name: string,
        description: string,
        visibility: TMListVisibility,
        sourceTags: Option[seq[string]] = none[seq[string]](),
        sourceExcludeTags: Option[seq[string]] = none[seq[string]](),
        sourceCreatedBefore: Option[DateTime] = none[DateTime](),
        sourceCreatedAfter: Option[DateTime] = none[DateTime](),
        sourceMime: Option[string] = none[string](),
        showAllUserFiles: Option[bool] = none[bool]()
    ): Future[void] {.base, async.} =
    ## Creates a new automatically populated list
    
    # Put fields in body if present
    let body = %*{
        "type": AutomaticallyPopulatedList.ord,
        "name": name,
        "description": description,
        "visibility": visibility.ord
    }
    if sourceTags.isSome:
        body.add("sourceTags", sourceTags.get.stringSeqToJsonArray)
    if sourceExcludeTags.isSome:
        body.add("sourceExcludeTags", sourceExcludeTags.get.stringSeqToJsonArray)
    if sourceCreatedBefore.isSome:
        body.add("sourceCreatedBefore", newJString(sourceCreatedBefore.get.dateTimeToIsoString))
    if sourceCreatedAfter.isSome:
        body.add("sourceCreatedAfter", newJString(sourceCreatedAfter.get.dateTimeToIsoString))
    if sourceMime.isSome:
        body.add("sourceMime", newJString(source_mime.get))
    if showAllUserFiles.isSome:
        body.add("showAllUserFiles", newJBool(showAllUserFiles.get))
    
    discard await this.request(HttpPost, "/lists/create", body)

method fetchSelfAccountInfo(this: TMClient): Future[TMSelfAccountInfo] {.base, async.} =
    ## Fetches this client's account info (and stores in the client account property)

    let info = await this.request(HttpGet, "/account/info")
    let account = TMSelfAccountInfo(
        id: info["id"].getInt,
        permissions: info["permissions"].jsonArrayToStringSeq,
        name: info["name"].getStr,
        email: info["email"].getStr,
        isAdmin: info["admin"].getBool,
        creationDate: info["creation_date"].getStr.isoStringToDateTime,
        excludeTags: info["exclude_tags"].jsonArrayToStringSeq,
        excludeOtherMedia: info["exclude_other_media"].getBool,
        excludeOtherLists: info["exclude_other_lists"].getBool,
        excludeOtherProcesses: info["exclude_other_processes"].getBool,
        maxUploadSize: info["max_upload"].getBiggestInt,
        isApiToken: info["api_token"].getBool
    )
    this.account = account

    return account

method fetchInstanceInfo(this: TMClient): Future[TMInstanceInfo] {.base, async.} =
    ## Fetches information about this TwineMedia instance

    let info = await this.request(HttpGet, "/info")
    return TMInstanceInfo(
        version: info["version"].getStr,
        apiVersions: info["api_versions"].jsonArrayToStringSeq
    )

method fetchMediaById(this: TMClient, id: string): Future[TMMedia] {.base, async.} =
    ## Fetches the media file with the specified ID, otherwises raises MediaNotFoundError

    return this.mediaJsonToObj(await this.request(HttpGet, "/media/"&id))

method fetchMedia(this: TMClient, offset: int = 0, limit: int = 100, order: TMMediaOrder = MediaCreatedOnDesc): Future[seq[TMMedia]] {.base, async.} =
    ## Fetches all media
    
    let files = (await this.request(HttpGet, "/media", %*{
        "offset": offset,
        "limit": limit,
        "order": order.ord
    }))["files"].getElems
    var res = newSeq[TMMedia](files.len)
    for i, media in files:
        res[i] = this.mediaJsonToObj(media)
    
    return res

method fetchMediaByPlaintextSearch(
        this: TMClient,
        query: string,
        searchNames: bool = true,
        searchFilenames: bool = true,
        searchDescriptions: bool = true,
        searchTags: bool = true,
        offset: int = 0,
        limit: int = 100,
        order: TMMediaOrder = MediaCreatedOnDesc
    ): Future[seq[TMMedia]] {.base, async.} =
    ## Fetches all media that matches the specified plaintext search query
    
    let files = (await this.request(HttpGet, "/media/search", %*{
        "query": query,
        "searchNames": $searchNames,
        "searchFilenames": $searchFilenames,
        "searchDescriptions": $searchDescriptions,
        "searchTags": $searchTags,
        "offset": offset,
        "limit": limit,
        "order": order.ord
    }))["files"].getElems
    var res = newSeq[TMMedia](files.len)
    for i, media in files:
        res[i] = this.mediaJsonToObj(media)
    
    return res

method fetchMediaByTags(this: TMClient, tags: seq[string], excludeTags: seq[string] = @[], offset: int = 0, limit: int = 100, order: TMMediaOrder = MediaCreatedOnDesc): Future[seq[TMMedia]] {.base, async.} =
    ## Fetches all media that contain the specified tags (and don't contain the specified excluded tags)
    
    let files = (await this.request(HttpGet, "/media/tags", %*{
        "tags": stringSeqToJsonArray(tags),
        "excludeTags": stringSeqToJsonArray(excludeTags),
        "offset": offset,
        "limit": limit,
        "order": order.ord
    }))["files"].getElems
    var res = newSeq[TMMedia](files.len)
    for i, media in files:
        res[i] = this.mediaJsonToObj(media)
    
    return res

method fetchMediaByList(this: TMClient, list: string, offset: int = 0, limit: int = 100, order: TMMediaOrder = MediaCreatedOnDesc): Future[seq[TMMedia]] {.base, async.} =
    ## Fetches all media in the specified list
    
    let files = (await this.request(HttpGet, "/media/list/"&list, %*{
        "offset": offset,
        "limit": limit,
        "order": order.ord
    }))["files"].getElems
    var res = newSeq[TMMedia](files.len)
    for i, media in files:
        res[i] = this.mediaJsonToObj(media)
    
    return res

method fetchTags(this: TMClient, query: string = "", offset: int = 0, limit: int = 100, order: TMTagOrder = TagNameAsc): Future[seq[TMTag]] {.base, async.} =
    ## Fetchs all tags (optionally matching the specified query, using "%" as a wildcard)
    
    let tagElems = (await this.request(HttpGet, "/tags", %*{
        "query": query,
        "offset": offset,
        "limit": limit,
        "order": order.ord
    }))["tags"].getElems

    # Convert tags to objects
    var tags = newSeq[TMTag](tagElems.len)
    for i, tag in tagElems:
        tags[i] = TMTag(name: tag["name"].getStr, files: tag["files"].getInt)

    return tags

method fetchListById(this: TMClient, id: string): Future[TMList] {.base, async.} =
    ## Fetches a list's info by its ID
    
    return this.listJsonToObj(await this.request(HttpGet, "/list/"&id))

method fetchLists(
        this: TMClient,
        listType: Option[TMListType] = none[TMListType](),
        containsMedia: Option[string] = none[string](),
        offset: int = 0,
        limit: int = 100,
        order: TMListOrder = ListCreatedOnDesc
    ): Future[seq[TMList]] {.base, async.} =
    ## Fetches all lists, optionally returning only lists of the specified type, and optionally causing lists to contain whether they contain the specified media file by ID
    
    # Figure out which parameters need to be added
    let body = %*{
        "offset": offset,
        "limit": limit,
        "order": order.ord
    }
    if listType.isSome:
        body.add("type", newJInt(listType.get.ord))
    if containsMedia.isSome:
        body.add("media", newJString(containsMedia.get))

    # Get lists
    let listElems = (await this.request(HttpGet, "/lists", body))["lists"].getElems
    var lists = newSeq[TMList](listElems.len)
    for i, list in listElems:
        lists[i] = this.listJsonToObj(list)
    
    return lists

method fetchListsByPlaintextSearch(
        this: TMClient,
        query: string,
        searchNames: bool = true,
        searchDescriptions: bool = true,
        listType: Option[TMListType] = none[TMListType](),
        containsMedia: Option[string] = none[string](),
        offset: int = 0,
        limit: int = 100,
        order: TMListOrder = ListCreatedOnDesc
    ): Future[seq[TMList]] {.base, async.} =
    ## Fetches lists by the specified plaintext search query, optionally returning only lists of the specified type, and optionally causing lists to contain whether they contain the specified media file by ID
    
    # Figure out which parameters need to be added
    let body = %*{
        "query": query,
        "searchNames": searchNames,
        "searchDescriptions": searchDescriptions,
        "offset": offset,
        "limit": limit,
        "order": order.ord
    }
    if listType.isSome:
        body.add("type", newJInt(listType.get.ord))
    if containsMedia.isSome:
        body.add("media", newJString(containsMedia.get))

    # Get lists
    let listElems = (await this.request(HttpGet, "/lists/search", body))["lists"].getElems
    var lists = newSeq[TMList](listElems.len)
    for i, list in listElems:
        lists[i] = this.listJsonToObj(list)
    
    return lists

method editFile(
        this: TMClient,
        id: string,
        name: Option[string] = none[string](),
        filename: Option[string] = none[string](),
        description: Option[string] = none[string](),
        tags: Option[seq[string]] = none[seq[string]]()
    ): Future[void] {.base, async.} =
    ## Edits the file with the specified ID, changing properties if provided (name, filename, description, tags)

    # Figure out which parameters need to be added
    let body = newJObject()
    if name.isSome:
        body.add("name", newJString(name.get))
    if filename.isSome:
        body.add("filename", newJString(filename.get))
    if description.isSome:
        body.add("description", newJString(description.get))
    if tags.isSome:
        body.add("tags", tags.get.stringSeqToJsonArray)
    
    # Edit file
    discard await this.request(HttpPost, "/media/"&id&"/edit", body)

method editListAsStandard(this: TMClient, id: string, name: string, description: string, visibility: TMListVisibility): Future[void] {.base, async.} =
    ## Edits a list as a standard list (calling this on an automatically populated list will convert it into a standard list)
    
    discard await this.request(HttpPost, "/list/"&id&"/edit", %*{
        "type": StandardList.ord,
        "name": name,
        "description": description,
        "visibility": visibility.ord
    })

method editListAsAutomaticallyPopulated(
        this: TMClient,
        id: string,
        name: string,
        description: string,
        visibility: TMListVisibility,
        sourceTags: Option[seq[string]] = none[seq[string]](),
        sourceExcludeTags: Option[seq[string]] = none[seq[string]](),
        sourceCreatedBefore: Option[DateTime] = none[DateTime](),
        sourceCreatedAfter: Option[DateTime] = none[DateTime](),
        sourceMime: Option[string] = none[string](),
        showAllUserFiles: Option[bool] = none[bool]()
    ): Future[void] {.base, async.} =
    ## Edits a list as an automatically populated list (calling this on an automatically populated list will convert it into a standard list)
    
    # Put fields in body if present
    let body = %*{
        "type": AutomaticallyPopulatedList.ord,
        "name": name,
        "description": description,
        "visibility": visibility.ord
    }
    if sourceTags.isSome:
        body.add("sourceTags", sourceTags.get.stringSeqToJsonArray)
    if sourceExcludeTags.isSome:
        body.add("sourceExcludeTags", sourceExcludeTags.get.stringSeqToJsonArray)
    if sourceCreatedBefore.isSome:
        body.add("sourceCreatedBefore", newJString(sourceCreatedBefore.get.dateTimeToIsoString))
    if sourceCreatedAfter.isSome:
        body.add("sourceCreatedAfter", newJString(sourceCreatedAfter.get.dateTimeToIsoString))
    if sourceMime.isSome:
        body.add("sourceMime", newJString(source_mime.get))
    if showAllUserFiles.isSome:
        body.add("showAllUserFiles", newJBool(showAllUserFiles.get))
    
    discard await this.request(HttpPost, "/list/"&id&"/edit", body)

method deleteFile(this: TMClient, id: string): Future[void] {.base, async.} =
    ## Deletes a file
    
    discard await this.request(HttpPost, "/file/"&id&"/delete")

method deleteList(this: TMClient, id: string): Future[void] {.base, async.} =
    ## Deletes a list
    
    discard await this.request(HttpPost, "/list/"&id&"/delete")

method addFileToList(this: TMClient, file: string, list: string): Future[void] {.base, async.} =
    ## Adds a media file to a list
    
    discard await this.request(HttpPost, "/list/"&list&"/add/"&file)

method removeFileFromList(this: TMClient, file: string, list: string): Future[void] {.base, async.} =
    ## Removes a media file from a list
    
    discard await this.request(HttpPost, "/list/"&list&"/remove/"&file)

proc createClientWithToken*(rootUrl: string, token: string): TMClient =
    ## Creates a TwineMedia client with the provided root URL and token.
    ## Does not fetch account information, call fetchSelfAccountInfo(client) to fetch or update it.
    
    return TMClient(rootUrl: rootUrl.stripTrailingSlash, token: token)

proc createClientWithEmail*(rootUrl: string, email: string, password: string): Future[TMClient] {.async.} =
    ## Creates a TwineMedia client with the providede root URL, email, and password.
    ## Contacts the API to authenticate with email, and as such takes more time than creating a client with a token.
    ## Does not fetch account information, call fetchSelfAccountInfo(client) to fetch or update it.
    
    # Create HTTP client for login
    let root = rootUrl.stripTrailingSlash
    let http = newAsyncHttpClient(headers = newHttpHeaders({ "Content-Type": "application/json" }))
    let credentials = %* {
        "email": email,
        "password": password
    }
    let httpRes = await http.request(root&"/api/v1/auth", HttpPost, $credentials)

    # Make sure 200 status is returned
    if httpRes.status.startsWith("200"):
        # Get body and parse JSON
        let json = parseJson(await httpRes.body())
        
        # Get status
        let status = json["status"].getStr

        # Create client or handle bad status
        if status == "success":
            result = TMClient(rootUrl: root, token: json["token"].getStr)
            http.close()
        elif status == "error":
            let msg = json["error"].getStr("No error field in response")

            var error: ref CatchableError

            # Check if this is an authentication error
            if msg.startsWith("Invalid"):
                error = newException(InvalidCredentialsError, msg)
            else:
                let err = newException(ErrorStatusError, "API returned error \"$1\""%msg)
                err.errorMessage = msg
                error = err

            http.close()

            raise error
        else:
            http.close()
            raise newException(UnknownStatusError, "API returned unknown status \"$1\""%status)

        # Finally close connection
        http.close()
    else:
        # Close connection before throwing exception
        http.close()
        raise newException(BadStatusCodeError, "API returned HTTP status "&httpRes.status)
    
    return result