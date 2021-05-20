type
    TMListType* = enum
        ## Enum of possible list types
        
        StandardList = 0,
        AutomaticallyPopulatedList = 1
    
    TMListVisibility* = enum
        ## Enum of possible list visibilities
        
        PrivateList = 0,
        PublicList = 1

    TMMediaOrder* = enum
        ## Enum of orders that media can be returned in

        MediaCreatedOnDesc = 0,
        MediaCreatedOnAsc = 1,
        MediaNameAsc = 2,
        MediaNameDesc = 3,
        MediaSizeDesc = 4,
        MediaSizeAsc = 5,
        MediaModifiedOnDesc = 6,
        MediaModifiedOnAsc = 7
    
    TMTagOrder* = enum
        ## Enum of orders that tags can be returned in
        
        TagNameAsc = 0,
        TagNameDesc = 1,
        TagLengthAsc = 2,
        TagLengthDesc = 3,
        TagFilesAsc = 4,
        TagFilesDesc = 5
    
    TMListOrder* = enum
        ## Enum of orders that tags can be returned in
        
        ListCreatedOnDesc = 0,
        ListCreatedOnAsc = 1,
        ListNameAsc = 2,
        ListNameDesc = 3,
        ListModifiedOnDesc = 4,
        ListModifiedOnAsc = 5