type ApiError* = object of CatchableError
    ## Raised if an API error occurred
type ContactError* = object of ApiError
    ## Raised if the API cannot be contacted
type ErrorStatusError* = object of ApiError
    ## Raised if an API returned an error status
    
    errorMessage*: string
type UnknownStatusError* = object of ApiError
    ## Raised if an API returned an unknown status
type MediaNotFoundError* = object of ErrorStatusError
    ## Raised if an API returned a file not found error on a media file
type BadStatusCodeError* = object of ApiError
    ## Raised if an API returns a bad (non-200) status code
type UnauthorizedError* = object of BadStatusCodeError
    ## Raised if the API returns an Unauthorized status code

type AuthError* = object of CatchableError
    ## Raised if an authentication error occurred
type InvalidCredentialsError* = object of AuthError
    ## Raised if invalid credentials are used to authenticate