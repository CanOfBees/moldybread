import httpclient, strformat, xmltools, strutils, base64, progress

type
  FedoraRequest* = ref object
    ## Type to Handle Fedora requests
    base_url*: string
    results*: seq[string]
    client: HttpClient
    max_results*: int
    output_directory: string
    authentication: (string, string)

  Message* = ref object
    ## Type to handle messaging
    errors*: seq[string]
    successes*: seq[string]
    attempts*: int

proc initFedoraRequest*(url: string="http://localhost:8080", auth=("admin", "admin")): FedoraRequest =
  ## Initializes new Fedora Request.
  ##
  ## Examples:
  ## .. code-block:: nim
  ##
  ##    let fedora_connection = initFedoraRequest()
  ##
  let client = newHttpClient()
  client.headers["Authorization"] = "Basic " & base64.encode(auth[0] & ":" & auth[1])
  FedoraRequest(base_url: url, authentication: auth, client: client, max_results: 1, output_directory: "/home/mark/nim_projects/moldybread/sample_output")

method grab_pids(this: FedoraRequest, response: string): seq[string] {. base .} =
  let xml_response = Node.fromStringE(response)
  let results = $(xml_response // "pid")
  for word in split(results, '<'):
    let new_word = word.replace("/", "").replace("pid>", "")
    if len(new_word) > 0:
      result.add(new_word)

method get_token(this: FedoraRequest, response: string): string {. base .} =
  let xml_response = Node.fromStringE(response)
  let results = $(xml_response // "token")
  if results.len > 0:
    result = results.replace("<token>", "").replace("</token>", "")

method get_cursor(this: FedoraRequest, response: string): string {. base .} =
  let xml_response = Node.fromStringE(response)
  let results = $(xml_response // "cursor")
  if results.len > 0:
    result = results.replace("<cursor>", "").replace("</cursor>", "")
  else:
    result = "No cursor"

method get_extension(this: FedoraRequest, header: HttpHeaders): string {. base .} =
  case $header["content-type"]
  of "application/xml":
    ".xml"
  else:
    ".bin"

method write_output(this: FedoraRequest, filename: string, contents: string): string {. base .} =
  let path = fmt"{this.output_directory}/{filename}"
  writeFile(path, contents)
  fmt"Creatred {filename} at {this.output_directory}."

method populate_results*(this: FedoraRequest, query: string): seq[string] {. base .} =
  ## Populates results for a Fedora request.
  ##
  ## Examples:
  ## .. code-block:: nim
  ##
  ##    let fedora_connection = initFedoraRequest()
  ##    echo fedora_connection.populate_results()
  ##
  var new_pids: seq[string] = @[]
  var token: string = "temporary"
  var request: string = fmt"{this.base_url}/fedora/objects?query=pid%7E{query}*&pid=true&resultFormat=xml&maxResults={this.max_results}"
  var response: string = ""
  while token.len > 0:
    response = this.client.getContent(request)
    new_pids = this.grab_pids(response)
    for pid in new_pids:
      result.add(pid)
    token = this.get_token(response)
    request = fmt"{this.base_url}/fedora/objects?query=pid%7E{query}*&pid=true&resultFormat=xml&maxResults={this.max_results}&sessionToken={token}"

method harvest_metadata*(this: FedoraRequest, datastream_id="MODS"): Message {. base .} =
  ## Populates results for a Fedora request.
  ##
  ## Examples:
  ## .. code-block:: nim
  ##
  ##    let fedora_connection = initFedoraRequest()
  ##    fedora_connection.populate_results()
  ##    fedora_connection.harvest_metadata("DC")
  ##
  var url: string
  var successes, errors: seq[string]
  var attempts: int
  var bar = newProgressBar()
  bar.start()
  var pid = ""
  for i in 1..len(this.results):
    pid = this.results[i-1]
    url = fmt"{this.base_url}/fedora/objects/{pid}/datastreams/{datastream_id}/content"
    var response = this.client.request(url, httpMethod = HttpGet)
    var extension = this.get_extension(response.headers)
    if response.status == "200 OK":
      successes.add(pid)
      discard this.write_output(fmt"{pid}{extension}", response.body)
    else:
      errors.add(pid)
    attempts += 1
    bar.increment()
  attempts = attempts
  bar.finish()
  Message(errors: errors, successes: successes, attempts: attempts)
