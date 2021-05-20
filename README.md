# nim-tm-client
Asychronous API client library for TwineMedia for Nim

Include in your project by importing "tm_client".

# Examples

Authenticate with a token:

```nim
import tm_client
import asyncdispatch
import strformat

const root = "https://your.tm.instance"
const token = "YOUR_TOKEN_HERE"

proc main() {.async.} =
    # Create client
    let client = createClientWithToken(root, token)

    # Optionally fetch client account info
    let info = await client.fetchSelfAccountInfo()

    echo fmt"Account name is: {info.name}, and email is: {info.email}"

# Wait for async code
waitFor main()
```

Authenticate with email and password:

```nim
import tm_client
import asyncdispatch
import strformat

const root = "https://your.tm.instance"
const email = "me@example.com"
const password = "drowssap"

proc main() {.async.} =
    # Create client with credentials
    let client = await createClientWithEmail(root, email, password)

    # Optionally fetch client account info
    let info = await client.fetchSelfAccountInfo()

    echo fmt"Account name is: {info.name}, and email is: {info.email}"

# Wait for async code
waitFor main()
```

Fetch first 3 uploaded files:

```nim
import tm_client
import tm_client/enum
import asyncdispatch
import strformat

# ...Client creation code, etc...

let media = await client.fetchMedia(limit = 3, order = MediaCreatedOnAsc)

for file in media:
    echo fmt"Name: {file.name}, size: {file.size}"
```