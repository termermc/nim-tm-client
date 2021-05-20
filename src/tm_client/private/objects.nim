import times
import options

type
    TMSelfAccountInfo* = object
        ## Stores info about the account associated with a TwineMedia client

        id*: int
        permissions*: seq[string]
        name*: string
        email*: string
        isAdmin*: bool
        creationDate*: DateTime
        excludeTags*: seq[string]
        excludeOtherMedia*: bool
        excludeOtherLists*: bool
        excludeOtherProcesses*: bool
        maxUploadSize*: int64
        isApiToken*: bool

    TMMedia* = object
        ## Stores information about a media file.
        ## Note: "parent" will be empty if the media file has no parent, but if it does, it will contain exactly 1 TMMedia object.
            
        id*: string
        name*: string
        filename*: string
        creatorId*: int
        creatorName*: string
        size*: int64
        mime*: string
        createdOn*: DateTime
        modifiedOn*: DateTime
        fileHash*: string
        hasThumbnail*: bool
        thumbnailUrl*: string
        downloadUrl*: string
        tags*: seq[string]
        isProcessing*: bool
        processError*: string
        description*: string
        parent*: seq[TMMedia]
        children*: seq[TMMedia]

    TMInstanceInfo* = object
        ## Stores information about a TwineMedia instance
        
        version*: string
        apiVersions*: seq[string]
    
    TMTag* = object
        ## Stores information about a TwineMedia tag
        
        name*: string
        files*: int
    
    TMList* = object
        ## Stores information about a TwineMedia list
        
        id*: string
        name*: string
        description*: string
        creatorId*: int
        creatorName*: string
        listType*: TMListType
        listVisibility*: TMListVisibility
        createdOn*: DateTime
        modifiedOn*: DateTime
        sourceTags*: Option[seq[string]]
        sourceExcludeTags*: Option[seq[string]]
        sourceCreatedBefore*: Option[DateTime]
        sourceCreatedAfter*: Option[DateTime]
        sourceMime*: Option[string]
        showAllUserFiles*: Option[bool]
        itemCount*: Option[int]
        containsMedia*: Option[bool]