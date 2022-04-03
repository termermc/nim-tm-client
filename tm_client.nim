## Module that provides an asynchronous client for TwineMedia and utilities for interacting with it

import json
import strutils
import mimetypes
import httpclient
import asyncdispatch
import cgi
import options
import times

import tm_client/private/enums
import tm_client/private/exceptions
import tm_client/private/objects
import tm_client/private/utils

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
        return this.rootUrl&"/download/"&id&"/"&encodeUrl(filename, false)
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
        source: json{"source"}.getInt,
        sourceType: json{"source_type"}.getStr(""),
        sourceName: json{"source_name"}.getStr(""),
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

method sourceJsonToObj(this: TMClient, json: JsonNode): TMSource {.base.} =
    # Resolve optional values
    let containsRemainingStorage = json{"remaining_storage"}
    let remainingStorage = if containsRemainingStorage == nil or containsRemainingStorage.kind == JNull:
        none[int64]()
    else:
        some(containsRemainingStorage.getBiggestInt)

    # Create object
    return TMSource(
        id: json["id"].getInt,
        sourceType: json["type"].getStr,
        name: json["name"].getStr,
        creatorId: json["creator"].getInt,
        creatorName: json["creator_name"].getStr,
        isGlobal: json["global"].getBool,
        mediaCount: json["media_count"].getInt,
        config: json["config"],
        schema: json["schema"],
        remainingStorage: remainingStorage,
        createdOn: json["created_on"].getStr.isoStringToDateTime,
    )

method sourceInfoJsonToObj(this: TMClient, json: JsonNode): TMSourceInfo {.base.} =
    # Create object
    return TMSourceInfo(
        id: json["id"].getInt,
        sourceType: json["type"].getStr,
        name: json["name"].getStr,
        creatorId: json["creator"].getInt,
        creatorName: json["creator_name"].getStr,
        isGlobal: json["global"].getBool,
        mediaCount: json["media_count"].getInt,
        createdOn: json["created_on"].getStr.isoStringToDateTime,
    )

method sourceTypeJsonToObj(this: TMClient, json: JsonNode): TMSourceType {.base.} =
    # Create object
    return TMSourceType(
        sourceType: json["type"].getStr,
        name: json["name"].getStr,
        description: json["description"].getStr,
        schema: json["schema"]
    )

method accountJsonToObj(this: TMClient, json: JsonNode): TMAccount {.base.} =
    # Create object
    return TMAccount(
        id: json["id"].getInt,
        email: json["email"].getStr,
        name: json["name"].getStr,
        permissions: json["permissions"].jsonArrayToStringSeq,
        isAdmin: json["admin"].getBool,
        defaultSource: json["default_source"].getInt,
        defaultSourceType: json["default_source_type"].getStr,
        defaultSourceName: json["default_source_name"].getStr,
        filesCreated: json["files_created"].getInt,
        createdOn: json["creation_date"].getStr.isoStringToDateTime
    )

method taskJsonToObj(this: TMClient, json: JsonNode): TMTask {.base.} =
    # Resolve optional values
    let containsViewPermission = json{"view_permission"}
    let viewPermission = if containsViewPermission == nil or containsViewPermission.kind == JNull:
        none[string]()
    else:
        some(containsViewPermission.getStr)
    
    let containsCancelPermission = json{"cancel_permission"}
    let cancelPermission = if containsCancelPermission == nil or containsCancelPermission.kind == JNull:
        none[string]()
    else:
        some(containsCancelPermission.getStr)

    let containsTotalItems = json{"total_items"}
    let totalItems = if containsTotalItems == nil or containsTotalItems.kind == JNull:
        none[int]()
    else:
        some(containsTotalItems.getInt)
    
    let containsSubtask = json{"subtask"}
    let subtask = if containsSubtask == nil or containsSubtask.kind == JNull:
        none[string]()
    else:
        some(containsSubtask.getStr)

    # Create object
    return TMTask(
        id: json["id"].getInt,
        name: json["name"].getStr,
        isCancellable: json["cancellable"].getBool,
        viewPermission: viewPermission,
        cancelPermission: cancelPermission,
        isGlobal: json["global"].getBool,
        progressType: parseEnum[TMTaskProgressType](json["progress_type"].getStr),
        finishedItems: json["finished_items"].getInt,
        totalItems: totalItems,
        subtask: subtask,
        isSucceeded: json["succeeded"].getBool,
        isCancelled: json["cancelled"].getBool,
        isFailed: json["failed"].getBool,
        isCancelling: json["cancelling"].getBool,
        createdOn: json["created_on"].getStr.isoStringToDateTime,
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

method uploadFile*(
        this: TMClient,
        path: string,
        name: Option[string] = none[string](),
        description: Option[string] = none[string](),
        tags: Option[seq[string]] = none[seq[string]](),
        noThumbnail: bool = false,
        doNotProcess: bool = false,
        ignoreHash: bool = false,
        source: Option[int] = none[int](),
    ): Future[string] {.base, async.} =
    ## Uploads a file and returns its ID
    
    # Setup headers
    var headers = @[
        ("Authorization", "Bearer "&this.token)
    ]
    if name.isSome:
        headers.add(("X-FILE-NAME", encodeUrl(name.get, false)))
    if description.isSome:
        headers.add(("X-FILE-DESCRIPTION", encodeUrl(description.get, false)))
    if tags.isSome:
        headers.add(("X-FILE-TAGS", encodeUrl($tags.get.stringSeqToJsonArray, false)))
    if noThumbnail:
        headers.add(("X-NO-THUMBNAIL", "true"))
    if doNotProcess:
        headers.add(("X-NO-PROCESS", "true"))
    if ignoreHash:
        headers.add(("X-IGNORE-HASH", "true"))
    if source.isSome:
        headers.add(("X-MEDIA-SOURCE", $source.get))

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

method createStandardList*(this: TMClient, id: string, name: string, description: string, visibility: TMListVisibility): Future[string] {.base, async.} =
    ## Create a new standard list
    
    let res = await this.request(HttpPost, "/lists/create", %*{
        "type": StandardList.ord,
        "name": name,
        "description": description,
        "visibility": visibility.ord
    })

    return res["id"].getStr

method createAutomaticallyPopulatedList*(
        this: TMClient,
        name: string,
        description: string,
        visibility: TMListVisibility,
        sourceTags: Option[seq[string]] = none[seq[string]](),
        sourceExcludeTags: Option[seq[string]] = none[seq[string]](),
        sourceCreatedBefore: Option[DateTime] = none[DateTime](),
        sourceCreatedAfter: Option[DateTime] = none[DateTime](),
        sourceMime: Option[string] = none[string](),
        showAllUserFiles: Option[bool] = none[bool]()
    ): Future[string] {.base, async.} =
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
    
    let res = await this.request(HttpPost, "/lists/create", body)

    return res["id"].getStr

method createSource*(
        this: TMClient,
        name: string,
        sourceType: string,
        config: JsonNode,
        testConfig: bool,
        isGlobal: bool
    ): Future[int] {.base, async.} =
    ## Creates a new source
    
    # Put fields in body
    let body = %*{
        "name": name,
        "type": sourceType,
        "config": config,
        "test": testConfig,
        "global": isGlobal
    }

    let res = await this.request(HttpPost, "/sources/create", body)

    return res["id"].getInt

method createAccount*(
        this: TMClient,
        name: string,
        email: string,
        isAdmin: bool,
        permissions: seq[string],
        password: string,
        defaultSource: int
    ): Future[int] {.base, async.} =
    ## Creates a new account
    
    # Put fields in body
    let body = %*{
        "name": name,
        "email": email,
        "admin": isAdmin,
        "permissions": permissions.stringSeqToJsonArray,
        "password": password,
        "defaultSource": defaultSource
    }

    let res = await this.request(HttpPost, "/accounts/create", body)

    return res["id"].getInt

method fetchSelfAccountInfo*(this: TMClient): Future[TMSelfAccountInfo] {.base, async.} =
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
        excludeOtherSources: info["exclude_other_sources"].getBool,
        maxUploadSize: info["max_upload"].getBiggestInt,
        isApiToken: info["api_token"].getBool,
        defaultSource: info["default_source"].getInt
    )
    this.account = account

    return account

method fetchInstanceInfo*(this: TMClient): Future[TMInstanceInfo] {.base, async.} =
    ## Fetches information about this TwineMedia instance

    let info = await this.request(HttpGet, "/info")
    return TMInstanceInfo(
        version: info["version"].getStr,
        apiVersions: info["api_versions"].jsonArrayToStringSeq
    )

method fetchMediaById*(this: TMClient, id: string): Future[TMMedia] {.base, async.} =
    ## Fetches the media file with the specified ID, otherwises raises MediaNotFoundError

    return this.mediaJsonToObj(await this.request(HttpGet, "/media/"&id))

method fetchMedia*(this: TMClient, offset: int = 0, limit: int = 100, mime: string = "%", order: TMMediaOrder = MediaCreatedOnDesc): Future[seq[TMMedia]] {.base, async.} =
    ## Fetches all media
    ## Provided MIME can use % as a wildcard character
    
    let files = (await this.request(HttpGet, "/media", %*{
        "offset": offset,
        "limit": limit,
        "mime": mime,
        "order": order.ord
    }))["files"].getElems
    var res = newSeq[TMMedia](files.len)
    for i, media in files:
        res[i] = this.mediaJsonToObj(media)
    
    return res

method fetchMediaByPlaintextSearch*(
        this: TMClient,
        query: string,
        searchNames: bool = true,
        searchFilenames: bool = true,
        searchDescriptions: bool = true,
        searchTags: bool = true,
        offset: int = 0,
        limit: int = 100,
        mime: string = "%",
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
        "mime": mime,
        "order": order.ord
    }))["files"].getElems
    var res = newSeq[TMMedia](files.len)
    for i, media in files:
        res[i] = this.mediaJsonToObj(media)
    
    return res

method fetchMediaByTags*(this: TMClient, tags: seq[string], excludeTags: seq[string] = @[], offset: int = 0, limit: int = 100, order: TMMediaOrder = MediaCreatedOnDesc): Future[seq[TMMedia]] {.base, async.} =
    ## Fetches all media that contain the specified tags (and don't contain the specified excluded tags)
    ## Provided MIME can use % as a wildcard character
    
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

method fetchMediaByList*(this: TMClient, list: string, offset: int = 0, limit: int = 100, order: TMMediaOrder = MediaCreatedOnDesc): Future[seq[TMMedia]] {.base, async.} =
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

method fetchTags*(this: TMClient, query: string = "", offset: int = 0, limit: int = 100, order: TMTagOrder = TagNameAsc): Future[seq[TMTag]] {.base, async.} =
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

method fetchListById*(this: TMClient, id: string): Future[TMList] {.base, async.} =
    ## Fetches a list's info by its ID
    
    return this.listJsonToObj(await this.request(HttpGet, "/list/"&id))

method fetchLists*(
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

method fetchListsByPlaintextSearch*(
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

method fetchSources*(
    this: TMClient,
        creator: Option[int] = none[int](),
        query: Option[string] = none[string](),
        offset: int,
        limit: int,
        order: TMSourceOrder = SourceCreatedOnDesc
    ): Future[seq[TMSourceInfo]] {.base, async.} =
    ## Fetches all sources, optionally returning only sources with the specified creator, and optionally by the specified plaintext search query
    
    # Figure out which parameters need to be added
    let body = %*{
        "offset": offset,
        "limit": limit,
        "order": order.ord
    }
    if creator.isSome:
        body.add("creator", newJInt(creator.get))
    if query.isSome:
        body.add("query", newJString(query.get))

    # Get sources
    let sourceElems = (await this.request(HttpGet, "/sources", body))["sources"].getElems
    var sources = newSeq[TMSourceInfo](sourceElems.len)
    for i, source in sourceElems:
        sources[i] = this.sourceInfoJsonToObj(source)
    
    return sources

method fetchSourceById*(this: TMClient, id: int): Future[TMSource] {.base, async.} =
    ## Fetches the source with the specified ID
    
    return this.sourceJsonToObj(await this.request(HttpGet, "/source/"&($id)))

method fetchSourceTypes*(this: TMClient): Future[seq[TMSourceType]] {.base, async.} =
    ## Fetches all available source types
    
    # Get types
    let typeElems = (await this.request(HttpGet, "/sources/types"))["types"].getElems
    var types = newSeq[TMSourceType](typeElems.len)
    for i, sourceType in typeElems:
        types[i] = this.sourceTypeJsonToObj(sourceType)
    
    return types

method fetchSourceType*(this: TMClient, sourceType: string): Future[TMSourceType] {.base, async.} =
    ## Fetches a specific source type's info
    
    return this.sourceTypeJsonToObj(await this.request(HttpGet, "/sources/type/"&sourceType))

method fetchTasks*(this: TMClient): Future[seq[TMTask]] {.base, async.} =
    ## Fetches all tasks visible to the client

    # Get tasks
    let taskElems = (await this.request(HttpGet, "/tasks"))["tasks"].getElems
    var tasks = newSeq[TMTask](taskElems.len)
    for i, task in taskElems:
        tasks[i] = this.taskJsonToObj(task)
    
    return tasks

method fetchTaskById*(this: TMClient, id: int): Future[TMTask] {.base, async.} =
    ## Fetches the task with the specified ID
    
    return this.taskJsonToObj(await this.request(HttpGet, "/task/"&($id)))

method fetchAccounts*(
        this: TMClient,
        query: Option[string],
        offset: int,
        limit: int,
        order: TMAccountOrder = AccountCreatedOnDesc
    ): Future[seq[TMAccount]] {.base, async.} =
    ## Fetches all lists, optionally returning only lists of the specified type, and optionally causing lists to contain whether they contain the specified media file by ID
    
    # Figure out which parameters need to be added
    let body = %*{
        "offset": offset,
        "limit": limit
    }
    if query.isSome:
        body.add("query", newJString(query.get))

    # Get accounts
    let accountElems = (await this.request(HttpGet, "/accounts", body))["accounts"].getElems
    var accounts = newSeq[TMAccount](accountElems.len)
    for i, account in accountElems:
        accounts[i] = this.accountJsonToObj(account)
    
    return accounts

method fetchAccountById*(this: TMClient, id: int): Future[TMAccount] {.base, async.} =
    ## Fetches the account with the specified ID
    
    return this.accountJsonToObj(await this.request(HttpGet, "/account/"&($id)))

method editFile*(
        this: TMClient,
        id: string,
        name: Option[string] = none[string](),
        filename: Option[string] = none[string](),
        description: Option[string] = none[string](),
        tags: Option[seq[string]] = none[seq[string]](),
        creator: Option[int] = none[int]()
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
    if creator.isSome:
        body.add("creator", newJInt(creator.get))
    
    # Edit file
    discard await this.request(HttpPost, "/media/"&id&"/edit", body)

method editListAsStandard*(this: TMClient, id: string, name: string, description: string, visibility: TMListVisibility): Future[void] {.base, async.} =
    ## Edits a list as a standard list (calling this on an automatically populated list will convert it into a standard list)
    
    discard await this.request(HttpPost, "/list/"&id&"/edit", %*{
        "type": StandardList.ord,
        "name": name,
        "description": description,
        "visibility": visibility.ord
    })

method editListAsAutomaticallyPopulated*(
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
    ## Edits a list as an automatically populated list (calling this on a standard list will convert it into an automatically populated list)
    
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

method editSource*(
        this: TMClient,
        id: int,
        name: Option[string] = none[string](),
        config: Option[JsonNode] = none[JsonNode](),
        creator: Option[int] = none[int](),
        isGlobal: Option[bool] = none[bool](),
        testConfig: bool = false,
        forceEdit: bool = false
    ): Future[void] {.base, async.} =
    ## Edits a source
    
    # Put fields in body if present
    let body = %*{
        "test": testConfig,
        "forceEdit": forceEdit
    }
    if name.isSome:
        body.add("name", newJString(name.get))
    if config.isSome:
        body.add("config", config.get)
    if creator.isSome:
        body.add("creator", newJInt(creator.get))
    if isGlobal.isSome:
        body.add("global", newJBool(isGlobal.get))

    discard await this.request(HttpPost, "/source/"&($id)&"/edit", body)

method editSelfAccount*(
        this: TMClient,
        currentPassword: Option[string] = none[string](),
        name: Option[string] = none[string](),
        email: Option[string] = none[string](),
        password: Option[string] = none[string](),
        defaultSource: Option[int] = none[int](),
        excludeTags: Option[seq[string]] = none[seq[string]](),
        excludeOtherMedia: Option[bool] = none[bool](),
        excludeOtherLists: Option[bool] = none[bool](),
        excludeOtherTags: Option[bool] = none[bool](),
        excludeOtherProcesses: Option[bool] = none[bool](),
        excludeOtherSources: Option[bool] = none[bool]()
    ): Future[void] {.base, async.} =
    ## Edits the client's account (currentPassword is required if changing email or password)
    
    # Put fields in body if present
    let body = newJObject()
    if currentPassword.isSome:
        body.add("currentPassword", newJString(currentPassword.get))
    if name.isSome:
        body.add("name", newJString(name.get))
    if email.isSome:
        body.add("email", newJString(email.get))
    if password.isSome:
        body.add("password", newJString(password.get))
    if defaultSource.isSome:
        body.add("defaultSource", newJInt(defaultSource.get))
    if excludeTags.isSome:
        body.add("excludeTags", excludeTags.get.stringSeqToJsonArray)
    if excludeOtherMedia.isSome:
        body.add("excludeOtherMedia", newJBool(excludeOtherMedia.get))
    if excludeOtherLists.isSome:
        body.add("excludeOtherLists", newJBool(excludeOtherLists.get))
    if excludeOtherTags.isSome:
        body.add("excludeOtherTags", newJBool(excludeOtherTags.get))
    if excludeOtherProcesses.isSome:
        body.add("excludeOtherProcesses", newJBool(excludeOtherProcesses.get))
    if excludeOtherSources.isSome:
        body.add("excludeOtherSources", newJBool(excludeOtherSources.get))

    discard await this.request(HttpPost, "/account/self/edit", body)

method editAccount*(
        this: TMClient,
        id: int,
        name: Option[string] = none[string](),
        email: Option[string] = none[string](),
        permissions: Option[seq[string]] = none[seq[string]](),
        isAdmin: Option[bool] = none[bool](),
        password: Option[string] = none[string](),
        defaultSource: Option[int] = none[int]()
    ): Future[void] {.base, async.} =
    ## Edits an account
    
    # Put fields in body if present
    let body = newJObject()
    if name.isSome:
        body.add("name", newJString(name.get))
    if email.isSome:
        body.add("email", newJString(email.get))
    if permissions.isSome:
        body.add("permissions", permissions.get.stringSeqToJsonArray)
    if isAdmin.isSome:
        body.add("admin", newJBool(isAdmin.get))
    if password.isSome:
        body.add("password", newJString(password.get))
    if defaultSource.isSome:
        body.add("defaultSource", newJInt(defaultSource.get))

    discard await this.request(HttpPost, "/account/"&($id)&"/edit", body)

method deleteFile*(this: TMClient, id: string): Future[void] {.base, async.} =
    ## Deletes a file
    
    discard await this.request(HttpPost, "/media/"&id&"/delete")

method deleteList*(this: TMClient, id: string): Future[void] {.base, async.} =
    ## Deletes a list
    
    discard await this.request(HttpPost, "/list/"&id&"/delete")

method deleteSource*(
        this: TMClient,
        id: int,
        forceDelete: bool = false,
        deleteContents: bool = false
    ): Future[void] {.base, async.} =
    ## Deletes a source
    
    # Put fields in body
    let body = %*{
        "forceDelete": forceDelete,
        "deleteContents": deleteContents
    }

    discard await this.request(HttpPost, "/source/"&($id)&"/delete", body)

method deleteAccount*(this: TMClient, id: int): Future[void] {.base, async.} =
    ## Deletes an account
    
    discard await this.request(HttpPost, "/source/"&($id)&"/delete")

method addFileToList*(this: TMClient, file: string, list: string): Future[void] {.base, async.} =
    ## Adds a media file to a list
    
    discard await this.request(HttpPost, "/list/"&list&"/add/"&file)

method removeFileFromList*(this: TMClient, file: string, list: string): Future[void] {.base, async.} =
    ## Removes a media file from a list
    
    discard await this.request(HttpPost, "/list/"&list&"/remove/"&file)

method cancelTask*(this: TMClient, id: int): Future[void] {.base, async.} =
    ## Requests that the task with the specified ID be cancelled
    
    discard await this.request(HttpPost, "/task/"&($id)&"/cancel")

proc createClientWithToken*(rootUrl: string, token: string): TMClient =
    ## Creates a TwineMedia client with the provided root URL and token.
    ## Does not fetch account information, call fetchSelfAccountInfo(client) to fetch or update it.
    
    return TMClient(rootUrl: rootUrl.stripTrailingSlash, token: token)

proc createAnonymousClient*(rootUrl: string): TMClient =
    ## Creates a TwineMedia client the provided root URL, and a blank token
    ## Is only able to perform anonymous requests, such as fetchInstanceInfo
    
    return TMClient(rootUrl: rootUrl.stripTrailingSlash, token: "")

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