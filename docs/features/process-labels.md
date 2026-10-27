# Process labels

The CPU menu names a busy process by its executable, and `ruby` or `node` alone says little. Process
labels ask an OpenAI-compatible chat service what the process is doing, then show the answer in the
menu as `ruby (dev server in ~/dev/shop)`. Settings › Process Labels holds the endpoint, the model
and the token.

## Invariants

- **Nothing is sent until an endpoint and a model are set.** `ProcessLabelCoordinator.observe` clears
  its state and returns at once while either is empty.
- **Apps are never sent.** A pid with an `NSRunningApplication` bundle already has a clear name.
- **Only the redacted signature leaves the Mac.** `ProcessSignature.text` is both the cache key and
  the whole user message. Nothing else about the process goes into the request.
- **The fetch follows the networked-feature rule.** `ProcessLabelService` uses a private `.ephemeral`
  session with `urlCache = nil`, never `URLSession.shared`.
- **The token lives only in the Keychain**, under `KeychainSecretStore.processLabels`. settings.json
  carries the endpoint and the model, never the token. `settings-file-test` checks that.
- **The math stays in `Model/`.** `ProcessSignature`, `ProcessLabelFormat` and `ProcessLabelCache`
  import neither AppKit nor SwiftUI, so `Tests/process-labels-test.swift` compiles them directly.

## When a request goes out

1. `CPUSampler` publishes the top 10 each second. `StatusItemController` passes them to
   `ProcessLabelCoordinator.observe`.
2. A pid must stay in the top 10 for 5 seconds. A pid that leaves the list starts again.
3. `ProcessFactsReader` reads the path, argv (`KERN_PROCARGS2`), working directory and parent name
   off the main actor. Another user's process cannot be read, so it gets no label.
4. A signature with a cached label costs nothing. Otherwise the coordinator sends one request at a
   time.
5. A failure pauses all requests for 5 minutes, and Settings shows the reason. A change to the
   endpoint, the model or the token ends the pause.

The menu rebuilds each time it opens, so a label that arrives while it is open shows the next time.

## The signature

`ProcessSignature(facts:home:)` turns the facts into four lines: executable, arguments, working
directory and parent. Each value is changed in this order:

| Step | Example |
| --- | --- |
| The home folder becomes `~` | `/Users/dev/shop` → `~/shop` |
| URL user info is hidden | `postgres://admin:pw@db` → `postgres://<redacted>@db` |
| A run of 24+ letters and digits is hidden | an API key, a UUID, a content hash |
| A run of 3+ digits becomes `#` | `-p 3000` → `-p #` |
| A value longer than 120 characters is cut | |

Then the value after a sensitive flag (`--token x`) is hidden, as is the value in `name=value` when the
name is sensitive. A name is sensitive when it contains `token`, `secret`, `passw`, `pwd`, `apikey`,
`api-key`, `api_key`, `auth`, `credential` or `key`. Only the first 40 arguments are kept.

The digit step is what makes the cache work. A dev server on port 3000 and one on 3001 in the same
folder share a signature, and so do two runs with different pids in their arguments.

## The request

`ProcessLabelFormat.endpoint(from:)` completes what the user typed:

| Typed | Endpoint |
| --- | --- |
| `https://api.openai.com` | `https://api.openai.com/v1/chat/completions` |
| `https://openrouter.ai/api/v1` | `https://openrouter.ai/api/v1/chat/completions` |
| `http://localhost:11434/v1` | `http://localhost:11434/v1/chat/completions` |

The body is only `model` and two messages: the instructions as `system`, the signature as `user`.
It sets no `temperature` or token limit, because some reasoning models refuse both. A token, when
saved, goes in `Authorization: Bearer`. Ollama needs none.

The reply's first non-empty line is the label. Quotes, parentheses and a final period are removed, and
the label is cut at 60 characters.

## Settings helpers

- **The model menu.** The button next to the Model field lists what `GET <base>/models` returns.
  `ProcessLabelFormat.modelsEndpoint(from:)` builds that URL from the same base as the chat endpoint.
  The pane fetches the list on open, 600 ms after the endpoint changes, and when a token is saved or
  removed. The list stays in memory. A line under the Model title shows the load state or the
  reason it failed, and the text field still works. A reply of type `text/html` fails as `.webPage`,
  because that is a web app's page at the API path, such as Open WebUI's page at `/v1`.
- **Test.** Until an endpoint and a model are set, the row says so and **Ask** stays off. **Ask** sends one of `ProcessLabelFormat.testQuestions` as the only message and shows the
  whole answer. The test skips the pause and the cache. A success also ends a failure pause.

## The cache

`ProcessLabelStore` keeps `ProcessLabelCache` in memory and rewrites
`~/Library/Caches/<bundle ID>/process-labels.json` after each change. It holds 500 labels, and the
oldest go first. A label never expires on its own. **Clear** in Settings empties it, so every process
is asked about again.
